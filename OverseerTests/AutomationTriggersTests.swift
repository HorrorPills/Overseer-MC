//
//  AutomationTriggersTests.swift
//  OverseerTests
//

import Testing
import Foundation
@testable import Overseer

@Suite("MilestoneEvaluator")
struct MilestoneEvaluatorTests {

    @Test("No milestone crossed below the first threshold")
    func belowFirstThreshold() {
        let crossed = MilestoneEvaluator.newlyCrossedMilestones(playTimeSeconds: 49 * 3600, alreadyAwardedHours: [])
        #expect(crossed.isEmpty)
    }

    @Test("Crosses exactly the 50-hour milestone once reached")
    func crosses50Hours() {
        let crossed = MilestoneEvaluator.newlyCrossedMilestones(playTimeSeconds: 50 * 3600, alreadyAwardedHours: [])
        #expect(crossed == [50])
    }

    @Test("Already-awarded milestones are never returned again")
    func skipsAlreadyAwarded() {
        let crossed = MilestoneEvaluator.newlyCrossedMilestones(playTimeSeconds: 50 * 3600, alreadyAwardedHours: [50])
        #expect(crossed.isEmpty)
    }

    @Test("A large jump (e.g. app was offline) surfaces every newly-crossed milestone, ascending")
    func jumpsMultipleMilestones() {
        let crossed = MilestoneEvaluator.newlyCrossedMilestones(playTimeSeconds: 300 * 3600, alreadyAwardedHours: [])
        #expect(crossed == [50, 100, 250])
    }

    @Test("A jump only surfaces milestones not already awarded")
    func jumpSkipsPartiallyAwarded() {
        let crossed = MilestoneEvaluator.newlyCrossedMilestones(playTimeSeconds: 300 * 3600, alreadyAwardedHours: [50])
        #expect(crossed == [100, 250])
    }
}

@Suite("AdWindowTrigger")
struct AdWindowTriggerTests {

    @Test("Does not fire below the velocity threshold")
    func belowThreshold() {
        #expect(!AdWindowTrigger.shouldBroadcast(velocityPerMinute: 0.1, lastBroadcast: nil))
    }

    @Test("Does not fire with nil velocity")
    func nilVelocity() {
        #expect(!AdWindowTrigger.shouldBroadcast(velocityPerMinute: nil, lastBroadcast: nil))
    }

    @Test("Fires on strong growth with no prior broadcast")
    func firesWithNoPriorBroadcast() {
        #expect(AdWindowTrigger.shouldBroadcast(velocityPerMinute: 1.0, lastBroadcast: nil))
    }

    @Test("Respects the cooldown after a recent broadcast")
    func respectsCooldown() {
        let now = Date()
        let recent = now.addingTimeInterval(-60) // 1 minute ago
        #expect(!AdWindowTrigger.shouldBroadcast(velocityPerMinute: 1.0, lastBroadcast: recent, now: now))
    }

    @Test("Fires again once the cooldown has elapsed")
    func firesAfterCooldownElapses() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-AdWindowTrigger.cooldown - 1)
        #expect(AdWindowTrigger.shouldBroadcast(velocityPerMinute: 1.0, lastBroadcast: longAgo, now: now))
    }
}

@Suite("HappyHourWindow")
struct HappyHourWindowTests {

    private func warsawDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return AnalyticsEngine.warsawCalendar.date(from: components)!
    }

    @Test("Triggers on a Friday evening within the window")
    func triggersFridayEvening() {
        // 2026-08-07 is a Friday.
        let date = warsawDate(year: 2026, month: 8, day: 7, hour: 19)
        #expect(HappyHourWindow.shouldTrigger(now: date, lastTriggered: nil))
    }

    @Test("Does not trigger on a weekday afternoon")
    func doesNotTriggerWeekdayAfternoon() {
        // 2026-08-04 is a Tuesday.
        let date = warsawDate(year: 2026, month: 8, day: 4, hour: 15)
        #expect(!HappyHourWindow.shouldTrigger(now: date, lastTriggered: nil))
    }

    @Test("Does not trigger twice on the same day")
    func doesNotTriggerTwiceSameDay() {
        let date = warsawDate(year: 2026, month: 8, day: 7, hour: 20)
        #expect(!HappyHourWindow.shouldTrigger(now: date, lastTriggered: date.addingTimeInterval(-3600)))
    }

    @Test("Triggers again on a subsequent qualifying day")
    func triggersAgainNextWeek() {
        let lastWeek = warsawDate(year: 2026, month: 8, day: 7, hour: 19)
        let thisWeek = warsawDate(year: 2026, month: 8, day: 14, hour: 19) // next Friday
        #expect(HappyHourWindow.shouldTrigger(now: thisWeek, lastTriggered: lastWeek))
    }
}
