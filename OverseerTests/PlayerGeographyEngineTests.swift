//
//  PlayerGeographyEngineTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("PlayerGeographyEngine")
struct PlayerGeographyEngineTests {

    private func geo(_ ip: String, country: String, code: String, tz: String? = nil) -> PlayerGeoLocation {
        PlayerGeoLocation(ipAddress: ip, country: country, countryCode: code, timezoneIdentifier: tz)
    }

    @Test("Country distribution groups usernames by their most recent IP's resolved country")
    func countryDistributionGroupsByLatestIP() {
        let now = Date()
        let records = [
            PlayerLoginRecord(username: "Steve", ipAddress: "1.1.1.1", timestamp: now.addingTimeInterval(-100)),
            PlayerLoginRecord(username: "Alex", ipAddress: "2.2.2.2", timestamp: now.addingTimeInterval(-50)),
            // Steve later logs in from a different IP/country -> should count under the newer one.
            PlayerLoginRecord(username: "Steve", ipAddress: "3.3.3.3", timestamp: now)
        ]
        let lookup: [String: PlayerGeoLocation] = [
            "1.1.1.1": geo("1.1.1.1", country: "Poland", code: "PL"),
            "2.2.2.2": geo("2.2.2.2", country: "Poland", code: "PL"),
            "3.3.3.3": geo("3.3.3.3", country: "Germany", code: "DE")
        ]
        let distribution = PlayerGeographyEngine.countryDistribution(loginRecords: records, geoLookup: lookup)
        let poland = distribution.first { $0.country == "Poland" }
        let germany = distribution.first { $0.country == "Germany" }
        #expect(poland?.usernames == ["Alex"]) // only Alex, since Steve's latest IP resolved to Germany
        #expect(germany?.usernames == ["Steve"])
    }

    @Test("Country distribution excludes IPs with failed resolution")
    func countryDistributionExcludesFailedResolution() {
        let now = Date()
        let records = [PlayerLoginRecord(username: "Ghost", ipAddress: "9.9.9.9", timestamp: now)]
        let lookup: [String: PlayerGeoLocation] = [
            "9.9.9.9": PlayerGeoLocation(ipAddress: "9.9.9.9", resolutionFailed: true)
        ]
        #expect(PlayerGeographyEngine.countryDistribution(loginRecords: records, geoLookup: lookup).isEmpty)
    }

    @Test("Alternate account candidates group usernames sharing an IP, excluding IPs used by only one")
    func alternateAccountCandidatesGroupsSharedIPs() {
        let now = Date()
        let records = [
            PlayerLoginRecord(username: "Steve", ipAddress: "5.5.5.5", timestamp: now),
            PlayerLoginRecord(username: "AltSteve", ipAddress: "5.5.5.5", timestamp: now.addingTimeInterval(60)),
            PlayerLoginRecord(username: "Alex", ipAddress: "6.6.6.6", timestamp: now)
        ]
        let candidates = PlayerGeographyEngine.alternateAccountCandidates(loginRecords: records)
        #expect(candidates.count == 1)
        #expect(candidates[0].ipAddress == "5.5.5.5")
        #expect(candidates[0].usernames == ["AltSteve", "Steve"])
    }

    @Test("Prime time in Warsaw shifts by the two zones' current UTC offset difference")
    func primeTimeInWarsawShiftsCorrectly() {
        // Pick a fixed reference date to avoid DST-transition flakiness.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 15; comps.hour = 12
        let reference = Calendar(identifier: .gregorian).date(from: comps)!

        // America/New_York is UTC-5 in January; Europe/Warsaw is UTC+1 -> 6-hour shift.
        let window = PlayerGeographyEngine.primeTimeInWarsaw(
            timezoneIdentifier: "America/New_York",
            localStartHour: 18,
            localEndHour: 22,
            referenceDate: reference
        )
        #expect(window == "00:00–04:00 Warsaw time")
    }

    @Test("Prime time in Warsaw returns nil for an unrecognized timezone identifier")
    func primeTimeInWarsawNilForBadTimezone() {
        #expect(PlayerGeographyEngine.primeTimeInWarsaw(timezoneIdentifier: "Not/A_Zone") == nil)
    }
}
