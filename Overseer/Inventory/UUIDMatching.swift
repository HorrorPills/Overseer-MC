//
//  UUIDMatching.swift
//  Overseer
//
//  Minecraft writes UUIDs into filenames dashed ("069a79f4-44e9-...")
//  but `Player.uuid` (resolved via MojangAPI, whose profile API returns
//  it undashed) may be stored either way depending on when it was
//  fetched — so any UUID-keyed lookup across the two needs to normalize
//  first. Shared by InventoryAnalyzerView and PlaytimeImporterView
//  rather than duplicated, since a drift between the two copies would
//  silently break matching in only one of them.
//

import Foundation

enum UUIDMatching {
    static func normalize(_ uuid: String) -> String {
        uuid.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func matches(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        return normalize(a) == normalize(b)
    }
}
