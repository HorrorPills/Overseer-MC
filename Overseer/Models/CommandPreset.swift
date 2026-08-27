//
//  CommandPreset.swift
//  Overseer
//
//  A saved, one-click RCON command — the middle tier between the
//  built-in quick-action buttons (RCONConsoleView's hardcoded row) and
//  typing a raw command into the console. Validated against
//  VanillaCommands.isStrictlyVanilla when created (see
//  CommandPresetSheet), same as every other command path in the app.
//

import Foundation
import SwiftData

@Model
final class CommandPreset {
    var label: String
    var command: String
    var createdAt: Date

    init(label: String, command: String, createdAt: Date = .now) {
        self.label = label
        self.command = command
        self.createdAt = createdAt
    }
}
