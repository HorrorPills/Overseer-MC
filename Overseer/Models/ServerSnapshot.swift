//
//  ServerSnapshot.swift
//  Overseer
//
//  A single point-in-time reading of the server, taken by ServerQueryEngine
//  on every poll cycle. This is the raw time series that HistoricalAnalytics
//  and AnalyticsEngine downsample for charting.
//

import Foundation
import SwiftData

@Model
final class ServerSnapshot {
    /// When this reading was taken (UTC instant; render in Europe/Warsaw for display).
    var timestamp: Date

    /// Number of players online at the time of the query.
    var playerCount: Int

    /// Round-trip latency in milliseconds measured via Server List Ping.
    /// -1 indicates the server did not respond to this poll.
    var pingMs: Int

    /// Max player slots as reported by the server (GS4 `maxplayers`).
    var maxPlayers: Int

    /// Current map/world name as reported by GS4 `map`.
    var mapName: String

    /// Whether this snapshot represents a successful poll (server reachable).
    var isOnline: Bool

    init(
        timestamp: Date = .now,
        playerCount: Int,
        pingMs: Int,
        maxPlayers: Int,
        mapName: String,
        isOnline: Bool = true
    ) {
        self.timestamp = timestamp
        self.playerCount = playerCount
        self.pingMs = pingMs
        self.maxPlayers = maxPlayers
        self.mapName = mapName
        self.isOnline = isOnline
    }
}

// NOTE on indexing: SwiftData's `#Index` macro (fast compound/sorted indexes)
// requires macOS 15+. This project targets macOS 14+, so we rely on
// FetchDescriptor(sortBy:) with `timestamp` and let SwiftData use its default
// primary-key index. If the deployment target is raised to macOS 15, add:
//
//   #Index<ServerSnapshot>([\.timestamp])
//
// at file scope to get an explicit B-tree index on timestamp for large
// datasets (this app can accumulate ~2,880 snapshots/day at a 30s interval).
