//
//  AutomationTriggers.swift
//  Overseer
//
//  Pure decision logic for the RCON automation engine — deliberately
//  separated from RCONAutomationCoordinator so "should we fire?" is
//  unit-testable without a live socket, a timer, or SwiftData. The
//  coordinator's job is just to call these and, on `true`, dispatch the
//  corresponding VanillaCommands through RCONClient.
//

import Foundation

// MARK: - Playtime milestones

enum MilestoneEvaluator {
    /// Hour thresholds that trigger a reward. 50 hours is the spec's
    /// headline milestone; the rest extend the same mechanism.
    static let thresholdsHours: [Int] = [50, 100, 250, 500, 1000]

    /// Given a player's total playtime and the milestones already
    /// awarded, returns any newly-crossed milestones (ascending). A
    /// session that jumps past multiple thresholds at once (e.g. the
    /// app was closed for a while) returns all of them, in order, so
    /// the caller can announce each.
    static func newlyCrossedMilestones(playTimeSeconds: Double, alreadyAwardedHours: Set<Int>) -> [Int] {
        let hours = Int(playTimeSeconds / 3600)
        return thresholdsHours
            .filter { $0 <= hours && !alreadyAwardedHours.contains($0) }
            .sorted()
    }
}

// MARK: - Ad-window synergy

enum AdWindowTrigger {
    /// Minimum time between automated "traffic is peaking" broadcasts,
    /// so a sustained ramp-up doesn't spam chat every poll cycle.
    static let cooldown: TimeInterval = 60 * 60 // 1 hour

    /// `velocityPerMinute` is players/minute over a short trailing
    /// window (e.g. `AnalyticsEngine.velocityReport(...).last15Minutes`).
    static func shouldBroadcast(
        velocityPerMinute: Double?,
        threshold: Double = 0.5,
        lastBroadcast: Date?,
        now: Date = .now
    ) -> Bool {
        guard let velocityPerMinute, velocityPerMinute >= threshold else { return false }
        guard let lastBroadcast else { return true }
        return now.timeIntervalSince(lastBroadcast) >= cooldown
    }
}

// MARK: - Weekend "Happy Hour"

enum HappyHourWindow {
    /// Fri/Sat/Sun evenings, Poland time — tune this window to your own
    /// server's actual peak hours.
    static let weekdays: Set<Int> = [6, 7, 1] // Calendar weekday: 1=Sun, 6=Fri, 7=Sat
    static let startHour = 18
    static let endHour = 23 // exclusive

    /// Fires at most once per calendar day within the window.
    static func shouldTrigger(now: Date, lastTriggered: Date?, calendar: Calendar = AnalyticsEngine.warsawCalendar) -> Bool {
        let comps = calendar.dateComponents([.weekday, .hour], from: now)
        guard let weekday = comps.weekday, let hour = comps.hour else { return false }
        guard weekdays.contains(weekday), hour >= startHour, hour < endHour else { return false }
        guard let lastTriggered else { return true }
        return !calendar.isDate(lastTriggered, inSameDayAs: now)
    }
}
