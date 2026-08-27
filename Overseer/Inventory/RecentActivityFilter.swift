//
//  RecentActivityFilter.swift
//  Overseer
//
//  A `.dat` file's on-disk modification time changes whenever the
//  player's data is written — on disconnect, or during a server
//  auto-save while they're still online — so "modified recently" is a
//  reasonable, RCON-free proxy for "has played recently" once the file
//  has been pulled off the server. Pure so InventoryAnalyzerView's
//  48-hour toggle is testable without touching the filesystem.
//

import Foundation

enum RecentActivityFilter {
    static func isWithin(_ hours: Double, modifiedAt: Date?, referenceDate: Date = .now) -> Bool {
        guard let modifiedAt else { return false }
        return referenceDate.timeIntervalSince(modifiedAt) <= hours * 3600
    }
}
