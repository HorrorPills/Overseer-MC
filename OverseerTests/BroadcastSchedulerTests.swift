//
//  BroadcastSchedulerTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("BroadcastScheduler")
struct BroadcastSchedulerTests {

    @Test("A never-sent, enabled message is due immediately")
    func neverSentIsDue() {
        let message = BroadcastMessage(text: "Hello", intervalMinutes: 15)
        #expect(BroadcastScheduler.isDue(message))
    }

    @Test("A disabled message is never due, even if overdue")
    func disabledIsNeverDue() {
        let message = BroadcastMessage(text: "Hello", intervalMinutes: 15, isEnabled: false, lastSentAt: Date().addingTimeInterval(-3600))
        #expect(!BroadcastScheduler.isDue(message))
    }

    @Test("Not due before its interval has elapsed")
    func notYetDue() {
        let now = Date()
        let message = BroadcastMessage(text: "Hello", intervalMinutes: 15, lastSentAt: now.addingTimeInterval(-5 * 60))
        #expect(!BroadcastScheduler.isDue(message, now: now))
    }

    @Test("Due once the interval has fully elapsed")
    func dueAfterInterval() {
        let now = Date()
        let message = BroadcastMessage(text: "Hello", intervalMinutes: 15, lastSentAt: now.addingTimeInterval(-15 * 60))
        #expect(BroadcastScheduler.isDue(message, now: now))
    }

    @Test("A non-positive interval is never due")
    func nonPositiveIntervalNeverDue() {
        let message = BroadcastMessage(text: "Hello", intervalMinutes: 0)
        #expect(!BroadcastScheduler.isDue(message))
        let negative = BroadcastMessage(text: "Hello", intervalMinutes: -5)
        #expect(!BroadcastScheduler.isDue(negative))
    }

    @Test("due(_:) filters a mixed batch to just the due messages")
    func dueFiltersBatch() {
        let now = Date()
        let overdue = BroadcastMessage(text: "Overdue", intervalMinutes: 10, lastSentAt: now.addingTimeInterval(-20 * 60))
        let fresh = BroadcastMessage(text: "Fresh", intervalMinutes: 10, lastSentAt: now.addingTimeInterval(-1 * 60))
        let disabled = BroadcastMessage(text: "Disabled", intervalMinutes: 10, isEnabled: false, lastSentAt: now.addingTimeInterval(-20 * 60))
        let due = BroadcastScheduler.due([overdue, fresh, disabled], now: now)
        #expect(due.map(\.text) == ["Overdue"])
    }

    @Test("nextFireDate is nil for a disabled or non-positive-interval message")
    func nextFireDateNilCases() {
        #expect(BroadcastScheduler.nextFireDate(BroadcastMessage(text: "x", intervalMinutes: 10, isEnabled: false)) == nil)
        #expect(BroadcastScheduler.nextFireDate(BroadcastMessage(text: "x", intervalMinutes: 0)) == nil)
    }

    @Test("nextFireDate anchors off lastSentAt when present, else createdAt")
    func nextFireDateAnchoring() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let neverSent = BroadcastMessage(text: "x", intervalMinutes: 10, createdAt: created)
        #expect(BroadcastScheduler.nextFireDate(neverSent) == created.addingTimeInterval(600))

        let lastSent = created.addingTimeInterval(3600)
        let sent = BroadcastMessage(text: "x", intervalMinutes: 10, lastSentAt: lastSent, createdAt: created)
        #expect(BroadcastScheduler.nextFireDate(sent) == lastSent.addingTimeInterval(600))
    }
}
