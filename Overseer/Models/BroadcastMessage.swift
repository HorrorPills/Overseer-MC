//
//  BroadcastMessage.swift
//  Overseer
//
//  A user-authored chat broadcast, repeated on its own schedule via
//  vanilla `/say` — see VanillaCommands.say and
//  RCONAutomationCoordinator's broadcast scheduler loop. Deliberately
//  plain `/say` (not `/tellraw`, unlike the built-in ad-window/Happy
//  Hour broadcasts) since these are free-text messages an admin typed,
//  not app-generated JSON text components.
//

import Foundation
import SwiftData

@Model
final class BroadcastMessage {
    var text: String

    /// How often this message repeats, in minutes. Must be positive;
    /// BroadcastScheduler treats anything <= 0 as never-due.
    var intervalMinutes: Double

    /// Per-message on/off switch — disabling doesn't delete the
    /// message or its schedule, just pauses it.
    var isEnabled: Bool

    /// Nil until the first send (automatic or manual); a message with
    /// no `lastSentAt` is due immediately once enabled.
    var lastSentAt: Date?

    var createdAt: Date

    init(
        text: String,
        intervalMinutes: Double,
        isEnabled: Bool = true,
        lastSentAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.text = text
        self.intervalMinutes = intervalMinutes
        self.isEnabled = isEnabled
        self.lastSentAt = lastSentAt
        self.createdAt = createdAt
    }
}
