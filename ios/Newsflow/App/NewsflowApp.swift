import SwiftUI
import UIKit

@main
struct NewsflowApp: App {
    @State private var app = AppState()
    @State private var player = AudioPlayer.shared

    init() {
        Self.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(player)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await app.start() }
                .onOpenURL { app.handle(url: $0) }
        }
    }

    /// Pasek kart: czarne tło, aktywna karta biała, nieaktywne szare.
    private static func configureAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.bg)
        tab.shadowColor = .clear
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(Theme.text3)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.text3)]
        item.selected.iconColor = .white
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 30, weight: .heavy)]
        nav.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 16, weight: .bold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}
