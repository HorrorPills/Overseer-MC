//
//  SuspicionEngineTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("SuspicionEngine")
struct SuspicionEngineTests {

    private func player(items: [InventoryItemStack]) -> ParsedPlayerData {
        ParsedPlayerData(uuid: "u", fileURL: URL(fileURLWithPath: "/tmp/u.dat"), fileModifiedAt: nil, mainInventory: items, enderChest: [])
    }

    private func stack(_ id: String, slot: Int = 0) -> InventoryItemStack {
        InventoryItemStack(slot: slot, itemID: id, count: 1, damage: nil, customName: nil, enchantments: [])
    }

    @Test("No watchlisted items means no flag regardless of playtime")
    func noItemsNoFlag() {
        let flag = SuspicionEngine.evaluate(player: player(items: [stack("minecraft:dirt")]), playTimeSeconds: 0)
        #expect(!flag.hasWatchlistedItems)
        #expect(!flag.isLowPlaytimeWithValuables)
    }

    @Test("Watchlisted items with playtime above the threshold are noted but not flagged as suspicious")
    func valuablesWithEnoughPlaytimeAreNotFlagged() {
        let flag = SuspicionEngine.evaluate(
            player: player(items: [stack("minecraft:elytra")]),
            playTimeSeconds: 10 * 3600,
            lowPlaytimeThresholdSeconds: 2 * 3600
        )
        #expect(flag.hasWatchlistedItems)
        #expect(!flag.isLowPlaytimeWithValuables)
    }

    @Test("Watchlisted items with playtime below the threshold are flagged")
    func valuablesWithLowPlaytimeAreFlagged() {
        let flag = SuspicionEngine.evaluate(
            player: player(items: [stack("minecraft:netherite_ingot")]),
            playTimeSeconds: 600,
            lowPlaytimeThresholdSeconds: 2 * 3600
        )
        #expect(flag.isLowPlaytimeWithValuables)
        #expect(flag.watchlistedItems.map(\.itemID) == ["minecraft:netherite_ingot"])
    }

    @Test("Both main inventory and ender chest are scanned")
    func scansBothContainers() {
        let data = ParsedPlayerData(
            uuid: "u", fileURL: URL(fileURLWithPath: "/tmp/u.dat"), fileModifiedAt: nil,
            mainInventory: [stack("minecraft:dirt")],
            enderChest: [stack("minecraft:dragon_egg")]
        )
        let flag = SuspicionEngine.evaluate(player: data, playTimeSeconds: 0)
        #expect(flag.watchlistedItems.map(\.itemID) == ["minecraft:dragon_egg"])
    }

    @Test("Non-watchlisted valuable-adjacent items (plain diamond sword) are not flagged")
    func plainDiamondGearIsNotWatchlisted() {
        #expect(!ValuableItemWatchlist.matches("minecraft:diamond_sword"))
        #expect(ValuableItemWatchlist.matches("minecraft:diamond"))
    }

    @Test("Exactly at the threshold counts as enough playtime, not low")
    func exactlyAtThresholdIsNotLow() {
        let flag = SuspicionEngine.evaluate(
            player: player(items: [stack("minecraft:elytra")]),
            playTimeSeconds: 7200,
            lowPlaytimeThresholdSeconds: 7200
        )
        #expect(!flag.isLowPlaytimeWithValuables)
    }
}
