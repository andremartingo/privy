import AppIntents
import SwiftData
import SwiftUI

@main
struct privyApp: App {
    @State private var settings = AppSettings()

    init() {
        PrivyShortcuts.updateAppShortcutParameters()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Memo.self,
            TranscriptSegment.self,
            Speaker.self,
            SpeakerSegment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .preferredColorScheme(settings.colorScheme)
        }
        .modelContainer(sharedModelContainer)

        #if os(macOS)
            Settings {
                SettingsView(settings: settings)
            }
        #endif
    }
}
