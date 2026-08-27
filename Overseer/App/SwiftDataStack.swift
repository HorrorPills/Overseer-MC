//
//  SwiftDataStack.swift
//  Overseer
//
//  Single shared ModelContainer, so both the SwiftUI app scene and
//  out-of-process contexts (App Intents, a future widget extension)
//  read/write the same on-disk store.
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataStack {
    static let shared = SwiftDataStack()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            ServerSnapshot.self,
            Player.self,
            PlayerSession.self,
            TickSample.self,
            ModerationEvent.self,
            BroadcastMessage.self,
            TempBan.self,
            CommandPreset.self,
            InvestigationNote.self,
            ConfigChangeEvent.self,
            PlayerPositionSample.self,
            PlayerLoginRecord.self,
            PlayerGeoLocation.self,
            ServerUpdateEvent.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }
}
