//
//  AnalyticsEngineTests.swift
//  OverseerTests
//

import Testing
import Foundation
@testable import Overseer

@Suite("AnalyticsEngine")
struct AnalyticsEngineTests {

    private func snapshot(minutesAgo: Double, players: Int, ping: Int = 40, isOnline: Bool = true, from reference: Date) -> ServerSnapshot {
        ServerSnapshot(
            timestamp: reference.addingTimeInterval(-minutesAgo * 60),
            playerCount: players,
            pingMs: ping,
            maxPlayers: 40,
            mapName: "world",
            isOnline: isOnline
        )
    }

    @Test("Velocity reports positive players/minute for a ramping-up server")
    func velocityDetectsGrowth() {
        let now = Date()
        let snapshots = [
            snapshot(minutesAgo: 60, players: 2, from: now),
            snapshot(minutesAgo: 30, players: 8, from: now),
            snapshot(minutesAgo: 15, players: 12, from: now),
            snapshot(minutesAgo: 0, players: 20, from: now)
        ].sorted { $0.timestamp < $1.timestamp }

        let report = AnalyticsEngine.velocityReport(snapshots: snapshots)
        #expect(report.last15Minutes! > 0)
        #expect(report.last30Minutes! > 0)
        #expect(report.last60Minutes! > 0)
        // 20 players now vs 2 an hour ago = 18 players / 60 min = 0.3/min
        #expect(abs(report.last60Minutes! - 0.3) < 0.01)
    }

    @Test("Velocity is nil with insufficient history")
    func velocityNilWithoutHistory() {
        let now = Date()
        let snapshots = [snapshot(minutesAgo: 0, players: 5, from: now)]
        let report = AnalyticsEngine.velocityReport(snapshots: snapshots)
        #expect(report.last15Minutes == nil)
        #expect(report.last30Minutes == nil)
        #expect(report.last60Minutes == nil)
    }

    @Test("Downsampling into 5-minute buckets preserves total sample count")
    func downsamplePreservesSampleCount() {
        let now = Date()
        let snapshots = (0..<24).map { i in
            snapshot(minutesAgo: Double(i) * 5, players: i % 6, from: now)
        }
        let points = AnalyticsEngine.downsample(snapshots, bucketSeconds: 300)
        let totalSamples = points.reduce(0) { $0 + $1.sampleCount }
        #expect(totalSamples == snapshots.count)
        // Ascending order.
        #expect(points == points.sorted { $0.timestamp < $1.timestamp })
    }

    @Test("Weekly activity matrix has exactly 168 cells covering every weekday/hour")
    func weeklyMatrixShape() {
        let matrix = AnalyticsEngine.weeklyActivityMatrix(from: [])
        #expect(matrix.count == 168)
        let weekdays = Set(matrix.map(\.weekday))
        #expect(weekdays == Set(1...7))
        for weekday in 1...7 {
            let hours = Set(matrix.filter { $0.weekday == weekday }.map(\.hour))
            #expect(hours == Set(0..<24))
        }
    }

    @Test("Weekly activity matrix averages only online snapshots, in Europe/Warsaw local time")
    func weeklyMatrixAveragesCorrectly() {
        var warsawCalendar = Calendar(identifier: .gregorian)
        warsawCalendar.timeZone = AnalyticsEngine.warsawTimeZone

        // Pin a known Monday 10:00 Warsaw time.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 3 // a Monday
        comps.hour = 10; comps.minute = 0
        let mondayTenAM = warsawCalendar.date(from: comps)!

        let snapshots = [
            ServerSnapshot(timestamp: mondayTenAM, playerCount: 10, pingMs: 30, maxPlayers: 40, mapName: "world", isOnline: true),
            ServerSnapshot(timestamp: mondayTenAM.addingTimeInterval(60), playerCount: 20, pingMs: 30, maxPlayers: 40, mapName: "world", isOnline: true),
            ServerSnapshot(timestamp: mondayTenAM.addingTimeInterval(120), playerCount: 999, pingMs: -1, maxPlayers: 40, mapName: "world", isOnline: false)
        ]

        let matrix = AnalyticsEngine.weeklyActivityMatrix(from: snapshots)
        let mondayComponents = warsawCalendar.dateComponents([.weekday, .hour], from: mondayTenAM)
        let cell = matrix.first { $0.weekday == mondayComponents.weekday && $0.hour == mondayComponents.hour }!

        #expect(cell.sampleCount == 2) // the offline snapshot must be excluded
        #expect(cell.averagePlayers == 15) // (10 + 20) / 2
    }

