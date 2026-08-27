//
//  PlayerLoginRecord.swift
//  Overseer
//
//  One join event with the IP it came from, parsed out of a manually
//  imported server log file (see ServerLogJoinParser / LocationView) —
//  vanilla's own `logs/latest.log` records this on every login, the
//  same data the server itself already has. Import is a deliberate,
//  admin-triggered folder pick, never automatic background scraping.
//
//  Kept as raw per-login rows (not collapsed to "last known IP per
//  player") on purpose: grouping by `ipAddress` across all players is
//  what surfaces shared-IP clusters — the alt-account/ban-evasion signal
//  in PlayerGeographyEngine.alternateAccountCandidates. Collapsing to
//  one row per player would throw that away.
//

import Foundation
import SwiftData

@Model
final class PlayerLoginRecord {
    var username: String
    var ipAddress: String
    var timestamp: Date

    init(username: String, ipAddress: String, timestamp: Date) {
        self.username = username
        self.ipAddress = ipAddress
        self.timestamp = timestamp
    }
}

/// Shared by LocationView's manual import and SFTPSyncCoordinator's
/// automatic one, so the two paths can never drift apart on how
/// duplicates are detected.
enum PlayerLoginRecordStore {
    @discardableResult
    static func persist(_ records: [LogJoinRecord], modelContext: ModelContext) -> Int {
        guard !records.isEmpty else { return 0 }
        let existing = (try? modelContext.fetch(FetchDescriptor<PlayerLoginRecord>())) ?? []
        var existingKeys = Set(existing.map { key(username: $0.username, ip: $0.ipAddress, timestamp: $0.timestamp) })

        var inserted = 0
        for record in records {
            let recordKey = key(username: record.username, ip: record.ipAddress, timestamp: record.timestamp)
            guard !existingKeys.contains(recordKey) else { continue }
            modelContext.insert(PlayerLoginRecord(username: record.username, ipAddress: record.ipAddress, timestamp: record.timestamp))
            existingKeys.insert(recordKey)
            inserted += 1
        }
        if inserted > 0 { try? modelContext.save() }
        return inserted
    }

    private static func key(username: String, ip: String, timestamp: Date) -> String {
        "\(username)|\(ip)|\(timestamp.timeIntervalSince1970)"
    }
}
