import SwiftUI
import SwiftData

@main
struct MusicAiApp: App {
    @State private var settings = SettingsManager()

    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: HistorySchemaV1.self),
                migrationPlan: HistoryMigrationPlan.self
            )
        } catch {
            fatalError("Couldn't open the History store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }
        .modelContainer(modelContainer)
    }
}
