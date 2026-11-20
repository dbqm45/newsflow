import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable { case loading, notConfigured, signedOut, notMember, ready }
    enum Tab: Hashable { case home, feed, library, sources, settings }

    var phase: Phase = .loading
    var tab: Tab = .home
    var showPlayer = false
    /// Ustawiane przez link newsflow://briefing/2026-11-20
    var pendingBriefingDate: String?
    var userEmail: String?

    func start() async {
        guard AppConfig.isConfigured else { phase = .notConfigured; return }
        for await (event, session) in Supa.client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .signedOut, .userUpdated, .tokenRefreshed:
                await refresh(session: session)
            default:
                break
            }
        }
    }

    private func refresh(session: Session?) async {
        // Wygasła sesja przy starcie jest odświeżana automatycznie przez SDK.
        guard let session else {
            userEmail = nil
            phase = .signedOut
            return
        }
        userEmail = session.user.email
        do {
            phase = try await API.isMember() ? .ready : .notMember
        } catch {
            // Brak sieci: pozwól wejść (dane się nie wczytają, ale UI nie blokuje).
            phase = .ready
        }
    }

    func handle(url: URL) {
        guard url.scheme == "newsflow" else { return }
        let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        if parts.first == "briefing", parts.count > 1 {
            pendingBriefingDate = parts[1]
            tab = .home
        }
    }
}
