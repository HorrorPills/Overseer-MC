//
//  ServerStatusIntent.swift
//  Overseer
//
//  Exposes live server status to Shortcuts/Siri via App Intents, e.g.
//  "Hey Siri, what's my server's player count?"
//

import AppIntents
import SwiftData

struct GetServerStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Server Status"
    static let description = IntentDescription("Reports whether the server is online and how many players are on it.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = SwiftDataStack.shared.container.mainContext
        var descriptor = FetchDescriptor<ServerSnapshot>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first else {
            return .result(value: "Unknown", dialog: "I don't have any monitoring data yet.")
        }

        if latest.isOnline {
            let summary = "The server is online with \(latest.playerCount)/\(latest.maxPlayers) players on \(latest.mapName)."
            return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
        } else {
            let summary = "The server appears to be offline."
            return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
        }
    }
}

struct OverseerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetServerStatusIntent(),
            phrases: [
                "Check \(.applicationName) status",
                "Is the server online in \(.applicationName)",
                "Server player count in \(.applicationName)"
            ],
            shortTitle: "Server Status",
            systemImageName: "server.rack"
        )
    }
}
