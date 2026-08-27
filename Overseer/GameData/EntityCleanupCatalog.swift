//
//  EntityCleanupCatalog.swift
//  Overseer
//
//  The "clear lag" feature's category → target-selector mapping — the
//  strictly-vanilla equivalent of a ClearLag/EssentialsX clearlag
//  plugin's item/mob sweep, built entirely on `/kill @e[type=...]`.
//
//  Verified against the current Minecraft Wiki rather than assumed from
//  memory (this app targets 26.3-snapshot-8, recent enough to include
//  mobs — "parched", "sulfur_cube" — that predate no stable knowledge):
//  there is no single vanilla tag covering "all hostile mobs" generically
//  (https://minecraft.wiki/w/Entity_type_tag_(Java_Edition)), so
//  `.hostileMobs` below is a hand-maintained list of individual entity
//  IDs plus the one tag (`#minecraft:raiders`) that's a clean, safe
//  subset. `/kill`'s own syntax (`kill [<targets>]`, target optional
//  since 1.15) is unchanged (https://minecraft.wiki/w/Commands/kill).
//
//  Also verified: mobs killed via `/kill` DO drop their normal item
//  loot (rotten flesh, bones, gunpowder, ...) — it routes through the
//  standard death event, not a silent despawn — but do NOT drop XP
//  orbs, since orb drops require dying within 3 seconds of being
//  *attacked*, which `/kill` isn't. Primed TNT killed via `/kill`
//  despawns silently with no explosion and no drops, so it never adds
//  to the pile. This is why `LagClearCategory.sweepOrder` below runs
//  `.hostileMobs` before `.droppedItems`/`.experienceOrbs` — a single
//  sweep's own item pass catches loot the mob pass just created,
//  instead of leaving it on the ground for the next scheduled run.
//

import Foundation

enum LagClearCategory: String, CaseIterable, Identifiable, Codable {
    case droppedItems
    case experienceOrbs
    case projectiles
    case primedTNT
    case hostileMobs
    case enderPearls

    var id: String { rawValue }

    var label: String {
        switch self {
        case .droppedItems: return "Dropped Items"
        case .experienceOrbs: return "Experience Orbs"
        case .projectiles: return "Stray Projectiles"
        case .primedTNT: return "Primed TNT"
        case .hostileMobs: return "Hostile Mobs"
        case .enderPearls: return "Thrown Ender Pearls"
        }
    }

    var systemImage: String {
        switch self {
        case .droppedItems: return "shippingbox.fill"
        case .experienceOrbs: return "sparkles"
        case .projectiles: return "arrow.up.forward"
        case .primedTNT: return "flame.fill"
        case .hostileMobs: return "pawprint.fill"
        case .enderPearls: return "arrow.triangle.2.circlepath"
        }
    }

    /// Shown as an explicit callout in the UI for the categories where
    /// "removed automatically every 10 minutes" is a real risk, not
    /// just a theoretical one.
    var riskNote: String? {
        switch self {
        case .primedTNT:
            return "Removes ALL primed TNT instantly, including mid-fuse inside an active TNT cannon or farm."
        case .hostileMobs:
            return "Removes every hostile mob server-wide, including ones a player is actively fighting."
        case .enderPearls:
            return "Off by default for a reason: this can break active ender pearl stasis chambers (instant-home teleporters) and ender-pearl chunk loaders. Only enable if pearls are genuinely piling up and causing lag."
        default:
            return nil
        }
    }

    /// Loot/debris-producing categories first, item/orb cleanup last —
    /// see the file-level doc comment. `.projectiles`/`.enderPearls`
    /// produce no drops either way, so their position doesn't matter;
    /// they're grouped with the other "doesn't add to the pile"
    /// categories for clarity.
    private static let sweepOrder: [LagClearCategory] = [.hostileMobs, .primedTNT, .projectiles, .enderPearls, .droppedItems, .experienceOrbs]

    /// Orders an arbitrary set of enabled categories into sweep order.
    static func sweepOrdered(_ categories: Set<LagClearCategory>) -> [LagClearCategory] {
        sweepOrder.filter { categories.contains($0) }
    }
}

enum EntityCleanupCatalog {
    /// Target-selector `type=` values for one category — either a bare
    /// namespaced entity ID ("minecraft:item") or an entity type tag
    /// ("#minecraft:raiders"), both valid directly inside `type=`.
    static func selectors(for category: LagClearCategory) -> [String] {
        switch category {
        case .droppedItems:
            return ["minecraft:item"]

        case .experienceOrbs:
            return ["minecraft:experience_orb"]

        case .projectiles:
            // Deliberately excludes minecraft:ender_pearl — see
            // .enderPearls below, its own separate opt-in category
            // rather than bundled in here, since it needs its own risk
            // note and its own off-by-default decision independent of
            // "clear arrows/snowballs/etc."
            return [
                "minecraft:arrow", "minecraft:spectral_arrow",
                "minecraft:snowball", "minecraft:egg",
                "minecraft:trident", "minecraft:fishing_bobber",
                "minecraft:firework_rocket",
                "minecraft:splash_potion", "minecraft:lingering_potion",
                "minecraft:experience_bottle",
                "minecraft:small_fireball", "minecraft:fireball"
            ]

        case .primedTNT:
            return ["minecraft:tnt"]

        case .enderPearls:
            // Split out from .projectiles and off by default: a thrown
            // pearl held in a stasis chamber (instant-home teleporters,
            // ender-pearl chunk loaders) is a real entity sitting in the
            // world for as long as its owner is online and hasn't
            // triggered it, not a stray leftover — a blind /kill can't
            // tell the difference (verified: https://minecraft.wiki/w/Tutorial:Chunk_loader).
            // Kept available, not removed outright, since an admin who
            // knows their server has no such builds may still want it
            // if pearls are genuinely accumulating and causing lag.
            return ["minecraft:ender_pearl"]

        case .hostileMobs:
            // Every vanilla "Monster"-category mob EXCEPT:
            //  - Boss mobs (Wither, Ender Dragon) — killing one mid-fight
            //    is destructive, not a lag fix.
            //  - The Warden — rare, plot-significant, not a mass-spawn
            //    lag source; not meant to be casually killed at all.
            //  - Skeleton Horse / Zombie Horse — mountable, frequently a
            //    player's tamed pet despite the "hostile" category tag.
            //  - Endermite — thrown ender pearls have a chance to spawn
            //    one, which is the actual mechanism a public enderman
            //    farm's bait/aggro system runs on; auto-killing it mid-cycle
            //    would break the farm, not just tidy up after it.
            return [
                "minecraft:blaze", "minecraft:bogged", "minecraft:breeze", "minecraft:cave_spider",
                "minecraft:creaking", "minecraft:creeper", "minecraft:drowned", "minecraft:elder_guardian",
                "minecraft:enderman", "minecraft:ghast", "minecraft:guardian",
                "minecraft:hoglin", "minecraft:husk", "minecraft:magma_cube", "minecraft:parched",
                "minecraft:phantom", "minecraft:piglin", "minecraft:piglin_brute", "minecraft:shulker",
                "minecraft:silverfish", "minecraft:skeleton", "minecraft:slime", "minecraft:spider",
                "minecraft:stray", "minecraft:sulfur_cube", "minecraft:vex", "minecraft:wither_skeleton",
                "minecraft:zoglin", "minecraft:zombie", "minecraft:zombie_villager", "minecraft:zombified_piglin",
                "#minecraft:raiders" // evoker, illusioner, pillager, ravager, vindicator, witch
            ]
        }
    }
}
