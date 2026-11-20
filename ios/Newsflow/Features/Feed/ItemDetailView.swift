import SwiftUI

struct ItemDetailView: View {
    @State var item: FeedItem
    @State private var related: [FeedItem] = []
    @State private var rating = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(item.sourceName).font(.subheadline.bold()).foregroundStyle(.tint)
                        if item.isPrivate { Tag(text: "newsletter", systemImage: "envelope") }
                        Spacer()
                        Text(Fmt.dateTime(item.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.title).font(.title3.bold())
                    if item.originalTitle != item.title {
                        Text(item.originalTitle).font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        ScoreBadge(value: item.importanceScore, label: "ważność")
                        ScoreBadge(value: item.reliabilityScore, label: "wiarygodność")
                        if let n = item.storySourceCount, n > 1 { Tag(text: Fmt.sources(n), systemImage: "checkmark.seal") }
                    }
                    if item.completeness == "partial" {
                        Label("Analiza na podstawie fragmentu treści", systemImage: "doc.badge.ellipsis")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            if let summary = item.summary { Section("Streszczenie") { Text(summary) } }

            if let points = item.keyPoints, !points.isEmpty {
                Section("Najważniejsze punkty") {
                    ForEach(points, id: \.self) { p in Label(p, systemImage: "smallcircle.filled.circle").labelStyle(BulletLabelStyle()) }
                }
            }
            if let why = item.whyItMatters { Section("Dlaczego to ważne") { Text(why) } }
            if let use = item.practicalValue { Section("Zastosowanie w praktyce") { Text(use) } }

            if let claims = item.claims, !claims.isEmpty {
                Section {
                    ForEach(claims, id: \.self) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.label.uppercased()).font(.caption2.bold()).foregroundStyle(color(for: c.type))
                            Text(c.text).font(.subheadline)
                        }
                    }
                } header: { Text("Fakty, opinie i deklaracje") } footer: {
                    Text("Deklaracje producentów nie zostały niezależnie potwierdzone.")
                }
            }

            Section {
                if let url = item.url {
                    Link(destination: url) { Label("Otwórz oryginał", systemImage: "safari") }
                }
                HStack {
                    Text("Czy to było przydatne?")
                    Spacer()
                    RatingButtons(rating: $rating) { r in try? await API.setFeedback(itemId: item.id, rating: r) }
                }
            } footer: {
                Text("Twoje oceny wpływają na wybór tematów w kolejnych briefingach.")
            }

            if !related.isEmpty {
                Section("To samo wydarzenie w innych źródłach") {
                    ForEach(related) { r in NavigationLink(value: r) { FeedRow(item: r) } }
                }
            }
        }
        .navigationTitle(item.subcategoryName ?? "Materiał")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { if let s = try? await API.toggleSaved(itemId: item.id) { item.isSaved = s } }
                } label: { Image(systemName: item.isSaved ? "bookmark.fill" : "bookmark") }
                .accessibilityLabel(item.isSaved ? "Usuń z zapisanych" : "Zapisz")
            }
            if let url = item.url {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) }
            }
        }
        .task {
            rating = item.myRating ?? 0
            if let sid = item.storyId { related = (try? await API.related(storyId: sid, excluding: item.id)) ?? [] }
        }
    }

    private func color(for type: String) -> Color {
        switch type {
        case "fact": return .green
        case "forecast": return .blue
        case "marketing": return .orange
        default: return .secondary
        }
    }
}

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(.tint)
            configuration.title
        }
    }
}
