//
//  BiomeColorPalette.swift
//  Overseer
//
//  Chunkbase-style flat biome colors for the World Map's terrain layer.
//  Deliberately not exhaustive of every possible biome ID a modpack or
//  a future vanilla snapshot might add — anything unrecognized falls
//  back to a neutral gray rather than guessing, which is a more honest
//  failure mode for a griefer-investigation tool than a wrong color.
//

import SwiftUI

enum BiomeColorPalette {
    private static let colors: [String: Color] = [
        // Oceans
        "minecraft:ocean": Color(red: 0.02, green: 0.29, blue: 0.64),
        "minecraft:deep_ocean": Color(red: 0.01, green: 0.16, blue: 0.45),
        "minecraft:warm_ocean": Color(red: 0.09, green: 0.51, blue: 0.85),
        "minecraft:lukewarm_ocean": Color(red: 0.06, green: 0.40, blue: 0.75),
        "minecraft:deep_lukewarm_ocean": Color(red: 0.04, green: 0.24, blue: 0.55),
        "minecraft:cold_ocean": Color(red: 0.10, green: 0.24, blue: 0.45),
        "minecraft:deep_cold_ocean": Color(red: 0.07, green: 0.17, blue: 0.35),
        "minecraft:frozen_ocean": Color(red: 0.55, green: 0.62, blue: 0.75),
        "minecraft:deep_frozen_ocean": Color(red: 0.40, green: 0.48, blue: 0.62),
        "minecraft:river": Color(red: 0.15, green: 0.45, blue: 0.80),
        "minecraft:frozen_river": Color(red: 0.60, green: 0.68, blue: 0.82),

        // Plains / grassy
        "minecraft:plains": Color(red: 0.55, green: 0.71, blue: 0.31),
        "minecraft:sunflower_plains": Color(red: 0.62, green: 0.76, blue: 0.28),
        "minecraft:meadow": Color(red: 0.51, green: 0.75, blue: 0.32),

        // Forests
        "minecraft:forest": Color(red: 0.31, green: 0.56, blue: 0.24),
        "minecraft:flower_forest": Color(red: 0.42, green: 0.63, blue: 0.30),
        "minecraft:birch_forest": Color(red: 0.42, green: 0.60, blue: 0.32),
        "minecraft:old_growth_birch_forest": Color(red: 0.38, green: 0.55, blue: 0.30),
        "minecraft:dark_forest": Color(red: 0.24, green: 0.36, blue: 0.16),
        "minecraft:old_growth_spruce_taiga": Color(red: 0.25, green: 0.42, blue: 0.30),
        "minecraft:old_growth_pine_taiga": Color(red: 0.27, green: 0.44, blue: 0.32),
        "minecraft:taiga": Color(red: 0.29, green: 0.46, blue: 0.36),
        "minecraft:snowy_taiga": Color(red: 0.55, green: 0.66, blue: 0.62),
        "minecraft:grove": Color(red: 0.58, green: 0.70, blue: 0.70),

        // Mountains / hills
        "minecraft:windswept_hills": Color(red: 0.55, green: 0.53, blue: 0.47),
        "minecraft:windswept_gravelly_hills": Color(red: 0.58, green: 0.57, blue: 0.55),
        "minecraft:windswept_forest": Color(red: 0.40, green: 0.48, blue: 0.38),
        "minecraft:windswept_savanna": Color(red: 0.62, green: 0.58, blue: 0.36),
        "minecraft:jagged_peaks": Color(red: 0.80, green: 0.82, blue: 0.86),
        "minecraft:frozen_peaks": Color(red: 0.75, green: 0.80, blue: 0.88),
        "minecraft:stony_peaks": Color(red: 0.60, green: 0.58, blue: 0.55),
        "minecraft:snowy_slopes": Color(red: 0.82, green: 0.86, blue: 0.90),

        // Desert / dry
        "minecraft:desert": Color(red: 0.87, green: 0.78, blue: 0.47),
        "minecraft:badlands": Color(red: 0.68, green: 0.42, blue: 0.27),
        "minecraft:eroded_badlands": Color(red: 0.72, green: 0.46, blue: 0.30),
        "minecraft:wooded_badlands": Color(red: 0.60, green: 0.44, blue: 0.28),
        "minecraft:savanna": Color(red: 0.72, green: 0.68, blue: 0.34),
        "minecraft:savanna_plateau": Color(red: 0.68, green: 0.65, blue: 0.34),

        // Swamp / jungle
        "minecraft:swamp": Color(red: 0.34, green: 0.40, blue: 0.32),
        "minecraft:mangrove_swamp": Color(red: 0.30, green: 0.42, blue: 0.30),
        "minecraft:jungle": Color(red: 0.20, green: 0.55, blue: 0.16),
        "minecraft:sparse_jungle": Color(red: 0.30, green: 0.58, blue: 0.22),
        "minecraft:bamboo_jungle": Color(red: 0.24, green: 0.58, blue: 0.20),

        // Snowy / cold
        "minecraft:snowy_plains": Color(red: 0.85, green: 0.88, blue: 0.90),
        "minecraft:ice_spikes": Color(red: 0.78, green: 0.88, blue: 0.92),

        // Beaches / misc
        "minecraft:beach": Color(red: 0.87, green: 0.82, blue: 0.58),
        "minecraft:snowy_beach": Color(red: 0.85, green: 0.87, blue: 0.86),
        "minecraft:stony_shore": Color(red: 0.55, green: 0.54, blue: 0.52),
        "minecraft:mushroom_fields": Color(red: 0.62, green: 0.38, blue: 0.44),

        // Caves / underground (unlikely at the sampled Y, kept for completeness)
        "minecraft:dripstone_caves": Color(red: 0.46, green: 0.38, blue: 0.30),
        "minecraft:lush_caves": Color(red: 0.28, green: 0.52, blue: 0.30),
        "minecraft:deep_dark": Color(red: 0.14, green: 0.14, blue: 0.18),

        // Nether / End (not rendered by default — World Map is overworld-only — kept in case a future dimension toggle uses this palette too)
        "minecraft:nether_wastes": Color(red: 0.45, green: 0.16, blue: 0.12),
        "minecraft:crimson_forest": Color(red: 0.55, green: 0.10, blue: 0.14),
        "minecraft:warped_forest": Color(red: 0.10, green: 0.45, blue: 0.42),
        "minecraft:soul_sand_valley": Color(red: 0.30, green: 0.25, blue: 0.22),
        "minecraft:basalt_deltas": Color(red: 0.35, green: 0.33, blue: 0.35),
        "minecraft:the_end": Color(red: 0.85, green: 0.85, blue: 0.72),
        "minecraft:end_highlands": Color(red: 0.82, green: 0.82, blue: 0.68),
        "minecraft:end_midlands": Color(red: 0.80, green: 0.80, blue: 0.66),
        "minecraft:small_end_islands": Color(red: 0.78, green: 0.78, blue: 0.64),
        "minecraft:end_barrens": Color(red: 0.70, green: 0.70, blue: 0.58)
    ]

    /// Neutral gray for anything not in the table above, rather than a
    /// guessed color — an unrecognized biome ID should read as "unknown
    /// to this app," never as if it confidently identified the terrain.
    static let unknown = Color(white: 0.5)

    static func color(for biomeID: String) -> Color {
        colors[biomeID] ?? unknown
    }
}
