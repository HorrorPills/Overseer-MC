//
//  ConfigChangeEvent.swift
//  Overseer
//
//  Audit trail entry for the config drift watchdog (see
//  RCONAutomationCoordinator.checkConfigDrift): a gamerule or the
//  difficulty changed between two watchdog polls. On a strictly-vanilla
//  survival server, someone flipping `mobGriefing`/`keepInventory` via
//  console/OP access is as serious as a griefing incident — this is the
//  paper trail for it.
//

import Foundation
import SwiftData

@Model
final class ConfigChangeEvent {
    var timestamp: Date

    /// The watched key, e.g. "mobGriefing", "difficulty" — matches
    /// VanillaCommands.queryGamerule's rule name, or "difficulty".
    var key: String
    var oldValue: String
    var newValue: String

    init(timestamp: Date = .now, key: String, oldValue: String, newValue: String) {
        self.timestamp = timestamp
        self.key = key
        self.oldValue = oldValue
        self.newValue = newValue
    }
}
