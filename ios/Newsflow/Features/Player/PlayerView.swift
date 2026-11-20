import SwiftUI

/// Pełnoekranowy odtwarzacz: tło w kolorze okładki tematu, tempo, rozdziały, podgląd tekstu.
struct PlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue: Double = 0
    @State private var showLyrics = false

    var body: some View {
        let style = player.currentStyle
        ZStack {
            LinearGradient(colors: [style.tint.blend(with: .black, by: 0.15), style.tint.blend(with: .black, by: 0.7), Theme.bg],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: style)

            if let track = player.current {
                ScrollView {
                    VStack(spacing: 0) {
                        topBar(track)
                        CoverArt(style: style, kicker: kicker, title: style == .daily ? "AI Daily" : style.word, size: 330, showWave: style == .daily, cornerRadius: 14)
                            .shadow(color: .black.opacity(0.45), radius: 30, y: 20)
                            .padding(.top, 26)
                            .animation(.easeInOut(duration: 0.4), value: style)

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(player.currentChapter?.title ?? track.title)
                                    .font(Theme.display(21)).lineLimit(2)
                                Text("NEWSFLOW · głos AI").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        .padding(.top, 26)

                        scrubber.padding(.top, 18)
                        controls.padding(.top, 14)

                        if !player.currentParagraphs.isEmpty {
                            lyricsPreview.padding(.top, 26)
                        }
                        chapters(track).padding(.top, 24)
                        if !player.queue.isEmpty { queue.padding(.top, 20) }

                        Label("Głos i treść wygenerowane przez AI", systemImage: "sparkles")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.top, 24)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView("Nic nie gra", systemImage: "waveform", description: Text("Wybierz audycję na ekranie Dziś."))
                    .overlay(alignment: .topLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.bold()).padding() }
                    }
            }
        }
        .fullScreenCover(isPresented: $showLyrics) { LyricsView() }
    }

    private var kicker: String {
        guard let ch = player.currentChapter, let t = player.current else { return "" }
        return "Rozdział \(ch.index + 1) z \(t.chapters.count)"
    }

    private func topBar(_ track: Track) -> some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 20, weight: .bold)) }
                .accessibilityLabel("Zamknij odtwarzacz")
            Spacer()
            VStack(spacing: 2) {
                Text("ODTWARZANE Z BRIEFINGU").font(.system(size: 10.5, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.7))
                Text(track.subtitle).font(.system(size: 13, weight: .bold)).lineLimit(1)
            }
            Spacer()
            Menu {
                Button { player.stop(); dismiss() } label: { Label("Zatrzymaj i zamknij", systemImage: "stop.fill") }
            } label: { Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).frame(width: 30, height: 30) }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(get: { player.isScrubbing ? scrubValue : player.currentTime },
                                  set: { scrubValue = $0 }),
                   in: 0...max(player.duration, 1)) { editing in
                if editing { scrubValue = player.currentTime; player.isScrubbing = true }
                else { player.seek(to: scrubValue); player.isScrubbing = false }
            }
            .tint(.white)
            HStack {
                Text(Fmt.clock(player.isScrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text("-" + Fmt.clock(max(player.duration - (player.isScrubbing ? scrubValue : player.currentTime), 0) / Double(player.rate)))
            }
            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var controls: some View {
        HStack {
            SpeedMenu()
            Spacer()
            Button { player.previousChapter() } label: { Image(systemName: "backward.end.fill") }
                .accessibilityLabel("Poprzedni rozdział")
            Spacer()
            PlayButton(isPlaying: player.isPlaying, size: 68, white: true) { player.togglePlay() }
            Spacer()
            Button { player.nextChapter() } label: { Image(systemName: "forward.end.fill") }
                .accessibilityLabel("Następny rozdział")
            Spacer()
            Button { player.skip(30) } label: { Pill(text: "30", systemImage: "goforward") }
                .accessibilityLabel("Do przodu 30 sekund")
        }
        .font(.system(size: 26))
        .buttonStyle(.plain)
    }

    private var lyricsPreview: some View {
        let paras = player.currentParagraphs
        let i = min(player.currentParagraphIndex, max(paras.count - 1, 0))
        return Button { showLyrics = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tekst").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .bold))
                }
                Text(paras.isEmpty ? "" : paras[i])
                    .font(Theme.display(17, .bold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(player.currentStyle.top.blend(with: .black, by: 0.25), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pokaż pełny tekst")
    }

    private func chapters(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rozdziały").font(Theme.display(18, .bold)).padding(.bottom, 8)
            ForEach(track.chapters) { ch in
                let active = player.currentChapter?.index == ch.index
                Button { player.seek(to: ch.startSeconds); if !player.isPlaying { player.resume() } } label: {
                    HStack(spacing: 12) {
                        CoverArt(style: ch.index < track.styles.count ? track.styles[ch.index] : .daily, size: 40, cornerRadius: 6)
                        Text(ch.title).font(.system(size: 14.5, weight: active ? .bold : .medium))
                            .foregroundStyle(active ? Theme.accentSoft : .white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Text(Fmt.clock(ch.durationSeconds)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Następne w kolejce").font(Theme.display(18, .bold))
            ForEach(player.queue) { t in
                HStack(spacing: 12) {
                    CoverArt(style: .daily, size: 40, cornerRadius: 6)
                    Text(t.title).font(.system(size: 14.5, weight: .medium)).lineLimit(1)
                    Spacer()
                    Button { player.removeFromQueue(t) } label: { Image(systemName: "xmark").foregroundStyle(.white.opacity(0.6)) }
                        .buttonStyle(.plain).accessibilityLabel("Usuń z kolejki")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tekst rozdziału podświetlany w trakcie słuchania (jak tekst piosenki).
struct LyricsView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let style = player.currentStyle
        let paras = player.currentParagraphs
        let current = player.currentParagraphIndex
        ZStack(alignment: .bottom) {
            style.top.blend(with: .black, by: 0.3).ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(paras.enumerated()), id: \.offset) { i, p in
                            Text(p)
                                .font(Theme.display(23, .bold))
                                .foregroundStyle(.white.opacity(i == current ? 1 : (i < current ? 0.45 : 0.6)))
                                .id(i)
                                .onTapGesture { seek(toParagraph: i, of: paras) }
                                .animation(.easeInOut(duration: 0.3), value: current)
                        }
                        if paras.isEmpty {
                            Text("Brak tekstu dla tego rozdziału.").font(.system(size: 17)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 200)
                }
                .scrollIndicators(.hidden)
                .onChange(of: current) { _, i in withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(i, anchor: .center) } }
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 20, weight: .bold)) }
                        .accessibilityLabel("Zamknij tekst")
                    Spacer()
                    VStack(spacing: 2) {
                        Text(player.currentChapter?.title ?? "").font(.system(size: 13, weight: .bold)).lineLimit(1)
                        Text(player.chapterLabel + " · Tekst").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Color.clear.frame(width: 20, height: 20)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(style.top.blend(with: .black, by: 0.3))
            }

            VStack(spacing: 14) {
                ProgressView(value: player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0)
                    .tint(.white)
                HStack(spacing: 44) {
                    Button { player.previousChapter() } label: { Image(systemName: "backward.end.fill") }
                    PlayButton(isPlaying: player.isPlaying, size: 58, white: true) { player.togglePlay() }
                    Button { player.nextChapter() } label: { Image(systemName: "forward.end.fill") }
                }
                .font(.system(size: 24))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 14)
            .background(LinearGradient(colors: [style.top.blend(with: .black, by: 0.3).opacity(0), style.top.blend(with: .black, by: 0.4)],
                                       startPoint: .top, endPoint: .center))
        }
        .foregroundStyle(.white)
    }

    /// Przewija nagranie do początku akapitu (szacunek proporcjonalny do długości tekstu).
    private func seek(toParagraph i: Int, of paras: [String]) {
        guard let ch = player.currentChapter else { return }
        let total = Double(paras.reduce(0) { $0 + $1.count })
        guard total > 0 else { return }
        let before = Double(paras.prefix(i).reduce(0) { $0 + $1.count })
        player.seek(to: ch.startSeconds + ch.durationSeconds * before / total + 0.1)
    }
}
