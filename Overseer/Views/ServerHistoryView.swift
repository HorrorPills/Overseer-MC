//
//  ServerHistoryView.swift
//  Overseer
//
//  Renamed and rebuilt from HistoricalAnalyticsView. That page had
//  grown into eight stacked sections added incrementally over the
//  course of this project, only three of which actually responded to
//  its own range picker — the rest (retention, the weekly heatmap, ad
//  suggestions, player timelines) silently ignored it, which is exactly
//  the "not interactive, doesn't relate to the data" complaint that
//  prompted this rewrite. It also predated several major features
//  (SFTP sync, config-drift watchdog, World Map, Auto Updater) and
//  never grew to reflect any of them.
//
//  This page now answers three genuinely distinct questions Dashboard
//  (fixed 24h, "is it healthy right now") doesn't:
//   1. How has traffic/latency/tick performance trended over a
//      selectable range, and is the server actually growing? (Growth &
//      Traffic)
//   2. When is the best time to advertise, based on the server's own
//      historical pattern? (Best Times)
//   3. What actually happened — outages, config drift, deploys,
//      moderation actions — in one chronological, filterable feed?
//      (Event Timeline — new; nothing like this existed before)
//   4. Who was online at the same time as whom? (Session Overlap — kept
//      from the old page, now actually scoped by the range picker)
//
//  The old "Player Activity Map" section was cut outright — World Map
//  already shows player breadcrumbs against real terrain with a table
//  and hover coordinates; this page's flat, context-free scatter of the
//  same samples was a strictly worse duplicate. Velocity (Δ players per
//  15/30/60 min) was also cut: on a 1-4 concurrent player server it's
//  mostly noise, and "what's happening right now" already belongs on
//  Dashboard, not a page whose entire premise is looking backward.
//

import SwiftUI
import SwiftData
import Charts

struct ServerHistoryView: View {
    @Query(sort: \ServerSnapshot.timestamp) private var snapshots: [ServerSnapshot]
    @Query(sort: \PlayerSession.startTime, order: .reverse) private var allSessions: [PlayerSession]
    @Query(sort: \Player.username) private var allPlayers: [Player]
    @Query(sort: \TickSample.timestamp) private var tickSamples: [TickSample]
    @Query(sort: \ConfigChangeEvent.timestamp, order: .reverse) private var configChanges: [ConfigChangeEvent]
    @Query(sort: \ServerUpdateEvent.timestamp, order: .reverse) private var updateEvents: [ServerUpdateEvent]
    @Query(sort: \ModerationEvent.timestamp, order: .reverse) private var moderationEvents: [ModerationEvent]

    private enum TrendMetric: String, CaseIterable, Identifiable {
        case players = "Players"
        case ping = "Ping"
        case tick = "Tick (MSPT)"
        var id: String { rawValue }
    }

    @State private var selectedRange: AnalyticsEngine.TimeRange = .last7Days
    @State private var selectedMetric: TrendMetric = .players
    @State private var selectedPoint: AnalyticsEngine.DownsampledPoint?
    @State private var showDataTable = false
    @State private var selectedEventCategories: Set<ServerEventCategory> = Set(ServerEventCategory.allCases)
    @State private var selectedPlayerIDs: Set<PersistentIdentifier> = []

    // MARK: - Derived data

    private var rangeStart: Date? { selectedRange.startDate() }

