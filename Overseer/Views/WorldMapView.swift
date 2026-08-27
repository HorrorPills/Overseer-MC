//
//  WorldMapView.swift
//  Overseer
//
//  A Chunkbase-style top-down terrain/biome view, but built from the
//  server's own real, already-explored world (region files mirrored
//  over SFTP — see SFTPSyncCoordinator.syncWorldMap) rather than a
//  from-scratch simulation of the world seed. Reimplementing Mojang's
//  exact terrain-generation algorithm for a hypothetical future
//  snapshot with no public specification risks rendering biomes that
//  are simply wrong — a bad failure mode for a tool used to reason
//  about real coordinates during a griefing investigation. Unexplored
//  chunks just render blank rather than a guess.
//
//  The parsed biome grid lives in WorldMapCache (app-lifetime, shared
//  via RootView) rather than this view's own @State — SwiftUI tears
//  down and rebuilds this whole view's state every time the sidebar
//  selection changes away and back, so without an externally-owned
//  cache, opening this page meant re-reading and re-decompressing
//  every mirrored region file from scratch on every single click.
//
//  Overlaid on that terrain: each player's breadcrumb trail, from
//  PlayerPositionSample (RCON `/data get entity ... Pos`, its own
//  5-minute-default scheduler — see RCONAutomationCoordinator.
//  positionTrackingLoop). Chosen over parsing logs for continuous
//  position data since vanilla's server log doesn't carry it — only
//  join/death/disconnect events do, far too sparse for a trail. A
//  breadcrumb path leading from a player's own base straight to
//  another player's, right around when that other player reported
//  something stolen, is exactly the kind of circumstantial evidence
//  this view exists to surface — never proof on its own.
//

import SwiftUI
import SwiftData

struct WorldMapView: View {
    var sftpCoordinator: SFTPSyncCoordinator
    var cache: WorldMapCache

    @Query(sort: \PlayerPositionSample.timestamp) private var allPositions: [PlayerPositionSample]
    @Query(sort: \Player.username) private var allPlayers: [Player]

