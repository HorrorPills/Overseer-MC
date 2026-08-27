//
//  GeoIPService.swift
//  Overseer
//
//  Resolves an IP address (pulled from an imported server log — see
//  ServerLogJoinParser) to a country/region/timezone via ipapi.co's
//  free, unauthenticated HTTPS endpoint (no key, ~1000 lookups/day —
//  ample for occasional resolution, see https://ipapi.co/free/).
//
//  Every call here is explicitly admin-triggered (LocationView's
//  "Resolve Locations" button), never automatic — this sends a
//  player's IP to a third-party service, which is more sensitive than
//  anything else this app does, even though it's the server's own log
//  data about its own connections. Results are cached indefinitely in
//  PlayerGeoLocation (keyed by IP) so a given IP is only ever resolved
//  once, matching MojangAPI's caching posture for the same reason:
//  don't hammer a free, rate-limited third party.
//

import Foundation

/// Plain, Sendable result of one lookup — kept separate from
/// `PlayerGeoLocation` (a SwiftData `@Model`, main-actor-isolated and
/// not Sendable) so the actor below can hand results back across the
/// actor boundary; callers convert this into a `PlayerGeoLocation` to
/// insert once they're back on the main actor.
struct GeoIPResult: Sendable {
    var ipAddress: String
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
    var timezoneIdentifier: String?
    var isp: String?
    var resolutionFailed: Bool
}

actor GeoIPService {
    static let shared = GeoIPService()

    private struct Response: Decodable {
        var country_name: String?
        var country_code: String?
        var region: String?
        var city: String?
        var timezone: String?
        var org: String?
        var error: Bool?
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Private-range/loopback/link-local addresses (LAN testing,
    /// localhost) resolve to nothing meaningful and shouldn't be sent to
    /// a public API at all.
    static func isPrivateOrReserved(_ ip: String) -> Bool {
        if ip.contains(":") {
            let lower = ip.lowercased()
            return lower == "::1" || lower.hasPrefix("fe80") || lower.hasPrefix("fc") || lower.hasPrefix("fd")
        }
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return true } // malformed -> treat as unresolvable
        if parts[0] == 10 { return true }
        if parts[0] == 127 { return true }
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        if parts[0] == 192, parts[1] == 168 { return true }
        if parts[0] == 169, parts[1] == 254 { return true }
        return false
    }

    func resolve(ip: String) async -> GeoIPResult {
        guard !Self.isPrivateOrReserved(ip), let url = URL(string: "https://ipapi.co/\(ip)/json/") else {
            return GeoIPResult(ipAddress: ip, resolutionFailed: true)
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return GeoIPResult(ipAddress: ip, resolutionFailed: true)
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard decoded.error != true else {
                return GeoIPResult(ipAddress: ip, resolutionFailed: true)
            }
            return GeoIPResult(
                ipAddress: ip,
                country: decoded.country_name,
                countryCode: decoded.country_code,
                region: decoded.region,
                city: decoded.city,
                timezoneIdentifier: decoded.timezone,
                isp: decoded.org,
                resolutionFailed: false
            )
        } catch {
            return GeoIPResult(ipAddress: ip, resolutionFailed: true)
        }
    }
}
