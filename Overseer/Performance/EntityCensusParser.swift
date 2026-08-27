//
//  EntityCensusParser.swift
//  Overseer
//
//  Counts rows per distinct value of a CSV column — used for both
//  entities.csv ("type" column: minecraft:zombie, minecraft:item, …)
//  and block_entities.csv (also "type": minecraft:furnace,
//  minecraft:hopper, …), since both are just "count how many of each
//  kind exist right now." This is the actual mob/block-entity count the
//  Performance feature exists for — a live snapshot, not an estimate
//  derived from the profiler's per-tick sampling.
//

import Foundation

enum EntityCensusParser {
    static func count(csv text: String, column: String = "type") -> [EntityTypeCount] {
        let rows = SimpleCSV.rows(text)
        guard let header = rows.first else { return [] }
        let index = SimpleCSV.columnIndex(header: header)
        guard let typeIndex = index[column] else { return [] }

        var counts: [String: Int] = [:]
        for row in rows.dropFirst() where row.count > typeIndex {
            counts[row[typeIndex], default: 0] += 1
        }
        return counts
            .map { EntityTypeCount(type: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.type < $1.type : $0.count > $1.count }
    }
}
