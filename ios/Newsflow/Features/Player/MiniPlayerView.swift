import SwiftUI

extension View {
    /// Mini-odtwarzacz nad paskiem kart (jak w aplikacjach muzycznych).
    func withMiniPlayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerView() }
    }
}

struct MiniPlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppState.self) private var app

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Artwork(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentChapter?.title ?? track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(track.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if player.isLoading {
                        ProgressView()
                    } else {
                        Button { player.togglePlay() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                                .frame(width: 36, height: 36)
                        }
                        .accessibilityLabel(player.isPlaying ? "Pauza" : "Odtwarzaj")
                    }
                    Button { player.skip(30) } label: {
                        Image(systemName: "goforward.30").font(.title3).frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Do przodu 30 sekund")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                ProgressView(value: player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .scaleEffect(x: 1, y: 0.6)
            }
            .foregroundStyle(.primary)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 8).padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { app.showPlayer = true }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
