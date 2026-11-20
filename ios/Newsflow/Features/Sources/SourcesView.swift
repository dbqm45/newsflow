import SwiftUI

struct SourcesView: View {
    @State private var sources: [Source] = []
    @State private var showAdd = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            ForEach(grouped, id: \.0) { group in
                Section(SourceKind(rawValue: group.0)?.label ?? group.0.capitalized) {
                    ForEach(group.1) { s in SourceRow(source: s, onToggle: { v in await setActive(s, v) }) }
                        .onDelete { idx in let list = group.1; Task { await delete(idx.map { list[$0] }) } }
                }
            }
            Section {
                Text("X i LinkedIn będą dodane wyłącznie przez oficjalne, dozwolone integracje. Newslettery: oznaczaj w Gmailu etykietą AI-READ.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .screenBackground()
        .navigationTitle("Źródła")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Dodaj źródło")
            }
        }
        .sheet(isPresented: $showAdd) { AddSourceView { await load() } }
        .refreshable { await load() }
        .task { await load() }
    }

    private var grouped: [(String, [Source])] {
        Dictionary(grouping: sources, by: \.type).map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    private func load() async {
        do { sources = try await API.sources(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func setActive(_ s: Source, _ active: Bool) async {
        do {
            try await API.updateSource(s.id, active: active)
            if let i = sources.firstIndex(of: s) { sources[i].active = active }
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ list: [Source]) async {
        for s in list where s.type != "gmail" {
            do { try await API.deleteSource(s.id) } catch { self.error = error.localizedDescription }
        }
        await load()
    }
}

struct SourceRow: View {
    let source: Source
    let onToggle: (Bool) async -> Void
    @State private var active: Bool

    init(source: Source, onToggle: @escaping (Bool) async -> Void) {
        self.source = source
        self.onToggle = onToggle
        _active = State(initialValue: source.active)
    }

    var body: some View {
        Toggle(isOn: Binding(get: { active }, set: { v in active = v; Task { await onToggle(v) } })) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: SourceKind(rawValue: source.type)?.symbol ?? "envelope").foregroundStyle(.tint)
                    Text(source.name).font(.subheadline.weight(.semibold))
                    Text(String(repeating: "•", count: source.priority)).font(.caption2).foregroundStyle(.tertiary)
                }
                if let err = source.lastError, source.errorCount > 0 {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if let d = source.lastSuccessAt {
                    Text("Sprawdzone \(Fmt.ago(d))").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Jeszcze nie sprawdzone").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdded: () async -> Void
    @State private var kind: SourceKind = .rss
    @State private var name = ""
    @State private var input = ""
    @State private var language = "en"
    @State private var priority = 3
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Rodzaj", selection: $kind) {
                    ForEach(SourceKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                TextField("Nazwa", text: $name)
                Section {
                    TextField(kind.inputHint, text: $input, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    if let url = kind.feedURL(from: input) {
                        Text(url).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                } header: { Text("Adres") } footer: {
                    if kind == .youtube { Text("ID kanału znajdziesz w „Udostępnij kanał → Kopiuj identyfikator kanału”.") }
                }
                Picker("Język", selection: $language) {
                    Text("angielski").tag("en"); Text("polski").tag("pl"); Text("inny").tag("other")
                }
                Stepper("Priorytet: \(priority)/5", value: $priority, in: 1...5)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Nowe źródło")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dodaj") { Task { await add() } }
                        .disabled(busy || name.isEmpty || kind.feedURL(from: input) == nil)
                }
            }
        }
    }

    private func add() async {
        guard let url = kind.feedURL(from: input) else { return }
        busy = true
        defer { busy = false }
        do {
            try await API.addSource(NewSource(name: name, type: kind.rawValue, url: url, language: language,
                                              priority: priority, checkIntervalMinutes: kind == .podcast ? 720 : 180))
            await onAdded()
            dismiss()
        } catch {
            self.error = "Nie udało się dodać: \(error.localizedDescription)"
        }
    }
}
