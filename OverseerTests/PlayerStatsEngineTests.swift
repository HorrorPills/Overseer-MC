//
//  PlayerStatsEngineTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("PlayerStatsEngine")
struct PlayerStatsEngineTests {

    @Test("Summary averages sessions and playtime over days/weeks since firstSeen")
    func summaryComputesAverages() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let firstSeen = now.addingTimeInterval(-14 * 86400) // 14 days ago -> 2 weeks

        let player = Player(username: "Alice", firstSeen: firstSeen, lastSeen: now, playTimeSeconds: 3600 * 4)
        let s1 = PlayerSession(player: player, startTime: firstSeen, endTime: firstSeen.addingTimeInterval(3600))
        let s2 = PlayerSession(player: player, startTime: firstSeen.addingTimeInterval(86400), endTime: firstSeen.addingTimeInterval(86400 + 3 * 3600))
        // One still-open session: shouldn't count toward closedSessionCount
        // or the average-session-length math (no durationSeconds yet).
        let open = PlayerSession(player: player, startTime: now)

        let summary = PlayerStatsEngine.summary(
            sessions: [s1, s2, open],
            firstSeen: firstSeen,
            totalPlaytimeSeconds: player.playTimeSeconds,
            now: now
        )

        #expect(summary.closedSessionCount == 2)
        #expect(summary.longestSessionSeconds == 3 * 3600)
        #expect(summary.averageSessionSeconds == 3600 * 4 / 2)
        // ~14 days (Calendar.current, so tolerate a DST-adjacent off-by-one
        // on whatever timezone the test happens to run in).
        #expect((13...15).contains(summary.daysSinceFirstSeen))

