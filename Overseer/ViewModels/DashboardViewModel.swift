//
//  DashboardViewModel.swift
//  Overseer
//
//  Thin presentation layer over `PollingCoordinator.lastResult`. Most
//  historical/list data is read directly in views via SwiftData's
//  `@Query` (that's what it's for); this view model exists for state
//  that doesn't map to a `@Query` — the live roster derived from the
//  most recent poll, and lazily-fetched avatar images.
//

import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
@Observable
final class DashboardViewModel {
    private let coordinator: PollingCoordinator
    private(set) var avatarImages: [String: NSImage] = [:]

    init(coordinator: PollingCoordinator) {
        self.coordinator = coordinator
    }

    var isOnline: Bool { coordinator.lastResult?.isOnline ?? false }

    var motd: String {
        coordinator.lastResult?.fullStat?.motd ?? coordinator.lastResult?.slpStatus?.description.text ?? ""
    }

    var mapName: String { coordinator.lastResult?.fullStat?.mapName ?? "" }

    /// The live-reported running version string (e.g. "26.3-snapshot-8"),
    /// from Server List Ping — the ground truth AutoUpdaterCoordinator
    /// compares against Mojang's manifest, since it reflects whatever
    /// build is actually running right now rather than whatever was last
    /// deployed.
    var serverVersion: String? { coordinator.lastResult?.slpStatus?.version.name }

    var pingMs: Int? { coordinator.lastResult?.pingMs }

    var playerCount: Int {
        coordinator.lastResult?.fullStat?.players.count
            ?? coordinator.lastResult?.slpStatus?.players.online
            ?? 0
    }

    var maxPlayers: Int {
        coordinator.lastResult?.fullStat?.maxPlayers
            ?? coordinator.lastResult?.slpStatus?.players.max
            ?? 0
    }

    /// Roster of currently-online usernames, from the most authoritative
    /// source available in the last poll (GS4 full list, else SLP's
    /// sample).
    var onlineUsernames: [String] {
        if let players = coordinator.lastResult?.fullStat?.players {
            return players.sorted()
        }
        if let sample = coordinator.lastResult?.slpStatus?.players.sample {
            return sample.map(\.name).sorted()
        }
        return []
    }

    var lastUpdated: Date? { coordinator.lastResult?.timestamp }

    var consecutiveFailures: Int { coordinator.consecutiveFailures }

    func refreshNow() async {
        await coordinator.pollNow()
    }

    /// Lazily resolves and caches a player's avatar image, kicking off
    /// the head-render lookup in the background if needed. Fetched
    /// directly by username — no Mojang UUID resolution required.
    func avatarImage(for player: Player) -> NSImage? {
        if let cached = avatarImages[player.username] { return cached }
        Task { await loadAvatar(username: player.username) }
        return nil
    }

    private func loadAvatar(username: String) async {
        guard avatarImages[username] == nil else { return }
        guard let data = await MojangAPI.shared.avatarImageData(username: username),
              let image = NSImage(data: data) else { return }
        avatarImages[username] = image
    }
}
