//
//  MinecraftItemCatalog.swift
//  Overseer
//
//  Static catalog of official vanilla `minecraft:` item IDs, used by the
//  Give Item picker (GiveItemSheet) so admins search by display name
//  rather than typing raw IDs. Deliberately a curated, commonly-used
//  subset of the ~1400-entry vanilla item registry (tools, combat,
//  armor, food, building blocks, redstone, brewing, materials,
//  decoration, spawn eggs) rather than an exhaustive dump — every ID
//  below is a real, stable vanilla item, hand-picked for what an admin
//  actually hands out (rewards, kits, fixing a grief) rather than
//  needing all 1400.
//
//  Every ID is namespaced ("minecraft:diamond_sword") since that's what
//  `/give` expects; VanillaCommands.giveItem builds the final command
//  string from `MinecraftItem.id` as-is.
//

import Foundation

enum MinecraftItemCategory: String, CaseIterable, Identifiable {
    case tools = "Tools"
    case combat = "Combat"
    case armor = "Armor"
    case food = "Food"
    case buildingBlocks = "Building Blocks"
    case redstone = "Redstone"
    case brewing = "Brewing"
    case materials = "Materials"
    case decoration = "Decoration"
    case spawnEggs = "Spawn Eggs"
    case miscellaneous = "Miscellaneous"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .tools: return "hammer.fill"
        case .combat: return "shield.lefthalf.filled"
        case .armor: return "helmet"
        case .food: return "fork.knife"
        case .buildingBlocks: return "cube.fill"
        case .redstone: return "bolt.fill"
        case .brewing: return "flask.fill"
        case .materials: return "diamond.fill"
        case .decoration: return "photo.fill"
        case .spawnEggs: return "hare.fill"
        case .miscellaneous: return "shippingbox.fill"
        }
    }
}

struct MinecraftItem: Identifiable, Hashable {
    /// Fully namespaced vanilla ID, e.g. "minecraft:diamond_sword".
    var id: String
    var displayName: String
    var category: MinecraftItemCategory
}

enum MinecraftItemCatalog {

