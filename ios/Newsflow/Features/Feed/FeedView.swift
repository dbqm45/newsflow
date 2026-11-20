import SwiftUI

struct FeedView: View {
    @State private var items: [FeedItem] = []
    @State private var query = API.FeedQuery()
    @State private var onlyImportant = false
    @State private var loading = false
    @State private var reachedEnd = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ChipBar(options: Self.filterOptions, selection: $query.subcategory)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                Toggle("Tylko ważne (ocena ≥ 6)", isOn: $onlyImportant)
                    .font(.subheadline)
            }
            if let error { ErrorBanner(message: error) { Task { await reload() } } }
            ForEach(items) { item in
                NavigationLink(value: item) { FeedRow(item: item) }
                    .swipeActions(edge: .leading) {
                        Button { Task { await toggleSave(item) } } label: {
                            Label(item.isSaved ? "Usuń" : "Zapisz", systemImage: item.isSaved ? "bookmark.slash" : "bookmark")
                        }
                        .tint(.accentColor)
                    }
                    .onAppear { if item.id == items.last?.id { Task { await loadMore() } } }
            }
            if loading { HStack { Spacer(); ProgressView(); Spacer() } }
            if !loading && items.isEmpty && error == nil {
                ContentUnavailableView("Brak materiałów", systemImage: "tray",
                                       description: Text("Zmień filtry albo poczekaj na kolejny przebieg WF03."))
            }
        }
        .listStyle(.plain)
        .navigationTitle("Wiadomości")
        .searchable(text: $query.search, prompt: "Szukaj w tytułach i streszczeniach")
        .refreshable { await reload() }
        .task { if items.isEmpty { await reload() } }
        .onChange(of: query.subcategory) { _, _ in Task { await reload() } }
        .onChange(of: onlyImportant) { _, v in query.minImportance = v ? 6 : nil; Task { await reload() } }
        .onSubmit(of: .search) { Task { await reload() } }
        .onChange(of: query.search) { _, v in if v.isEmpty { Task { await reload() } } }
    }

    private static let filterOptions: [(String?, String)] =
        [(nil, "Wszystko")] + Fmt.subcategories.map { (Optional($0.slug), $0.name) }

    private func reload() async {
        reachedEnd = false
        loading = true
        defer { loading = false }
        do {
            items = try await API.feed(query)
            reachedEnd = items.count < 40
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !loading, !reachedEnd else { return }
        loading = true
        defer { loading = false }
        if let more = try? await API.feed(query, offset: items.count) {
            items += more.filter { m in !items.contains { $0.id == m.id } }
            reachedEnd = more.count < 40
        }
    }

    private func toggleSave(_ item: FeedItem) async {
        guard let saved = try? await API.toggleSaved(itemId: item.id),
              let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isSaved = saved
    }
}
