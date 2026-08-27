//
//  TickSample.swift
//  Overseer
//
//  One `/tick query` reading. Kept as its own model rather than folded
//  into `ServerSnapshot` since it's polled on a much slower cadence
//  (1–5 minutes, over RCON) than the GS4/SLP snapshot loop (default
//  30 seconds) and can fail/be disabled independently (RCON down while
//  Query/SLP stay up, or vice versa).
//

import Foundation
import SwiftData

@Model
final class TickSample {
    var timestamp: Date
    var targetTps: Double
    var actualTps: Double
    var mspt: Double

    init(timestamp: Date = .now, targetTps: Double, actualTps: Double, mspt: Double) {
        self.timestamp = timestamp
        self.targetTps = targetTps
        self.actualTps = actualTps
        self.mspt = mspt
    }

    /// True when the server is meaningfully behind its target tick
    /// rate — a physical-lag signal independent of network ping.
    var isLagging: Bool { actualTps < targetTps * 0.95 }
}
