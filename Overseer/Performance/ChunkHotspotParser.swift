//
//  ChunkHotspotParser.swift
//  Overseer
//
//  Ranks chunks (or, for live entity tracking, chunk *sections* —
//  entity_chunks.csv is keyed by x/y/z, not just x/z) by a count column,
//  so an admin can jump straight to wherever entities or block entities
//  have piled up, instead of guessing from the aggregate counts alone.
//

import Foundation

enum ChunkHotspotParser {
    /// entity_chunks.csv: x,y,z,visibility,load_status,entity_count —
    /// chunk *sections* ranked by how many entities are tracked there.
    static func entityHotspots(csv text: String, limit: Int = 15) -> [ChunkHotspot] {
        hotspots(csv: text, xColumn: "x", yColumn: "y", zColumn: "z", valueColumn: "entity_count", limit: limit)
    }

    /// chunks.csv: ranked by block_entity_count — chunk *columns* (no y).
    static func blockEntityHotspots(csv text: String, limit: Int = 15) -> [ChunkHotspot] {
        hotspots(csv: text, xColumn: "x", yColumn: nil, zColumn: "z", valueColumn: "block_entity_count", limit: limit)
    }

    static func totalLoadedChunks(csv text: String) -> Int {
        max(0, SimpleCSV.rows(text).count - 1)
    }

    /// Sums an integer column across every row — used for
    /// block_ticks/fluid_ticks totals in chunks.csv.
    static func sum(csv text: String, column: String) -> Int {
        let rows = SimpleCSV.rows(text)
        guard let header = rows.first, let index = SimpleCSV.columnIndex(header: header)[column] else { return 0 }
        return rows.dropFirst().reduce(0) { total, row in
            guard row.count > index, let value = Int(row[index]) else { return total }
            return total + value
        }
    }

    private static func hotspots(
        csv text: String, xColumn: String, yColumn: String?, zColumn: String, valueColumn: String, limit: Int
    ) -> [ChunkHotspot] {
        let rows = SimpleCSV.rows(text)
        guard let header = rows.first else { return [] }
        let index = SimpleCSV.columnIndex(header: header)
        guard let xIndex = index[xColumn], let zIndex = index[zColumn], let valueIndex = index[valueColumn] else {
            return []
        }
        let yIndex = yColumn.flatMap { index[$0] }

        var results: [ChunkHotspot] = []
        for row in rows.dropFirst() {
            guard row.count > xIndex, row.count > zIndex, row.count > valueIndex,
                  let x = Int(row[xIndex]), let z = Int(row[zIndex]), let value = Int(row[valueIndex]) else { continue }
            let y = yIndex.flatMap { row.count > $0 ? Int(row[$0]) : nil }
            results.append(ChunkHotspot(x: x, y: y, z: z, value: value))
        }
        return Array(results.sorted { $0.value > $1.value }.prefix(limit))
    }
}
