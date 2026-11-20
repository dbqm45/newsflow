import Foundation

// MARK: - Briefing (widok v_briefings)

struct Briefing: Decodable, Identifiable, Hashable {
    let id: UUID
    let briefingDate: String
    let edition: String
    let title: String
    let summary: String?
    let textContent: String?
    let sections: [BriefingSection]
    let trends: String?
    let chapters: [Chapter]
    let status: String
    let itemsConsidered: Int?
    let itemsAnalyzed: Int?
    let itemsRejected: Int?
    let createdAt: Date
    let audioAssetId: UUID?
    let audioPath: String?
    let audioDurationSeconds: Double?
    let myPositionSeconds: Double?
    var isSaved: Bool?

    var hasAudio: Bool { audioPath != nil && audioAssetId != nil }
    var date: Date? { DateParsing.day(briefingDate) }
    var headline: BriefingSection? { sections.first { $0.section == "headline" } ?? sections.first }

    func chapter(forStory storyId: String) -> Chapter? {
        chapters.first { ($0.storyIds ?? []).contains(storyId) }
    }
}

struct BriefingSection: Decodable, Hashable, Identifiable {
    var id: String { storyId }
    let position: Int
    let section: String
    let storyId: String
    let headline: String
    let summary: String
    let whyItMatters: String?
    let practicalUse: String?
    let discrepancies: String?
    let subcategory: String?
    let importanceScore: Double?
    let sourceCount: Int?
    let sources: [SourceRef]

    var sectionLabel: String {
        switch section {
        case "headline": return "Najważniejsze"
        case "tools": return "Narzędzia"
        case "brief": return "W skrócie"
        default: return "Temat dnia"
        }
    }
}

struct SourceRef: Decodable, Hashable {
    let contentItemId: String?
    let title: String?
    let source: String?
    let url: String
}

struct Chapter: Decodable, Hashable, Identifiable {
    var id: Int { index }
    let index: Int
    let title: String
    let startSeconds: Double
    let durationSeconds: Double
    let audioAssetId: String?
    let storyIds: [String]?
}

// MARK: - Feed (widok v_feed)

struct FeedItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let originalTitle: String
    let originalUrl: String
    let author: String?
    let publishedAt: Date?
    let collectedAt: Date
    let visibility: String
    let extractionStatus: String
    let analysisStatus: String
    let sourceId: UUID
    let sourceName: String
    let sourceType: String
    let summary: String?
    let keyPoints: [String]?
    let practicalValue: String?
    let whyItMatters: String?
    let claims: [Claim]?
    let completeness: String?
    let sourceLanguage: String?
    let importanceScore: Double?
    let reliabilityScore: Double?
    let subcategorySlug: String?
    let subcategoryName: String?
    let storyId: UUID?
    let storyItemCount: Int?
    let storySourceCount: Int?
    var myRating: Int?
    var isSaved: Bool

    var url: URL? { URL(string: originalUrl) }
    var date: Date { publishedAt ?? collectedAt }
    var isPrivate: Bool { visibility == "private" }
}

struct Claim: Decodable, Hashable {
    let text: String
    let type: String

    var label: String {
        switch type {
        case "fact": return "Fakt"
        case "opinion": return "Opinia"
        case "forecast": return "Prognoza"
        case "marketing": return "Deklaracja producenta"
        default: return type
        }
    }
}

// MARK: - Źródła

struct Source: Decodable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let type: String
    let url: String
    let language: String
    var priority: Int
    var active: Bool
    let visibility: String
    let lastCheckedAt: Date?
    let lastSuccessAt: Date?
    let lastError: String?
    let errorCount: Int
}

enum SourceKind: String, CaseIterable, Identifiable {
    case rss, youtube, blog, medium, reddit, podcast, web
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rss: return "RSS"
        case .youtube: return "YouTube"
        case .blog: return "Blog"
        case .medium: return "Medium"
        case .reddit: return "Reddit"
        case .podcast: return "Podcast"
        case .web: return "Strona WWW (RSS)"
        }
    }
    var symbol: String {
        switch self {
        case .rss, .web: return "dot.radiowaves.up.forward"
        case .youtube: return "play.rectangle.fill"
        case .blog: return "text.book.closed"
        case .medium: return "m.square"
        case .reddit: return "bubble.left.and.bubble.right"
        case .podcast: return "mic"
        }
    }
    var inputHint: String {
        switch self {
        case .youtube: return "ID kanału (UC…) lub adres youtube.com/channel/UC…"
        case .reddit: return "r/LocalLLaMA lub adres subreddita"
        case .medium: return "@autor, nazwa publikacji lub adres feedu"
        case .podcast: return "Adres RSS podcastu"
        default: return "Adres feedu RSS/Atom"
        }
    }

    /// Zamienia wpis użytkownika na adres feedu.
    func feedURL(from input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        switch self {
        case .youtube:
            if let r = s.range(of: #"UC[A-Za-z0-9_-]{22}"#, options: .regularExpression) {
                return "https://www.youtube.com/feeds/videos.xml?channel_id=\(s[r])"
            }
            return s.contains("feeds/videos.xml") ? s : nil
        case .reddit:
            if let r = s.range(of: #"r/[A-Za-z0-9_]+"#, options: .regularExpression) {
                return "https://www.reddit.com/\(s[r])/top/.rss?t=day"
            }
            return nil
        case .medium:
            return s.hasPrefix("http") ? s : "https://medium.com/feed/\(s)"
        default:
            return s.hasPrefix("http") ? s : "https://\(s)"
        }
    }
}

struct NewSource: Encodable {
    let name: String
    let type: String
    let url: String
    let language: String
    let priority: Int
    let checkIntervalMinutes: Int

    enum CodingKeys: String, CodingKey {
        case name, type, url, language, priority
        case checkIntervalMinutes = "check_interval_minutes"
    }
}

// MARK: - Ustawienia

/// Odczyt (dekoder konwertuje snake_case -> camelCase, więc bez własnych CodingKeys).
struct UserPreferences: Decodable, Equatable {
    var userId: UUID
    var language: String = "pl"
    var briefingTime: String = "08:00:00"
    var timezone: String = "Europe/Warsaw"
    var preferredAudioLength: Int = 12
    var playbackRate: Double = 1.0
    var interests: [String] = []
    var email: String?

    init(userId: UUID) { self.userId = userId }

    var row: PreferencesRow {
        PreferencesRow(userId: userId, language: language, briefingTime: briefingTime, timezone: timezone,
                       preferredAudioLength: preferredAudioLength, playbackRate: playbackRate,
                       interests: interests, email: email)
    }
}

/// Zapis (jawne nazwy kolumn).
struct PreferencesRow: Encodable {
    let userId: UUID
    let language: String
    let briefingTime: String
    let timezone: String
    let preferredAudioLength: Int
    let playbackRate: Double
    let interests: [String]
    let email: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", language, timezone, interests, email
        case briefingTime = "briefing_time"
        case preferredAudioLength = "preferred_audio_length"
        case playbackRate = "playback_rate"
    }
}

// MARK: - Stan systemu

struct PipelineRun: Decodable, Identifiable, Hashable {
    let id: Int
    let workflow: String
    let status: String
    let finishedAt: Date
    let error: String?
}

struct CostDay: Decodable, Hashable {
    let day: String
    let provider: String
    let calls: Int
    let costUsd: Double?
    let characters: Int?
}