    /// Breadcrumbs only ever exist for the last 12 hours — see
    /// RCONAutomationCoordinator.purgeStalePositions — so unlike other
    /// range pickers in this app, this one deliberately doesn't offer
    /// 7D/30D/All-Time options; there's never anything there to show.
    private enum BreadcrumbRange: String, CaseIterable, Identifiable {
        case lastHour = "1H"
        case last3Hours = "3H"
        case last12Hours = "12H"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .lastHour: return 3600
            case .last3Hours: return 3 * 3600
            case .last12Hours: return 12 * 3600
            }
        }
    }

    @State private var selectedRange: BreadcrumbRange = .last12Hours
    @State private var selectedUsernames: Set<String> = []
    @State private var frameAction: WorldMapFrameAction?
    @State private var showTable = true
    /// Set by clicking a player's name in the Breadcrumb Log table (or
    /// the legend) — see WorldMapCanvasView.highlightedUsername.
    @State private var highlightedUsername: String?

    static let playerColors: [Color] = [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .indigo, .purple, .pink]

    private var breadcrumbsByPlayer: [String: [PlayerPositionSample]] {
        let start = Date.now.addingTimeInterval(-selectedRange.seconds)
        let filtered = allPositions.filter { sample in
            sample.timestamp >= start
                && (selectedUsernames.isEmpty || selectedUsernames.contains(sample.username))
        }
        return Dictionary(grouping: filtered, by: \.username)
    }

    private func toggleHighlight(_ username: String) {
        highlightedUsername = highlightedUsername == username ? nil : username
    }

    /// Every currently-visible breadcrumb, most recent first, for the
    /// side table — the map's dots communicate rough position and
    /// recency at a glance, this is for reading exact stops in order.
    private var tableRows: [PlayerPositionSample] {
        breadcrumbsByPlayer.values.flatMap { $0 }.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controlBar
            Divider()
            if cache.regions.isEmpty && breadcrumbsByPlayer.isEmpty && !cache.isLoading {
                emptyState
            } else {
                // Deliberately NOT inside a ScrollView — the canvas
                // handles its own pan (drag) and zoom (pinch)
                // internally, and a surrounding ScrollView would fight
                // it for drag gestures.
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        WorldMapCanvasView(
                            regions: cache.regions,
                            breadcrumbsByPlayer: breadcrumbsByPlayer,
                            playerColors: Self.playerColors,
                            highlightedUsername: highlightedUsername,
                            frameAction: $frameAction
                        )
                        .frame(minHeight: 440)
                        legend
                    }
                    if showTable {
                        breadcrumbTable
                            .frame(width: 260)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("World Map")
        .task { await cache.ensureLoaded(directory: sftpCoordinator.worldMapMirrorDirectory) }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await cache.refresh(directory: sftpCoordinator.worldMapMirrorDirectory) }
            } label: {
                if cache.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh Map", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(cache.isLoading)
            .help("Only re-reads region files that are new or changed since the last load.")

            Button {
                Task {
                    await sftpCoordinator.syncNow()
                    await cache.refresh(directory: sftpCoordinator.worldMapMirrorDirectory)
                }
            } label: {
                Label("Sync World Files", systemImage: "network")
            }
            .buttonStyle(.bordered)
            .disabled(sftpCoordinator.isSyncing || cache.isLoading)

            Button {
                frameAction = .spawn
            } label: {
                Label("Center on Spawn", systemImage: "scope")
            }
            .buttonStyle(.bordered)

            Button {
                frameAction = .fitAll
            } label: {
                Label("Fit All", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)

            Toggle("Table", isOn: $showTable)
                .toggleStyle(.button)
                .controlSize(.regular)

            Text("\(cache.chunkCount) chunk\(cache.chunkCount == 1 ? "" : "s") across \(cache.regions.count) region\(cache.regions.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Range", selection: $selectedRange) {
                ForEach(BreadcrumbRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .help("Breadcrumbs are only ever kept for 12 hours — older positions are purged automatically.")

            PlayerFilterPicker(players: allPlayers.map(\.username), selected: $selectedUsernames)
        }
        .padding(14)
    }

    // MARK: - Breadcrumb table

    private var breadcrumbTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Breadcrumb Log").font(.subheadline.weight(.semibold))
                Spacer()
                if highlightedUsername != nil {
                    Button("Clear") { highlightedUsername = nil }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            if highlightedUsername != nil {
                Text("Click the player again to unhighlight.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Click a player's name to trace their path on the map.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if tableRows.isEmpty {
                Text("No recorded positions for the current filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Table(tableRows) {
                    TableColumn("Player") { sample in
                        Button {
                            toggleHighlight(sample.username)
                        } label: {
                            Text(sample.username)
                                .font(.caption.weight(highlightedUsername == sample.username ? .bold : .regular))
                                .foregroundStyle(highlightedUsername == sample.username ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    TableColumn("Time") { sample in
                        Text(sample.timestamp, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                    }
                    TableColumn("X, Z") { sample in
                        Text("\(Int(sample.x)), \(Int(sample.z))")
                            .font(.caption.monospacedDigit())
                    }
                }
                .frame(minHeight: 440)
            }
        }
    }

    // MARK: - Legend / empty state

    private var legend: some View {
        let sortedPlayers = breadcrumbsByPlayer.keys.sorted()
        return VStack(alignment: .leading, spacing: 8) {
            if !sortedPlayers.isEmpty {
                Text("Breadcrumb Trails").font(.caption.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(sortedPlayers.enumerated()), id: \.element) { index, username in
                            Button {
                                toggleHighlight(username)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Self.playerColors[index % Self.playerColors.count])
                                        .frame(width: 8, height: 8)
                                    Text(username)
                                        .font(.caption.weight(highlightedUsername == username ? .bold : .regular))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("Drag to pan, pinch (or the +/– buttons) to zoom, hover for coordinates, click a name (here or in the table) to trace their path — dots mark each recorded stop (bolder = more recent); the white cross is spawn (0, 0). Terrain is rendered from real explored chunks only, synced over SFTP — unexplored/ungenerated areas show blank rather than a simulated guess. Breadcrumbs are kept for 12 hours only, then purged automatically — this is a \"where has this player been recently\" tool, not a permanent log. A shared trail between two players' bases is circumstantial, not proof.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Map Data Yet",
            systemImage: "map",
            description: Text("Enable World Map sync and position tracking in Settings, or tap \"Sync World Files\" above. Terrain fills in as SFTP mirrors world/region; breadcrumbs fill in as RCON records player positions.")
        )
        .frame(maxHeight: .infinity)
    }
}
