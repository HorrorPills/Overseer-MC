//
//  BroadcastScheduler.swift
//  Overseer
//
//  Pure "is this message due?" logic for user-authored BroadcastMessage
//  rows, kept separate from RCONAutomationCoordinator (which owns the
//  actual timer loop and dispatch) so the scheduling rule is testable
//  without a live RCON connection — mirrors AutomationTriggers.swift's
//  split for the built-in triggers.
//

import Foundation

enum BroadcastScheduler {

    /// A message is due once `intervalMinutes` has elapsed since it was
    /// last sent — or immediately, the first time, since `lastSentAt`
    /// is nil until a send actually happens.
    static func isDue(_ message: BroadcastMessage, now: Date = .now) -> Bool {
        guard message.isEnabled, message.intervalMinutes > 0 else { return false }
        guard let lastSentAt = message.lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) >= message.intervalMinutes * 60
    }

    /// Filters to just the due messages, in no particular order — the
    /// caller dispatches each and stamps `lastSentAt` as it goes.
    static func due(_ messages: [BroadcastMessage], now: Date = .now) -> [BroadcastMessage] {
        messages.filter { isDue($0, now: now) }
    }

    /// For UI display: when `message` will next fire, or nil if it's
    /// disabled or has no positive interval (never fires).
    static func nextFireDate(_ message: BroadcastMessage) -> Date? {
        guard message.isEnabled, message.intervalMinutes > 0 else { return nil }
        let anchor = message.lastSentAt ?? message.createdAt
        return anchor.addingTimeInterval(message.intervalMinutes * 60)
    }
}
