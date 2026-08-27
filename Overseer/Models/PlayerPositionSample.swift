//
//  PlayerPositionSample.swift
//  Overseer
//
//  One `/data get entity <player> Pos` reading for one online player,
//  taken at the same cadence as the RCON `/list` roster poll (see
//  RCONAutomationCoordinator.recordPositions). Builds up a world-space
//  activity map over time — where players actually spend their time,
//  independent of chunk-level perf-report hotspots — which doubles as a
//  griefing signal: a player suddenly showing up somewhere they've never
//  been is worth a second look.
//
//  Y (vertical) is deliberately not recorded — a 2D X/Z scatter is all
//  the activity map needs, and one fewer field to poll for/store.
//

import Foundation
import SwiftData

@Model
final class PlayerPositionSample {
    var timestamp: Date
    var username: String
    var x: Double
    var z: Double

    init(timestamp: Date = .now, username: String, x: Double, z: Double) {
        self.timestamp = timestamp
        self.username = username
        self.x = x
        self.z = z
    }
}
