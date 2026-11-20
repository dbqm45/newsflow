import SwiftUI

struct PlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue: Double = 0

    var body: some View {
        NavigationStack {
            if let track = player.current {
                ScrollView {
                    VStack(spacing: 22) {
                        Artwork(size: 240).shadow(radius: 20, y: 10).padding(.top, 12)
                        VStack(spacing: 6) {
                            Text(player.currentChapter?.title ?? track.title)
                                .font(.title3.bold()).multilineTextAlignment(.center)
                            Text(track.title).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Text(track.subtitle).font(.caption).foregroundStyle(.tertiary)
                        }
                        scrubber
                        controls
                        HStack {
                            Menu {
                                ForEach(AudioPlayer.rates, id: \.self) { r in
                                    Button { player.rate = r } label: {
                                        if r == player.rate { Label(rateLabel(r), systemImage: "checkmark") } else { Text(rateLabel(r)) }
                                    }
                                }
                            } label: {
                                Label(rateLabel(player.rate), systemImage: "speedometer").font(.subheadline.bold())
                            }
                            Spacer()
                            Label("Głos wygenerowany przez AI", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        if !track.chapters.isEmpty { chapters(track) }
                        if !player.queue.isEmpty { queue }
                    }
                    .padding(.bottom, 32)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down") }
                    }
                }
            } else {
                ContentUnavailableView("Nic nie gra", systemImage: "waveform", description: Text("Wybierz audycję na ekranie Dziś."))
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { player.isScrubbing ? scrubValue : player.currentTime },
                                  set: { scrubValue = $0 }),
                   in: 0...max(player.duration, 1)) { editing in
                if editing { scrubValue = player.currentTime; player.isScrubbing = true }
                else { player.seek(to: scrubValue); player.isScrubbing = false }
            }
            HStack {
                Text(Fmt.clock(player.isScrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text("-" + Fmt.clock(max(player.duration - (player.isScrubbing ? scrubValue : player.currentTime), 0) / Double(player.rate)))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { player.previousChapter() } label: { Image(systemName: "backward.end.fill") }
                .accessibilityLabel("Poprzedni rozdział")
            Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
                .accessibilityLabel("Wstecz 15 sekund")
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
            }
            .accessibilityLabel(player.isPlaying ? "Pauza" : "Odtwarzaj")
            Button { player.skip(30) } label: { Image(systemName: "goforward.30") }
                .accessibilityLabel("Do przodu 30 sekund")
            Button { player.nextChapter() } label: { Image(systemName: "forward.end.fill") }
                .accessibilityLabel("Następny rozdział")
        }
        .font(.title2)
        .buttonStyle(.plain)
    }

    private func chapters(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rozdziały").font(.headline).padding(.horizontal).padding(.bottom, 8)
            ForEach(track.chapters) { ch in
                let active = player.currentChapter?.index == ch.index
                Button { player.seek(to: ch.startSeconds); if !player.isPlaying { player.resume() } } label: {
                    HStack {
                        Image(systemName: active ? "speaker.wave.2.fill" : "circle.fill")
                            .font(active ? .footnote : .system(size: 5))
                            .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .frame(width: 20)
                        Text(ch.title).font(.subheadline.weight(active ? .semibold : .regular)).multilineTextAlignment(.leading)
                        Spacer()
                        Text(Fmt.clock(ch.startSeconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 44)
            }
        }
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Następne w kolejce").font(.headline)
            ForEach(player.queue) { t in
                HStack {
                    Artwork(size: 32)
                    Text(t.title).font(.subheadline).lineLimit(1)
                    Spacer()
                    Button { player.removeFromQueue(t) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    private func rateLabel(_ r: Float) -> String {
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",") + "×"
    }
}