    @Test("Ad window predictor surfaces Monday's highest-average-traffic window with a Poland-time label")
    func advertisingWindowSuggestion() {
        // Build a matrix where Monday ramps steadily from 0 at 00:00 to
        // a peak at 18:00 then falls off. The predictor ranks by average
        // concurrent players (see AnalyticsEngine.advertisingWindowSuggestions),
        // so it should land on the window right around that peak, not
        // the whole ramp.
        var cells: [AnalyticsEngine.HourlyActivity] = []
        for weekday in 1...7 {
            for hour in 0..<24 {
                let average: Double
                if weekday == 2 { // Monday
                    average = hour <= 18 ? Double(hour) : Double(36 - hour)
                } else {
                    average = 5 // flat, no growth run
                }
                cells.append(.init(weekday: weekday, hour: hour, averagePlayers: average, minPlayers: Int(average), sampleCount: 10))
            }
        }

        let suggestions = AnalyticsEngine.advertisingWindowSuggestions(from: cells, topN: 3)
        #expect(!suggestions.isEmpty)
        let monday = suggestions.first { $0.weekday == 2 }
        #expect(monday != nil)
        #expect(monday!.startHour == 17)
        #expect(monday!.endHour == 19)
        #expect(monday!.label.contains("avg"))
        #expect(monday!.label.contains("CET") || monday!.label.contains("CEST"))
    }

    @Test("Uptime is 100% for an all-online window")
    func uptimeAllOnline() {
        let now = Date()
        let snapshots = [
            snapshot(minutesAgo: 60, players: 5, from: now),
            snapshot(minutesAgo: 30, players: 5, from: now),
            snapshot(minutesAgo: 0, players: 5, from: now)
        ]
        let summary = AnalyticsEngine.uptimeSummary(snapshots: snapshots, since: now.addingTimeInterval(-3600), now: now)
        #expect(summary.percentage == 100)
        #expect(summary.totalDowntimeSeconds == 0)
        #expect(summary.longestOutageSeconds == 0)
    }

    @Test("Uptime is time-weighted: a single failed sample followed by a long gap counts the whole gap as downtime")
    func uptimeIsTimeWeightedNotSampleFraction() {
        let now = Date()
        // Healthy for the first half hour, then ONE failed sample that
        // stands in for a 30-minute backoff gap before recovery — a
        // naive "fraction of samples" count would call this ~67% up
        // (2 of 3 online samples); time-weighting must call it 50%.
        let snapshots = [
            snapshot(minutesAgo: 60, players: 5, isOnline: true, from: now),
            snapshot(minutesAgo: 30, players: 0, isOnline: false, from: now),
            snapshot(minutesAgo: 0, players: 5, isOnline: true, from: now)
        ]
        let summary = AnalyticsEngine.uptimeSummary(snapshots: snapshots, since: now.addingTimeInterval(-3600), now: now)
        #expect(abs(summary.percentage - 50) < 0.01)
        #expect(abs(summary.totalDowntimeSeconds - 1800) < 1)
        #expect(abs(summary.longestOutageSeconds - 1800) < 1)
    }

    @Test("Uptime defaults to 100% with no data in the window rather than reading as downtime")
    func uptimeDefaultsTo100WithNoData() {
        let now = Date()
        let summary = AnalyticsEngine.uptimeSummary(snapshots: [], since: now.addingTimeInterval(-3600), now: now)
        #expect(summary.percentage == 100)
    }

    @Test("Hourly uptime buckets cover exactly `hours` consecutive hours ending at now, oldest first")
    func hourlyUptimeBucketsShape() {
        let now = Date()
        let buckets = AnalyticsEngine.hourlyUptimeBuckets(snapshots: [], hours: 24, now: now)
        #expect(buckets.count == 24)
        #expect(buckets == buckets.sorted { $0.hourStart < $1.hourStart })
        for bucket in buckets {
            #expect(!bucket.hasData)
        }
    }

    @Test("Hourly uptime buckets mark a bucket with data using a sample fraction")
    func hourlyUptimeBucketsComputesFraction() {
        let now = Date()
        let calendar = Calendar.current
        let bucketStart = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        let snapshots = [
            ServerSnapshot(timestamp: bucketStart.addingTimeInterval(60), playerCount: 1, pingMs: 30, maxPlayers: 40, mapName: "world", isOnline: true),
            ServerSnapshot(timestamp: bucketStart.addingTimeInterval(120), playerCount: 1, pingMs: 30, maxPlayers: 40, mapName: "world", isOnline: false)
        ]
        let buckets = AnalyticsEngine.hourlyUptimeBuckets(snapshots: snapshots, hours: 24, now: now)
        let current = buckets.last! // the bucket containing `now`
        #expect(current.hasData)
        #expect(current.percentage == 50)
    }

