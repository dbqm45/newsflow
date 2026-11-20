import SwiftUI

/// Briefing jak album: okładka, Play, a tematy jako „utwory” (rozdziały audycji).
struct BriefingDetailView: View {
    @Environment(AudioPlayer.self) private var player
    @State var briefing: Briefing
    @State private var rating = 0

    private var track: Track? { Track.from(briefing) }
    private var isCurrent: Bool { player.current?.id == track?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CoverArt(style: .daily, kicker: Fmt.dayLong(briefing.briefingDate), title: "AI Daily", size: 210, showWave: true)
                    .shadow(color: .black.opacity(0.5), radius: 25, y: 18)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                Text(briefing.title).font(Theme.display(23)).foregroundStyle(.white).padding(.top, 20)
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").foregroundStyle(Theme.accentSoft)
                    Text(meta)
                }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2).padding(.top, 8)

                actionRow.padding(.top, 14)

                if let lead = briefing.summary {
                    Text(lead).font(.system(size: 14.5)).foregroundStyle(Theme.text2).padding(.top, 14)
                }

                if let track, !briefing.chapters.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(briefing.chapters) { ch in chapterRow(ch, track: track) }
                    }
                    .padding(.top, 12)
                } else {
                    SectionTitle(text: "Tematy")
                    ForEach(briefing.sections) { s in
                        NavigationLink(value: SectionRoute(briefing: briefing, section: s)) { ShortListenRow(briefing: briefing, section: s) }
                            .buttonStyle(.plain)
                    }
                }

                if let trends = briefing.trends, !trends.isEmpty {
                    SectionTitle(text: "Trendy i wnioski")
                    Text(trends).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.85))
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Czy ten briefing był przydatny?").font(.system(size: 14, weight: .medium))
                        Spacer()
                        RatingButtons(rating: $rating) { r in try? await API.setBriefingFeedback(briefing.id, rating: r) }
                    }
                    Text("Briefing i audycja przygotowane automatycznie przez AI na podstawie podlinkowanych źródeł. Głos w nagraniu jest syntetyczny.")
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x4B33C9), Theme.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 460).ignoresSafeArea()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var meta: String {
        var parts = ["NEWSFLOW", "głos AI"]
        if briefing.hasAudio { parts.append(Fmt.minutes(briefing.audioDurationSeconds)) }
        if let a = briefing.itemsAnalyzed { parts.append("\(a) przeanalizowanych") }
        return parts.joined(separator: " · ")
    }

    private var actionRow: some View {
        HStack(spacing: 20) {
            Button {
                Task { if let s = try? await API.toggleSaved(briefingId: briefing.id) { briefing.isSaved = s } }
            } label: { Image(systemName: briefing.isSaved == true ? "heart.fill" : "heart") }
                .foregroundStyle(briefing.isSaved == true ? Theme.accentSoft : Theme.text2)
                .accessibilityLabel(briefing.isSaved == true ? "Usuń z zapisanych" : "Zapisz")
            if let text = briefing.textContent {
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }.foregroundStyle(Theme.text2)
            }
            if let track {
                Button { player.enqueue(track) } label: { Image(systemName: "text.badge.plus") }
                    .foregroundStyle(Theme.text2).accessibilityLabel("Dodaj do kolejki")
            }
            Spacer()
            if let track {
                SpeedMenu()
                PlayButton(isPlaying: isCurrent && player.isPlaying, size: 58) {
                    if isCurrent { player.togglePlay() } else { Task { await player.play(track, from: briefing.myPositionSeconds) } }
                }
            }
        }
        .font(.system(size: 21, weight: .medium))
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chapterRow(_ ch: Chapter, track: Track) -> some View {
        let section = briefing.section(for: ch)
        let active = isCurrent && player.currentChapter?.index == ch.index
        HStack(spacing: 12) {
            Group {
                if active && player.isPlaying {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: true)
                } else if section != nil {
                    Text("\(position(of: ch))")
                } else {
                    Image(systemName: "mic")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(active ? Theme.accentSoft : Theme.text2)
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(section?.headline ?? ch.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(active ? Theme.accentSoft : .white).lineLimit(2)
                HStack(spacing: 4) {
                    if section?.section == "headline" {
                        Circle().fill(Theme.hot).frame(width: 7, height: 7)
                        Text("Najważniejsze").foregroundStyle(Theme.hot)
                        Text("·")
                    }
                    Text([section?.section == "headline" ? nil : section?.subcategory,
                          section?.sourceCount.map { Fmt.sources($0) },
                          Fmt.clock(ch.durationSeconds)].compactMap { $0 }.joined(separator: " · "))
                }
                .font(.system(size: 12.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
            if let section {
                NavigationLink(value: SectionRoute(briefing: briefing, section: section)) {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.text3).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Szczegóły tematu")
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { Task { await player.play(track, from: ch.startSeconds) } }
    }

    /// Numer tematu (bez intro/outro/trendów).
    private func position(of ch: Chapter) -> Int {
        (briefing.chapters.filter { briefing.section(for: $0) != nil }.firstIndex(of: ch) ?? 0) + 1
    }
}

/// Wybór tempa jako pigułka.
struct SpeedMenu: View {
    @Environment(AudioPlayer.self) private var player
    var body: some View {
        Menu {
            ForEach(AudioPlayer.rates, id: \.self) { r in
                Button { player.rate = r } label: {
                    if r == player.rate { Label(Self.label(r), systemImage: "checkmark") } else { Text(Self.label(r)) }
                }
            }
        } label: {
            Pill(text: Self.label(player.rate))
        }
        .accessibilityLabel("Tempo odtwarzania")
    }

    static func label(_ r: Float) -> String {
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",") + "×"
    }
}

/// Temat: czytaj i słuchaj w jednym miejscu.
struct SectionDetailView: View {
    @Environment(AudioPlayer.self) private var player
    let briefing: Briefing
    let section: BriefingSection
    @State private var items: [FeedItem] = []

    var body: some View {
        let style = CoverStyle.forKey(section.subcategory)
        let ch = briefing.chapter(forStory: section.storyId)
        let track = Track.from(briefing)
        let active = track != nil && player.current?.id == track?.id && ch != nil && player.currentChapter?.index == ch?.index

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if section.section == "headline" { Badge(text: "Najważniejsze", color: Theme.hot) }
                    Badge(text: section.subcategory ?? section.sectionLabel, color: .white)
                }
                Text(section.headline).font(Theme.display(25)).foregroundStyle(.white).padding(.top, 10)
                HStack(spacing: 8) {
                    ScoreBadge(value: section.importanceScore, label: "ważność")
                    if let r = items.compactMap(\.reliabilityScore).max() { ScoreBadge(value: r, label: "wiarygodność") }
                    if let n = section.sourceCount { Text(Fmt.sources(n)).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.warn) }
                }
                .padding(.top, 12)

                if let track, let ch {
                    HStack(spacing: 12) {
                        PlayButton(isPlaying: active && player.isPlaying) {
                            if active { player.togglePlay() } else { Task { await player.play(track, from: ch.startSeconds) } }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Odsłuchaj temat").font(.system(size: 14, weight: .semibold))
                            Text("\(Fmt.clock(ch.durationSeconds)) · głos AI").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                    }
                    .padding(.top, 16)
                }

                Text(section.summary).font(.system(size: 16)).lineSpacing(5).foregroundStyle(Color.white.opacity(0.85)).padding(.top, 18)

                if let why = section.whyItMatters { block("Dlaczego to ważne", why) }
                if let use = section.practicalUse { block("Zastosowanie w praktyce", use) }
                if let d = section.discrepancies {
                    Label(d, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14)).foregroundStyle(Theme.warn)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 16)
                }

                let points = items.first?.keyPoints ?? []
                if !points.isEmpty {
                    SectionTitle(text: "Najważniejsze punkty")
                    ForEach(points, id: \.self) { p in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.accentSoft).frame(width: 6, height: 6).offset(y: -3)
                            Text(p).font(.system(size: 14.5)).foregroundStyle(Color.white.opacity(0.85))
                        }
                        .padding(.vertical, 4)
                    }
                }

                SectionTitle(text: "Źródła")
                FlowSources(sources: section.sources)

                if !items.isEmpty {
                    SectionTitle(text: "Materiały")
                    ForEach(items) { item in NavigationLink(value: item) { FeedRow(item: item) }.buttonStyle(.plain) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [style.bottom, Theme.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 320).ignoresSafeArea()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { items = (try? await API.items(ids: section.sources.compactMap(\.contentItemId))) ?? [] }
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentSoft).textCase(.uppercase)
            Text(text).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.top, 18)
    }
}

