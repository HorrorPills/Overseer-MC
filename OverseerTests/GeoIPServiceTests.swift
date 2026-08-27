//
//  GeoIPServiceTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("GeoIPService")
struct GeoIPServiceTests {

    @Test("Recognizes private/reserved IPv4 ranges")
    func recognizesPrivateIPv4() {
        #expect(GeoIPService.isPrivateOrReserved("192.168.1.5"))
        #expect(GeoIPService.isPrivateOrReserved("10.0.0.1"))
        #expect(GeoIPService.isPrivateOrReserved("172.16.5.5"))
        #expect(GeoIPService.isPrivateOrReserved("172.31.0.1"))
        #expect(GeoIPService.isPrivateOrReserved("127.0.0.1"))
        #expect(GeoIPService.isPrivateOrReserved("169.254.1.1"))
    }

    @Test("Does not flag a routable public IPv4 address as private")
    func doesNotFlagPublicIPv4() {
        #expect(!GeoIPService.isPrivateOrReserved("203.0.113.42"))
        #expect(!GeoIPService.isPrivateOrReserved("8.8.8.8"))
        // 172.32.x is outside the 172.16-31 private block.
        #expect(!GeoIPService.isPrivateOrReserved("172.32.0.1"))
    }

    @Test("Recognizes loopback and link-local IPv6")
    func recognizesPrivateIPv6() {
        #expect(GeoIPService.isPrivateOrReserved("::1"))
        #expect(GeoIPService.isPrivateOrReserved("fe80::1"))
        #expect(GeoIPService.isPrivateOrReserved("fd00::1"))
    }

    @Test("Malformed IPv4 is treated as unresolvable")
    func malformedIPv4TreatedAsUnresolvable() {
        #expect(GeoIPService.isPrivateOrReserved("not-an-ip"))
        #expect(GeoIPService.isPrivateOrReserved("1.2.3"))
    }
}
