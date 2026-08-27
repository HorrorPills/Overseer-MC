//
//  SchematicPlacerTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("SchematicPlacer")
struct SchematicPlacerTests {

    private func schematic() -> ParsedSchematic {
        ParsedSchematic(width: 2, height: 1, length: 1, blocks: [
            SchematicBlock(x: 0, y: 0, z: 0, blockID: "minecraft:stone", properties: [:]),
            SchematicBlock(x: 1, y: 0, z: 0, blockID: "minecraft:air", properties: [:])
        ])
    }

    @Test("ignoreAir drops air blocks when enabled")
    func ignoreAirFiltersAirBlocks() {
        let placed = SchematicPlacer.placedBlocks(
            schematic: schematic(), target: WorldPosition(x: 0, y: 0, z: 0),
            rotation: .none, anchor: .corner, ignoreAir: true
        )
        #expect(placed.count == 1)
        #expect(placed[0].blockID == "minecraft:stone")
    }

    @Test("ignoreAir disabled keeps air blocks")
    func ignoreAirDisabledKeepsAirBlocks() {
        let placed = SchematicPlacer.placedBlocks(
            schematic: schematic(), target: WorldPosition(x: 0, y: 0, z: 0),
            rotation: .none, anchor: .corner, ignoreAir: false
        )
        #expect(placed.count == 2)
    }

    @Test("Rotation is applied to both position and block-state properties")
    func rotationAppliesToPositionAndProperties() {
        let facing = ParsedSchematic(width: 1, height: 1, length: 1, blocks: [
            SchematicBlock(x: 0, y: 0, z: 0, blockID: "minecraft:furnace", properties: ["facing": "north"])
        ])
        let placed = SchematicPlacer.placedBlocks(
            schematic: facing, target: WorldPosition(x: 10, y: 10, z: 10),
            rotation: .clockwise90, anchor: .corner, ignoreAir: true
        )
        #expect(placed.count == 1)
        #expect(placed[0].properties["facing"] == "east")
        #expect(placed[0].position == WorldPosition(x: 10, y: 10, z: 10)) // 1x1 footprint, no positional change
    }

    @Test("Anchor and target offset both apply to the final world position")
    func anchorAndTargetOffsetApply() {
        let schematic = ParsedSchematic(width: 4, height: 1, length: 4, blocks: [
            SchematicBlock(x: 0, y: 0, z: 0, blockID: "minecraft:stone", properties: [:])
        ])
        let placed = SchematicPlacer.placedBlocks(
            schematic: schematic, target: WorldPosition(x: 100, y: 64, z: 200),
            rotation: .none, anchor: .centerBottom, ignoreAir: true
        )
        #expect(placed[0].position == WorldPosition(x: 98, y: 64, z: 198))
    }
}
