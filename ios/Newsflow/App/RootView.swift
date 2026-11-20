import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.phase {
            case .loading:
                ProgressView("NEWSFLOW").controlSize(.large)
            case .notConfigured:
                ContentUnavailableView("Brak konfiguracji", systemImage: "gearshape.2",
                    description: Text("Uzupełnij ios/Config/Secrets.xcconfig (SUPABASE_HOST i SUPABASE_PUBLISHABLE_KEY) i zbuduj aplikację ponownie."))
            case .signedOut:
                LoginView()
            case .notMember:
                NotMemberView()
            case .ready:
                MainTabs()
            }
        }
        .sheet(isPresented: $app.showPlayer) {
            PlayerView()
                .presentationDragIndicator(.visible)
        }
        .alert("Odtwarzanie", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
    }
}

struct MainTabs: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            NavigationStack { HomeView().newsflowDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Dziś", systemImage: "sun.horizon") }
                .tag(AppState.Tab.home)
            NavigationStack { FeedView().newsflowDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Wiadomości", systemImage: "list.bullet.rectangle") }
                .tag(AppState.Tab.feed)
            NavigationStack { LibraryView().newsflowDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Biblioteka", systemImage: "square.stack") }
                .tag(AppState.Tab.library)
            NavigationStack { SourcesView().newsflowDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Źródła", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AppState.Tab.sources)
            NavigationStack { SettingsView().newsflowDestinations() }
                .withMiniPlayer()
                .tabItem { Label("Ustawienia", systemImage: "gearshape") }
                .tag(AppState.Tab.settings)
        }
    }
}

struct NotMemberView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        ContentUnavailableView {
            Label("Brak dostępu", systemImage: "lock")
        } description: {
            Text("Konto \(app.userEmail ?? "") nie jest dodane do tabeli app_members. Uruchom w Supabase SQL z docs/SETUP.md (krok „Właściciel”).")
        } actions: {
            Button("Wyloguj") { Task { await API.signOut() } }
        }
    }
}

extension View {
    /// Wspólne cele nawigacji dla wszystkich kart.
    func newsflowDestinations() -> some View {
        navigationDestination(for: FeedItem.self) { ItemDetailView(item: $0) }
            .navigationDestination(for: Briefing.self) { BriefingDetailView(briefing: $0) }
            .navigationDestination(for: SectionRoute.self) { SectionDetailView(briefing: $0.briefing, section: $0.section) }
    }
}