    private var chartPoints: [AnalyticsEngine.DownsampledPoint] {
        AnalyticsEngine.chartPoints(for: selectedRange, snapshots: snapshots)
    }
    private var tickChartSamples: [TickSample] {
        TickProfiler.chartSamples(for: selectedRange, samples: tickSamples)
    }
    private var weeklyMatrix: [AnalyticsEngine.HourlyActivity] {
        AnalyticsEngine.weeklyActivityMatrix(from: snapshots)
    }
    private var laggyHours: Set<Int> {
        AnalyticsEngine.laggyHourKeys(from: tickSamples)
    }
    private var adSuggestions: [AnalyticsEngine.AdWindowSuggestion] {
        AnalyticsEngine.advertisingWindowSuggestions(from: weeklyMatrix, laggyHourKeys: laggyHours)
    }
    private var retention: PlayerStatsEngine.RetentionSummary {
        PlayerStatsEngine.retentionSummary(players: allPlayers)
    }
    private var newPlayersInRange: Int {
        guard let start = rangeStart else { return allPlayers.count }
        return allPlayers.filter { $0.firstSeen >= start }.count
    }
    private var outageEvents: [AnalyticsEngine.OutageEvent] {
        AnalyticsEngine.outageEvents(snapshots: snapshots, since: rangeStart ?? .distantPast)
    }
    private var timelineEntries: [ServerTimelineEntry] {
        ServerEventTimeline.build(
            outages: outageEvents,
            configChanges: configChanges,
            updates: updateEvents,
            moderation: moderationEvents,
            categories: selectedEventCategories,
            since: rangeStart
        )
    }
    private var timelineSessions: [PlayerSession] {
        let activeIDs: Set<PersistentIdentifier>
        if selectedPlayerIDs.isEmpty {
            activeIDs = Set(
                allPlayers.sorted { $0.playTimeSeconds > $1.playTimeSeconds }
                    .prefix(8)
                    .map(\.persistentModelID)
            )
        } else {
            activeIDs = selectedPlayerIDs
        }
        return allSessions.filter { session in
            guard let id = session.player?.persistentModelID, activeIDs.contains(id) else { return false }
            guard let start = rangeStart else { return true }
            let sessionEnd = session.endTime ?? .now
            return sessionEnd >= start // overlaps the selected range at all
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                rangePicker
                growthSection
                Divider()
                bestTimesSection
                Divider()
                eventTimelineSection
                Divider()
                sessionOverlapSection
            }
            .padding(20)
        }
        .navigationTitle("Server History")
    }

    // MARK: - Range picker (drives every section below)

    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(AnalyticsEngine.TimeRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
    }

    // MARK: - Growth & Traffic

    private var growthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Growth & Traffic").font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                SummaryCard(title: "New Players", value: "\(newPlayersInRange)", systemImage: "person.badge.plus", tint: .green)
                SummaryCard(
                    title: "Returning Rate (All-Time)",
                    value: String(format: "%.0f%%", retention.returningPlayerRate),
                    systemImage: "arrow.uturn.left.circle.fill",
                    tint: .blue
                )
                SummaryCard(
                    title: "30-Day Active (All-Time)",
                    value: retention.eligibleCohortSize > 0 ? String(format: "%.0f%%", retention.activeRate30Days) : "—",
                    systemImage: "calendar.badge.checkmark",
                    tint: .teal
                )
            }

            trendChartCard
        }
    }

    private var trendChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(TrendMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
                Toggle("Table", isOn: $showDataTable).toggleStyle(.button).controlSize(.small)
            }
            Group {
                switch selectedMetric {
                case .players:
                    PlayerCountChart(points: chartPoints, selectedPoint: $selectedPoint)
                case .ping:
                    PingChart(points: chartPoints)
                case .tick:
                    if tickChartSamples.isEmpty {
                        Text("No RCON tick samples yet — check the RCON Console's connection status.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        MSPTChart(samples: tickChartSamples)
                    }
                }
            }
            .frame(height: 220)
            if showDataTable && selectedMetric != .tick {
                dataTable
            }
        }
    }

    private var dataTable: some View {
        Table(chartPoints) {
            TableColumn("Time") { point in
                Text(point.timestamp, format: .dateTime.month().day().hour().minute())
            }
            TableColumn("Avg Players") { point in
                Text(String(format: "%.1f", point.averagePlayers))
            }
            TableColumn("Avg Ping (ms)") { point in
                Text(String(format: "%.0f", point.averagePing))
            }
        }
        .frame(height: min(CGFloat(chartPoints.count) * 28 + 40, 300))
    }

    // MARK: - Best Times To Play / Advertise

    private var bestTimesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Best Times To Play").font(.title3.weight(.semibold))
                Spacer()
                Text("All-time pattern — not affected by the range above")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("168-Hour Weekly Heatmap (Poland Time)").font(.headline)
                WeeklyHeatmapView(matrix: weeklyMatrix)
                    .frame(height: 260)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Advertising Window Predictor").font(.headline)
                Text("Ranked by how busy the server actually tends to be — not by growth rate — so a bump lands when there's the least chance of a visitor clicking through to an empty server. Windows that historically ran into lag (MSPT above the 20-TPS floor) are excluded regardless of how busy they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if adSuggestions.isEmpty {
                    Text("Not enough data yet to recommend a window — needs a few historical readings per hour first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(adSuggestions) { suggestion in
                        Label(suggestion.label, systemImage: "megaphone.fill")
                            .font(.callout)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - Event Timeline

    private var eventTimelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Event Timeline").font(.title3.weight(.semibold))
            Text("Every outage, config change, server update, and moderation action, in one feed — scoped to the range above.")
                .font(.caption)
                .foregroundStyle(.secondary)
            eventCategoryFilters
            if timelineEntries.isEmpty {
                Text("No events in this range for the selected filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                eventTimelineList
            }
        }
    }

    private var eventCategoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ServerEventCategory.allCases) { category in
                    let isSelected = selectedEventCategories.contains(category)
                    Button {
                        if isSelected {
                            selectedEventCategories.remove(category)
                        } else {
                            selectedEventCategories.insert(category)
                        }
                    } label: {
                        Label(category.rawValue, systemImage: category.systemImage)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .quaternaryLabelColor).opacity(0.15), in: Capsule())
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var eventTimelineList: some View {
        VStack(spacing: 0) {
            ForEach(timelineEntries.prefix(200)) { entry in
                eventRow(entry)
                if entry.id != timelineEntries.prefix(200).last?.id { Divider() }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func eventRow(_ entry: ServerTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.category.systemImage)
                .foregroundStyle(entry.isNotable ? .red : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.callout.weight(.medium))
                if !entry.detail.isEmpty {
                    Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Session Overlap

    private var sessionOverlapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Session Overlap").font(.title3.weight(.semibold))
                Spacer()
                Menu("Select Players") {
                    Button("Top 8 by playtime (default)") { selectedPlayerIDs.removeAll() }
                    Divider()
                    ForEach(allPlayers) { player in
                        Button {
                            if selectedPlayerIDs.contains(player.persistentModelID) {
                                selectedPlayerIDs.remove(player.persistentModelID)
                            } else {
                                selectedPlayerIDs.insert(player.persistentModelID)
                            }
                        } label: {
                            Label(player.username, systemImage: selectedPlayerIDs.contains(player.persistentModelID) ? "checkmark" : "")
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Text("Who was online at the same time as whom, within the range above — useful for corroborating a griefing report against who else was around.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if timelineSessions.isEmpty {
                Text("No sessions in this range for the selected players.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                PlayerTimelineView(sessions: timelineSessions)
                    .frame(height: max(120, CGFloat(min(timelineSessions.count, 40)) * 6 + 80))
            }
        }
    }
}
