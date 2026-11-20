import SwiftUI

/// Generowana okładka: gradient podkategorii, dwa koła, opcjonalna fala i duży napis.
struct CoverArt: View {
    let style: CoverStyle
    var kicker: String? = nil
    var title: String? = nil
    var size: CGFloat = 56
    var showWave = false
    var cornerRadius: CGFloat? = nil

    var body: some View {
        let radius = cornerRadius ?? max(6, size * 0.07)
        RoundedRectangle(cornerRadius: radius)
            .fill(LinearGradient(colors: [style.top, style.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white.opacity(0.18))
                    .frame(width: size * 0.7, height: size * 0.7)
                    .offset(x: size * 0.18, y: -size * 0.18)
            }
            .overlay(alignment: .leading) {
                Circle().fill(.black.opacity(0.18))
                    .frame(width: size * 0.4, height: size * 0.4)
                    .offset(x: -size * 0.1, y: size * 0.05)
            }
            .overlay(alignment: .topLeading) {
                if showWave { WaveGlyph(height: size * 0.18).padding(size * 0.08) }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: size * 0.02) {
                    if let kicker, size >= 90 {
                        Text(kicker.uppercased())
                            .font(.system(size: max(8, size * 0.05), weight: .semibold))
                            .tracking(1.2)
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                    Text((title ?? style.word).uppercased())
                        .font(.system(size: size * 0.15, weight: .black))
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(.white)
                .padding(size * 0.08)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .accessibilityHidden(true)
    }
}

struct WaveGlyph: View {
    var height: CGFloat = 20
    private let bars: [CGFloat] = [0.35, 0.65, 1, 0.5, 0.75, 0.4]
    var body: some View {
        HStack(alignment: .center, spacing: height * 0.12) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, h in
                Capsule().fill(.white.opacity(0.9)).frame(width: height * 0.14, height: height * h)
            }
        }
        .frame(height: height)
    }
}

/// Okrągły przycisk Play/Pauza.
struct PlayButton: View {
    var isPlaying = false
    var size: CGFloat = 52
    var white = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(white ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.accent))
                .frame(width: size, height: size)
                .shadow(color: white ? .clear : Theme.accent.opacity(0.45), radius: 12, y: 6)
                .overlay {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size * 0.36, weight: .bold))
                        .foregroundStyle(white ? Color.black : Color.white)
                        .offset(x: isPlaying ? 0 : size * 0.03)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pauza" : "Odtwarzaj")
    }
}

/// Mała etykieta-pigułka (np. tempo, „Czytaj”).
struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.white.opacity(0.12), in: Capsule())
        .foregroundStyle(.white)
    }
}

/// Sekcja z nagłówkiem w stylu „Tematy dnia”.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.display(21, .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24).padding(.bottom, 12)
    }
}

/// Awatar użytkownika — otwiera ustawienia.
struct AvatarButton: View {
    @Environment(AppState.self) private var app
    var body: some View {
        Button { app.showSettings = true } label: {
            Circle()
                .fill(LinearGradient(colors: [Theme.hot, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
                .overlay(Text(String((app.userEmail ?? "N").prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ustawienia")
    }
}
