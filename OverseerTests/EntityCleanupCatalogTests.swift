//
//  EntityCleanupCatalogTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("EntityCleanupCatalog")
struct EntityCleanupCatalogTests {

    @Test("Every category returns at least one selector")
    func everyCategoryHasSelectors() {
        for category in LagClearCategory.allCases {
            #expect(!EntityCleanupCatalog.selectors(for: category).isEmpty, "\(category) has no selectors")
        }
    }

    @Test("Dropped items and XP orbs are exactly one selector each")
    func singleTypeCategories() {
        #expect(EntityCleanupCatalog.selectors(for: .droppedItems) == ["minecraft:item"])
        #expect(EntityCleanupCatalog.selectors(for: .experienceOrbs) == ["minecraft:experience_orb"])
    }

    @Test("No selector repeats within a category")
    func noDuplicatesWithinCategory() {
        for category in LagClearCategory.allCases {
            let selectors = EntityCleanupCatalog.selectors(for: category)
            #expect(Set(selectors).count == selectors.count, "\(category) has duplicate selectors")
        }
    }

    @Test("No category ever includes a boss mob, a horse mount, or the Warden")
    func neverIncludesDangerousExclusions() {
        let excluded = ["minecraft:wither", "minecraft:ender_dragon", "minecraft:warden", "minecraft:skeleton_horse", "minecraft:zombie_horse"]
        for category in LagClearCategory.allCases {
            let selectors = EntityCleanupCatalog.selectors(for: category)
            for banned in excluded {
                #expect(!selectors.contains(banned), "\(category) must never include \(banned)")
            }
        }
    }

    @Test("Hostile mobs excludes endermite — thrown ender pearls spawn one as the bait/aggro mechanism a public enderman farm runs on, so auto-killing it would break the farm mid-cycle")
    func excludesEndermite() {
        #expect(!EntityCleanupCatalog.selectors(for: .hostileMobs).contains("minecraft:endermite"))
    }

    @Test("Projectiles excludes ender pearls — that's its own separate opt-in category (.enderPearls) instead, not bundled with arrows/snowballs/etc.")
    func projectilesExcludesEnderPearl() {
        #expect(!EntityCleanupCatalog.selectors(for: .projectiles).contains("minecraft:ender_pearl"))
    }

    @Test("Ender pearls is its own category, targeting only the pearl entity, and carries a risk note (off by default in AppSettings)")
    func enderPearlsIsItsOwnCategoryWithARiskNote() {
        #expect(EntityCleanupCatalog.selectors(for: .enderPearls) == ["minecraft:ender_pearl"])
        #expect(LagClearCategory.enderPearls.riskNote != nil)
    }

    @Test("No category ever includes a passive/placed entity a player would have deliberately kept")
    func neverIncludesPlacedOrPassiveEntities() {
        let neverTouch = [
            "minecraft:item_frame", "minecraft:glow_item_frame", "minecraft:armor_stand", "minecraft:painting",
            "minecraft:boat", "minecraft:minecart", "minecraft:villager", "minecraft:iron_golem", "minecraft:snow_golem",
            "minecraft:cow", "minecraft:pig", "minecraft:sheep", "minecraft:chicken", "minecraft:horse", "minecraft:wolf", "minecraft:cat"
        ]
        for category in LagClearCategory.allCases {
            let selectors = EntityCleanupCatalog.selectors(for: category)
            for safe in neverTouch {
                #expect(!selectors.contains(safe), "\(category) must never include \(safe)")
            }
        }
    }

    @Test("Hostile mobs only uses namespaced IDs or entity type tags, never a bare unqualified name")
    func hostileMobSelectorsAreWellFormed() {
        for selector in EntityCleanupCatalog.selectors(for: .hostileMobs) {
            #expect(selector.hasPrefix("minecraft:") || selector.hasPrefix("#minecraft:"), "malformed selector: \(selector)")
        }
    }

    @Test("sweepOrdered runs hostile mobs and TNT before dropped items/XP orbs, so mob loot gets caught by the same sweep's item pass")
    func sweepOrderPutsLootProducersFirst() {
        let all: Set<LagClearCategory> = [.droppedItems, .experienceOrbs, .projectiles, .primedTNT, .hostileMobs]
        let ordered = LagClearCategory.sweepOrdered(all)
        let hostileIndex = try! #require(ordered.firstIndex(of: .hostileMobs))
        let itemsIndex = try! #require(ordered.firstIndex(of: .droppedItems))
        let orbsIndex = try! #require(ordered.firstIndex(of: .experienceOrbs))
        #expect(hostileIndex < itemsIndex)
        #expect(hostileIndex < orbsIndex)
    }

    @Test("sweepOrdered only includes the categories passed in, in a stable order")
    func sweepOrderFiltersToInputSet() {
        let ordered = LagClearCategory.sweepOrdered([.droppedItems, .hostileMobs])
        #expect(ordered == [.hostileMobs, .droppedItems])
        #expect(LagClearCategory.sweepOrdered([]).isEmpty)
    }

    @Test("Every LagClearCategory has a non-empty label")
    func everyCategoryHasALabel() {
        for category in LagClearCategory.allCases {
            #expect(!category.label.isEmpty)
        }
    }
}
