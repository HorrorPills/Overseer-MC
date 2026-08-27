//
//  PlayerStatsFileParser.swift
//  Overseer
//
//  Decodes a vanilla per-player stats file (`world/stats/<uuid>.json`)
//  just far enough to pull out total play time. Unlike playerdata's
//  `.dat` files this is plain JSON, not NBT — a separate, simpler
//  format vanilla has used since the 1.13 stat-namespacing rework.
//
//  The stat's ID was renamed once: `minecraft:play_one_minute`
//  (1.13–1.16, a holdover name from the pre-1.13 flat-stats era even
//  though it was already tracked per-tick) became `minecraft:play_time`
//  in 1.17. Both are read here — whichever key is present — so this
//  works regardless of server version. The older pre-1.13 flat
//  (non-namespaced) stats format isn't supported; this app's vanilla
//  target has always been well past that.
//
//  Units: the stat is in game ticks, 20 per real-world second — the
//  same fixed rate the rest of the app already assumes for MSPT/TPS.
//

import Foundation

struct ParsedPlayerStats {
    var uuid: String
    var fileURL: URL
    var playTimeTicks: Int64?

    var playTimeSeconds: Double? {
        playTimeTicks.map { Double($0) / 20.0 }
    }
}

enum PlayerStatsFileParserError: Error, LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "File isn't a valid player stats JSON document."
        }
    }
}

enum PlayerStatsFileParser {
    static func parse(uuid: String, data: Data, fileURL: URL) throws -> ParsedPlayerStats {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stats = root["stats"] as? [String: Any] else {
            throw PlayerStatsFileParserError.invalidJSON
        }
        let custom = stats["minecraft:custom"] as? [String: Any]
        let ticks = numericValue(custom?["minecraft:play_time"]) ?? numericValue(custom?["minecraft:play_one_minute"])
        return ParsedPlayerStats(uuid: uuid, fileURL: fileURL, playTimeTicks: ticks)
    }

    private static func numericValue(_ any: Any?) -> Int64? {
        (any as? NSNumber)?.int64Value
    }
}
