//
//  PlayerGeoLocation.swift
//  Overseer
//
//  Cached geolocation result for one IP address — resolved on demand
//  (see GeoIPService / LocationView's "Resolve Locations" action), never
//  automatically, so repeated imports don't re-hit the lookup API for
//  an IP already resolved. Keyed by IP rather than by player, since one
//  IP can be shared by multiple usernames (see PlayerLoginRecord) and
//  one player can log in from more than one IP over time.
//

import Foundation
import SwiftData

@Model
final class PlayerGeoLocation {
    @Attribute(.unique) var ipAddress: String
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
    var timezoneIdentifier: String?
    var isp: String?
    var resolvedAt: Date

    /// True for a lookup that failed (private/reserved IP, API error,
    /// unresolvable address) — cached too, so a bad IP isn't retried
    /// forever on every import.
    var resolutionFailed: Bool

    init(
        ipAddress: String,
        country: String? = nil,
        countryCode: String? = nil,
        region: String? = nil,
        city: String? = nil,
        timezoneIdentifier: String? = nil,
        isp: String? = nil,
        resolvedAt: Date = .now,
        resolutionFailed: Bool = false
    ) {
        self.ipAddress = ipAddress
        self.country = country
        self.countryCode = countryCode
        self.region = region
        self.city = city
        self.timezoneIdentifier = timezoneIdentifier
        self.isp = isp
        self.resolvedAt = resolvedAt
        self.resolutionFailed = resolutionFailed
    }
}
