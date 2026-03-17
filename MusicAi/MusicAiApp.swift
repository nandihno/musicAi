import SwiftUI

@main
struct MusicAiApp: App {
    @State private var settings = SettingsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }
    }
}
