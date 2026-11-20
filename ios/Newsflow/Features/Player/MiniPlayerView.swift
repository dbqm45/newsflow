import SwiftUI
import UIKit

extension View {
    /// Mini-odtwarzacz nad paskiem kart.
    func withMiniPlayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerView() }
    }
}

struct MiniPlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppState.self) private var app

    var body: some View {
        if let track = player.current {
            let style = player.currentStyle
            HStack(spacing: 10) {
                CoverArt(style: style, size: 42, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentChapter?.title ?? track.title)
                        .font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text([player.chapterLabel, "AI Daily"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 8)
                if player.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pauza" : "Odtwarzaj")
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 8).padding(.trailing, 6)
            .frame(height: 58)
            .background(
                LinearGradient(colors: [style.tint.blend(with: .black, by: 0.35), style.tint.blend(with: .black, by: 0.55)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white)
                            .frame(width: geo.size.width * (player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 10)
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
            .contentShape(Rectangle())
            .onTapGesture { app.showPlayer = true }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension Color {
    /// Mieszanie kolorów (zgodne z iOS 17; `Color.mix` jest dopiero od iOS 18).
    func blend(with other: Color, by amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(.sRGB, red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t), opacity: Double(a1 + (a2 - a1) * t))
    }
}
