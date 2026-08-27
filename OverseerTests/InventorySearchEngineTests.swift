//
//  InventorySearchEngineTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("InventorySearchEngine")
struct InventorySearchEngineTests {

    private func player(uuid: String, inventory: [InventoryItemStack] = [], ender: [InventoryItemStack] = []) -> ParsedPlayerData {
        ParsedPlayerData(uuid: uuid, fileURL: URL(fileURLWithPath: "/tmp/\(uuid).dat"), fileModifiedAt: nil, mainInventory: inventory, enderChest: ender)
    }

    private func stack(slot: Int, id: String, count: Int = 1, customName: String? = nil) -> InventoryItemStack {
        InventoryItemStack(slot: slot, itemID: id, count: count, damage: nil, customName: customName, enchantments: [])
    }

    @Test("Empty query returns no results")
    func emptyQueryReturnsNothing() {
        let players = [player(uuid: "a", inventory: [stack(slot: 0, id: "minecraft:diamond")])]
        #expect(InventorySearchEngine.search(query: "", in: players).isEmpty)
        #expect(InventorySearchEngine.search(query: "   ", in: players).isEmpty)
    }

    @Test("Matches by bare item name without the namespace")
    func matchesByBareName() {
        let players = [player(uuid: "a", inventory: [stack(slot: 0, id: "minecraft:diamond_sword")])]
        let results = InventorySearchEngine.search(query: "diamond", in: players)
        #expect(results.count == 1)
        #expect(results[0].container == .inventory)
    }

    @Test("Matches by custom name, and finds items across both inventory and ender chest")
    func matchesAcrossContainers() {
        let players = [
            player(
                uuid: "a",
                inventory: [stack(slot: 0, id: "minecraft:diamond_sword", customName: "Stolen Blade")],
                ender: [stack(slot: 3, id: "minecraft:netherite_ingot", count: 5)]
            )
        ]
        let byCustomName = InventorySearchEngine.search(query: "stolen", in: players)
        #expect(byCustomName.count == 1)
        #expect(byCustomName[0].container == .inventory)

        let byEnderItem = InventorySearchEngine.search(query: "netherite", in: players)
        #expect(byEnderItem.count == 1)
        #expect(byEnderItem[0].container == .enderChest)
        #expect(byEnderItem[0].item.count == 5)
    }

    @Test("Results across multiple players are sorted by count descending")
    func sortsByCountDescending() {
        let players = [
            player(uuid: "a", inventory: [stack(slot: 0, id: "minecraft:emerald", count: 3)]),
            player(uuid: "b", inventory: [stack(slot: 0, id: "minecraft:emerald", count: 40)])
        ]
        let results = InventorySearchEngine.search(query: "emerald", in: players)
        #expect(results.map { $0.player.uuid } == ["b", "a"])
    }

    @Test("No match yields an empty result set")
    func noMatchYieldsEmpty() {
        let players = [player(uuid: "a", inventory: [stack(slot: 0, id: "minecraft:dirt")])]
        #expect(InventorySearchEngine.search(query: "diamond", in: players).isEmpty)
    }
}
