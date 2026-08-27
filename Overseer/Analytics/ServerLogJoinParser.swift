//
//  ServerLogJoinParser.swift
//  Overseer
//
//  Parses vanilla's own `logs/latest.log` / rotated `logs/YYYY-MM-DD-N.log(.gz)`
//  for each player's login line, which vanilla has always logged with
//  the connecting IP:
//
//    [09:15:24] [Server thread/INFO]: Steve[/203.0.113.42:54321] logged in with entity id 123 at (...)
//
//  This is the server's own data about its own connections — not a new
//  exposure, just surfacing what's already in the log — read only from
//  a folder the admin explicitly imports (see LocationView), never
//  scraped automatically. Log lines only carry a time-of-day, not a
//  full date, so the calendar day comes from the filename (rotated
//  logs are named `YYYY-MM-DD-N.log`) or, for `latest.log`, from the
//  date the import happened to run.
//
//  Pure and dependency-free so it's directly unit-testable.
//

import Foundation

struct LogJoinRecord: Equatable {
    var username: String
    var ipAddress: String
    var timestamp: Date
}

enum ServerLogJoinParser {
    /// Group 1-3: HH:MM:SS: Group 4: username. Group 5: bracketed IPv6.
    /// Group 6: bare IPv4. Vanilla usernames are 1-16 chars of
    /// [A-Za-z0-9_] — the same charset every other parser in this app
    /// (PlayerListParser etc.) assumes.
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\[(\d{2}):(\d{2}):(\d{2})\].*?([A-Za-z0-9_]{1,16})\[/(?:\[([0-9a-fA-F:]+)\]|([0-9.]+)):\d+\]\s+logged in with entity id"#
    )

    /// Every join event found in `logText`, in file order. `day` anchors
    /// the HH:MM:SS time-of-day each line carries to a real calendar
    /// date, in Europe/Warsaw (this app's convention throughout — see
    /// AnalyticsEngine's file-level comment) since vanilla's log
    /// timestamps are server-local time and the app has no other way to
    /// know the server's actual timezone.
    static func parseJoins(from logText: String, day: Date, calendar: Calendar = AnalyticsEngine.warsawCalendar) -> [LogJoinRecord] {
        let dayStart = calendar.startOfDay(for: day)
        var records: [LogJoinRecord] = []
        logText.enumerateLines { line, _ in
            if let record = parseLine(line, dayStart: dayStart, calendar: calendar) {
                records.append(record)
            }
        }
        return records
    }

    private static func parseLine(_ line: String, dayStart: Date, calendar: Calendar) -> LogJoinRecord? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = pattern.firstMatch(in: line, range: range),
              let hourRange = Range(match.range(at: 1), in: line),
              let minuteRange = Range(match.range(at: 2), in: line),
              let secondRange = Range(match.range(at: 3), in: line),
              let usernameRange = Range(match.range(at: 4), in: line),
              let hour = Int(line[hourRange]), let minute = Int(line[minuteRange]), let second = Int(line[secondRange])
        else { return nil }

        let ipAddress: String
        if let ipv6Range = Range(match.range(at: 5), in: line) {
            ipAddress = String(line[ipv6Range])
        } else if let ipv4Range = Range(match.range(at: 6), in: line) {
            ipAddress = String(line[ipv4Range])
        } else {
            return nil
        }

        var comps = DateComponents()
        comps.hour = hour; comps.minute = minute; comps.second = second
        guard let timestamp = calendar.date(byAdding: comps, to: dayStart) else { return nil }

        return LogJoinRecord(username: String(line[usernameRange]), ipAddress: ipAddress, timestamp: timestamp)
    }

    private static let filenameDatePattern = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})-\d+\.log"#)

    /// Best-effort calendar date from a rotated log's filename
    /// (`YYYY-MM-DD-N.log[.gz]`). Returns nil for `latest.log`, which
    /// carries no date in its name — callers should fall back to the
    /// date the import ran.
    static func inferredDate(fromFilename filename: String) -> Date? {
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = filenameDatePattern.firstMatch(in: filename, range: range),
              let yearRange = Range(match.range(at: 1), in: filename),
              let monthRange = Range(match.range(at: 2), in: filename),
              let dayRange = Range(match.range(at: 3), in: filename),
              let year = Int(filename[yearRange]), let month = Int(filename[monthRange]), let day = Int(filename[dayRange])
        else { return nil }
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        return AnalyticsEngine.warsawCalendar.date(from: comps)
    }
}