    @Test("Peak and average player count only consider online snapshots within the window")
    func peakAndAveragePlayerCount() {
        let now = Date()
        let snapshots = [
            snapshot(minutesAgo: 90, players: 999, from: now),       // outside the 60-minute window
            snapshot(minutesAgo: 30, players: 10, from: now),
            snapshot(minutesAgo: 15, players: 20, from: now),
            snapshot(minutesAgo: 5, players: 30, isOnline: false, from: now) // offline, excluded
        ]
        let start = now.addingTimeInterval(-3600)
        #expect(AnalyticsEngine.peakPlayerCount(snapshots: snapshots, since: start) == 20)
        #expect(AnalyticsEngine.averagePlayerCount(snapshots: snapshots, since: start) == 15) // (10 + 20) / 2
    }

    @Test("Average ping ignores offline snapshots and the -1 sentinel")
    func averagePingIgnoresOfflineAndSentinel() {
        let now = Date()
        let snapshots = [
            snapshot(minutesAgo: 20, players: 5, ping: 40, from: now),
            snapshot(minutesAgo: 10, players: 5, ping: 60, from: now),
            snapshot(minutesAgo: 5, players: 0, ping: -1, isOnline: false, from: now)
        ]
        let average = AnalyticsEngine.averagePing(snapshots: snapshots, since: now.addingTimeInterval(-3600))
        #expect(average == 50)
    }

    @Test("Ping percentiles compute p50/p95 over online, non-sentinel readings only")
    func pingPercentilesComputesCorrectly() {
        let now = Date()
        // 100 readings, 40...139ms, evenly spaced -> sorted p50 ~ index 49-50, p95 ~ index 94-95.
        let snapshots = (0..<100).map { i in
            snapshot(minutesAgo: Double(99 - i), players: 5, ping: 40 + i, from: now)
        }
        let percentiles = AnalyticsEngine.pingPercentiles(snapshots: snapshots, since: now.addingTimeInterval(-200 * 60))
        #expect(abs(percentiles.p50 - 89) <= 1)
        #expect(abs(percentiles.p95 - 134) <= 1)
    }

    @Test("Ping percentiles ignore offline snapshots and the -1 sentinel")
    func pingPercentilesIgnoreOfflineAndSentinel() {
        let now = Date()
        let snapshots = [
            snapshot(minutesAgo: 10, players: 5, ping: 50, from: now),
            snapshot(minutesAgo: 5, players: 0, ping: -1, isOnline: false, from: now)
        ]
        let percentiles = AnalyticsEngine.pingPercentiles(snapshots: snapshots, since: now.addingTimeInterval(-3600))
        #expect(percentiles.p50 == 50)
        #expect(percentiles.p95 == 50)
    }

    @Test("Ping percentiles default to zero with no data")
    func pingPercentilesDefaultToZero() {
        let percentiles = AnalyticsEngine.pingPercentiles(snapshots: [], since: Date().addingTimeInterval(-3600))
        #expect(percentiles.p50 == 0)
        #expect(percentiles.p95 == 0)
    }

    @Test("Outage events pair each offline stretch with its recovery, most recent first")
    func outageEventsPairsUpDownTransitions() {
        let now = Date()
        let snapshots = [
            snapshot(minutesAgo: 60, players: 5, from: now),
            snapshot(minutesAgo: 50, players: 0, isOnline: false, from: now), // outage #1 begins
            snapshot(minutesAgo: 40, players: 5, from: now),                  // outage #1 recovers (10 min)
            snapshot(minutesAgo: 20, players: 5, from: now),
            snapshot(minutesAgo: 15, players: 0, isOnline: false, from: now), // outage #2 begins
            snapshot(minutesAgo: 10, players: 5, from: now)                   // outage #2 recovers (5 min)
        ]
        let events = AnalyticsEngine.outageEvents(snapshots: snapshots, since: now.addingTimeInterval(-3600), now: now)
        #expect(events.count == 2)
        #expect(events[0].start > events[1].start) // most recent first
        #expect(abs(events[1].durationSeconds - 600) < 1) // the older 10-minute outage
        #expect(abs(events[0].durationSeconds - 300) < 1) // the newer 5-minute outage
    }

