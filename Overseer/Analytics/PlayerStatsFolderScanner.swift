//
//  PlayerStatsFolderScanner.swift
//  Overseer
//
//  Batch counterpart to PlayerStatsFileParser, same split as
//  PlayerDataFolderScanner: takes already-read bytes so it stays a pure,
//  unit-testable function, while PlaytimeImporterView owns the actual
//  directory enumeration and security-scoped file access.
//

import Foundation

struct PlayerStatsScanEntry {
    var uuid: String
    var data: Data
    var fileURL: URL
}

struct PlayerStatsScanFailure {
    var uuid: String
    var message: String
}

struct PlayerStatsScanResult {
    var stats: [ParsedPlayerStats]
    var failures: [PlayerStatsScanFailure]
}

enum PlayerStatsFolderScanner {
    static func isStatsFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
    }

    static func scan(entries: [PlayerStatsScanEntry]) -> PlayerStatsScanResult {
        var stats: [ParsedPlayerStats] = []
        var failures: [PlayerStatsScanFailure] = []
        for entry in entries {
            do {
                stats.append(try PlayerStatsFileParser.parse(uuid: entry.uuid, data: entry.data, fileURL: entry.fileURL))
            } catch {
                failures.append(PlayerStatsScanFailure(uuid: entry.uuid, message: error.localizedDescription))
            }
        }
        return PlayerStatsScanResult(stats: stats, failures: failures)
    }
}