struct Badge: View {
    let text: String
    var color: Color = .white
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold)).tracking(1).textCase(.uppercase)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(color)
    }
}

/// Źródła jako „pigułki” z kolorowym znacznikiem, zawijane w wiersze.
struct FlowSources: View {
    let sources: [SourceRef]
    private let colors: [Color] = [Theme.accent, Theme.warn, Theme.ok, Color(hex: 0xFF6B8A), Color(hex: 0x4AA8FF)]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(sources.enumerated()), id: \.offset) { i, s in
                if let url = URL(string: s.url) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(colors[i % colors.count]).frame(width: 14, height: 14)
                            Text(s.source ?? url.host() ?? "Źródło").font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

/// Prosty układ zawijający elementy do kolejnych wierszy.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// Kciuk w górę / w dół. 0 = brak oceny.
struct RatingButtons: View {
    @Binding var rating: Int
    let onChange: (Int) async -> Void

    var body: some View {
        HStack(spacing: 14) {
            button(1, "hand.thumbsup")
            button(-1, "hand.thumbsdown")
        }
    }

    private func button(_ value: Int, _ symbol: String) -> some View {
        Button {
            rating = rating == value ? 0 : value
            let r = rating
            Task { await onChange(r) }
        } label: {
            Image(systemName: rating == value ? symbol + ".fill" : symbol).font(.title3)
                .foregroundStyle(rating == value ? Theme.accentSoft : Theme.text2)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityLabel(value > 0 ? "Przydatne" : "Nieprzydatne")
    }
}
