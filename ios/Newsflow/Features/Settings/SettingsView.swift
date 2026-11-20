import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(AudioPlayer.self) private var player
    @State private var prefs: UserPreferences?
    @State private var interests = ""
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Konto") {
                LabeledContent("Zalogowano", value: app.userEmail ?? "–")
                Button("Wyloguj", role: .destructive) {
                    player.stop()
                    Task { await API.signOut() }
                }
            }

            if let binding = Binding($prefs) {
                Section {
                    Stepper("Długość audycji: \(binding.wrappedValue.preferredAudioLength) min",
                            value: binding.preferredAudioLength, in: 5...25)
                    Picker("Domyślne tempo", selection: Binding(get: { Float(binding.wrappedValue.playbackRate) },
                                                                set: { binding.wrappedValue.playbackRate = Double($0); player.rate = $0 })) {
                        ForEach(AudioPlayer.rates, id: \.self) { Text(String(format: "%.2f×", $0)).tag($0) }
                    }
                    TextField("Zainteresowania (po przecinku)", text: $interests, axis: .vertical)
                } header: { Text("Preferencje") } footer: {
                    Text("Długość audycji i zainteresowania są zapisywane w user_preferences. Na wybór tematów wpływają też Twoje oceny 👍/👎.")
                }
                Section {
                    Button(saved ? "Zapisano ✓" : "Zapisz preferencje") { Task { await save() } }
                }
            } else {
                Section { ProgressView() }
            }

            Section("System") {
                NavigationLink("Stan systemu i koszty") { SystemStatusView() }
                NavigationLink { VoiceLabView() } label: { Label("Porównanie głosów", systemImage: "waveform.badge.mic") }
            }

            Section("Informacje") {
                LabeledContent("Wersja", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")
                Text("Streszczenia przygotowuje AI (OpenAI), audycje czyta syntetyczny głos (ElevenLabs). Zawsze możesz otworzyć oryginalne źródło.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .navigationTitle("Ustawienia")
        .task { await load() }
    }

    private func load() async {
        do {
            let p = try await API.preferences()
            prefs = p
            interests = p.interests.joined(separator: ", ")
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard var p = prefs else { return }
        p.interests = interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        p.email = p.email ?? app.userEmail
        do {
            try await API.save(p)
            prefs = p
            saved = true
            try? await Task.sleep(for: .seconds(2))
            saved = false
        } catch { self.error = error.localizedDescription }
    }
}

struct SystemStatusView: View {
    @State private var runs: [PipelineRun] = []
    @State private var costs: [CostDay] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            Section("Koszty (30 dni)") {
                ForEach(totals, id: \.0) { t in
                    LabeledContent(t.0) { Text("\(Fmt.usd(t.1)) · \(t.2) wywołań") }
                }
                LabeledContent("Razem") { Text(Fmt.usd(totals.reduce(0) { $0 + $1.1 })).bold() }
                LabeledContent("Dziś") {
                    Text(Fmt.usd(costs.filter { $0.day == DateParsing.dayString(Date()) }.reduce(0) { $0 + ($1.costUsd ?? 0) }))
                }
            }
            Section("Ostatnie przebiegi") {
                ForEach(runs) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: icon(r.status)).foregroundStyle(color(r.status))
                            Text(r.workflow).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Fmt.ago(r.finishedAt)).font(.caption).foregroundStyle(.secondary)
                        }
                        if let e = r.error { Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    }
                }
            }
        }
        .navigationTitle("Stan systemu")
        .refreshable { await load() }
        .task { await load() }
    }

    private var totals: [(String, Double, Int)] {
        Dictionary(grouping: costs, by: \.provider)
            .map { ($0.key, $0.value.reduce(0) { $0 + ($1.costUsd ?? 0) }, $0.value.reduce(0) { $0 + $1.calls }) }
            .sorted { $0.0 < $1.0 }
    }

    private func load() async {
        do {
            async let r = API.pipelineRuns()
            async let c = API.costs()
            runs = try await r
            costs = try await c
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func icon(_ s: String) -> String {
        switch s { case "success": return "checkmark.circle.fill"; case "partial": return "exclamationmark.circle.fill"; default: return "xmark.octagon.fill" }
    }
    private func color(_ s: String) -> Color {
        switch s { case "success": return .green; case "partial": return .orange; default: return .red }
    }
}
