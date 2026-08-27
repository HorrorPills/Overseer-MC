//
//  AnalyticsEngine.swift
//  Overseer
//
//  Pure, side-effect-free analytics over arrays of `ServerSnapshot`.
//  Deliberately takes plain arrays rather than a ModelContext so it's
//  trivial to unit test and to reuse from both the dashboard (recent
//  window) and the historical charts (arbitrary ranges).
//
//  Every time-of-day / day-of-week calculation is anchored to
//  Europe/Warsaw (CET/CEST) — the original deployment's audience
//  timezone. Change `warsawCalendar` below if your players are
//  elsewhere.
//

import Foundation

enum AnalyticsEngine {

    static let warsawTimeZone = TimeZone(identifier: "Europe/Warsaw")!

    static var warsawCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = warsawTimeZone
        return calendar
    }

    // MARK: - Historical downsampling

    struct DownsampledPoint: Identifiable, Equatable {
        var id: Date { timestamp }
        var timestamp: Date
        var averagePlayers: Double
        var averagePing: Double
        var maxPlayerCount: Int
        var sampleCount: Int
    }

    enum TimeRange: String, CaseIterable, Identifiable {
        case last24Hours = "24 Hours"
        case last7Days = "7 Days"
        case last30Days = "30 Days"
        case allTime = "All-Time"

        var id: String { rawValue }

        func startDate(relativeTo now: Date = .now) -> Date? {
            switch self {
            case .last24Hours: return Calendar.current.date(byAdding: .hour, value: -24, to: now)
            case .last7Days: return Calendar.current.date(byAdding: .day, value: -7, to: now)
            case .last30Days: return Calendar.current.date(byAdding: .day, value: -30, to: now)
            case .allTime: return nil
            }
        }
    }

    /// Filters `snapshots` to `range` and downsamples to a resolution
    /// appropriate for smooth chart rendering: 5-minute buckets for
    /// 24H, hourly for 7D, daily for 30D/All-Time.
    static func chartPoints(for range: TimeRange, snapshots: [ServerSnapshot], now: Date = .now) -> [DownsampledPoint] {
        let filtered: [ServerSnapshot]
        if let start = range.startDate(relativeTo: now) {
            filtered = snapshots.filter { $0.timestamp >= start }
        } else {
            filtered = snapshots
        }
        switch range {
        case .last24Hours: return downsample(filtered, bucketSeconds: 5 * 60)
        case .last7Days: return downsample(filtered, calendarComponent: .hour)
        case .last30Days, .allTime: return downsample(filtered, calendarComponent: .day)
        }
    }

    /// Fixed-width time buckets (used for the 24H view, where calendar
    /// alignment doesn't matter — we just want smooth 5-minute steps).
    static func downsample(_ snapshots: [ServerSnapshot], bucketSeconds: TimeInterval) -> [DownsampledPoint] {
        var buckets: [TimeInterval: [ServerSnapshot]] = [:]
        for snapshot in snapshots {
            let key = (snapshot.timestamp.timeIntervalSinceReferenceDate / bucketSeconds).rounded(.down) * bucketSeconds
            buckets[key, default: []].append(snapshot)
        }
        return buckets
            .map { makePoint(timestamp: Date(timeIntervalSinceReferenceDate: $0.key), group: $0.value) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Calendar-aligned buckets (Europe/Warsaw) — used for hourly/daily
    /// rollups so bucket boundaries line up with human-meaningful hours
    /// and midnights rather than an arbitrary epoch offset.
    static func downsample(_ snapshots: [ServerSnapshot], calendarComponent: Calendar.Component, timeZone: TimeZone = warsawTimeZone) -> [DownsampledPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var buckets: [Date: [ServerSnapshot]] = [:]
        for snapshot in snapshots {
            let start = calendar.dateInterval(of: calendarComponent, for: snapshot.timestamp)?.start ?? snapshot.timestamp
            buckets[start, default: []].append(snapshot)
        }
        return buckets
            .map { makePoint(timestamp: $0.key, group: $0.value) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private static func makePoint(timestamp: Date, group: [ServerSnapshot]) -> DownsampledPoint {
        let online = group.filter { $0.isOnline }
        let avgPlayers = online.isEmpty ? 0 : Double(online.reduce(0) { $0 + $1.playerCount }) / Double(online.count)
        let avgPing = online.isEmpty ? 0 : Double(online.reduce(0) { $0 + $1.pingMs }) / Double(online.count)
        let maxPlayers = group.map(\.maxPlayers).max() ?? 0
        return DownsampledPoint(
            timestamp: timestamp,
            averagePlayers: avgPlayers,
            averagePing: avgPing,
            maxPlayerCount: maxPlayers,
            sampleCount: group.count
        )
    }

    // MARK: - 168-hour weekly activity matrix

    /// One cell of the Sun–Sat × 00–23 heatmap. `weekday` follows
    /// `Calendar`'s convention (1 = Sunday ... 7 = Saturday), evaluated
    /// in Europe/Warsaw local time.
    struct HourlyActivity: Identifiable, Equatable {
        var id: Int { weekday * 24 + hour }
        var weekday: Int
        var hour: Int
        var averagePlayers: Double
        /// Lowest concurrent player count ever actually observed in this
        /// bucket (across every week of history) — the real floor, not
        /// just a low average. Feeds `advertisingWindowSuggestions`' goal
        /// of never recommending a slot that has genuinely shown 0
        /// players before, even if its average looks fine.
        var minPlayers: Int
        var sampleCount: Int
    }

    static func weeklyActivityMatrix(from snapshots: [ServerSnapshot]) -> [HourlyActivity] {
        var sums: [Int: Double] = [:]
        var mins: [Int: Int] = [:]
        var counts: [Int: Int] = [:]
        let calendar = warsawCalendar

        for snapshot in snapshots where snapshot.isOnline {
            let comps = calendar.dateComponents([.weekday, .hour], from: snapshot.timestamp)
            guard let weekday = comps.weekday, let hour = comps.hour else { continue }
            let key = weekday * 24 + hour
            sums[key, default: 0] += Double(snapshot.playerCount)
            mins[key] = min(mins[key] ?? Int.max, snapshot.playerCount)
            counts[key, default: 0] += 1
        }

        var matrix: [HourlyActivity] = []
        matrix.reserveCapacity(168)
        for weekday in 1...7 {
            for hour in 0..<24 {
                let key = weekday * 24 + hour
                let count = counts[key] ?? 0
                let average = count > 0 ? (sums[key] ?? 0) / Double(count) : 0
                let minimum = count > 0 ? (mins[key] ?? 0) : 0
                matrix.append(HourlyActivity(weekday: weekday, hour: hour, averagePlayers: average, minPlayers: minimum, sampleCount: count))
            }
        }
        return matrix
    }

    // MARK: - Traffic velocity

    struct VelocityReport: Equatable {
        /// Players per minute, net change over each trailing window.
        var last15Minutes: Double?
        var last30Minutes: Double?
        var last60Minutes: Double?
    }

    /// dPlayers/dTime over the trailing `windowMinutes`, in players per
    /// minute. `snapshots` must be sorted ascending by timestamp.
    static func velocity(snapshots: [ServerSnapshot], windowMinutes: Double) -> Double? {
        guard let latest = snapshots.last(where: { $0.isOnline }) else { return nil }
        let targetTime = latest.timestamp.addingTimeInterval(-windowMinutes * 60)
        guard let past = snapshots.last(where: { $0.isOnline && $0.timestamp <= targetTime }) else { return nil }
        let dtMinutes = latest.timestamp.timeIntervalSince(past.timestamp) / 60
        guard dtMinutes > 0 else { return nil }
        return Double(latest.playerCount - past.playerCount) / dtMinutes
    }

    static func velocityReport(snapshots: [ServerSnapshot]) -> VelocityReport {
        VelocityReport(
            last15Minutes: velocity(snapshots: snapshots, windowMinutes: 15),
            last30Minutes: velocity(snapshots: snapshots, windowMinutes: 30),
            last60Minutes: velocity(snapshots: snapshots, windowMinutes: 60)
        )
    }

    // MARK: - Uptime

    struct UptimeSummary: Equatable {
        /// 0...100. Defaults to 100 for an empty window rather than 0 —
        /// "no data yet" shouldn't read as "the server was down."
        var percentage: Double
        var totalDowntimeSeconds: Double
        var longestOutageSeconds: Double
    }

    /// Time-weighted uptime over `[start, now]`, NOT a fraction of
    /// samples: `PollingCoordinator` backs off to longer and longer
    /// intervals between polls while the server stays unreachable, so a
    /// failed sample represents far more elapsed wall-clock time than a
    /// healthy one at the normal poll interval. Counting samples would
    /// systematically understate downtime; instead, each snapshot's
    /// online/offline status is attributed to the time elapsed until the
    /// *next* snapshot (or `now`, for the last one).
    static func uptimeSummary(snapshots: [ServerSnapshot], since start: Date, now: Date = .now) -> UptimeSummary {
        let windowed = snapshots.filter { $0.timestamp >= start }.sorted { $0.timestamp < $1.timestamp }
        guard !windowed.isEmpty else {
            return UptimeSummary(percentage: 100, totalDowntimeSeconds: 0, longestOutageSeconds: 0)
        }

        var upSeconds: Double = 0
        var downSeconds: Double = 0
        var longestOutage: Double = 0
        var currentOutage: Double = 0

        for (index, snapshot) in windowed.enumerated() {
            let intervalEnd = index + 1 < windowed.count ? windowed[index + 1].timestamp : now
            let duration = max(0, intervalEnd.timeIntervalSince(snapshot.timestamp))
            if snapshot.isOnline {
                upSeconds += duration
                longestOutage = max(longestOutage, currentOutage)
                currentOutage = 0
            } else {
                downSeconds += duration
                currentOutage += duration
            }
        }
        longestOutage = max(longestOutage, currentOutage)

        let total = upSeconds + downSeconds
        let percentage = total > 0 ? (upSeconds / total) * 100 : 100
        return UptimeSummary(percentage: percentage, totalDowntimeSeconds: downSeconds, longestOutageSeconds: longestOutage)
    }

    /// One hour-wide cell of the rolling 24-hour uptime strip shown on
    /// the dashboard. Unlike `uptimeSummary` above, this is a simple
    /// sample fraction (not time-weighted) — over a single hour the
    /// backoff-skew it corrects for is negligible, and a plain fraction
    /// is the standard, easily-understood status-page convention.
    struct UptimeBucket: Identifiable, Equatable {
        var id: Date { hourStart }
        var hourStart: Date
        var percentage: Double
        var hasData: Bool
    }

    /// `hours` consecutive hour-aligned buckets ending at the top of the
    /// hour containing `now`. A hard-coded 3600s wall interval per
    /// bucket, not a calendar-day-anchored `Calendar.dateInterval`, since
    /// this is a rolling "last N hours" strip, not "today's hours."
    static func hourlyUptimeBuckets(snapshots: [ServerSnapshot], hours: Int = 24, now: Date = .now) -> [UptimeBucket] {
        let calendar = Calendar.current
        let alignedNow = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: 0, second: 0, of: now
        ) ?? now

        return (0..<hours).map { offset in
            let bucketStart = calendar.date(byAdding: .hour, value: offset - (hours - 1), to: alignedNow) ?? alignedNow
            let bucketEnd = calendar.date(byAdding: .hour, value: 1, to: bucketStart) ?? bucketStart.addingTimeInterval(3600)
            let inBucket = snapshots.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }
            guard !inBucket.isEmpty else {
                return UptimeBucket(hourStart: bucketStart, percentage: 0, hasData: false)
            }
            let upCount = inBucket.filter(\.isOnline).count
            return UptimeBucket(hourStart: bucketStart, percentage: Double(upCount) / Double(inBucket.count) * 100, hasData: true)
        }
    }

    // MARK: - Peak / average player count

    static func peakPlayerCount(snapshots: [ServerSnapshot], since start: Date) -> Int {
        snapshots.filter { $0.timestamp >= start && $0.isOnline }.map(\.playerCount).max() ?? 0
    }

    static func averagePlayerCount(snapshots: [ServerSnapshot], since start: Date) -> Double {
        let online = snapshots.filter { $0.timestamp >= start && $0.isOnline }
        guard !online.isEmpty else { return 0 }
        return Double(online.reduce(0) { $0 + $1.playerCount }) / Double(online.count)
    }

    static func averagePing(snapshots: [ServerSnapshot], since start: Date) -> Double {
        let online = snapshots.filter { $0.timestamp >= start && $0.isOnline && $0.pingMs >= 0 }
        guard !online.isEmpty else { return 0 }
        return Double(online.reduce(0) { $0 + $1.pingMs }) / Double(online.count)
    }

    // MARK: - Ping percentiles

    struct PingPercentiles: Equatable {
        var p50: Double
        var p95: Double
    }

    /// A flat average hides "fine most of the time, brutal for 20
    /// minutes every evening" — p95 surfaces that a plain mean can't.
    static func pingPercentiles(snapshots: [ServerSnapshot], since start: Date) -> PingPercentiles {
        let pings = snapshots
            .filter { $0.timestamp >= start && $0.isOnline && $0.pingMs >= 0 }
            .map { Double($0.pingMs) }
            .sorted()
        guard !pings.isEmpty else { return PingPercentiles(p50: 0, p95: 0) }
        func percentile(_ p: Double) -> Double {
            let index = Int((p * Double(pings.count - 1)).rounded())
            return pings[min(max(index, 0), pings.count - 1)]
        }
        return PingPercentiles(p50: percentile(0.5), p95: percentile(0.95))
    }

    // MARK: - Outage events

    struct OutageEvent: Identifiable, Equatable {
        var id: Date { start }
        var start: Date
        var end: Date
        var durationSeconds: Double

        /// Short gaps are almost always a scheduled restart script
        /// cycling the server, not a real crash — 3 minutes comfortably
        /// covers a normal vanilla `/stop` + relaunch.
        var isLikelyScheduledRestart: Bool { durationSeconds <= 180 }
    }

    /// Individual up→down→up transitions within the window, most recent
    /// first — the event-level counterpart to `uptimeSummary`'s
    /// aggregate percentage.
    static func outageEvents(snapshots: [ServerSnapshot], since start: Date, now: Date = .now) -> [OutageEvent] {
        let windowed = snapshots.filter { $0.timestamp >= start }.sorted { $0.timestamp < $1.timestamp }
        guard !windowed.isEmpty else { return [] }

        var events: [OutageEvent] = []
        var outageStart: Date?

        for snapshot in windowed {
            if !snapshot.isOnline {
                if outageStart == nil { outageStart = snapshot.timestamp }
            } else if let outageBegan = outageStart {
                events.append(OutageEvent(start: outageBegan, end: snapshot.timestamp, durationSeconds: snapshot.timestamp.timeIntervalSince(outageBegan)))
                outageStart = nil
            }
        }
        if let outageBegan = outageStart {
            events.append(OutageEvent(start: outageBegan, end: now, durationSeconds: now.timeIntervalSince(outageBegan)))
        }
        return events.sorted { $0.start > $1.start }
    }

    // MARK: - Advertising window predictor

    struct AdWindowSuggestion: Identifiable, Equatable {
        var id: String { "\(weekday)-\(startHour)-\(endHour)" }
        var weekday: Int
        var startHour: Int
        var endHour: Int
        /// Mean concurrent players across the window — the primary
        /// ranking signal. A bump/listing site visitor sees whatever the
        /// server happens to show at the moment they click, so "usually
        /// busy" beats "occasionally spikes."
        var averagePlayers: Double
        /// The lowest concurrent count this window has ever actually
        /// shown, across every week of history — i.e. worst case, has
        /// this slot ever listed 0 (or close to it)? Surfaced alongside
        /// the average specifically so a window that looks good on
        /// average but has a real risk of showing up empty isn't
        /// recommended blind.
        var minimumPlayersObserved: Int
        var label: String
    }

    /// Finds the highest-traffic `windowHours`-wide slots in the week —
    /// i.e. when the server is actually most likely to be visibly
    /// populated the moment someone clicks a bump/listing link, not
    /// when traffic is *growing* fastest (a steep ramp from 0→2 players
    /// ranked above a steady 6-player evening would recommend
    /// advertising into a near-empty server, exactly the "0 players on
    /// the ad banner" outcome this exists to avoid).
    ///
    /// `laggyHourKeys` (see `laggyHourKeys(from:)`) still excludes any
    /// window touching an hour where the server has historically
    /// struggled to keep up — a new visitor's first impression
    /// shouldn't be a lagging server. `minSampleCount` guards against
    /// recommending a slot backed by only one or two historical
    /// readings. Overlapping windows are suppressed greedily (highest-
    /// ranked wins) so the results aren't just the same peak hour
    /// reported three times with a one-hour shift.
    static func advertisingWindowSuggestions(
        from matrix: [HourlyActivity],
        windowHours: Int = 2,
        topN: Int = 5,
        minSampleCount: Int = 3,
        referenceDate: Date = .now,
        laggyHourKeys: Set<Int> = []
    ) -> [AdWindowSuggestion] {
        let candidates = peakWindowCandidates(from: matrix, windowHours: windowHours, minSampleCount: minSampleCount, laggyHourKeys: laggyHourKeys)
        let ranked = candidates.sorted {
            $0.averagePlayers != $1.averagePlayers ? $0.averagePlayers > $1.averagePlayers : $0.minPlayers > $1.minPlayers
        }
        let selected = selectNonOverlapping(ranked, limit: topN)
        return selected.map(makeSuggestion(referenceDate: referenceDate))
    }

    private struct WindowCandidate {
        var weekday: Int
        var start: Int
        var end: Int
        var averagePlayers: Double
        var minPlayers: Int
    }

    private static func peakWindowCandidates(
        from matrix: [HourlyActivity],
        windowHours: Int,
        minSampleCount: Int,
        laggyHourKeys: Set<Int>
    ) -> [WindowCandidate] {
        guard windowHours >= 1, windowHours <= 24 else { return [] }
        var candidates: [WindowCandidate] = []

        for weekday in 1...7 {
            let hours = matrix.filter { $0.weekday == weekday }.sorted { $0.hour < $1.hour }
            guard hours.count == 24 else { continue }

            for start in 0...(24 - windowHours) {
                let window = hours[start..<(start + windowHours)]
                guard window.allSatisfy({ $0.sampleCount >= minSampleCount }) else { continue }
                guard !window.contains(where: { laggyHourKeys.contains(weekday * 24 + $0.hour) }) else { continue }
                let average = window.reduce(0.0) { $0 + $1.averagePlayers } / Double(windowHours)
                let minimum = window.map(\.minPlayers).min() ?? 0
                candidates.append(WindowCandidate(weekday: weekday, start: start, end: start + windowHours, averagePlayers: average, minPlayers: minimum))
            }
        }
        return candidates
    }

    private static func selectNonOverlapping(_ ranked: [WindowCandidate], limit: Int) -> [WindowCandidate] {
        var selected: [WindowCandidate] = []
        for candidate in ranked {
            let overlapsExisting = selected.contains { existing in
                existing.weekday == candidate.weekday && existing.start < candidate.end && candidate.start < existing.end
            }
            guard !overlapsExisting else { continue }
            selected.append(candidate)
            if selected.count == limit { break }
        }
        return selected
    }

    private static func makeSuggestion(referenceDate: Date) -> (WindowCandidate) -> AdWindowSuggestion {
        { candidate in
            let dayName = warsawCalendar.weekdaySymbols[candidate.weekday - 1]
            let tzAbbreviation = timeZoneAbbreviation(forWeekday: candidate.weekday, hour: candidate.start, referenceDate: referenceDate)
            let label = "\(dayName) \(formatHour(candidate.start))–\(formatHour(candidate.end)) \(tzAbbreviation) · " +
                "avg \(String(format: "%.1f", candidate.averagePlayers)) online, rarely below \(candidate.minPlayers)"
            return AdWindowSuggestion(
                weekday: candidate.weekday,
                startHour: candidate.start,
                endHour: candidate.end,
                averagePlayers: candidate.averagePlayers,
                minimumPlayersObserved: candidate.minPlayers,
                label: label
            )
        }
    }

    /// weekday*24+hour keys (Europe/Warsaw) where average MSPT across
    /// `TickSample` readings in that bucket exceeds `threshold` (default
    /// 50ms — the same 20-TPS floor `MSPTChart` marks). Feeds
    /// `advertisingWindowSuggestions` so it never recommends a slot the
    /// server has historically struggled to keep up with.
    static func laggyHourKeys(from tickSamples: [TickSample], threshold: Double = 50) -> Set<Int> {
        var sums: [Int: Double] = [:]
        var counts: [Int: Int] = [:]
        let calendar = warsawCalendar
        for sample in tickSamples {
            let comps = calendar.dateComponents([.weekday, .hour], from: sample.timestamp)
            guard let weekday = comps.weekday, let hour = comps.hour else { continue }
            let key = weekday * 24 + hour
            sums[key, default: 0] += sample.mspt
            counts[key, default: 0] += 1
        }
        var laggy: Set<Int> = []
        for (key, count) in counts where count > 0 {
            if (sums[key] ?? 0) / Double(count) > threshold {
                laggy.insert(key)
            }
        }
        return laggy
    }

    private static func formatHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour % 24)
    }

    /// Resolves whether a given (weekday, hour) in Europe/Warsaw falls
    /// in CET or CEST by projecting forward to the next real calendar
    /// date matching it.
    private static func timeZoneAbbreviation(forWeekday weekday: Int, hour: Int, referenceDate: Date) -> String {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        let calendar = warsawCalendar
        let date = calendar.nextDate(after: referenceDate, matching: components, matchingPolicy: .nextTime) ?? referenceDate
        return warsawTimeZone.isDaylightSavingTime(for: date) ? "CEST" : "CET"
    }
}
