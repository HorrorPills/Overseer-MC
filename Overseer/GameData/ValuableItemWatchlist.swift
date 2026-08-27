//
//  ValuableItemWatchlist.swift
//  Overseer
//
//  A curated set of vanilla items worth flagging when found in a
//  low-playtime player's inventory — either individually rare/expensive
//  to obtain (netherite gear, elytra, totems), effectively one-per-world
//  (dragon egg/head), or valuable for what they might be hiding (shulker
//  boxes). Deliberately not the full ~1400-item registry, same curation
//  philosophy as MinecraftItemCatalog: real, stable IDs worth an admin's
//  attention, not an exhaustive dump.
//

import Foundation

enum ValuableItemWatchlist {
    static let itemIDs: Set<String> = [
        // Netherite — the single most time-costly tier to gear up in,
        // each piece needing ancient debris plus a full diamond piece.
        "minecraft:netherite_ingot",
        "minecraft:netherite_block",
        "minecraft:ancient_debris",
        "minecraft:netherite_scrap",
        "minecraft:netherite_upgrade_smithing_template",
        "minecraft:netherite_sword",
        "minecraft:netherite_axe",
        "minecraft:netherite_pickaxe",
        "minecraft:netherite_shovel",
        "minecraft:netherite_hoe",
        "minecraft:netherite_helmet",
        "minecraft:netherite_chestplate",
        "minecraft:netherite_leggings",
        "minecraft:netherite_boots",

        // Effectively one-of-a-kind, or requiring a boss/structure fight.
        "minecraft:elytra",
        "minecraft:totem_of_undying",
        "minecraft:nether_star",
        "minecraft:dragon_egg",
        "minecraft:dragon_head",
        "minecraft:beacon",
        "minecraft:enchanted_golden_apple",
        "minecraft:shulker_shell",

        // Storage worth stealing for its contents, not just itself —
        // every colored variant plus the undyed base block.
        "minecraft:shulker_box",
        "minecraft:white_shulker_box", "minecraft:orange_shulker_box", "minecraft:magenta_shulker_box",
        "minecraft:light_blue_shulker_box", "minecraft:yellow_shulker_box", "minecraft:lime_shulker_box",
        "minecraft:pink_shulker_box", "minecraft:gray_shulker_box", "minecraft:light_gray_shulker_box",
        "minecraft:cyan_shulker_box", "minecraft:purple_shulker_box", "minecraft:blue_shulker_box",
        "minecraft:brown_shulker_box", "minecraft:green_shulker_box", "minecraft:red_shulker_box",
        "minecraft:black_shulker_box",

        // Diamond-tier — not individually rare, but worth flagging in bulk.
        "minecraft:diamond_block",
        "minecraft:diamond",
        "minecraft:emerald_block"
    ]

    static func matches(_ itemID: String) -> Bool {
        itemIDs.contains(itemID)
    }
}
