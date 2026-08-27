//
//  PlayerStatsEngine.swift
//  Overseer
//
//  Pure, side-effect-free stats over one player's `[PlayerSession]`,
//  mirroring AnalyticsEngine's split between "pure computation" and
//  "SwiftUI reads it via @Query" — trivial to unit test, and reusable
//  from both PlayerDetailView and (eventually) any per-player widget.
//

import Foundation

enum PlayerStatsEngine {

    struct Summary: Equatable {
        var totalPlaytimeSeconds: Double
        /// Only sessions with a recorded duration (i.e. closed ones) —
        /// the currently-open session, if any, isn't counted yet.
        var closedSessionCount: Int
        var averageSessionSeconds: Double
        var longestSessionSeconds: Double
        /// Sessions opened per week since `firstSeen`.
        var averageSessionsPerWeek: Double
        /// Playtime per calendar day since `firstSeen`.
        var averagePlaytimePerDaySeconds: Double
        var daysSinceFirstSeen: Int
    }

    /// - Parameters:
    ///   - sessions: every session (open or closed) for the player.
    ///   - totalPlaytimeSeconds: `Player.playTimeSeconds` — the
    ///     authoritative rollup, kept in lockstep with closed sessions
    ///     by PollingCoordinator rather than resummed here.
    static func summary(
        sessions: [PlayerSession],
        firstSeen: Date,
        totalPlaytimeSeconds: Double,
        now: Date = .now
    ) -> Summary {
        let closedDurations = sessions.compactMap(\.durationSeconds)
        let closedCount = closedDurations.count
        let averageSession = closedCount > 0 ? totalPlaytimeSeconds / Double(closedCount) : 0
        let longestSession = closedDurations.max() ?? 0

        let daysSinceFirstSeen = max(1, Calendar.current.dateComponents([.day], from: firstSeen, to: now).day ?? 1)
        let weeksSinceFirstSeen = max(1.0 / 7.0, Double(daysSinceFirstSeen) / 7.0)

        return Summary(
            totalPlaytimeSeconds: totalPlaytimeSeconds,
            closedSessionCount: closedCount,
            averageSessionSeconds: averageSession,
            longestSessionSeconds: longestSession,
            averageSessionsPerWeek: Double(sessions.count) / weeksSinceFirstSeen,
            averagePlaytimePerDaySeconds: totalPlaytimeSeconds / Double(daysSinceFirstSeen),
            daysSinceFirstSeen: daysSinceFirstSeen
        )
    }

    /// Average cumulative playtime across players who have actually
    /// played (zero-playtime players — e.g. someone who joined once and
    /// immediately left mid-poll-interval — are excluded rather than
    /// dragging the average toward zero).
    static func averagePlaytimeSeconds(players: [Player]) -> Double {
        let withPlaytime = players.filter { $0.playTimeSeconds > 0 }
        guard !withPlaytime.isEmpty else { return 0 }
        return withPlaytime.reduce(0) { $0 + $1.playTimeSeconds } / Double(withPlaytime.count)
    }

    // MARK: - Retention

    struct RetentionSummary: Equatable {
        /// % of players with any recorded playtime who have more than
        /// one closed session — i.e. actually came back, rather than
        /// playing once and never again.
        var returningPlayerRate: Double
        /// Of players who first joined at least 30 days ago, % last
        /// seen within the last 30 days — a classic "did they stick
        /// around" cohort metric.
        var activeRate30Days: Double
        var eligibleCohortSize: Int
    }

    static func retentionSummary(players: [Player], now: Date = .now) -> RetentionSummary {
        let withPlaytime = players.filter { $0.playTimeSeconds > 0 }
        let returning = withPlaytime.filter { $0.sessions.compactMap(\.durationSeconds).count > 1 }
        let returningRate = withPlaytime.isEmpty ? 0 : Double(returning.count) / Double(withPlaytime.count) * 100

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let eligibleCohort = withPlaytime.filter { $0.firstSeen <= thirtyDaysAgo }
        let stillActive = eligibleCohort.filter { $0.lastSeen >= thirtyDaysAgo }
        let activeRate = eligibleCohort.isEmpty ? 0 : Double(stillActive.count) / Double(eligibleCohort.count) * 100

        return RetentionSummary(returningPlayerRate: returningRate, activeRate30Days: activeRate, eligibleCohortSize: eligibleCohort.count)
    }

    // MARK: - Per-player login-time fingerprint

    /// One cell of a single player's own 168-hour "when do they usually
    /// log on" matrix — the per-player counterpart to
    /// AnalyticsEngine.HourlyActivity, bucketed by session *start* time
    /// rather than snapshot-sampled concurrent count (a player has no
    /// "concurrent players" of their own, just join times).
    struct HourlyLoginFrequency: Identifiable, Equatable {
        var id: Int { weekday * 24 + hour }
        var weekday: Int
        var hour: Int
        var sessionCount: Int
    }

    static func weeklyLoginFrequency(sessions: [PlayerSession], calendar: Calendar = AnalyticsEngine.warsawCalendar) -> [HourlyLoginFrequency] {
        var counts: [Int: Int] = [:]
        for session in sessions {
            let comps = calendar.dateComponents([.weekday, .hour], from: session.startTime)
            guard let weekday = comps.weekday, let hour = comps.hour else { continue }
            counts[weekday * 24 + hour, default: 0] += 1
        }
        var matrix: [HourlyLoginFrequency] = []
        matrix.reserveCapacity(168)
        for weekday in 1...7 {
            for hour in 0..<24 {
                matrix.append(HourlyLoginFrequency(weekday: weekday, hour: hour, sessionCount: counts[weekday * 24 + hour] ?? 0))
            }
        }
        return matrix
    }

    // MARK: - Daily playtime rollup

    struct DailyPlaytime: Identifiable, Equatable {
        var id: Date { date }
        var date: Date
        var seconds: Double
    }

    /// Buckets each closed session's full duration into the calendar
    /// day (Europe/Warsaw) its session *started* on. A session spanning
    /// midnight attributes its whole duration to the start day rather
    /// than splitting across the boundary — sessions are short enough
    /// in practice that this simplification doesn't meaningfully skew
    /// the chart, and it keeps the bucketing a single pass.
    static func dailyPlaytime(
        sessions: [PlayerSession],
        days: Int = 30,
        now: Date = .now,
        calendar: Calendar = AnalyticsEngine.warsawCalendar
    ) -> [DailyPlaytime] {
        guard days > 0, let earliestDay = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else {
            return []
        }

        var buckets: [Date: Double] = [:]
        var cursor = earliestDay
        for _ in 0..<days {
            buckets[cursor] = 0
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        for session in sessions {
            guard let duration = session.durationSeconds, session.startTime >= earliestDay else { continue }
            let day = calendar.startOfDay(for: session.startTime)
            guard buckets[day] != nil else { continue }
            buckets[day, default: 0] += duration
        }

        return buckets
            .map { DailyPlaytime(date: $0.key, seconds: $0.value) }
            .sorted { $0.date < $1.date }
    }
}
