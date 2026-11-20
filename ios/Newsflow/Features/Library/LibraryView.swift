import SwiftUI

struct LibraryView: View {
    enum Segment: String, CaseIterable { case episodes = "Audycje", saved = "Zapisane" }
    @Environment(AudioPlayer.self) private var player
    @State private var segment: Segment = .episodes
    @State private var briefings: [Briefing] = []
    @State private var savedItems: [FeedItem] = []
    @State private var savedBriefings: [Briefing] = []
    @State private var error: String?

    var body: some View {
        List {
            Picker("Widok", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if let error { ErrorBanner(message: error) { Task { await load() } } }

            switch segment {
            case .episodes:
                ForEach(briefings) { b in
                    NavigationLink(value: b) { EpisodeRow(briefing: b) }
                        .swipeActions {
                            if let t = Track.from(b) {
                                Button { player.enqueue(t) } label: { Label("Do kolejki", systemImage: "text.badge.plus") }.tint(.indigo)
                            }
                        }
                }
                if briefings.isEmpty && error == nil {
                    ContentUnavailableView("Archiwum jest puste", systemImage: "square.stack")
                }
            case .saved:
                if !savedBriefings.isEmpty {
                    Section("Briefingi") { ForEach(savedBriefings) { b in NavigationLink(value: b) { EpisodeRow(briefing: b) } } }
                }
                Section("Materiały") {
                    ForEach(savedItems) { i in NavigationLink(value: i) { FeedRow(item: i) } }
                    if savedItems.isEmpty {
                        Text("Zapisuj materiały ikoną zakładki lub gestem w prawo na liście wiadomości.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Biblioteka")
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: segment) { _, _ in Task { await load() } }
    }

    private func load() async {
        do {
            switch segment {
            case .episodes:
                briefings = try await API.briefings(limit: 60)
            case .saved:
                async let i = API.feed(API.FeedQuery(savedOnly: true), limit: 100)
                async let b = API.savedBriefings()
                savedItems = try await i
                savedBriefings = try await b
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
            Artwork(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.dayShort(briefing.briefingDate)).font(.caption).foregroundStyle(.secondary)
                Text(briefing.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let d = briefing.audioDurationSeconds {
                    HStack(spacing: 6) {
                        Text(Fmt.minutes(d)).font(.caption).foregroundStyle(.secondary)
                        if let p = briefing.myPositionSeconds, p > 0 {
                            ProgressView(value: min(p / d, 1)).frame(width: 60).tint(.accentColor)
                        }
                    }
                } else {
                    Text("tylko tekst").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let t = Track.from(briefing) {
                Button {
                    if player.current?.id == t.id { player.togglePlay() } else { Task { await player.play(t, from: briefing.myPositionSeconds) } }
                } label: {
                    Image(systemName: player.current?.id == t.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title).foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
