import SwiftUI

/// Ocena ważności 1–10 jako kolorowy znaczek.
struct ScoreBadge: View {
    let value: Double?
    var label: String? = nil

    private var color: Color {
        guard let v = value else { return Theme.text3 }
        switch v {
        case 7...: return Theme.ok
        case 5.5..<7: return Theme.warn
        default: return Theme.text2
        }
    }

    var body: some View {
        Text([label, Fmt.score(value)].compactMap { $0 }.joined(separator: " "))
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(color)
            .accessibilityLabel("\(label ?? "Ocena") \(Fmt.score(value)) na 10")
    }
}

struct Tag: View {
    let text: String
    var systemImage: String? = nil
    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.white.opacity(0.1), in: Capsule())
    }
}

/// Wiersz materiału (okładka podkategorii + tytuł + źródło).
struct FeedRow: View {
    let item: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverArt(style: CoverStyle.forKey(item.subcategorySlug), title: CoverStyle.forKey(item.subcategorySlug).word, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 6) {
                    if item.isPrivate { Image(systemName: "envelope.fill").font(.system(size: 10)) }
                    Text("\(item.sourceName) · \(Fmt.ago(item.date))").lineLimit(1)
                    ScoreBadge(value: item.importanceScore)
                    if let n = item.storySourceCount, n > 1 {
                        Text(Fmt.sources(n)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.warn)
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                if let summary = item.summary {
                    Text(summary).font(.system(size: 13)).foregroundStyle(Theme.text3).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if item.isSaved { Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(Theme.accentSoft) }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Poziomy pasek filtrów.
struct ChipBar<Value: Hashable>: View {
    let options: [(Value?, String)]
    @Binding var selection: Value?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    let selected = opt.0 == selection
                    Button { selection = opt.0 } label: {
                        Text(opt.1).font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selected ? Theme.accent : Theme.surface2, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote)
            Spacer()
            if let retry { Button("Ponów", action: retry).font(.footnote.bold()) }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
