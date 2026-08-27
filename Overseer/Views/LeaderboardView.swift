//
//  LeaderboardView.swift
//  Overseer
//
//  Read-only rankings over data the app already collects — no RCON
//  involved. See LeaderboardEngine for the pure ranking logic.
//

import SwiftUI
import SwiftData

struct LeaderboardView: View {
    @Query(sort: \Player.username) private var allPlayers: [Player]
    var viewModel: DashboardViewModel
    var settings: AppSettings

    /// Excludes the server owner/admins (see AppSettings.excludedLeaderboardUsernames)
    /// so their own hours online don't dominate what's meant to be a
    /// ranking of the *player* community.
    private var rankablePlayers: [Player] {
        allPlayers.filter { !settings.isExcludedFromLeaderboards($0.username) }
    }

    private var topPlaytime: [LeaderboardEngine.PlaytimeEntry] { LeaderboardEngine.topByPlaytime(rankablePlayers) }
    private var topSessions: [LeaderboardEngine.SessionCountEntry] { LeaderboardEngine.topBySessionCount(rankablePlayers) }
    private var topLongestSession: [LeaderboardEngine.LongestSessionEntry] { LeaderboardEngine.topByLongestSession(rankablePlayers) }
    private var newest: [Player] { LeaderboardEngine.newestPlayers(rankablePlayers) }

    var body: some View {
        ScrollView {
            if allPlayers.isEmpty {
                ContentUnavailableView(
                    "No Players Yet",
                    systemImage: "trophy",
                    description: Text("Leaderboards fill in once players start joining.")
                )
                .padding(20)
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    section(title: "Top Playtime", systemImage: "clock.fill") {
                        ForEach(Array(topPlaytime.enumerated()), id: \.element.id) { index, entry in
                            leaderRow(rank: index + 1, player: entry.player, value: formatDuration(entry.totalPlaytimeSeconds))
                            Divider()
                        }
                    }
                    section(title: "Most Sessions", systemImage: "arrow.left.arrow.right") {
                        ForEach(Array(topSessions.enumerated()), id: \.element.id) { index, entry in
                            leaderRow(rank: index + 1, player: entry.player, value: "\(entry.sessionCount) sessions")
                            Divider()
                        }
                    }
                    section(title: "Longest Single Session", systemImage: "flame.fill") {
                        ForEach(Array(topLongestSession.enumerated()), id: \.element.id) { index, entry in
                            leaderRow(rank: index + 1, player: entry.player, value: formatDuration(entry.longestSessionSeconds))
                            Divider()
                        }
                    }
                    section(title: "Newest Players", systemImage: "sparkles") {
                        ForEach(Array(newest.enumerated()), id: \.element.persistentModelID) { index, player in
                            leaderRow(rank: index + 1, player: player, value: player.firstSeen.formatted(.relative(presentation: .named)))
                            Divider()
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Leaderboards")
    }

    private func section<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline)
            VStack(spacing: 0) { content() }
        }
    }

    private func leaderRow(rank: Int, player: Player, value: String) -> some View {
        PlayerLeaderRow(rank: rank, player: player, value: value, viewModel: viewModel)
    }
}
