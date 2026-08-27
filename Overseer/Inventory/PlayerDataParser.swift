//
//  PlayerDataParser.swift
//  Overseer
//
//  Decodes a vanilla player `.dat` file — the same gzip-compressed NBT
//  format as a `.schem` (see NBTParser.swift, reused as-is here) — into
//  a plain Swift snapshot of that player's inventory and vitals, for the
//  Inventory Analyzer. Read-only: this app never writes these files
//  back, so there's no round-trip/serialization concern, only decoding.
//
//  Minecraft has shipped two item-stack shapes on disk:
//   - Legacy (pre-1.20.5): `id` (string), `Count` (byte), optional `tag`
//     compound holding `Damage` (durability), `display.Name` (plain or
//     JSON-text string), `Enchantments` (list of `{id, lvl}`).
//   - Data Components (1.20.5+): `id`, `count`, optional `components`
//     compound holding `minecraft:damage` (int), `minecraft:custom_name`
//     (JSON-text string), `minecraft:enchantments.levels` (compound
//     mapping enchant id -> level).
//  Both are read here (whichever set of keys is present wins) so this
//  works regardless of which server version wrote the file, without
//  needing to know the version up front.
//

import Foundation

struct InventoryItemStack: Identifiable, Hashable {
    /// Raw Minecraft slot index: 0-8 hotbar, 9-35 main, 100-103 armor
    /// (boots/leggings/chestplate/helmet), -106 offhand, 0-26 ender chest.
    var slot: Int
    var itemID: String
    var count: Int
    var damage: Int?
    var customName: String?
    var enchantments: [String]

    var id: String { "\(slot)-\(itemID)-\(count)" }

    var isEnchanted: Bool { !enchantments.isEmpty }

    /// Best-effort human name: the curated give-item catalog's display
    /// name when this ID is in it, else the raw ID with its namespace
    /// stripped and underscores turned into title-cased words — good
    /// enough for "what is this" even for the ~1100 items the catalog
    /// doesn't curate.
    var displayName: String {
        if let custom = customName, !custom.isEmpty { return custom }
        if let known = MinecraftItemCatalog.items.first(where: { $0.id == itemID }) {
            return known.displayName
        }
        let bare = itemID.split(separator: ":").last.map(String.init) ?? itemID
        return bare
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

enum InventorySlotSection {
    case hotbar, main, armor, offhand, ender, other

    static func of(_ rawSlot: Int) -> InventorySlotSection {
        switch rawSlot {
        case 0...8: return .hotbar
        case 9...35: return .main
        case 100...103: return .armor
        case -106: return .offhand
        default: return .other
        }
    }

    /// Armor slots' fixed meaning — 100 is always boots, 103 always
    /// helmet, regardless of what's currently equipped there.
    static func armorLabel(_ rawSlot: Int) -> String? {
        switch rawSlot {
        case 100: return "Boots"
        case 101: return "Leggings"
        case 102: return "Chestplate"
        case 103: return "Helmet"
        default: return nil
        }
    }
}

struct ParsedPlayerData: Identifiable {
    var uuid: String
    var fileURL: URL
    var fileModifiedAt: Date?

    var health: Double?
    var foodLevel: Int?
    var xpLevel: Int?
    var xpTotal: Int?
    /// Raw `playerGameType`: 0 survival, 1 creative, 2 adventure, 3 spectator.
    var gameMode: Int?
    var dimension: String?
    var position: (x: Double, y: Double, z: Double)?

    /// Hotbar, main inventory, armor, and offhand — everything from the
    /// `Inventory` tag — keyed by raw slot, unsorted (callers group by
    /// `InventorySlotSection`).
    var mainInventory: [InventoryItemStack]
    /// The `EnderItems` tag — a separate 27-slot container.
    var enderChest: [InventoryItemStack]

    var id: String { uuid }

    var gameModeLabel: String {
        switch gameMode {
        case 0: return "Survival"
        case 1: return "Creative"
        case 2: return "Adventure"
        case 3: return "Spectator"
        default: return "Unknown"
        }
    }

    var allItems: [InventoryItemStack] { mainInventory + enderChest }
}

enum PlayerDataParserError: Error, LocalizedError {
    case notACompound
    case decodeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notACompound: return "File doesn't contain a valid player data compound."
        case .decodeFailed(let error): return "Couldn't decode NBT: \(error.localizedDescription)"
        }
    }
}

