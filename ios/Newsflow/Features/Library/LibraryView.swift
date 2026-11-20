import SwiftUI

struct LibraryView: View {
    enum Segment: String, CaseIterable { case episodes = "Audycje", saved = "Zapisane", queue = "Kolejka" }

    @Environment(AppState.self) private var app
    @Environment(AudioPlayer.self) private var player
    @State private var briefings: [Briefing] = []
    @State private var savedItems: [FeedItem] = []
    @State private var savedBriefings: [Briefing] = []
    @State private var error: String?

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    AvatarButton()
                    Text("Twoja biblioteka").font(Theme.display(24))
                    Spacer()
                }
                .padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach(Segment.allCases, id: \.self) { s in
                        ChipButton(title: s.rawValue, selected: app.libraryFilter == s) { app.libraryFilter = s }
                    }
                }
                .padding(.top, 14).padding(.bottom, 10)

                if let error { ErrorBanner(message: error) { Task { await load() } } }

                switch app.libraryFilter {
                case .episodes:
                    Label("Ostatnie audycje", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2).padding(.vertical, 6)
                    ForEach(briefings) { b in
                        NavigationLink(value: b) { EpisodeRow(briefing: b) }.buttonStyle(.plain)
                    }
                    if briefings.isEmpty && error == nil {
                        ContentUnavailableView("Archiwum jest puste", systemImage: "books.vertical")
                    }
                case .saved:
                    ForEach(savedBriefings) { b in NavigationLink(value: b) { EpisodeRow(briefing: b) }.buttonStyle(.plain) }
                    ForEach(savedItems) { i in NavigationLink(value: i) { FeedRow(item: i) }.buttonStyle(.plain) }
                    if savedItems.isEmpty && savedBriefings.isEmpty {
                        ContentUnavailableView("Nic nie zapisano", systemImage: "heart",
                                               description: Text("Zapisuj briefingi i materiały ikoną serca lub zakładki."))
                    }
                case .queue:
                    if let t = player.current {
                        Text("Teraz odtwarzane").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2).padding(.vertical, 6)
                        QueueRow(track: t, active: true)
                    }
                    if !player.queue.isEmpty {
                        Text("Następne").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2).padding(.top, 14).padding(.bottom, 6)
                        ForEach(player.queue) { t in
                            QueueRow(track: t, active: false)
                                .contextMenu { Button("Usuń z kolejki", role: .destructive) { player.removeFromQueue(t) } }
                        }
                    }
                    if player.current == nil && player.queue.isEmpty {
                        ContentUnavailableView("Kolejka jest pusta", systemImage: "list.bullet",
                                               description: Text("Dodawaj audycje przyciskiem + na ekranie briefingu."))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: app.libraryFilter) { _, _ in Task { await load() } }
    }

    private func load() async {
        do {
            switch app.libraryFilter {
            case .episodes:
                briefings = try await API.briefings(limit: 60)
            case .saved:
                async let i = API.feed(API.FeedQuery(savedOnly: true), limit: 100)
                async let b = API.savedBriefings()
                savedItems = try await i
                savedBriefings = try await b
            case .queue:
                break
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EpisodeRow: View {
    @Environment(AudioPlayer.self) private var player
    let briefing: Briefing

    var body: some View {
        HStack(spacing: 12) {
            CoverArt(style: .daily, kicker: nil, title: "AI Daily", size: 58, showWave: true)
                .hueRotation(.degrees(hue))
            VStack(alignment: .leading, spacing: 3) {
                Text(briefing.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(progressColor)
                if let p = progress, p > 0, p < 0.97 {
                    ProgressView(value: p).tint(.white).frame(maxWidth: 160)
                }
            }
            Spacer()
            if let t = Track.from(briefing) {
                let active = player.current?.id == t.id && player.isPlaying
                Button {
                    if player.current?.id == t.id { player.togglePlay() } else { Task { await player.play(t, from: briefing.myPositionSeconds) } }
                } label: {
                    Image(systemName: active ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32)).foregroundStyle(active ? Theme.accentSoft : .white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Każdy dzień w nieco innym odcieniu, żeby archiwum nie było monotonne.
    private var hue: Double {
        let day = Int(briefing.briefingDate.suffix(2)) ?? 0
        return Double((day * 37) % 120) - 60
    }

    private var progress: Double? {
        guard let p = briefing.myPositionSeconds, let d = briefing.audioDurationSeconds, d > 0 else { return nil }
        return p / d
    }

    private var subtitle: String {
        var parts = [Fmt.dayShort(briefing.briefingDate)]
        if let d = briefing.audioDurationSeconds { parts.append(Fmt.minutes(d)) } else { parts.append("tylko tekst") }
        if let p = progress {
            if p >= 0.97 { parts.append("✓ wysłuchane") }
            else if p > 0, let d = briefing.audioDurationSeconds { parts.append("zostało \(Fmt.minutes(d - (briefing.myPositionSeconds ?? 0)))") }
        }
        return parts.joined(separator: " · ")
    }

    private var progressColor: Color {
        guard let p = progress, p > 0, p < 0.97 else { return Theme.text2 }
        return Theme.accentSoft
    }
}

struct QueueRow: View {
    let track: Track
    let active: Bool
    var body: some View {
        HStack(spacing: 12) {
            CoverArt(style: .daily, title: "AI Daily", size: 52, showWave: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(active ? Theme.accentSoft : .white).lineLimit(2)
                Text(track.subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
