//
//  PlayerDataFolderScanner.swift
//  Overseer
//
//  Turns a batch of already-read `.dat` file entries into parsed player
//  data. Deliberately takes bytes rather than a directory URL — actual
//  directory enumeration and security-scoped file access are I/O
//  concerns that belong to InventoryAnalyzerView (same split as
//  SchematicBuilderView owning the file read while SpongeSchematicParser
//  stays a pure byte-in/model-out function), so this stays unit-testable
//  against synthetic fixtures with no filesystem involved.
//

import Foundation

struct PlayerDataScanEntry {
    var uuid: String
    var data: Data
    var fileURL: URL
    var modifiedAt: Date?
}

struct PlayerDataScanFailure {
    var uuid: String
    var message: String
}

struct PlayerDataScanResult {
    var players: [ParsedPlayerData]
    var failures: [PlayerDataScanFailure]
}

enum PlayerDataFolderScanner {
    /// A world's `playerdata/` folder can accumulate stray `.dat_old`
    /// backups and non-UUID files; only `<uuid>.dat` is a live player
    /// record, so anything else is filtered out before parsing rather
    /// than surfaced as a failure.
    static func isPlayerDataFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "dat"
    }

    static func scan(entries: [PlayerDataScanEntry]) -> PlayerDataScanResult {
        var players: [ParsedPlayerData] = []
        var failures: [PlayerDataScanFailure] = []
        for entry in entries {
            do {
                let parsed = try PlayerDataParser.parse(
                    uuid: entry.uuid, data: entry.data,
                    fileURL: entry.fileURL, fileModifiedAt: entry.modifiedAt
                )
                players.append(parsed)
            } catch {
                failures.append(PlayerDataScanFailure(uuid: entry.uuid, message: error.localizedDescription))
            }
        }
        return PlayerDataScanResult(players: players, failures: failures)
    }
}