enum PlayerDataParser {
    /// Parses a raw `.dat` file's bytes. `uuid` is the caller-supplied
    /// identity (Minecraft names the file `<uuid>.dat`, but the UUID
    /// itself isn't repeated inside the NBT body, so it can't be
    /// recovered from the bytes alone).
    static func parse(uuid: String, data: Data, fileURL: URL, fileModifiedAt: Date?) throws -> ParsedPlayerData {
        let root: NBTTag
        do {
            root = try NBTParser.parse(data: data).tag
        } catch {
            throw PlayerDataParserError.decodeFailed(error)
        }
        guard case .compound = root else { throw PlayerDataParserError.notACompound }

        var result = ParsedPlayerData(
            uuid: uuid,
            fileURL: fileURL,
            fileModifiedAt: fileModifiedAt,
            mainInventory: [],
            enderChest: []
        )

        if case .float(let value) = root["Health"] { result.health = Double(value) }
        else if case .short(let value) = root["Health"] { result.health = Double(value) }
        if case .int(let value) = root["foodLevel"] { result.foodLevel = Int(value) }
        if case .int(let value) = root["XpLevel"] { result.xpLevel = Int(value) }
        if case .int(let value) = root["XpTotal"] { result.xpTotal = Int(value) }
        if case .int(let value) = root["playerGameType"] { result.gameMode = Int(value) }

        switch root["Dimension"] {
        case .string(let name): result.dimension = name
        case .int(let raw):
            switch raw {
            case -1: result.dimension = "minecraft:the_nether"
            case 1: result.dimension = "minecraft:the_end"
            default: result.dimension = "minecraft:overworld"
            }
        default: break
        }

        if case .list(let coords) = root["Pos"], coords.count == 3 {
            let doubles = coords.map(Self.asDouble)
            if let x = doubles[0], let y = doubles[1], let z = doubles[2] {
                result.position = (x, y, z)
            }
        }

        if case .list(let items) = root["Inventory"] {
            result.mainInventory = items.compactMap(itemStack(from:))
        }
        if case .list(let items) = root["EnderItems"] {
            result.enderChest = items.compactMap(itemStack(from:))
        }

        return result
    }

    private static func asDouble(_ tag: NBTTag) -> Double? {
        switch tag {
        case .double(let v): return v
        case .float(let v): return Double(v)
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    private static func itemStack(from tag: NBTTag) -> InventoryItemStack? {
        guard case .compound(let item) = tag, case .string(let itemID)? = item["id"] else { return nil }

        var slot = 0
        if case .byte(let v)? = item["Slot"] { slot = Int(v) }

        var count = 1
        if case .byte(let v)? = item["Count"] { count = Int(v) }
        else if case .int(let v)? = item["count"] { count = Int(v) }
        else if case .byte(let v)? = item["count"] { count = Int(v) }

        var damage: Int?
        var customName: String?
        var enchantments: [String] = []

        if case .compound(let legacyTag)? = item["tag"] {
            if case .int(let v)? = legacyTag["Damage"] { damage = Int(v) }
            if case .compound(let display)? = legacyTag["display"], case .string(let name)? = display["Name"] {
                customName = decodeTextComponent(name)
            }
            if case .list(let list)? = legacyTag["Enchantments"] {
                enchantments = list.compactMap { enchant -> String? in
                    guard case .compound(let dict) = enchant, case .string(let id)? = dict["id"] else { return nil }
                    let level: Int
                    if case .short(let lvl)? = dict["lvl"] { level = Int(lvl) }
                    else if case .int(let lvl)? = dict["lvl"] { level = Int(lvl) }
                    else { level = 1 }
                    return formatEnchantment(id: id, level: level)
                }
            }
        }

        if case .compound(let components)? = item["components"] {
            if case .int(let v)? = components["minecraft:damage"] { damage = Int(v) }
            if case .string(let name)? = components["minecraft:custom_name"] {
                customName = decodeTextComponent(name)
            }
            if case .compound(let enchantComponent)? = components["minecraft:enchantments"],
               case .compound(let levels)? = enchantComponent["levels"] {
                enchantments = levels.compactMap { id, levelTag in
                    let level = levelTag.asInt ?? 1
                    return formatEnchantment(id: id, level: level)
                }.sorted()
            }
        }

        return InventoryItemStack(
            slot: slot, itemID: itemID, count: count,
            damage: damage, customName: customName, enchantments: enchantments
        )
    }

    /// Item/entity custom names are either a bare string (older format)
    /// or a JSON text component like `{"text":"My Sword"}` (newer).
    /// Extracts the readable text either way; falls back to the raw
    /// string if it isn't parseable JSON, since that's still the best
    /// available label.
    private static func decodeTextComponent(_ raw: String) -> String {
        guard raw.hasPrefix("{") || raw.hasPrefix("\""),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return raw
        }
        if let text = json as? String { return text }
        if let dict = json as? [String: Any], let text = dict["text"] as? String { return text }
        return raw
    }

    private static let romanNumerals: [Int: String] = [
        1: "I", 2: "II", 3: "III", 4: "IV", 5: "V",
        6: "VI", 7: "VII", 8: "VIII", 9: "IX", 10: "X"
    ]

    private static func formatEnchantment(id: String, level: Int) -> String {
        let bare = id.split(separator: ":").last.map(String.init) ?? id
        let name = bare
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        let numeral = romanNumerals[level] ?? "\(level)"
        return "\(name) \(numeral)"
    }
}
