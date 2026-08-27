//
//  RecentActivityFilterTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("RecentActivityFilter")
struct RecentActivityFilterTests {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Within the window returns true")
    func withinWindow() {
        let modified = reference.addingTimeInterval(-47 * 3600)
        #expect(RecentActivityFilter.isWithin(48, modifiedAt: modified, referenceDate: reference))
    }

    @Test("Exactly at the boundary is still included")
    func atBoundary() {
        let modified = reference.addingTimeInterval(-48 * 3600)
        #expect(RecentActivityFilter.isWithin(48, modifiedAt: modified, referenceDate: reference))
    }

    @Test("Past the window returns false")
    func pastWindow() {
        let modified = reference.addingTimeInterval(-49 * 3600)
        #expect(!RecentActivityFilter.isWithin(48, modifiedAt: modified, referenceDate: reference))
    }

    @Test("A future modification time (clock skew) still counts as recent")
    func futureTimestampCounts() {
        let modified = reference.addingTimeInterval(3600)
        #expect(RecentActivityFilter.isWithin(48, modifiedAt: modified, referenceDate: reference))
    }

    @Test("nil modification date is never recent")
    func nilIsNeverRecent() {
        #expect(!RecentActivityFilter.isWithin(48, modifiedAt: nil, referenceDate: reference))
    }
}
