import AppIntents

struct OpenPrivyIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Privy"
    static let description = IntentDescription("Open Privy.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct StartMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Memo"
    static let description = IntentDescription("Open Privy to start a new memo.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct PrivyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPrivyIntent(),
            phrases: [
                "Open \(.applicationName)",
            ],
            shortTitle: "Open Privy",
            systemImageName: "mic"
        )

        AppShortcut(
            intent: StartMemoIntent(),
            phrases: [
                "Start a memo in \(.applicationName)",
                "Record with \(.applicationName)",
            ],
            shortTitle: "Start Memo",
            systemImageName: "record.circle"
        )
    }
}
