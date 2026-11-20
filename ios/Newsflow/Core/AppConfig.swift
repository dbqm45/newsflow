import Foundation

/// Konfiguracja odczytywana z Info.plist (wartości pochodzą z Config/Secrets.xcconfig).
enum AppConfig {
    static let supabaseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        guard let url = URL(string: raw), url.host != nil, !raw.contains("YOUR-PROJECT-REF") else {
            return URL(string: "https://invalid.supabase.co")!
        }
        return url
    }()

    static let supabaseKey: String =
        Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String ?? ""

    static var isConfigured: Bool {
        supabaseURL.host != "invalid.supabase.co" && !supabaseKey.isEmpty && !supabaseKey.hasPrefix("REPLACE")
    }

    static let audioBucket = "audio"
    static let signedURLLifetime = 6 * 3600
}
