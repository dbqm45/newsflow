import Foundation

enum Fmt {
    static let pl = Locale(identifier: "pl_PL")

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = pl
        f.unitsStyle = .short
        return f
    }()

    private static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = pl
        f.timeZone = TimeZone(identifier: "Europe/Warsaw")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        return f
    }()

    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = pl
        f.timeZone = TimeZone(identifier: "Europe/Warsaw")
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = pl
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    static func ago(_ date: Date) -> String { relative.localizedString(for: date, relativeTo: Date()) }
    static func dayLong(_ isoDay: String) -> String { DateParsing.day(isoDay).map { longDay.string(from: $0) } ?? isoDay }
    static func dayShort(_ isoDay: String) -> String { DateParsing.day(isoDay).map { shortDay.string(from: $0) } ?? isoDay }
    static func dateTime(_ date: Date) -> String { dateTime.string(from: date) }

    /// 734 -> "12:14", 3725 -> "1:02:05"
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 734 -> "12 min"
    static func minutes(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        return "\(max(1, Int((seconds / 60).rounded()))) min"
    }

    static func score(_ v: Double?) -> String {
        guard let v else { return "–" }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func usd(_ v: Double) -> String { String(format: "$%.2f", v) }

    static func sources(_ n: Int) -> String {
        switch n {
        case 1: return "1 źródło"
        case 2...4: return "\(n) źródła"
        default: return "\(n) źródeł"
        }
    }

    static let subcategories: [(slug: String, name: String)] = [
        ("llm", "LLM"), ("agents", "Agenci"), ("automation", "Automatyzacja"), ("tools", "Narzędzia"),
        ("image-video", "Obraz i wideo"), ("voice-audio", "Głos i audio"), ("open-source", "Open source"),
        ("research", "Badania"), ("startups", "Startupy"), ("business", "Biznes"), ("coding", "Programowanie"),
        ("productivity", "Produktywność"), ("robotics", "Robotyka"), ("infrastructure", "Infrastruktura"),
        ("policy-safety", "Regulacje i bezpieczeństwo"),
    ]
}
