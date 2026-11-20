import Foundation
import Supabase

/// Jedyny klient Supabase w aplikacji (klucz publishable + sesja użytkownika; RLS po stronie bazy).
enum Supa {
    static let client = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
}

enum APIError: LocalizedError {
    case notSignedIn
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Nie jesteś zalogowany."
        }
    }
}

/// Dostęp do danych. Wszystkie zapytania dekodujemy własnym dekoderem (JSONCoding.decoder).
enum API {
    private static var db: SupabaseClient { Supa.client }

    private static func decode<T: Decodable>(_ builder: PostgrestBuilder) async throws -> T {
        let response = try await builder.execute()
        return try JSONCoding.decoder.decode(T.self, from: response.data)
    }

    static var userId: UUID? { db.auth.currentUser?.id }

    // MARK: Konto

    static func signIn(email: String, password: String) async throws {
        try await db.auth.signIn(email: email, password: password)
    }

    static func signOut() async {
        try? await db.auth.signOut()
    }

    struct Member: Decodable { let userId: UUID; let role: String }

    static func isMember() async throws -> Bool {
        let rows: [Member] = try await decode(db.from("app_members").select("user_id,role").limit(1))
        return !rows.isEmpty
    }

    // MARK: Briefingi

    static func briefings(limit: Int = 30, offset: Int = 0) async throws -> [Briefing] {
        try await decode(db.from("v_briefings").select()
            .order("briefing_date", ascending: false)
            .range(from: offset, to: offset + limit - 1))
    }

    static func briefing(date: String) async throws -> Briefing? {
        let rows: [Briefing] = try await decode(db.from("v_briefings").select().eq("briefing_date", value: date).limit(1))
        return rows.first
    }

    static func savedBriefings() async throws -> [Briefing] {
        try await decode(db.from("v_briefings").select().eq("is_saved", value: true)
            .order("briefing_date", ascending: false).limit(100))
    }

    static func setBriefingFeedback(_ id: UUID, rating: Int) async throws {
        try await db.rpc("set_briefing_feedback", params: BriefingFeedbackParams(briefingId: id, rating: rating)).execute()
    }

    // MARK: Feed

    struct FeedQuery: Equatable {
        var subcategory: String?
        var minImportance: Double?
        var search: String = ""
        var savedOnly = false
        var sinceHours: Int?
    }

    static func feed(_ q: FeedQuery, offset: Int = 0, limit: Int = 40) async throws -> [FeedItem] {
        var query = db.from("v_feed").select().eq("analysis_status", value: "analyzed")
        if let sub = q.subcategory { query = query.eq("subcategory_slug", value: sub) }
        if let min = q.minImportance { query = query.gte("importance_score", value: min) }
        if q.savedOnly { query = query.eq("is_saved", value: true) }
        if let h = q.sinceHours {
            let since = Date().addingTimeInterval(-Double(h) * 3600)
            query = query.gte("collected_at", value: ISO8601DateFormatter().string(from: since))
        }
        let term = q.search
            .replacingOccurrences(of: #"[,()*%\\.:"']"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            query = query.or("title.ilike.*\(term)*,summary.ilike.*\(term)*,source_name.ilike.*\(term)*")
        }
        return try await decode(query
            .order("published_at", ascending: false, nullsFirst: false)
            .range(from: offset, to: offset + limit - 1))
    }

