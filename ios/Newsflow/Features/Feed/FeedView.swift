import SwiftUI

struct CategoryRoute: Hashable {
    let style: CoverStyle
}

/// „Szukaj”: pole wyszukiwania, kafle kategorii i najnowsze materiały.
struct SearchView: View {
    @State private var query = ""
    @State private var results: [FeedItem] = []
    @State private var latest: [FeedItem] = []
    @State private var searching = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    AvatarButton()
                    Text("Szukaj").font(Theme.display(28)).padding(.leading, 6)
                    Spacer()
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold))
                    TextField("", text: $query, prompt: Text("Czego chcesz posłuchać?").foregroundColor(Color(hex: 0x555560)))
                        .font(.system(size: 15, weight: .medium))
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    if !query.isEmpty {
                        Button { query = ""; results = [] } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(Color(hex: 0x888890))
                    }
                }
                .foregroundStyle(Color(hex: 0x111111))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 14)

                if let error { ErrorBanner(message: error).padding(.top, 12) }

                if !query.isEmpty && (searching || !results.isEmpty) {
                    SectionTitle(text: searching ? "Szukam…" : "Wyniki")
                    ForEach(results) { item in NavigationLink(value: item) { FeedRow(item: item) }.buttonStyle(.plain) }
                } else {
                    SectionTitle(text: "Przeglądaj kategorie")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CoverStyle.categories, id: \.slug) { style in
                            NavigationLink(value: CategoryRoute(style: style)) { CategoryTile(style: style) }
                                .buttonStyle(.plain)
                        }
                    }
                    if !latest.isEmpty {
                        SectionTitle(text: "Najnowsze")
                        ForEach(latest) { item in NavigationLink(value: item) { FeedRow(item: item) }.buttonStyle(.plain) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await loadLatest() }
        .task { if latest.isEmpty { await loadLatest() } }
        .onChange(of: query) { _, v in
            guard v.count >= 3 else { if v.isEmpty { results = [] }; return }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if v == query { await search() }
            }
        }
    }

    private func loadLatest() async {
        do { latest = try await API.feed(API.FeedQuery(), limit: 15); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func search() async {
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            var fq = API.FeedQuery()
            fq.search = q
            results = try await API.feed(fq, limit: 40)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// Kafel kategorii (prostokątny, z „przechyloną” mini-okładką w rogu).
struct CategoryTile: View {
    let style: CoverStyle
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [style.top, style.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(style.name)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(12)
                .padding(.trailing, 30)
        }
        .frame(height: 96)
        .overlay(alignment: .bottomTrailing) {
            Circle().fill(.white.opacity(0.2)).frame(width: 56, height: 56).offset(x: 12, y: 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Materiały jednej kategorii: nagłówek w kolorze kategorii + lista z doładowaniem.
struct CategoryFeedView: View {
    let style: CoverStyle
    @State private var items: [FeedItem] = []
    @State private var onlyImportant = false
    @State private var loading = false
    @State private var reachedEnd = false
    @State private var error: String?

    private var query: API.FeedQuery {
        var q = API.FeedQuery()
        q.subcategory = style.slug
        q.minImportance = onlyImportant ? 6 : nil
        return q
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 16) {
                    CoverArt(style: style, size: 120)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(style.name).font(Theme.display(24)).lineLimit(3)
                        Toggle("Tylko ważne", isOn: $onlyImportant)
                            .font(.system(size: 13, weight: .medium))
                            .tint(Theme.accent)
                    }
                }
                .padding(.top, 8).padding(.bottom, 14)

                if let error { ErrorBanner(message: error) { Task { await reload() } } }
                ForEach(items) { item in
                    NavigationLink(value: item) { FeedRow(item: item) }
                        .buttonStyle(.plain)
                        .onAppear { if item.id == items.last?.id { Task { await loadMore() } } }
                }
                if loading { ProgressView().tint(.white).frame(maxWidth: .infinity).padding() }
                if !loading && items.isEmpty && error == nil {
                    ContentUnavailableView("Brak materiałów", systemImage: "tray", description: Text("W tej kategorii nic jeszcze nie ma."))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [style.bottom, Theme.bg], startPoint: .top, endPoint: .bottom).frame(height: 300).ignoresSafeArea()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if items.isEmpty { await reload() } }
        .onChange(of: onlyImportant) { _, _ in Task { await reload() } }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            items = try await API.feed(query)
            reachedEnd = items.count < 40
            error = nil
        } catch { self.error = error.localizedDescription }
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
}
