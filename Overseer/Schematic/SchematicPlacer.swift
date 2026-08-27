//
//  SchematicPlacer.swift
//  Overseer
//
//  Ties parsing, rotation, and coordinate transform together: a parsed
//  schematic + placement settings in, a flat list of "put this block
//  here" instructions out. RCONCommandPlanner turns that into actual
//  /setblock and /fill strings.
//

import Foundation

struct PlacedBlock: Equatable {
    var position: WorldPosition
    var blockID: String
    var properties: [String: String]

    var blockStateString: String {
        BlockStateStringParser.format(blockID: blockID, properties: properties)
    }
}

enum SchematicPlacer {
    static func placedBlocks(
        schematic: ParsedSchematic,
        target: WorldPosition,
        rotation: Rotation,
        anchor: AnchorPoint,
        ignoreAir: Bool
    ) -> [PlacedBlock] {
        schematic.blocks.compactMap { block in
            if ignoreAir && block.isAir { return nil }

            let rotatedProperties = BlockStateRotator.rotate(properties: block.properties, rotation: rotation)
            let worldPosition = SchematicTransform.worldPosition(
                relativeX: block.x,
                relativeY: block.y,
                relativeZ: block.z,
                schematicWidth: schematic.width,
                schematicLength: schematic.length,
                rotation: rotation,
                anchor: anchor,
                target: target
            )
            return PlacedBlock(position: worldPosition, blockID: block.blockID, properties: rotatedProperties)
        }
    }
}
