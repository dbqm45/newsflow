import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Paleta i typografia NEWSFLOW (ciemny motyw w stylu aplikacji muzycznych). Makieta: design/mockup.html
enum Theme {
    static let bg = Color(hex: 0x09090C)
    static let surface1 = Color(hex: 0x131318)
    static let surface2 = Color(hex: 0x1C1C23)
    static let surface3 = Color(hex: 0x26262F)
    static let text2 = Color(hex: 0xA3A3AE)
    static let text3 = Color(hex: 0x6B6B76)
    static let accent = Color(hex: 0x7C5CFF)
    static let accentSoft = Color(hex: 0xA594FF)
    static let hot = Color(hex: 0xFF6B4A)
    static let ok = Color(hex: 0x3DDC97)
    static let warn = Color(hex: 0xFFB547)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Styl okładki: każda podkategoria ma własny gradient i słowo na okładce.
struct CoverStyle: Hashable {
    let slug: String
    let word: String
    let name: String
    let top: Color
    let bottom: Color

    /// Ciemniejszy odcień do tła odtwarzacza i mini-odtwarzacza.
    var tint: Color { bottom }

    static let daily = CoverStyle(slug: "daily", word: "AI Daily", name: "Briefing dnia",
                                  top: Color(hex: 0x7C5CFF), bottom: Color(hex: 0x2A1878))

    static let categories: [CoverStyle] = [
        .init(slug: "llm", word: "LLM", name: "Modele językowe i LLM", top: Color(hex: 0x8E7CFF), bottom: Color(hex: 0x4B2BD6)),
        .init(slug: "agents", word: "Agenci", name: "Agenci AI", top: Color(hex: 0x21D4B4), bottom: Color(hex: 0x0B6D78)),
        .init(slug: "automation", word: "Automaty­zacja", name: "Automatyzacja", top: Color(hex: 0x5EE7FF), bottom: Color(hex: 0x1D6FA3)),
        .init(slug: "tools", word: "Narzędzia", name: "Narzędzia AI", top: Color(hex: 0xFFB547), bottom: Color(hex: 0xE5562E)),
        .init(slug: "image-video", word: "Obraz", name: "Generowanie obrazu i wideo", top: Color(hex: 0xFF9F43), bottom: Color(hex: 0xC2185B)),
        .init(slug: "voice-audio", word: "Głos", name: "Generowanie głosu i audio", top: Color(hex: 0xFF8FD8), bottom: Color(hex: 0x7A2BBF)),
        .init(slug: "open-source", word: "Open source", name: "Open source", top: Color(hex: 0xB6F25B), bottom: Color(hex: 0x2E8B3A)),
        .init(slug: "research", word: "Badania", name: "Badania naukowe", top: Color(hex: 0x4AA8FF), bottom: Color(hex: 0x1C3FA8)),
        .init(slug: "startups", word: "Startupy", name: "Startupy AI", top: Color(hex: 0xFFD84A), bottom: Color(hex: 0xD9822B)),
        .init(slug: "business", word: "Biznes", name: "AI w biznesie", top: Color(hex: 0x9AA5B1), bottom: Color(hex: 0x3A4452)),
        .init(slug: "coding", word: "Kod", name: "AI w programowaniu", top: Color(hex: 0x7CF2C9), bottom: Color(hex: 0x1E6F86)),
        .init(slug: "productivity", word: "Produk­tywność", name: "AI w produktywności", top: Color(hex: 0xC3A6FF), bottom: Color(hex: 0x6A3FD1)),
        .init(slug: "robotics", word: "Robotyka", name: "Robotyka i systemy autonomiczne", top: Color(hex: 0xFF7A7A), bottom: Color(hex: 0x8C1D2E)),
        .init(slug: "infrastructure", word: "Infra", name: "Infrastruktura i sprzęt AI", top: Color(hex: 0x8FB3FF), bottom: Color(hex: 0x2B3A8C)),
        .init(slug: "policy-safety", word: "Regulacje", name: "Regulacje i bezpieczeństwo AI", top: Color(hex: 0xFF6B8A), bottom: Color(hex: 0x9E1F5C)),
    ]

    /// Szuka po slugu (`agents`) albo pełnej nazwie (`Agenci AI`); domyślnie styl briefingu.
    static func forKey(_ key: String?) -> CoverStyle {
        guard let key, !key.isEmpty else { return .daily }
        let k = key.lowercased()
        return categories.first { $0.slug == k || $0.name.lowercased() == k } ?? .daily
    }
}
