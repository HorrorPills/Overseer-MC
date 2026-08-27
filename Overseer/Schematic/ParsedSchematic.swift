//
//  ParsedSchematic.swift
//  Overseer
//
//  Format-agnostic result of parsing a schematic file. Coordinates are
//  relative to the schematic's own (0,0,0) corner — SchematicTransform
//  is what maps these onto real world coordinates for placement.
//

import Foundation

struct SchematicBlock: Equatable, Sendable {
    var x: Int
    var y: Int
    var z: Int
    var blockID: String
    var properties: [String: String]

    /// Reassembles the vanilla blockstate string vanilla's `/setblock`
    /// and `/fill` expect, e.g. "minecraft:oak_stairs[facing=north]".
    var blockStateString: String {
        BlockStateStringParser.format(blockID: blockID, properties: properties)
    }

    /// Vanilla's own "nothing here" block IDs — what "Ignore Air
    /// Blocks" filters out. `cave_air`/`void_air` are included since
    /// they're functionally air and commonly appear in captured
    /// schematics (e.g. anything grabbed near a cave or the void).
    static let airBlockIDs: Set<String> = [
        "minecraft:air", "minecraft:cave_air", "minecraft:void_air", "minecraft:structure_void"
    ]

    var isAir: Bool { Self.airBlockIDs.contains(blockID) }
}

struct ParsedSchematic: Equatable, Sendable {
    var width: Int
    var height: Int
    var length: Int
    var blocks: [SchematicBlock]

    var totalVolume: Int { width * height * length }
}
