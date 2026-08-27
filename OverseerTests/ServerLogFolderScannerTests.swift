//
//  ServerLogFolderScannerTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("ServerLogFolderScanner")
struct ServerLogFolderScannerTests {

    @Test("Recognizes plain .log and gzip .log.gz files, rejects everything else")
    func recognizesLogFiles() {
        #expect(ServerLogFolderScanner.isLogFile(URL(fileURLWithPath: "/logs/latest.log")))
        #expect(ServerLogFolderScanner.isLogFile(URL(fileURLWithPath: "/logs/2026-08-15-1.log.gz")))
        #expect(!ServerLogFolderScanner.isLogFile(URL(fileURLWithPath: "/logs/debug.txt")))
        #expect(!ServerLogFolderScanner.isLogFile(URL(fileURLWithPath: "/world/level.dat")))
    }

    @Test("Scans a plain-text latest.log entry and anchors it to `today`")
    func scansPlainLogEntry() {
        let today = Date()
        let text = "[09:15:24] [Server thread/INFO]: Steve[/203.0.113.42:54321] logged in with entity id 123 at (0, 65, 0)"
        let entry = LogFileEntry(filename: "latest.log", data: text.data(using: .utf8)!)
        let records = ServerLogFolderScanner.scan(entries: [entry], today: today)
        #expect(records.count == 1)
        #expect(records[0].username == "Steve")
        #expect(records[0].ipAddress == "203.0.113.42")
    }

    @Test("Scans a rotated log's date from its filename rather than `today`")
    func scansRotatedLogUsesFilenameDate() {
        let today = Date()
        let text = "[09:15:24] [Server thread/INFO]: Alex[/198.51.100.7:5000] logged in with entity id 124 at (0, 65, 0)"
        let entry = LogFileEntry(filename: "2020-01-01-1.log", data: text.data(using: .utf8)!)
        let records = ServerLogFolderScanner.scan(entries: [entry], today: today)
        #expect(records.count == 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AnalyticsEngine.warsawTimeZone
        let comps = calendar.dateComponents([.year, .month, .day], from: records[0].timestamp)
        #expect(comps.year == 2020 && comps.month == 1 && comps.day == 1)
    }

    @Test("Skips a file whose bytes aren't valid UTF-8 text or gzip, rather than crashing")
    func skipsUndecodableFile() {
        let entry = LogFileEntry(filename: "latest.log", data: Data([0xFF, 0xFE, 0x00, 0x01]))
        let records = ServerLogFolderScanner.scan(entries: [entry], today: Date())
        #expect(records.isEmpty)
    }
}
