//
//  InventorySearchEngine.swift
//  Overseer
//
//  "Who has this item" search across every parsed player at once — the
//  actual workflow behind the feature (a player reports something
//  stolen; the admin needs to find who's currently holding it, not
//  browse one inventory at a time).
//

import Foundation

struct InventorySearchResult: Identifiable {
    var player: ParsedPlayerData
    var item: InventoryItemStack
    var container: InventoryContainer

    var id: String { "\(player.uuid)-\(container.rawValue)-\(item.id)" }
}

enum InventoryContainer: String {
    case inventory = "Inventory"
    case enderChest = "Ender Chest"
}

enum InventorySearchEngine {
    /// Matches on item ID (namespace optional, e.g. "diamond" matches
    /// "minecraft:diamond_sword"), display name, or custom name —
    /// whatever the admin is likely to type. Empty query returns no
    /// results (this is a targeted lookup, not a browse-everything view).
    static func search(query: String, in players: [ParsedPlayerData]) -> [InventorySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        var results: [InventorySearchResult] = []
        for player in players {
            for item in player.mainInventory where matches(item, trimmed) {
                results.append(InventorySearchResult(player: player, item: item, container: .inventory))
            }
            for item in player.enderChest where matches(item, trimmed) {
                results.append(InventorySearchResult(player: player, item: item, container: .enderChest))
            }
        }
        return results.sorted { $0.item.count > $1.item.count }
    }

    private static func matches(_ item: InventoryItemStack, _ query: String) -> Bool {
        item.itemID.lowercased().contains(query)
            || item.displayName.lowercased().contains(query)
            || (item.customName?.lowercased().contains(query) ?? false)
    }
}