        let days = Double(summary.daysSinceFirstSeen)
        let weeks = days / 7
        // 3 sessions opened (incl. the still-open one) over the elapsed weeks.
        #expect(abs(summary.averageSessionsPerWeek - 3 / weeks) < 0.0001)
        #expect(abs(summary.averagePlaytimePerDaySeconds - (3600 * 4 / days)) < 0.0001)
    }

    @Test("Summary with no sessions doesn't divide by zero")
    func summaryHandlesNoSessions() {
        let now = Date()
        let summary = PlayerStatsEngine.summary(sessions: [], firstSeen: now, totalPlaytimeSeconds: 0, now: now)
        #expect(summary.closedSessionCount == 0)
        #expect(summary.averageSessionSeconds == 0)
        #expect(summary.longestSessionSeconds == 0)
        #expect(summary.averageSessionsPerWeek == 0)
        #expect(summary.daysSinceFirstSeen == 1) // clamped to at least 1 day
    }

    @Test("Daily playtime buckets closed sessions by their start-of-day, ignores the still-open session")
    func dailyPlaytimeBucketsByStartDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AnalyticsEngine.warsawTimeZone
        let now = calendar.date(from: DateComponents(year: 2025, month: 6, day: 10, hour: 12))!
        let dayMinus1 = calendar.date(byAdding: .day, value: -1, to: now)!
        let startOfDayMinus1 = calendar.startOfDay(for: dayMinus1)

        let player = Player(username: "Bob")
        let closed = PlayerSession(player: player, startTime: startOfDayMinus1.addingTimeInterval(3600), endTime: startOfDayMinus1.addingTimeInterval(3600 + 1800))
        let stillOpen = PlayerSession(player: player, startTime: now)

        let points = PlayerStatsEngine.dailyPlaytime(sessions: [closed, stillOpen], days: 3, now: now, calendar: calendar)

        #expect(points.count == 3)
        let bucket = points.first { calendar.isDate($0.date, inSameDayAs: startOfDayMinus1) }
        #expect(bucket?.seconds == 1800)
        // The still-open session contributes nothing (durationSeconds is nil).
        let todayBucket = points.first { calendar.isDate($0.date, inSameDayAs: now) }
        #expect(todayBucket?.seconds == 0)
    }

    @Test("Average playtime excludes players with zero playtime")
    func averagePlaytimeExcludesZeroPlaytimePlayers() {
        let players = [
            Player(username: "Alice", playTimeSeconds: 3600),
            Player(username: "Bob", playTimeSeconds: 7200),
            Player(username: "NeverPlayed", playTimeSeconds: 0)
        ]
        #expect(PlayerStatsEngine.averagePlaytimeSeconds(players: players) == 5400) // (3600 + 7200) / 2
    }

    @Test("Average playtime is zero when no players have any recorded playtime")
    func averagePlaytimeZeroWithNoData() {
        #expect(PlayerStatsEngine.averagePlaytimeSeconds(players: []) == 0)
        #expect(PlayerStatsEngine.averagePlaytimeSeconds(players: [Player(username: "Fresh", playTimeSeconds: 0)]) == 0)
    }

    @Test("Retention summary computes returning-player rate from closed-session counts")
    func retentionReturningPlayerRate() {
        let now = Date()
        let oneSession = Player(username: "OneAndDone", firstSeen: now, lastSeen: now, playTimeSeconds: 3600)
        oneSession.sessions = [PlayerSession(player: oneSession, startTime: now, endTime: now.addingTimeInterval(3600))]

        let regular = Player(username: "Regular", firstSeen: now, lastSeen: now, playTimeSeconds: 7200)
        regular.sessions = [
            PlayerSession(player: regular, startTime: now, endTime: now.addingTimeInterval(3600)),
            PlayerSession(player: regular, startTime: now.addingTimeInterval(86400), endTime: now.addingTimeInterval(86400 + 3600))
        ]

        let never = Player(username: "NeverPlayed", firstSeen: now, lastSeen: now, playTimeSeconds: 0)

        let summary = PlayerStatsEngine.retentionSummary(players: [oneSession, regular, never], now: now)
        #expect(summary.returningPlayerRate == 50) // 1 of 2 players-with-playtime has >1 closed session
    }

    @Test("Retention summary's 30-day active rate only considers players eligible (joined 30+ days ago)")
    func retentionActiveRate30Days() {
        let now = Date()
        let veteranActive = Player(username: "VeteranActive", firstSeen: now.addingTimeInterval(-60 * 86400), lastSeen: now.addingTimeInterval(-5 * 86400), playTimeSeconds: 3600)
        let veteranGone = Player(username: "VeteranGone", firstSeen: now.addingTimeInterval(-60 * 86400), lastSeen: now.addingTimeInterval(-45 * 86400), playTimeSeconds: 3600)
        let tooNewToCount = Player(username: "TooNew", firstSeen: now.addingTimeInterval(-2 * 86400), lastSeen: now, playTimeSeconds: 3600)

        let summary = PlayerStatsEngine.retentionSummary(players: [veteranActive, veteranGone, tooNewToCount], now: now)
        #expect(summary.eligibleCohortSize == 2) // only the two veterans are eligible
        #expect(summary.activeRate30Days == 50) // only veteranActive was seen in the last 30 days
    }

    @Test("Weekly login frequency covers 168 cells and counts sessions by their start hour/weekday")
    func weeklyLoginFrequencyBucketsCorrectly() {
        var warsawCalendar = Calendar(identifier: .gregorian)
        warsawCalendar.timeZone = AnalyticsEngine.warsawTimeZone
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 3 // a Monday
        comps.hour = 20; comps.minute = 0
        let mondayEightPM = warsawCalendar.date(from: comps)!

        let player = Player(username: "NightOwl")
        let s1 = PlayerSession(player: player, startTime: mondayEightPM, endTime: mondayEightPM.addingTimeInterval(3600))
        let s2 = PlayerSession(player: player, startTime: mondayEightPM.addingTimeInterval(60), endTime: mondayEightPM.addingTimeInterval(3660))

        let matrix = PlayerStatsEngine.weeklyLoginFrequency(sessions: [s1, s2], calendar: warsawCalendar)
        #expect(matrix.count == 168)
        let mondayComps = warsawCalendar.dateComponents([.weekday, .hour], from: mondayEightPM)
        let cell = matrix.first { $0.weekday == mondayComps.weekday && $0.hour == mondayComps.hour }!
        #expect(cell.sessionCount == 2)
    }

    @Test("Daily playtime returns exactly `days` buckets, oldest first")
    func dailyPlaytimeBucketCountAndOrder() {
        let now = Date()
        let points = PlayerStatsEngine.dailyPlaytime(sessions: [], days: 7, now: now)
        #expect(points.count == 7)
        #expect(points == points.sorted { $0.date < $1.date })
    }
}
