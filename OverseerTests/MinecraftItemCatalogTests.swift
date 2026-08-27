//
//  MinecraftItemCatalogTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("MinecraftItemCatalog")
struct MinecraftItemCatalogTests {

    @Test("Every catalog entry is a namespaced, unique, non-empty vanilla ID")
    func catalogEntriesAreWellFormed() {
        #expect(!MinecraftItemCatalog.items.isEmpty)
        for item in MinecraftItemCatalog.items {
            #expect(item.id.hasPrefix("minecraft:"))
            #expect(!item.displayName.isEmpty)
        }
        let ids = MinecraftItemCatalog.items.map(\.id)
        #expect(Set(ids).count == ids.count, "catalog contains a duplicate item ID")
    }

    @Test("Search matches by display name or raw ID, case-insensitively")
    func searchMatchesNameOrID() {
        let byName = MinecraftItemCatalog.search("Diamond Sword")
        #expect(byName.contains { $0.id == "minecraft:diamond_sword" })

        let byID = MinecraftItemCatalog.search("diamond_sword")
        #expect(byID.contains { $0.id == "minecraft:diamond_sword" })

        let caseInsensitive = MinecraftItemCatalog.search("dIaMoNd sWoRd")
        #expect(caseInsensitive.contains { $0.id == "minecraft:diamond_sword" })
    }

    @Test("Empty query returns the full catalog")
    func emptyQueryReturnsEverything() {
        #expect(MinecraftItemCatalog.search("").count == MinecraftItemCatalog.items.count)
        #expect(MinecraftItemCatalog.search("   ").count == MinecraftItemCatalog.items.count)
    }

    @Test("A nonsense query matches nothing")
    func nonsenseQueryMatchesNothing() {
        #expect(MinecraftItemCatalog.search("qqqqzzzznotanitem").isEmpty)
    }

    @Test("items(in:) only returns entries tagged with that category")
    func itemsInCategoryAreFiltered() {
        let tools = MinecraftItemCatalog.items(in: .tools)
        #expect(!tools.isEmpty)
        #expect(tools.allSatisfy { $0.category == .tools })
    }
}