    @Test("A short outage is classified as a likely scheduled restart; a long one is not")
    func outageClassification() {
        let now = Date()
        let restart = AnalyticsEngine.OutageEvent(start: now.addingTimeInterval(-120), end: now, durationSeconds: 120)
        let crash = AnalyticsEngine.OutageEvent(start: now.addingTimeInterval(-1200), end: now, durationSeconds: 1200)
        #expect(restart.isLikelyScheduledRestart)
        #expect(!crash.isLikelyScheduledRestart)
    }

    @Test("An outage still in progress at `now` is included with an open-ended duration")
    func outageStillInProgress() {
        let now = Date()
        let snapshots = [
            snapshot(minutesAgo: 30, players: 5, from: now),
            snapshot(minutesAgo: 10, players: 0, isOnline: false, from: now)
        ]
        let events = AnalyticsEngine.outageEvents(snapshots: snapshots, since: now.addingTimeInterval(-3600), now: now)
        #expect(events.count == 1)
        #expect(abs(events[0].durationSeconds - 600) < 1)
    }

    @Test("Advertising window predictor excludes a run that overlaps a laggy hour")
    func advertisingWindowExcludesLaggyHours() {
        var cells: [AnalyticsEngine.HourlyActivity] = []
        for weekday in 1...7 {
            for hour in 0..<24 {
                let average: Double = weekday == 2 ? (hour <= 18 ? Double(hour) : Double(36 - hour)) : 5
                cells.append(.init(weekday: weekday, hour: hour, averagePlayers: average, minPlayers: Int(average), sampleCount: 10))
            }
        }
        // Without any laggy hours, Monday's peak window is suggested as before.
        let baseline = AnalyticsEngine.advertisingWindowSuggestions(from: cells, topN: 3)
        #expect(baseline.contains { $0.weekday == 2 })

        // Mark every hour of Monday as laggy -> Monday must no longer be
        // suggested anywhere, not just in its former peak window (the
        // predictor ranks by average players, so with only the peak
        // hours excluded it would just fall back to Monday's next-best,
        // still-clean window instead of dropping the day entirely).
        let laggy = Set((0..<24).map { 2 * 24 + $0 })
        let filtered = AnalyticsEngine.advertisingWindowSuggestions(from: cells, topN: 3, laggyHourKeys: laggy)
        #expect(!filtered.contains { $0.weekday == 2 })
    }

    @Test("laggyHourKeys flags weekday/hour buckets whose average MSPT exceeds the threshold")
    func laggyHourKeysFlagsHighMSPT() {
        var warsawCalendar = Calendar(identifier: .gregorian)
        warsawCalendar.timeZone = AnalyticsEngine.warsawTimeZone
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 3 // a Monday
        comps.hour = 20; comps.minute = 0
        let mondayEightPM = warsawCalendar.date(from: comps)!

        let samples = [
            TickSample(timestamp: mondayEightPM, targetTps: 20, actualTps: 15, mspt: 65),
            TickSample(timestamp: mondayEightPM.addingTimeInterval(60), targetTps: 20, actualTps: 15, mspt: 70),
            TickSample(timestamp: mondayEightPM.addingTimeInterval(3600 * 5), targetTps: 20, actualTps: 20, mspt: 30) // a healthy, different hour
        ]
        let laggy = AnalyticsEngine.laggyHourKeys(from: samples)
        let mondayComps = warsawCalendar.dateComponents([.weekday, .hour], from: mondayEightPM)
        let key = mondayComps.weekday! * 24 + mondayComps.hour!
        #expect(laggy.contains(key))
        #expect(laggy.count == 1)
    }

    @Test("Time ranges filter snapshots to the expected window")
    func timeRangeFiltering() {
        let now = Date()
        let snapshots = [
            snapshot(minutesAgo: 60 * 24 * 40, players: 1, from: now), // 40 days ago
            snapshot(minutesAgo: 60 * 24 * 10, players: 2, from: now), // 10 days ago
            snapshot(minutesAgo: 60 * 2, players: 3, from: now)        // 2 hours ago
        ]
        let last7Days = AnalyticsEngine.chartPoints(for: .last7Days, snapshots: snapshots, now: now)
        let totalIn7Days = last7Days.reduce(0) { $0 + $1.sampleCount }
        #expect(totalIn7Days == 1) // only the "2 hours ago" snapshot

        let allTime = AnalyticsEngine.chartPoints(for: .allTime, snapshots: snapshots, now: now)
        let totalAllTime = allTime.reduce(0) { $0 + $1.sampleCount }
        #expect(totalAllTime == 3)
    }
}
