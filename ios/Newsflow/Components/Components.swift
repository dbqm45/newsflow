import SwiftUI

/// Ocena ważności 1–10 jako kolorowy znaczek.
struct ScoreBadge: View {
    let value: Double?
    var label: String? = nil

    private var color: Color {
        guard let v = value else { return .gray }
        switch v {
        case 7...: return .green
        case 5.5..<7: return .orange
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if let label { Text(label).font(.caption2).foregroundStyle(.secondary) }
            Text(Fmt.score(value)).font(.caption.monospacedDigit().bold())
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
        .accessibilityLabel("Ocena \(Fmt.score(value)) na 10")
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
        .background(.quaternary, in: Capsule())
    }
}

/// Wiersz materiału w feedzie.
struct FeedRow: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.sourceName).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                if item.isPrivate { Image(systemName: "envelope.fill").font(.caption2).foregroundStyle(.secondary) }
                Text("· \(Fmt.ago(item.date))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if item.isSaved { Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.tint) }
                ScoreBadge(value: item.importanceScore)
            }
            Text(item.title).font(.headline).lineLimit(3)
            if let summary = item.summary {
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack(spacing: 6) {
                if let sub = item.subcategoryName { Tag(text: sub) }
                if let n = item.storySourceCount, n > 1 { Tag(text: Fmt.sources(n), systemImage: "checkmark.seal") }
                if item.completeness == "partial" { Tag(text: "fragment", systemImage: "doc.badge.ellipsis") }
            }
        }
        .padding(.vertical, 4)
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
                            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
                            .foregroundStyle(selected ? Color.white : Color.primary)
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

/// Okładka audycji (gradient + fala).
struct Artwork: View {
    var size: CGFloat = 56
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18)
            .fill(LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.16), Color(red: 0.31, green: 0.27, blue: 0.90)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "waveform").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
    }
}
