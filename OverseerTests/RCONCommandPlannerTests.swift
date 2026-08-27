//
//  RCONCommandPlannerTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("RCONCommandPlanner")
struct RCONCommandPlannerTests {

    @Test("setBlockCommands emits one /setblock per block, ordered bottom-up (Y, then Z, then X)")
    func setBlockCommandsOrderedBottomUp() {
        let blocks = [
            PlacedBlock(position: WorldPosition(x: 5, y: 2, z: 0), blockID: "minecraft:stone", properties: [:]),
            PlacedBlock(position: WorldPosition(x: 0, y: 0, z: 0), blockID: "minecraft:dirt", properties: [:]),
            PlacedBlock(position: WorldPosition(x: 0, y: 1, z: 0), blockID: "minecraft:oak_planks", properties: [:])
        ]
        let commands = RCONCommandPlanner.setBlockCommands(for: blocks)
        #expect(commands == [
            "/setblock 0 0 0 minecraft:dirt",
            "/setblock 0 1 0 minecraft:oak_planks",
            "/setblock 5 2 0 minecraft:stone"
        ])
    }

    @Test("setBlockCommands includes blockstate properties in bracket syntax")
    func setBlockCommandsIncludesProperties() {
        let block = PlacedBlock(position: WorldPosition(x: 1, y: 2, z: 3), blockID: "minecraft:oak_stairs", properties: ["facing": "east", "half": "bottom"])
        let commands = RCONCommandPlanner.setBlockCommands(for: [block])
        #expect(commands == ["/setblock 1 2 3 minecraft:oak_stairs[facing=east,half=bottom]"])
    }

    @Test("optimizedCommands merges a contiguous same-blockstate X run into one /fill")
    func optimizedCommandsMergesContiguousRun() {
        let blocks = (0...4).map {
            PlacedBlock(position: WorldPosition(x: $0, y: 0, z: 0), blockID: "minecraft:stone", properties: [:])
        }
        let commands = RCONCommandPlanner.optimizedCommands(for: blocks)
        #expect(commands == ["/fill 0 0 0 4 0 0 minecraft:stone"])
    }

    @Test("optimizedCommands does not merge across a gap in X")
    func optimizedCommandsDoesNotMergeAcrossGap() {
        let blocks = [0, 1, 2, 5, 6].map {
            PlacedBlock(position: WorldPosition(x: $0, y: 0, z: 0), blockID: "minecraft:stone", properties: [:])
        }
        let commands = RCONCommandPlanner.optimizedCommands(for: blocks)
        #expect(commands == [
            "/fill 0 0 0 2 0 0 minecraft:stone",
            "/fill 5 0 0 6 0 0 minecraft:stone"
        ])
    }

    @Test("optimizedCommands falls back to /setblock for an isolated single block")
    func optimizedCommandsIsolatedBlockUsesSetblock() {
        let commands = RCONCommandPlanner.optimizedCommands(for: [
            PlacedBlock(position: WorldPosition(x: 7, y: 3, z: 9), blockID: "minecraft:torch", properties: [:])
        ])
        #expect(commands == ["/setblock 7 3 9 minecraft:torch"])
    }

    @Test("optimizedCommands keeps different Y/Z/blockstate rows separate, ordered bottom-up")
    func optimizedCommandsKeepsRowsSeparate() {
        let blocks = [
            PlacedBlock(position: WorldPosition(x: 0, y: 1, z: 0), blockID: "minecraft:stone", properties: [:]),
            PlacedBlock(position: WorldPosition(x: 1, y: 1, z: 0), blockID: "minecraft:stone", properties: [:]),
            PlacedBlock(position: WorldPosition(x: 0, y: 0, z: 0), blockID: "minecraft:dirt", properties: [:]),
            PlacedBlock(position: WorldPosition(x: 0, y: 0, z: 1), blockID: "minecraft:dirt", properties: [:])
        ]
        let commands = RCONCommandPlanner.optimizedCommands(for: blocks)
        #expect(commands == [
            "/setblock 0 0 0 minecraft:dirt",
            "/setblock 0 0 1 minecraft:dirt",
            "/fill 0 1 0 1 1 0 minecraft:stone"
        ])
    }

    @Test("optimizedCommands never merges blocks with different blockstates even if adjacent")
    func optimizedCommandsDoesNotMergeDifferentBlockstates() {
        let blocks = [
            PlacedBlock(position: WorldPosition(x: 0, y: 0, z: 0), blockID: "minecraft:stone", properties: [:]),
            PlacedBlock(position: WorldPosition(x: 1, y: 0, z: 0), blockID: "minecraft:dirt", properties: [:])
        ]
        let commands = RCONCommandPlanner.optimizedCommands(for: blocks)
        #expect(commands.count == 2)
        #expect(commands.allSatisfy { $0.hasPrefix("/setblock") })
    }
}
