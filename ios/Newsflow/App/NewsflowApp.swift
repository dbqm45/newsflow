import SwiftUI

@main
struct NewsflowApp: App {
    @State private var app = AppState()
    @State private var player = AudioPlayer.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(player)
                .task { await app.start() }
                .onOpenURL { app.handle(url: $0) }
        }
    }
}
