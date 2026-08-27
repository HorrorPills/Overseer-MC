//
//  LeaderboardEngineTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("LeaderboardEngine")
struct LeaderboardEngineTests {

    @Test("topByPlaytime ranks descending and excludes zero-playtime players")
    func topByPlaytimeRanksAndFilters() {
        let a = Player(username: "Alice", playTimeSeconds: 3600)
        let b = Player(username: "Bob", playTimeSeconds: 7200)
        let c = Player(username: "Zero", playTimeSeconds: 0)
        let ranked = LeaderboardEngine.topByPlaytime([a, b, c])
        #expect(ranked.map(\.player.username) == ["Bob", "Alice"])
    }

    @Test("topByPlaytime respects the limit")
    func topByPlaytimeRespectsLimit() {
        let players = (0..<20).map { Player(username: "P\($0)", playTimeSeconds: Double($0 + 1) * 60) }
        #expect(LeaderboardEngine.topByPlaytime(players, limit: 5).count == 5)
    }

    @Test("topBySessionCount ranks by session count, excludes players with no sessions")
    func topBySessionCountRanksAndFilters() {
        let a = Player(username: "Alice")
        let b = Player(username: "Bob")
        let c = Player(username: "NoSessions")
        a.sessions = [PlayerSession(player: a), PlayerSession(player: a)]
        b.sessions = [PlayerSession(player: b)]
        let ranked = LeaderboardEngine.topBySessionCount([a, b, c])
        #expect(ranked.map(\.player.username) == ["Alice", "Bob"])
        #expect(ranked.map(\.sessionCount) == [2, 1])
    }

    @Test("topByLongestSession only considers closed sessions and picks the max")
    func topByLongestSessionUsesClosedSessionsOnly() {
        let alice = Player(username: "Alice")
        alice.sessions = [
            PlayerSession(player: alice, startTime: .now, endTime: .now.addingTimeInterval(1800)),
            PlayerSession(player: alice, startTime: .now, endTime: .now.addingTimeInterval(7200)),
            PlayerSession(player: alice, startTime: .now) // still open, no durationSeconds
        ]
        let noClosedSessions = Player(username: "OnlyOpen")
        noClosedSessions.sessions = [PlayerSession(player: noClosedSessions, startTime: .now)]

        let ranked = LeaderboardEngine.topByLongestSession([alice, noClosedSessions])
        #expect(ranked.map(\.player.username) == ["Alice"])
        #expect(ranked.first?.longestSessionSeconds == 7200)
    }

    @Test("newestPlayers sorts by firstSeen descending")
    func newestPlayersSortsDescending() {
        let now = Date()
        let old = Player(username: "Old", firstSeen: now.addingTimeInterval(-86400))
        let recent = Player(username: "Recent", firstSeen: now)
        #expect(LeaderboardEngine.newestPlayers([old, recent]).map(\.username) == ["Recent", "Old"])
    }
}
