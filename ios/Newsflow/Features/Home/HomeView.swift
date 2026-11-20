import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(AudioPlayer.self) private var player
    @State private var briefing: Briefing?
    @State private var top: [FeedItem] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                chips
                if let error {
                    ErrorBanner(message: error) { Task { await load() } }.padding(.top, 12)
                }
                if let b = briefing {
                    BriefingHero(briefing: b).padding(.top, 14)
                    if !b.sections.isEmpty {
                        SectionTitle(text: "Tematy dnia")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(b.sections) { s in
                                    NavigationLink(value: SectionRoute(briefing: b, section: s)) { TopicCard(briefing: b, section: s) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.horizontal, -16)

                        SectionTitle(text: "Krótkie odsłuchy")
                        ForEach(b.sections) { s in
                            NavigationLink(value: SectionRoute(briefing: b, section: s)) { ShortListenRow(briefing: b, section: s) }
                                .buttonStyle(.plain)
                        }
                    }
                } else if !loading {
                    ContentUnavailableView("Brak briefingu", systemImage: "sun.haze",
                                           description: Text("Pierwszy briefing pojawi się po uruchomieniu WF04 (codziennie o 07:00)."))
                        .padding(.top, 40)
                }
                if !top.isEmpty {
                    SectionTitle(text: "Najwyżej oceniane · 24 h")
                    ForEach(top) { item in
                        NavigationLink(value: item) { FeedRow(item: item) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay { if loading && briefing == nil { ProgressView().tint(.white) } }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: app.pendingBriefingDate) { _, date in
            guard let date else { return }
            Task {
                if let b = try? await API.briefing(date: date) { briefing = b }
                app.pendingBriefingDate = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AvatarButton()
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.dayLong(DateParsing.dayString(Date())).capitalized(with: Fmt.pl))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
                Text(greeting).font(Theme.display(28)).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipButton(title: "Wszystko", selected: true) {}
                ChipButton(title: "Audycje") { app.libraryFilter = .episodes; app.tab = .library }
                ChipButton(title: "Tematy") { app.tab = .search }
                ChipButton(title: "Zapisane") { app.libraryFilter = .saved; app.tab = .library }
            }
        }
        .padding(.top, 14)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Dzień dobry"
        case 12..<18: return "Cześć"
        default: return "Dobry wieczór"
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let b = API.briefings(limit: 1)
            async let t = API.topItems(hours: 24, limit: 5)
            briefing = try await b.first
            top = try await t
            error = nil
        } catch {
            self.error = "Nie udało się pobrać danych. \(error.localizedDescription)"
        }
    }
}

struct SectionRoute: Hashable {
    let briefing: Briefing
    let section: BriefingSection
}

/// Karta briefingu dnia (okładka + tytuł + Play / Czytaj).
struct BriefingHero: View {
    @Environment(AudioPlayer.self) private var player
    let briefing: Briefing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NavigationLink(value: briefing) {
                CoverArt(style: .daily, kicker: shortDate, title: "AI Daily", size: 118, showWave: true)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(briefing.hasAudio ? "Nowe · \(Fmt.minutes(briefing.audioDurationSeconds))" : "Tylko tekst")
                    .font(.system(size: 10, weight: .bold)).tracking(1).textCase(.uppercase)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Theme.accentSoft)
                Text(briefing.title)
                    .font(Theme.display(17, .bold)).foregroundStyle(.white)
                    .lineLimit(3).padding(.top, 8)
                Text("\(briefing.sections.count) tematów · \(Fmt.sources(briefing.totalSources))")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.text2).padding(.top, 5)
                Spacer(minLength: 10)
                HStack(spacing: 10) {
                    if let track = Track.from(briefing) {
                        let isCurrent = player.current?.id == track.id
                        PlayButton(isPlaying: isCurrent && player.isPlaying) {
                            if isCurrent { player.togglePlay() } else { Task { await player.play(track, from: resumePosition) } }
                        }
                    }
                    NavigationLink(value: briefing) { Pill(text: "Czytaj") }.buttonStyle(.plain)
                    if let track = Track.from(briefing) {
                        Button { player.enqueue(track) } label: { Pill(text: "+") }
                            .buttonStyle(.plain).accessibilityLabel("Dodaj do kolejki")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0x2A1D6E), Color(hex: 0x16121F)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private var shortDate: String {
        let p = briefing.briefingDate.split(separator: "-")
        return p.count == 3 ? "\(p[2]).\(p[1])" : briefing.briefingDate
    }

    private var resumePosition: Double? {
        guard let p = briefing.myPositionSeconds, p > 10,
              let d = briefing.audioDurationSeconds, p < d - 15 else { return nil }
        return p
    }
}

/// Kafel tematu w karuzeli „Tematy dnia”.
struct TopicCard: View {
    let briefing: Briefing
    let section: BriefingSection

    var body: some View {
        let style = CoverStyle.forKey(section.subcategory)
        let ch = briefing.chapter(forStory: section.storyId)
        VStack(alignment: .leading, spacing: 2) {
            CoverArt(style: style,
                     kicker: [ch.map { Fmt.clock($0.durationSeconds) }, section.sourceCount.map { Fmt.sources($0) }]
                        .compactMap { $0 }.joined(separator: " · "),
                     size: 150)
            Text(section.headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(2).padding(.top, 8)
            Text(section.section == "headline" ? "Najważniejsze dziś" : (section.subcategory ?? section.sectionLabel))
                .font(.system(size: 12)).foregroundStyle(section.section == "headline" ? Theme.hot : Theme.text2).lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
    }
}

/// Wiersz „krótkiego odsłuchu” — temat z przyciskiem odtworzenia jego rozdziału.
struct ShortListenRow: View {
    @Environment(AudioPlayer.self) private var player
    let briefing: Briefing
    let section: BriefingSection

    var body: some View {
        let ch = briefing.chapter(forStory: section.storyId)
        HStack(spacing: 12) {
            CoverArt(style: CoverStyle.forKey(section.subcategory), size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.headline).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 6) {
                    Text([section.subcategory, ch.map { Fmt.clock($0.durationSeconds) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                    ScoreBadge(value: section.importanceScore)
                }
            }
            Spacer()
            if let track = Track.from(briefing), let ch {
                let active = player.current?.id == track.id && player.currentChapter?.index == ch.index && player.isPlaying
                Button {
                    if active { player.pause() } else { Task { await player.play(track, from: ch.startSeconds) } }
                } label: {
                    Image(systemName: active ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30)).foregroundStyle(active ? Theme.accentSoft : .white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Odsłuchaj temat")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct ChipButton: View {
    let title: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.surface2, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
