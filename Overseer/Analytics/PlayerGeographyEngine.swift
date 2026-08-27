//
//  PlayerGeographyEngine.swift
//  Overseer
//
//  Pure aggregation over imported PlayerLoginRecord + resolved
//  PlayerGeoLocation rows — country distribution (for "where do my
//  players actually connect from"), shared-IP grouping (a real, if
//  imperfect, alt-account/ban-evasion signal), and mapping a resolved
//  timezone's evening back to Warsaw time so a country breakdown turns
//  into an actual ad-timing decision.
//

import Foundation

enum PlayerGeographyEngine {

    struct CountryEntry: Identifiable, Equatable {
        var id: String { countryCode ?? country }
        var country: String
        var countryCode: String?
        var timezoneIdentifier: String?
        var usernames: [String]
        var playerCount: Int { usernames.count }
    }

    struct AltAccountGroup: Identifiable, Equatable {
        var id: String { ipAddress }
        var ipAddress: String
        var usernames: [String]
    }

    /// Each username's IP as of their most recent recorded login — a
    /// player who has connected from more than one IP over time counts
    /// under whichever one they used most recently.
    static func latestIPPerUsername(_ records: [PlayerLoginRecord]) -> [String: String] {
        var latest: [String: (ip: String, timestamp: Date)] = [:]
        for record in records {
            if let existing = latest[record.username], existing.timestamp >= record.timestamp { continue }
            latest[record.username] = (record.ipAddress, record.timestamp)
        }
        return latest.mapValues(\.ip)
    }

    /// Each username's resolved location, if its most recent IP has
    /// been successfully geolocated.
    static func latestKnownLocation(loginRecords: [PlayerLoginRecord], geoLookup: [String: PlayerGeoLocation]) -> [String: PlayerGeoLocation] {
        var result: [String: PlayerGeoLocation] = [:]
        for (username, ip) in latestIPPerUsername(loginRecords) {
            guard let geo = geoLookup[ip], !geo.resolutionFailed else { continue }
            result[username] = geo
        }
        return result
    }

    static func countryDistribution(loginRecords: [PlayerLoginRecord], geoLookup: [String: PlayerGeoLocation]) -> [CountryEntry] {
        var grouped: [String: (countryCode: String?, timezoneIdentifier: String?, usernames: Set<String>)] = [:]
        for (username, geo) in latestKnownLocation(loginRecords: loginRecords, geoLookup: geoLookup) {
            guard let country = geo.country else { continue }
            var entry = grouped[country] ?? (geo.countryCode, geo.timezoneIdentifier, [])
            entry.usernames.insert(username)
            grouped[country] = entry
        }
        return grouped
            .map { CountryEntry(country: $0.key, countryCode: $0.value.countryCode, timezoneIdentifier: $0.value.timezoneIdentifier, usernames: $0.value.usernames.sorted()) }
            .sorted { $0.playerCount > $1.playerCount }
    }

    /// IPs shared by 2+ distinct usernames. A real signal worth a manual
    /// look, but explicitly NOT proof of anything on its own — a
    /// household sharing one internet connection (or NAT) looks
    /// identical to ban evasion from this data alone.
    static func alternateAccountCandidates(loginRecords: [PlayerLoginRecord]) -> [AltAccountGroup] {
        var byIP: [String: Set<String>] = [:]
        for record in loginRecords {
            byIP[record.ipAddress, default: []].insert(record.username)
        }
        return byIP
            .filter { $0.value.count > 1 }
            .map { AltAccountGroup(ipAddress: $0.key, usernames: $0.value.sorted()) }
            .sorted { $0.usernames.count > $1.usernames.count }
    }

    /// Where a `localStartHour`–`localEndHour` "prime time" window in
    /// `timezoneIdentifier` falls in Warsaw time right now. Uses the
    /// current UTC offset for both zones, so it can be off by an hour
    /// around a DST transition on one side but not the other — good
    /// enough for "roughly when to post," not a scheduling guarantee.
    static func primeTimeInWarsaw(timezoneIdentifier: String, localStartHour: Int = 18, localEndHour: Int = 22, referenceDate: Date = .now) -> String? {
        guard let remoteTZ = TimeZone(identifier: timezoneIdentifier) else { return nil }
        let warsawTZ = AnalyticsEngine.warsawTimeZone
        let offsetHours = Double(warsawTZ.secondsFromGMT(for: referenceDate) - remoteTZ.secondsFromGMT(for: referenceDate)) / 3600
        let shift = Int(offsetHours.rounded())
        func wrap(_ hour: Int) -> Int { ((hour + shift) % 24 + 24) % 24 }
        return String(format: "%02d:00–%02d:00 Warsaw time", wrap(localStartHour), wrap(localEndHour))
    }
}