    static func search(_ query: String) -> [MinecraftItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.displayName.lowercased().contains(trimmed) || $0.id.lowercased().contains(trimmed)
        }
    }

    static func items(in category: MinecraftItemCategory) -> [MinecraftItem] {
        items.filter { $0.category == category }
    }

    // MARK: - Catalog

    static let items: [MinecraftItem] = {
        func make(_ id: String, _ name: String, _ category: MinecraftItemCategory) -> MinecraftItem {
            MinecraftItem(id: "minecraft:\(id)", displayName: name, category: category)
        }

        var all: [MinecraftItem] = []

        // Tools
        for tier in ["Wooden", "Stone", "Golden", "Iron", "Diamond", "Netherite"] {
            let key = tier.lowercased()
            all.append(make("\(key)_pickaxe", "\(tier) Pickaxe", .tools))
            all.append(make("\(key)_axe", "\(tier) Axe", .tools))
            all.append(make("\(key)_shovel", "\(tier) Shovel", .tools))
            all.append(make("\(key)_hoe", "\(tier) Hoe", .tools))
        }
        all += [
            make("fishing_rod", "Fishing Rod", .tools),
            make("flint_and_steel", "Flint and Steel", .tools),
            make("shears", "Shears", .tools),
            make("compass", "Compass", .tools),
            make("clock", "Clock", .tools),
            make("spyglass", "Spyglass", .tools),
            make("lead", "Lead", .tools),
            make("name_tag", "Name Tag", .tools),
            make("bucket", "Bucket", .tools),
            make("water_bucket", "Water Bucket", .tools),
            make("lava_bucket", "Lava Bucket", .tools),
            make("milk_bucket", "Milk Bucket", .tools),
            make("saddle", "Saddle", .tools),
            make("elytra", "Elytra", .tools)
        ]

        // Combat
        for tier in ["Wooden", "Stone", "Golden", "Iron", "Diamond", "Netherite"] {
            all.append(make("\(tier.lowercased())_sword", "\(tier) Sword", .combat))
        }
        all += [
            make("bow", "Bow", .combat),
            make("crossbow", "Crossbow", .combat),
            make("arrow", "Arrow", .combat),
            make("spectral_arrow", "Spectral Arrow", .combat),
            make("tipped_arrow", "Tipped Arrow", .combat),
            make("trident", "Trident", .combat),
            make("shield", "Shield", .combat),
            make("totem_of_undying", "Totem of Undying", .combat)
        ]

        // Armor
        for tier in ["Leather", "Chainmail", "Iron", "Golden", "Diamond", "Netherite"] {
            let key = tier.lowercased()
            all.append(make("\(key)_helmet", "\(tier) Helmet", .armor))
            all.append(make("\(key)_chestplate", "\(tier) Chestplate", .armor))
            all.append(make("\(key)_leggings", "\(tier) Leggings", .armor))
            all.append(make("\(key)_boots", "\(tier) Boots", .armor))
        }
        all.append(make("turtle_helmet", "Turtle Shell Helmet", .armor))

        // Food
        all += [
            make("apple", "Apple", .food),
            make("golden_apple", "Golden Apple", .food),
            make("enchanted_golden_apple", "Enchanted Golden Apple", .food),
            make("bread", "Bread", .food),
            make("beef", "Raw Beef", .food),
            make("cooked_beef", "Steak", .food),
            make("porkchop", "Raw Porkchop", .food),
            make("cooked_porkchop", "Cooked Porkchop", .food),
            make("chicken", "Raw Chicken", .food),
            make("cooked_chicken", "Cooked Chicken", .food),
            make("mutton", "Raw Mutton", .food),
            make("cooked_mutton", "Cooked Mutton", .food),
            make("rabbit", "Raw Rabbit", .food),
            make("cooked_rabbit", "Cooked Rabbit", .food),
            make("cod", "Raw Cod", .food),
            make("cooked_cod", "Cooked Cod", .food),
            make("salmon", "Raw Salmon", .food),
            make("cooked_salmon", "Cooked Salmon", .food),
            make("carrot", "Carrot", .food),
            make("golden_carrot", "Golden Carrot", .food),
            make("potato", "Potato", .food),
            make("baked_potato", "Baked Potato", .food),
            make("poisonous_potato", "Poisonous Potato", .food),
            make("beetroot", "Beetroot", .food),
            make("beetroot_soup", "Beetroot Soup", .food),
            make("mushroom_stew", "Mushroom Stew", .food),
            make("rabbit_stew", "Rabbit Stew", .food),
            make("pumpkin_pie", "Pumpkin Pie", .food),
            make("cake", "Cake", .food),
            make("cookie", "Cookie", .food),
            make("melon_slice", "Melon Slice", .food),
            make("sweet_berries", "Sweet Berries", .food),
            make("glow_berries", "Glow Berries", .food),
            make("honey_bottle", "Honey Bottle", .food),
            make("dried_kelp", "Dried Kelp", .food),
            make("chorus_fruit", "Chorus Fruit", .food)
        ]

        // Building blocks
        all += [
            make("stone", "Stone", .buildingBlocks),
            make("cobblestone", "Cobblestone", .buildingBlocks),
            make("dirt", "Dirt", .buildingBlocks),
            make("grass_block", "Grass Block", .buildingBlocks),
            make("sand", "Sand", .buildingBlocks),
            make("gravel", "Gravel", .buildingBlocks),
            make("oak_log", "Oak Log", .buildingBlocks),
            make("oak_planks", "Oak Planks", .buildingBlocks),
            make("glass", "Glass", .buildingBlocks),
            make("sandstone", "Sandstone", .buildingBlocks),
            make("bricks", "Bricks", .buildingBlocks),
            make("obsidian", "Obsidian", .buildingBlocks),
            make("netherrack", "Netherrack", .buildingBlocks),
            make("end_stone", "End Stone", .buildingBlocks),
            make("purpur_block", "Purpur Block", .buildingBlocks),
            make("quartz_block", "Block of Quartz", .buildingBlocks),
            make("prismarine", "Prismarine", .buildingBlocks),
            make("sea_lantern", "Sea Lantern", .buildingBlocks),
            make("glowstone", "Glowstone", .buildingBlocks),
            make("bookshelf", "Bookshelf", .buildingBlocks),
            make("ladder", "Ladder", .buildingBlocks),
            make("scaffolding", "Scaffolding", .buildingBlocks),
            make("chest", "Chest", .buildingBlocks),
            make("ender_chest", "Ender Chest", .buildingBlocks),
            make("barrel", "Barrel", .buildingBlocks),
            make("crafting_table", "Crafting Table", .buildingBlocks),
            make("furnace", "Furnace", .buildingBlocks),
            make("blast_furnace", "Blast Furnace", .buildingBlocks),
            make("smoker", "Smoker", .buildingBlocks),
            make("anvil", "Anvil", .buildingBlocks),
            make("grindstone", "Grindstone", .buildingBlocks),
            make("stonecutter", "Stonecutter", .buildingBlocks),
            make("loom", "Loom", .buildingBlocks),
            make("cartography_table", "Cartography Table", .buildingBlocks),
            make("fletching_table", "Fletching Table", .buildingBlocks),
            make("smithing_table", "Smithing Table", .buildingBlocks),
            make("lectern", "Lectern", .buildingBlocks),
            make("beacon", "Beacon", .buildingBlocks),
            make("conduit", "Conduit", .buildingBlocks),
            make("respawn_anchor", "Respawn Anchor", .buildingBlocks),
            make("lodestone", "Lodestone", .buildingBlocks),
            make("tnt", "TNT", .buildingBlocks),
            make("note_block", "Note Block", .buildingBlocks),
            make("jukebox", "Jukebox", .buildingBlocks),
            make("composter", "Composter", .buildingBlocks),
            make("campfire", "Campfire", .buildingBlocks),
            make("soul_campfire", "Soul Campfire", .buildingBlocks),
            make("lantern", "Lantern", .buildingBlocks),
            make("soul_lantern", "Soul Lantern", .buildingBlocks)
        ]

        // Redstone
        all += [
            make("redstone", "Redstone Dust", .redstone),
            make("redstone_torch", "Redstone Torch", .redstone),
            make("redstone_block", "Block of Redstone", .redstone),
            make("repeater", "Redstone Repeater", .redstone),
            make("comparator", "Redstone Comparator", .redstone),
            make("piston", "Piston", .redstone),
            make("sticky_piston", "Sticky Piston", .redstone),
            make("observer", "Observer", .redstone),
            make("dropper", "Dropper", .redstone),
            make("dispenser", "Dispenser", .redstone),
            make("hopper", "Hopper", .redstone),
            make("lever", "Lever", .redstone),
            make("tripwire_hook", "Tripwire Hook", .redstone),
            make("daylight_detector", "Daylight Detector", .redstone),
            make("redstone_lamp", "Redstone Lamp", .redstone),
            make("target", "Target Block", .redstone)
        ]

        // Brewing
        all += [
            make("brewing_stand", "Brewing Stand", .brewing),
            make("cauldron", "Cauldron", .brewing),
            make("glass_bottle", "Glass Bottle", .brewing),
            make("potion", "Potion", .brewing),
            make("splash_potion", "Splash Potion", .brewing),
            make("lingering_potion", "Lingering Potion", .brewing),
            make("nether_wart", "Nether Wart", .brewing),
            make("fermented_spider_eye", "Fermented Spider Eye", .brewing),
            make("glistering_melon_slice", "Glistering Melon Slice", .brewing),
            make("rabbit_foot", "Rabbit's Foot", .brewing),
            make("pufferfish", "Pufferfish", .brewing),
            make("dragon_breath", "Dragon's Breath", .brewing)
        ]

        // Materials
        all += [
            make("coal", "Coal", .materials),
            make("charcoal", "Charcoal", .materials),
            make("raw_iron", "Raw Iron", .materials),
            make("iron_ingot", "Iron Ingot", .materials),
            make("raw_gold", "Raw Gold", .materials),
            make("gold_ingot", "Gold Ingot", .materials),
            make("raw_copper", "Raw Copper", .materials),
            make("copper_ingot", "Copper Ingot", .materials),
            make("diamond", "Diamond", .materials),
            make("emerald", "Emerald", .materials),
            make("lapis_lazuli", "Lapis Lazuli", .materials),
            make("netherite_ingot", "Netherite Ingot", .materials),
            make("netherite_scrap", "Netherite Scrap", .materials),
            make("quartz", "Nether Quartz", .materials),
            make("glowstone_dust", "Glowstone Dust", .materials),
            make("gunpowder", "Gunpowder", .materials),
            make("string", "String", .materials),
            make("spider_eye", "Spider Eye", .materials),
            make("bone", "Bone", .materials),
            make("bone_meal", "Bone Meal", .materials),
            make("feather", "Feather", .materials),
            make("leather", "Leather", .materials),
            make("ender_pearl", "Ender Pearl", .materials),
            make("ender_eye", "Eye of Ender", .materials),
            make("blaze_rod", "Blaze Rod", .materials),
            make("blaze_powder", "Blaze Powder", .materials),
            make("ghast_tear", "Ghast Tear", .materials),
            make("magma_cream", "Magma Cream", .materials),
            make("slime_ball", "Slimeball", .materials),
            make("nether_star", "Nether Star", .materials),
            make("prismarine_shard", "Prismarine Shard", .materials),
            make("prismarine_crystals", "Prismarine Crystals", .materials),
            make("phantom_membrane", "Phantom Membrane", .materials),
            make("shulker_shell", "Shulker Shell", .materials),
            make("amethyst_shard", "Amethyst Shard", .materials),
            make("echo_shard", "Echo Shard", .materials),
            make("honeycomb", "Honeycomb", .materials),
            make("clay_ball", "Clay Ball", .materials),
            make("brick", "Brick", .materials),
            make("nautilus_shell", "Nautilus Shell", .materials),
            make("heart_of_the_sea", "Heart of the Sea", .materials),
            make("scute", "Scute", .materials),
            make("snowball", "Snowball", .materials),
            make("ink_sac", "Ink Sac", .materials),
            make("glow_ink_sac", "Glow Ink Sac", .materials)
        ]

        // Decoration
        all += [
            make("torch", "Torch", .decoration),
            make("painting", "Painting", .decoration),
            make("item_frame", "Item Frame", .decoration),
            make("glow_item_frame", "Glow Item Frame", .decoration),
            make("armor_stand", "Armor Stand", .decoration),
            make("flower_pot", "Flower Pot", .decoration),
            make("oak_sign", "Oak Sign", .decoration),
            make("oak_hanging_sign", "Oak Hanging Sign", .decoration),
            make("oak_boat", "Oak Boat", .decoration),
            make("oak_chest_boat", "Oak Boat with Chest", .decoration),
            make("minecart", "Minecart", .decoration),
            make("chest_minecart", "Minecart with Chest", .decoration),
            make("hopper_minecart", "Minecart with Hopper", .decoration),
            make("tnt_minecart", "Minecart with TNT", .decoration)
        ]

        // Spawn eggs
        for (id, name) in [
            ("zombie", "Zombie"), ("skeleton", "Skeleton"), ("creeper", "Creeper"),
            ("spider", "Spider"), ("enderman", "Enderman"), ("cow", "Cow"),
            ("pig", "Pig"), ("sheep", "Sheep"), ("chicken", "Chicken"),
            ("horse", "Horse"), ("wolf", "Wolf"), ("cat", "Cat"),
            ("villager", "Villager"), ("iron_golem", "Iron Golem"), ("blaze", "Blaze"),
            ("ghast", "Ghast"), ("wither_skeleton", "Wither Skeleton"), ("piglin", "Piglin"),
            ("zombified_piglin", "Zombified Piglin"), ("guardian", "Guardian"),
            ("elder_guardian", "Elder Guardian"), ("phantom", "Phantom"), ("drowned", "Drowned"),
            ("dolphin", "Dolphin"), ("turtle", "Turtle"), ("fox", "Fox"), ("bee", "Bee"),
            ("axolotl", "Axolotl"), ("allay", "Allay"), ("camel", "Camel"),
            ("sniffer", "Sniffer"), ("glow_squid", "Glow Squid")
        ] {
            all.append(make("\(id)_spawn_egg", "\(name) Spawn Egg", .spawnEggs))
        }

        // Miscellaneous
        all += [
            make("book", "Book", .miscellaneous),
            make("enchanted_book", "Enchanted Book", .miscellaneous),
            make("written_book", "Written Book", .miscellaneous),
            make("writable_book", "Book and Quill", .miscellaneous),
            make("map", "Empty Map", .miscellaneous),
            make("filled_map", "Filled Map", .miscellaneous),
            make("firework_rocket", "Firework Rocket", .miscellaneous),
            make("firework_star", "Firework Star", .miscellaneous),
            make("experience_bottle", "Bottle o' Enchanting", .miscellaneous),
            make("diamond_block", "Block of Diamond", .miscellaneous),
            make("gold_block", "Block of Gold", .miscellaneous),
            make("iron_block", "Block of Iron", .miscellaneous),
            make("emerald_block", "Block of Emerald", .miscellaneous),
            make("music_disc_cat", "Music Disc (Cat)", .miscellaneous),
            make("music_disc_pigstep", "Music Disc (Pigstep)", .miscellaneous)
        ]

        return all
    }()
}
