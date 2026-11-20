import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(AudioPlayer.self) private var player
    @State private var briefing: Briefing?
    @State private var top: [FeedItem] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                ErrorBanner(message: error) { Task { await load() } }.listRowSeparator(.hidden)
            }
            if let b = briefing {
                Section {
                    BriefingHero(briefing: b)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                if !b.sections.isEmpty {
                    Section("Najważniejsze dziś") {
                        ForEach(b.sections) { s in
                            NavigationLink(value: SectionRoute(briefing: b, section: s)) { SectionRow(section: s) }
                        }
                    }
                }
            } else if !loading {
                ContentUnavailableView("Brak briefingu", systemImage: "sun.haze",
                                       description: Text("Pierwszy briefing pojawi się po uruchomieniu WF04 (codziennie o 07:00)."))
            }
            if !top.isEmpty {
                Section("Najwyżej oceniane (24 h)") {
                    ForEach(top) { item in
                        NavigationLink(value: item) { FeedRow(item: item) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(greeting)
        .overlay { if loading && briefing == nil { ProgressView() } }
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

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
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
            async let t = API.topItems(hours: 24, limit: 6)
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

/// Duża karta dzisiejszej audycji z przyciskiem Play.
struct BriefingHero: View {
    @Environment(AudioPlayer.self) private var player
    let briefing: Briefing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Fmt.dayLong(briefing.briefingDate).uppercased())
                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                if briefing.hasAudio {
                    Label(Fmt.minutes(briefing.audioDurationSeconds), systemImage: "headphones")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                } else {
                    Label("tylko tekst", systemImage: "text.alignleft").font(.caption).foregroundStyle(.white.opacity(0.85))
                }
            }
            Text(briefing.title).font(.title2.bold()).foregroundStyle(.white)
            if let lead = briefing.summary {
                Text(lead).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(4)
            }
            HStack(spacing: 12) {
                if let track = Track.from(briefing) {
                    let isCurrent = player.current?.id == track.id
                    Button {
                        if isCurrent { player.togglePlay() }
                        else { Task { await player.play(track, from: resumePosition) } }
                    } label: {
                        Label(isCurrent && player.isPlaying ? "Pauza" : (resumePosition != nil ? "Wznów" : "Słuchaj"),
                              systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(.white, in: Capsule())
                            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.6))
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(value: briefing) {
                    Text("Czytaj").font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.white.opacity(0.18), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.16), Color(red: 0.31, green: 0.27, blue: 0.90)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private var resumePosition: Double? {
        guard let p = briefing.myPositionSeconds, p > 10,
              let d = briefing.audioDurationSeconds, p < d - 15 else { return nil }
        return p
    }
}

struct SectionRow: View {
    let section: BriefingSection
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(section.sectionLabel.uppercased()).font(.caption2.weight(.bold))
                    .foregroundStyle(section.section == "headline" ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                if let sub = section.subcategory { Text("· \(sub)").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                if let n = section.sourceCount, n > 1 { Text(Fmt.sources(n)).font(.caption2).foregroundStyle(.secondary) }
            }
            Text(section.headline).font(.headline)
            Text(section.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}
