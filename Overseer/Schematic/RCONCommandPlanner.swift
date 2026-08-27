//
//  RCONCommandPlanner.swift
//  Overseer
//
//  Turns [PlacedBlock] into the actual vanilla /setblock and /fill
//  command strings RCONBuildQueue dispatches. Two modes:
//   - setBlockCommands: one /setblock per block, no optimization.
//   - optimizedCommands: merges contiguous same-blockstate runs along
//     the X axis into single /fill spans. A pragmatic middle ground
//     between "one command per block" and full 3D greedy box-merging
//     (not attempted — Y/Z merging would shrink large flat builds
//     further, but X-run merging alone already captures most of the
//     benefit for typical structures, at a fraction of the complexity).
//

import Foundation

enum RCONCommandPlanner {
    private struct Row: Hashable {
        var y: Int
        var z: Int
        var blockState: String
    }

    static func setBlockCommands(for blocks: [PlacedBlock]) -> [String] {
        orderedForPlacement(blocks).map {
            VanillaCommands.setBlock(x: $0.position.x, y: $0.position.y, z: $0.position.z, blockState: $0.blockStateString)
        }
    }

    static func optimizedCommands(for blocks: [PlacedBlock]) -> [String] {
        var rows: [Row: [Int]] = [:]
        for block in blocks {
            let row = Row(y: block.position.y, z: block.position.z, blockState: block.blockStateString)
            rows[row, default: []].append(block.position.x)
        }

        var commands: [String] = []
        let orderedRows = rows.keys.sorted { lhs, rhs in
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.z < rhs.z
        }
        for row in orderedRows {
            let xs = rows[row]!.sorted()
            var runStart = xs[0]
            var previous = xs[0]
            for x in xs.dropFirst() {
                if x == previous + 1 {
                    previous = x
                    continue
                }
                commands.append(command(from: runStart, to: previous, row: row))
                runStart = x
                previous = x
            }
            commands.append(command(from: runStart, to: previous, row: row))
        }
        return commands
    }

    private static func command(from start: Int, to end: Int, row: Row) -> String {
        if start == end {
            return VanillaCommands.setBlock(x: start, y: row.y, z: row.z, blockState: row.blockState)
        }
        return VanillaCommands.fill(x1: start, y1: row.y, z1: row.z, x2: end, y2: row.y, z2: row.z, blockState: row.blockState)
    }

    /// Bottom-up (ascending Y, then Z, then X) ordering. Vanilla
    /// `/setblock`/`/fill` bypass normal placement-support checks, but
    /// still trigger neighbor block updates — a block placed before
    /// whatever's meant to support it (e.g. a torch before its wall)
    /// can immediately pop off and drop as an item. Building bottom-up
    /// is a best-effort mitigation, not a guarantee; there's no vanilla
    /// command flag to fully suppress update-triggered breakage.
    private static func orderedForPlacement(_ blocks: [PlacedBlock]) -> [PlacedBlock] {
        blocks.sorted { lhs, rhs in
            if lhs.position.y != rhs.position.y { return lhs.position.y < rhs.position.y }
            if lhs.position.z != rhs.position.z { return lhs.position.z < rhs.position.z }
            return lhs.position.x < rhs.position.x
        }
    }
}
