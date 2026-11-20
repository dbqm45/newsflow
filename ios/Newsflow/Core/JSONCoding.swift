import Foundation

/// Dekodowanie odpowiedzi PostgREST: snake_case -> camelCase, daty timestamptz z dowolną precyzją.
enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = DateParsing.timestamp(raw) ?? DateParsing.day(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Nieznany format daty: \(raw)")
        }
        return d
    }()
}

enum DateParsing {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Warsaw")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "2026-11-20T07:00:01.123456+00:00", "2026-11-20T07:00:01Z", "2026-11-20 07:00:01+00"
    static func timestamp(_ raw: String) -> Date? {
        var s = raw.replacingOccurrences(of: " ", with: "T")
        var fraction: Double = 0
        if let dot = s.firstIndex(of: ".") {
            let afterDot = s.index(after: dot)
            let end = s[afterDot...].firstIndex(where: { !$0.isNumber }) ?? s.endIndex
            fraction = Double("0." + String(s[afterDot..<end])) ?? 0
            s.removeSubrange(dot..<end)
        }
        // "+00" -> "+00:00"
        if let r = s.range(of: #"[+-]\d{2}$"#, options: .regularExpression) {
            let offset = String(s[r]) + ":00"
            s.replaceSubrange(r, with: offset)
        }
        guard let base = iso.date(from: s) else { return nil }
        return base.addingTimeInterval(fraction)
    }

    static func day(_ raw: String) -> Date? { dayFormatter.date(from: raw) }
    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
}
