//
//  DashboardView.swift
//  Overseer
//
//  Live status view for the configured server — the landing page of
//  the NavigationSplitView shell. Meant to answer "is
//  the server healthy and how has it been doing" at a glance: uptime,
//  player traffic, tick performance, and the current top players —
//  everything below reads its numbers directly off the tiles/axes
//  rather than relying on an unlabeled sparkline.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    var viewModel: DashboardViewModel
    var settings: AppSettings
    var rconCoordinator: RCONAutomationCoordinator

    @Query(sort: \ServerSnapshot.timestamp, order: .reverse) private var recentSnapshots: [ServerSnapshot]
    @Query(sort: \Player.username) private var allPlayers: [Player]
    @Query(sort: \TickSample.timestamp) private var tickSamples: [TickSample]

    @State private var selectedTrendPoint: AnalyticsEngine.DownsampledPoint?

    private var uptimeWindowStart: Date {
        AnalyticsEngine.TimeRange.last24Hours.startDate() ?? Date().addingTimeInterval(-86400)
    }
    private var uptime: AnalyticsEngine.UptimeSummary {
        AnalyticsEngine.uptimeSummary(snapshots: recentSnapshots, since: uptimeWindowStart)
    }
    private var uptimeBuckets: [AnalyticsEngine.UptimeBucket] {
        AnalyticsEngine.hourlyUptimeBuckets(snapshots: recentSnapshots)
    }
    private var peakToday: Int {
        AnalyticsEngine.peakPlayerCount(snapshots: recentSnapshots, since: uptimeWindowStart)
    }
    private var avgPlayers24h: Double {
        AnalyticsEngine.averagePlayerCount(snapshots: recentSnapshots, since: uptimeWindowStart)
    }
    private var avgPing24h: Double {
        AnalyticsEngine.averagePing(snapshots: recentSnapshots, since: uptimeWindowStart)
    }
    private var pingPercentiles24h: AnalyticsEngine.PingPercentiles {
        AnalyticsEngine.pingPercentiles(snapshots: recentSnapshots, since: uptimeWindowStart)
    }
    private var recentOutages: [AnalyticsEngine.OutageEvent] {
        Array(AnalyticsEngine.outageEvents(snapshots: recentSnapshots, since: uptimeWindowStart).prefix(5))
    }
    /// Excludes the server owner/admins (see AppSettings.excludedLeaderboardUsernames)
    /// so their own hours online don't skew what's meant to reflect the
    /// player community — same exclusion LeaderboardView applies.
    private var rankablePlayers: [Player] {
        allPlayers.filter { !settings.isExcludedFromLeaderboards($0.username) }
    }

    private var avgPlaytimePerPlayer: Double {
        PlayerStatsEngine.averagePlaytimeSeconds(players: rankablePlayers)
    }
    private var trendPoints: [AnalyticsEngine.DownsampledPoint] {
        AnalyticsEngine.chartPoints(for: .last24Hours, snapshots: recentSnapshots)
    }
    private var latestTick: TickSample? { tickSamples.last }
    private var tickChartSamples: [TickSample] {
        TickProfiler.chartSamples(for: .last24Hours, samples: tickSamples)
    }
    private var topPlaytime: [LeaderboardEngine.PlaytimeEntry] {
        LeaderboardEngine.topByPlaytime(rankablePlayers, limit: 5)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statsGrid
                Divider()
                uptimeSection
                Divider()
                trendSection
                Divider()
                performanceSection
                Divider()
                leaderboardSection
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Online Now")
                        .font(.headline)
                    PlayerRosterView(viewModel: viewModel, rconCoordinator: rconCoordinator)
                        .frame(minHeight: 240)
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.refreshNow() }
                } label: {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusIndicator(isOnline: viewModel.isOnline, label: settings.host)
                Spacer()
                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(viewModel.motd.isEmpty ? "No message of the day" : viewModel.motd)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            if viewModel.consecutiveFailures > 0 {
                Label("\(viewModel.consecutiveFailures) consecutive failed polls — retrying with backoff", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Key stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            SummaryCard(
                title: "Players Online",
                value: "\(viewModel.playerCount)/\(viewModel.maxPlayers)",
                systemImage: "person.3.fill",
                tint: .green
            )
            SummaryCard(
                title: "Peak (24h)",
                value: "\(peakToday)",
                systemImage: "chart.line.uptrend.xyaxis",
                tint: .blue
            )
            SummaryCard(
                title: "Avg Players (24h)",
                value: String(format: "%.1f", avgPlayers24h),
                systemImage: "person.2.fill",
                tint: .teal
            )
            SummaryCard(
                title: "Ping avg / p95 (24h)",
                value: avgPing24h > 0 ? "\(Int(avgPing24h.rounded()))/\(Int(pingPercentiles24h.p95.rounded())) ms" : "—",
                systemImage: "bolt.fill",
                tint: .orange
            )
            SummaryCard(
                title: "Longest Outage (24h)",
                value: uptime.totalDowntimeSeconds > 0 ? formatDuration(uptime.longestOutageSeconds) : "None",
                systemImage: "exclamationmark.triangle.fill",
                tint: uptime.totalDowntimeSeconds > 0 ? .red : .secondary
            )
            SummaryCard(
                title: "Map",
                value: viewModel.mapName.isEmpty ? "—" : viewModel.mapName,
                systemImage: "map.fill",
                tint: .purple
            )
            SummaryCard(
                title: "Unique Players",
                value: "\(allPlayers.count)",
                systemImage: "person.crop.circle.badge.checkmark",
                tint: .indigo
            )
            SummaryCard(
                title: "Avg Playtime / Player",
                value: avgPlaytimePerPlayer > 0 ? formatDuration(avgPlaytimePerPlayer) : "—",
                systemImage: "clock.fill",
                tint: .pink
            )
        }
    }

    // MARK: - Uptime

    private var uptimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server Uptime").font(.headline)
            UptimeStatusStrip(buckets: uptimeBuckets, summary: uptime)
            if !recentOutages.isEmpty {
                recentOutagesTable
            }
        }
    }

    private var recentOutagesTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Outages (24h)").font(.subheadline.weight(.medium))
            VStack(spacing: 0) {
                ForEach(recentOutages) { outage in
                    HStack {
                        Text(outage.start, format: .dateTime.hour().minute())
                            .font(.caption)
                            .monospacedDigit()
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                        Text(formatDuration(outage.durationSeconds))
                            .font(.caption)
                            .monospacedDigit()
                        Spacer()
                        Label(
                            outage.isLikelyScheduledRestart ? "Restart" : "Outage",
                            systemImage: outage.isLikelyScheduledRestart ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(outage.isLikelyScheduledRestart ? Color.secondary : Color.red)
                    }
                    .padding(.vertical, 4)
                    if outage.id != recentOutages.last?.id { Divider() }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Player trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Player Activity (24H)").font(.headline)
                Spacer()
                Text("Peak \(peakToday) · Avg \(String(format: "%.1f", avgPlayers24h))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 20) {
                PlayerCountChart(points: trendPoints, selectedPoint: $selectedTrendPoint)
                    .frame(height: 200)
                PingGauge(pingMs: viewModel.pingMs)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Tick performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Server Tick Performance").font(.headline)
                Spacer()
                if let latestTick {
                    Text(String(format: "%.1f ms/tick now", latestTick.mspt))
                        .font(.caption)
                        .foregroundStyle(latestTick.isLagging ? .red : .secondary)
                }
            }
            if tickChartSamples.isEmpty {
                Text("No RCON tick samples yet — check the RCON Console's connection status.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                MSPTChart(samples: tickChartSamples)
                    .frame(height: 140)
            }
        }
    }

    // MARK: - Leaderboard preview

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Players by Playtime").font(.headline)
            if topPlaytime.isEmpty {
                Text("No playtime recorded yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topPlaytime.enumerated()), id: \.element.id) { index, entry in
                        PlayerLeaderRow(rank: index + 1, player: entry.player, value: formatDuration(entry.totalPlaytimeSeconds), viewModel: viewModel)
                        if entry.id != topPlaytime.last?.id { Divider() }
                    }
                }
            }
        }
    }
}
