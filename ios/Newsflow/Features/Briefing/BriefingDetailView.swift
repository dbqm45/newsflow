import SwiftUI

struct BriefingDetailView: View {
    @Environment(AudioPlayer.self) private var player
    @State var briefing: Briefing
    @State private var rating: Int = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Fmt.dayLong(briefing.briefingDate)).font(.subheadline).foregroundStyle(.secondary)
                    Text(briefing.title).font(.title2.bold())
                    if let lead = briefing.summary { Text(lead).font(.body) }
                    if let track = Track.from(briefing) {
                        HStack {
                            Button { Task { await player.play(track) } } label: {
                                Label("Odtwórz audycję · \(Fmt.minutes(briefing.audioDurationSeconds))", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            Button { player.enqueue(track) } label: { Image(systemName: "text.badge.plus") }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Dodaj do kolejki")
                        }
                    } else {
                        Label("Audio niedostępne — wersja tekstowa", systemImage: "speaker.slash").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !briefing.chapters.isEmpty, let track = Track.from(briefing) {
                Section("Rozdziały") {
                    ForEach(briefing.chapters) { ch in
                        Button { Task { await player.play(track, from: ch.startSeconds) } } label: {
                            HStack {
                                Text(ch.title).foregroundStyle(.primary)
                                Spacer()
                                Text(Fmt.clock(ch.startSeconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            ForEach(groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { s in
                        NavigationLink(value: SectionRoute(briefing: briefing, section: s)) { SectionRow(section: s) }
                    }
                }
            }

            if let trends = briefing.trends, !trends.isEmpty {
                Section("Trendy i wnioski") { Text(trends) }
            }

            Section {
                HStack {
                    Text("Czy ten briefing był przydatny?").font(.subheadline)
                    Spacer()
                    RatingButtons(rating: $rating) { r in try? await API.setBriefingFeedback(briefing.id, rating: r) }
                }
                if let a = briefing.itemsAnalyzed {
                    Text("Przeanalizowano \(a) materiałów, odrzucono \(briefing.itemsRejected ?? 0), rozważono \(briefing.itemsConsidered ?? 0) wydarzeń.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("Briefing i audycja przygotowane automatycznie przez AI. Sprawdzaj ważne informacje w źródłach.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Briefing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { if let s = try? await API.toggleSaved(briefingId: briefing.id) { briefing.isSaved = s } }
                } label: { Image(systemName: briefing.isSaved == true ? "bookmark.fill" : "bookmark") }
            }
            if let text = briefing.textContent {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: text) }
            }
        }
    }

    private var groups: [(String, [BriefingSection])] {
        let order = [("headline", "Najważniejsza informacja dnia"), ("main", "Główne tematy"), ("tools", "Narzędzia i zastosowania"), ("brief", "W skrócie")]
        return order.compactMap { key, label in
            let s = briefing.sections.filter { $0.section == key }
            return s.isEmpty ? nil : (label, s)
        }
    }
}

struct SectionDetailView: View {
    @Environment(AudioPlayer.self) private var player
    let briefing: Briefing
    let section: BriefingSection
    @State private var items: [FeedItem] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.sectionLabel.uppercased()).font(.caption.bold()).foregroundStyle(.tint)
                    Text(section.headline).font(.title3.bold())
                    Text(section.summary)
                    if let track = Track.from(briefing), let ch = briefing.chapter(forStory: section.storyId) {
                        Button { Task { await player.play(track, from: ch.startSeconds) } } label: {
                            Label("Odsłuchaj ten temat", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
            if let why = section.whyItMatters { Section("Dlaczego to ważne") { Text(why) } }
            if let use = section.practicalUse { Section("Zastosowanie w praktyce") { Text(use) } }
            if let d = section.discrepancies {
                Section("Rozbieżności między źródłami") { Label(d, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section("Materiały źródłowe") {
                if items.isEmpty {
                    ForEach(section.sources, id: \.url) { s in
                        if let url = URL(string: s.url) {
                            Link(destination: url) {
                                VStack(alignment: .leading) {
                                    Text(s.source ?? "Źródło").font(.caption.bold())
                                    Text(s.title ?? s.url).font(.subheadline)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(items) { item in NavigationLink(value: item) { FeedRow(item: item) } }
                }
            }
        }
        .navigationTitle(section.subcategory ?? "Temat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            items = (try? await API.items(ids: section.sources.compactMap(\.contentItemId))) ?? []
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
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityLabel(value > 0 ? "Przydatne" : "Nieprzydatne")
    }
}
