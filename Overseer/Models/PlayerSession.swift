//
//  PlayerSession.swift
//  Overseer
//
//  One continuous online stretch for a player, bounded by consecutive
//  polls. Session boundary logic (open/close) lives in
//  PollingCoordinator, which diffs the GS4 player list against the set
//  of currently-open sessions on every poll:
//
//   - Name in query, no open session  -> open a new PlayerSession.
//   - Name in query, has open session -> just bump Player.lastSeen.
//   - Open session, name NOT in query -> close it (endTime = now of the
//     query where the player was last confirmed present, NOT the query
//     that noticed the absence, to avoid over-counting by one poll
//     interval).
//

import Foundation
import SwiftData

@Model
final class PlayerSession {
    var player: Player?

    var startTime: Date

    /// Nil while the session is active (player currently online).
    var endTime: Date?

    /// Populated when the session closes. Kept as a stored field (rather
    /// than always computed) so historical Gantt charts can query it
    /// without loading/resolving `startTime`/`endTime` pairs repeatedly.
    var durationSeconds: Double?

    init(player: Player?, startTime: Date = .now, endTime: Date? = nil) {
        self.player = player
        self.startTime = startTime
        self.endTime = endTime
        if let endTime {
            self.durationSeconds = endTime.timeIntervalSince(startTime)
        }
    }

    var isActive: Bool { endTime == nil }

    /// Closes the session and returns the duration added, so callers can
    /// roll it into `Player.playTimeSeconds` without a second pass.
    @discardableResult
    func close(at time: Date) -> Double {
        endTime = time
        let duration = max(0, time.timeIntervalSince(startTime))
        durationSeconds = duration
        return duration
    }
}
