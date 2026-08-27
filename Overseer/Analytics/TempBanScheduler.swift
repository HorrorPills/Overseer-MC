//
//  TempBanScheduler.swift
//  Overseer
//
//  Pure "has this temp-ban expired?" logic, kept separate from
//  RCONAutomationCoordinator (which owns the timer loop and dispatches
//  the real `/pardon`) so the rule is testable without a live RCON
//  connection — mirrors BroadcastScheduler / AutomationTriggers.swift.
//

import Foundation

enum TempBanScheduler {

    /// A temp-ban is due for pardon once `expiresAt` has passed and it
    /// hasn't already been pardoned (manually or by a previous loop
    /// tick).
    static func isExpired(_ ban: TempBan, now: Date = .now) -> Bool {
        !ban.pardoned && now >= ban.expiresAt
    }

    static func expired(_ bans: [TempBan], now: Date = .now) -> [TempBan] {
        bans.filter { isExpired($0, now: now) }
    }

    /// For UI display: seconds remaining, clamped to zero once past
    /// `expiresAt` (the scheduler loop just hasn't caught up yet).
    static func timeRemaining(_ ban: TempBan, now: Date = .now) -> TimeInterval {
        max(0, ban.expiresAt.timeIntervalSince(now))
    }
}