    static func topItems(hours: Int = 24, limit: Int = 8) async throws -> [FeedItem] {
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(hours) * 3600))
        return try await decode(db.from("v_feed").select()
            .eq("analysis_status", value: "analyzed")
            .gte("collected_at", value: since)
            .order("importance_score", ascending: false, nullsFirst: false)
            .limit(limit))
    }

    static func item(id: UUID) async throws -> FeedItem? {
        let rows: [FeedItem] = try await decode(db.from("v_feed").select().eq("id", value: id).limit(1))
        return rows.first
    }

    static func items(ids: [String]) async throws -> [FeedItem] {
        guard !ids.isEmpty else { return [] }
        return try await decode(db.from("v_feed").select().in("id", values: ids))
    }

    static func related(storyId: UUID, excluding id: UUID) async throws -> [FeedItem] {
        try await decode(db.from("v_feed").select()
            .eq("story_id", value: storyId)
            .neq("id", value: id)
            .order("published_at", ascending: false, nullsFirst: false)
            .limit(10))
    }

    static func setFeedback(itemId: UUID, rating: Int) async throws {
        try await db.rpc("set_feedback", params: FeedbackParams(contentItemId: itemId, rating: rating)).execute()
    }

    @discardableResult
    static func toggleSaved(itemId: UUID? = nil, briefingId: UUID? = nil) async throws -> Bool {
        try await decode(db.rpc("toggle_saved", params: ToggleSavedParams(contentItemId: itemId, briefingId: briefingId)))
    }

    // MARK: Audio

    static func signedURL(path: String) async throws -> URL {
        try await db.storage.from(AppConfig.audioBucket).createSignedURL(path: path, expiresIn: AppConfig.signedURLLifetime)
    }

    static func saveProgress(assetId: UUID, position: Double, completed: Bool) async {
        _ = try? await db.rpc("save_progress", params: ProgressParams(audioAssetId: assetId, position: position, completed: completed)).execute()
    }

    // MARK: Źródła

    static func sources() async throws -> [Source] {
        try await decode(db.from("sources").select()
            .order("priority", ascending: false)
            .order("name"))
    }

    static func addSource(_ s: NewSource) async throws {
        try await db.from("sources").insert(s).execute()
    }

    static func updateSource(_ id: UUID, active: Bool? = nil, priority: Int? = nil) async throws {
        try await db.from("sources").update(SourcePatch(active: active, priority: priority)).eq("id", value: id).execute()
    }

    static func deleteSource(_ id: UUID) async throws {
        try await db.from("sources").delete().eq("id", value: id).execute()
    }

    // MARK: Ustawienia

    static func preferences() async throws -> UserPreferences {
        guard let uid = userId else { throw APIError.notSignedIn }
        let rows: [UserPreferences] = try await decode(db.from("user_preferences").select().eq("user_id", value: uid).limit(1))
        return rows.first ?? UserPreferences(userId: uid)
    }

    static func save(_ prefs: UserPreferences) async throws {
        try await db.from("user_preferences").upsert(prefs.row, onConflict: "user_id").execute()
    }

    // MARK: Stan systemu

    static func pipelineRuns(limit: Int = 30) async throws -> [PipelineRun] {
        try await decode(db.from("pipeline_runs").select("id,workflow,status,finished_at,error")
            .order("finished_at", ascending: false).limit(limit))
    }

    static func costs(days: Int = 30) async throws -> [CostDay] {
        let since = DateParsing.dayString(Date().addingTimeInterval(-Double(days) * 86400))
        return try await decode(db.from("v_cost_daily").select("day,provider,calls,cost_usd,characters")
            .gte("day", value: since).order("day", ascending: false))
    }
}

// MARK: - Parametry RPC / zapisów (jawne nazwy kolumn)

private struct FeedbackParams: Encodable {
    let contentItemId: UUID
    let rating: Int
    enum CodingKeys: String, CodingKey { case contentItemId = "p_content_item_id", rating = "p_rating" }
}

private struct BriefingFeedbackParams: Encodable {
    let briefingId: UUID
    let rating: Int
    enum CodingKeys: String, CodingKey { case briefingId = "p_briefing_id", rating = "p_rating" }
}

private struct ToggleSavedParams: Encodable {
    let contentItemId: UUID?
    let briefingId: UUID?
    enum CodingKeys: String, CodingKey { case contentItemId = "p_content_item_id", briefingId = "p_briefing_id" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contentItemId, forKey: .contentItemId)  // jawne null
        try c.encode(briefingId, forKey: .briefingId)
    }
}

private struct ProgressParams: Encodable {
    let audioAssetId: UUID
    let position: Double
    let completed: Bool
    enum CodingKeys: String, CodingKey {
        case audioAssetId = "p_audio_asset_id", position = "p_position_seconds", completed = "p_completed"
    }
}

private struct SourcePatch: Encodable {
    let active: Bool?
    let priority: Int?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(active, forKey: .active)
        try c.encodeIfPresent(priority, forKey: .priority)
    }
    enum CodingKeys: String, CodingKey { case active, priority }
}
