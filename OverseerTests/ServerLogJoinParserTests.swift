//
//  ServerLogJoinParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("ServerLogJoinParser")
struct ServerLogJoinParserTests {

    private var warsawCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AnalyticsEngine.warsawTimeZone
        return calendar
    }

    @Test("Parses an IPv4 login line into username, IP, and a combined timestamp")
    func parsesIPv4LoginLine() {
        let day = warsawCalendar.date(from: DateComponents(year: 2026, month: 8, day: 17))!
        let line = "[09:15:24] [Server thread/INFO]: Steve[/203.0.113.42:54321] logged in with entity id 123 at (16.5, 65.0, 32.5)"
        let records = ServerLogJoinParser.parseJoins(from: line, day: day, calendar: warsawCalendar)
        #expect(records.count == 1)
        #expect(records[0].username == "Steve")
        #expect(records[0].ipAddress == "203.0.113.42")
        let comps = warsawCalendar.dateComponents([.hour, .minute, .second], from: records[0].timestamp)
        #expect(comps.hour == 9 && comps.minute == 15 && comps.second == 24)
    }

    @Test("Parses a bracketed IPv6 login line")
    func parsesIPv6LoginLine() {
        let day = warsawCalendar.date(from: DateComponents(year: 2026, month: 8, day: 17))!
        let line = "[Server thread/INFO] (Minecraft) Notch[/[0:0:0:0:0:0:0:1%0]:56566] logged in with entity id 50 at (5.5, 64.0, 0.5)"
        // No leading HH:MM:SS on this variant -> shouldn't match (the parser anchors on it); use a realistic line instead:
        let realistic = "[14:02:10] [Server thread/INFO]: Notch[/[2001:db8::1]:56566] logged in with entity id 50 at (5.5, 64.0, 0.5)"
        _ = line
        let records = ServerLogJoinParser.parseJoins(from: realistic, day: day, calendar: warsawCalendar)
        #expect(records.count == 1)
        #expect(records[0].username == "Notch")
        #expect(records[0].ipAddress == "2001:db8::1")
    }

    @Test("Ignores unrelated log lines")
    func ignoresUnrelatedLines() {
        let day = Date()
        let logText = """
        [09:15:20] [Server thread/INFO]: Starting minecraft server version 26.3-snapshot-8
        [09:15:23] [User Authenticator #1/INFO]: UUID of player Steve is 069a79f4-44e9-4726-a5be-fca90e38aec5
        [09:15:24] [Server thread/INFO]: Steve[/203.0.113.42:54321] logged in with entity id 123 at (16.5, 65.0, 32.5)
        [09:16:00] [Server thread/INFO]: Steve lost connection: Disconnected
        """
        let records = ServerLogJoinParser.parseJoins(from: logText, day: day)
        #expect(records.count == 1)
        #expect(records[0].username == "Steve")
    }

    @Test("Parses multiple joins across multiple lines, in file order")
    func parsesMultipleJoins() {
        let day = Date()
        let logText = """
        [09:15:24] [Server thread/INFO]: Steve[/203.0.113.42:54321] logged in with entity id 123 at (16.5, 65.0, 32.5)
        [09:20:01] [Server thread/INFO]: Alex[/198.51.100.7:5000] logged in with entity id 124 at (0.0, 65.0, 0.0)
        """
        let records = ServerLogJoinParser.parseJoins(from: logText, day: day)
        #expect(records.count == 2)
        #expect(records[0].username == "Steve")
        #expect(records[1].username == "Alex")
        #expect(records[1].ipAddress == "198.51.100.7")
    }

    @Test("Infers a rotated log file's date from its filename")
    func infersDateFromFilename() {
        let date = ServerLogJoinParser.inferredDate(fromFilename: "2026-08-15-1.log.gz")
        #expect(date != nil)
        let comps = warsawCalendar.dateComponents([.year, .month, .day], from: date!)
        #expect(comps.year == 2026 && comps.month == 8 && comps.day == 15)
    }

    @Test("Returns nil inferring a date from latest.log's filename")
    func infersNilForLatestLog() {
        #expect(ServerLogJoinParser.inferredDate(fromFilename: "latest.log") == nil)
    }
}
