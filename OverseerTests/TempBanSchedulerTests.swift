//
//  TempBanSchedulerTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("TempBanScheduler")
struct TempBanSchedulerTests {

    @Test("Not expired before expiresAt")
    func notYetExpired() {
        let now = Date()
        let ban = TempBan(username: "Alice", expiresAt: now.addingTimeInterval(600))
        #expect(!TempBanScheduler.isExpired(ban, now: now))
    }

    @Test("Expired once expiresAt has passed")
    func expiredAfterDeadline() {
        let now = Date()
        let ban = TempBan(username: "Alice", expiresAt: now.addingTimeInterval(-1))
        #expect(TempBanScheduler.isExpired(ban, now: now))
    }

    @Test("Already-pardoned bans are never reported as expired")
    func pardonedNeverExpired() {
        let now = Date()
        let ban = TempBan(username: "Alice", expiresAt: now.addingTimeInterval(-600), pardoned: true)
        #expect(!TempBanScheduler.isExpired(ban, now: now))
    }

    @Test("expired(_:) filters a mixed batch")
    func expiredFiltersBatch() {
        let now = Date()
        let overdue = TempBan(username: "Overdue", expiresAt: now.addingTimeInterval(-60))
        let active = TempBan(username: "Active", expiresAt: now.addingTimeInterval(600))
        let alreadyPardoned = TempBan(username: "Pardoned", expiresAt: now.addingTimeInterval(-60), pardoned: true)
        let due = TempBanScheduler.expired([overdue, active, alreadyPardoned], now: now)
        #expect(due.map(\.username) == ["Overdue"])
    }

    @Test("timeRemaining clamps to zero once past expiry")
    func timeRemainingClampsAtZero() {
        let now = Date()
        let ban = TempBan(username: "Alice", expiresAt: now.addingTimeInterval(-100))
        #expect(TempBanScheduler.timeRemaining(ban, now: now) == 0)

        let active = TempBan(username: "Bob", expiresAt: now.addingTimeInterval(300))
        #expect(TempBanScheduler.timeRemaining(active, now: now) == 300)
    }
}
