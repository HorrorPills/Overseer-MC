//
//  PlayerDataParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

/// Same minimal NBT encoder as NBTParserTests' NBTFixture, scoped to
/// this file — builds synthetic `.dat`-shaped documents (legacy
/// id/Count/tag item stacks and the newer id/count/components shape).
private enum PlayerDataFixture {
    static func tagID(for tag: NBTTag) -> UInt8 {
        switch tag {
        case .byte: return 1
        case .short: return 2
        case .int: return 3
        case .long: return 4
        case .float: return 5
        case .double: return 6
        case .byteArray: return 7
        case .string: return 8
        case .list: return 9
        case .compound: return 10
        case .intArray: return 11
        case .longArray: return 12
        }
    }
    static func int16Bytes(_ v: Int16) -> [UInt8] {
        let u = UInt16(bitPattern: v)
        return [UInt8(u >> 8), UInt8(u & 0xFF)]
    }
    static func int32Bytes(_ v: Int32) -> [UInt8] {
        let u = UInt32(bitPattern: v)
        return [UInt8(u >> 24), UInt8((u >> 16) & 0xFF), UInt8((u >> 8) & 0xFF), UInt8(u & 0xFF)]
    }
    static func int64Bytes(_ v: Int64) -> [UInt8] {
        let u = UInt64(bitPattern: v)
        return (0..<8).map { UInt8((u >> ((7 - $0) * 8)) & 0xFF) }
    }
    static func encodeString(_ s: String) -> [UInt8] {
        let utf8 = Array(s.utf8)
        return int16Bytes(Int16(utf8.count)) + utf8
    }
    static func payload(for tag: NBTTag) -> [UInt8] {
        switch tag {
        case .byte(let v): return [UInt8(bitPattern: v)]
        case .short(let v): return int16Bytes(v)
        case .int(let v): return int32Bytes(v)
        case .long(let v): return int64Bytes(v)
        case .float(let v): return int32Bytes(Int32(bitPattern: v.bitPattern))
        case .double(let v): return int64Bytes(Int64(bitPattern: v.bitPattern))
        case .byteArray(let arr):
            return int32Bytes(Int32(arr.count)) + arr.map { UInt8(bitPattern: $0) }
        case .string(let s):
            return encodeString(s)
        case .list(let items):
            let elementType: UInt8 = items.first.map(tagID) ?? 0
            var bytes: [UInt8] = [elementType]
            bytes += int32Bytes(Int32(items.count))
            for item in items { bytes += payload(for: item) }
            return bytes
        case .compound(let dict):
            var bytes: [UInt8] = []
            for (key, value) in dict {
                bytes.append(tagID(for: value))
                bytes += encodeString(key)
                bytes += payload(for: value)
            }
            bytes.append(0)
            return bytes
        case .intArray(let arr):
            return int32Bytes(Int32(arr.count)) + arr.flatMap(int32Bytes)
        case .longArray(let arr):
            return int32Bytes(Int32(arr.count)) + arr.flatMap(int64Bytes)
        }
    }
    static func document(root: NBTTag) -> Data {
        var bytes: [UInt8] = [tagID(for: root)]
        bytes += encodeString("")
        bytes += payload(for: root)
        return Data(bytes)
    }
}

@Suite("PlayerDataParser")
struct PlayerDataParserTests {

    @Test("Parses vitals, position, and dimension")
    func parsesVitals() throws {
        let root: NBTTag = .compound([
            "Health": .float(14.5),
            "foodLevel": .int(18),
            "XpLevel": .int(23),
            "XpTotal": .int(910),
            "playerGameType": .int(0),
            "Dimension": .string("minecraft:the_nether"),
            "Pos": .list([.double(12.5), .double(64.0), .double(-8.25)])
        ])
        let data = PlayerDataFixture.document(root: root)
        let parsed = try PlayerDataParser.parse(
            uuid: "069a79f4-44e9-4726-a5be-fca90e38aaf5", data: data,
            fileURL: URL(fileURLWithPath: "/tmp/x.dat"), fileModifiedAt: nil
        )
        #expect(parsed.health == 14.5)
        #expect(parsed.foodLevel == 18)
        #expect(parsed.xpLevel == 23)
        #expect(parsed.xpTotal == 910)
        #expect(parsed.gameMode == 0)
        #expect(parsed.gameModeLabel == "Survival")
        #expect(parsed.dimension == "minecraft:the_nether")
        #expect(parsed.position?.x == 12.5)
        #expect(parsed.position?.y == 64.0)
        #expect(parsed.position?.z == -8.25)
    }

    @Test("Maps legacy integer Dimension values")
    func mapsLegacyDimension() throws {
        for (raw, expected) in [(-1, "minecraft:the_nether"), (1, "minecraft:the_end"), (0, "minecraft:overworld")] {
            let root: NBTTag = .compound(["Dimension": .int(Int32(raw))])
            let parsed = try PlayerDataParser.parse(
                uuid: "u", data: PlayerDataFixture.document(root: root),
                fileURL: URL(fileURLWithPath: "/tmp/x.dat"), fileModifiedAt: nil
            )
            #expect(parsed.dimension == expected)
        }
    }

    @Test("Parses legacy-format inventory items with tag metadata")
    func parsesLegacyInventory() throws {
        let sword: NBTTag = .compound([
            "Slot": .byte(0),
            "id": .string("minecraft:diamond_sword"),
            "Count": .byte(1),
            "tag": .compound([
                "Damage": .int(42),
                "display": .compound(["Name": .string("{\"text\":\"Excalibur\"}")]),
                "Enchantments": .list([
                    .compound(["id": .string("minecraft:sharpness"), "lvl": .short(5)])
                ])
            ])
        ])
        let dirt: NBTTag = .compound(["Slot": .byte(9), "id": .string("minecraft:dirt"), "Count": .byte(64)])
        let root: NBTTag = .compound(["Inventory": .list([sword, dirt])])
        let parsed = try PlayerDataParser.parse(
            uuid: "u", data: PlayerDataFixture.document(root: root),
            fileURL: URL(fileURLWithPath: "/tmp/x.dat"), fileModifiedAt: nil
        )
        #expect(parsed.mainInventory.count == 2)
        let swordStack = try #require(parsed.mainInventory.first { $0.slot == 0 })
        #expect(swordStack.itemID == "minecraft:diamond_sword")
        #expect(swordStack.damage == 42)
        #expect(swordStack.customName == "Excalibur")
        #expect(swordStack.enchantments == ["Sharpness V"])
        #expect(swordStack.displayName == "Excalibur")

        let dirtStack = try #require(parsed.mainInventory.first { $0.slot == 9 })
        #expect(dirtStack.count == 64)
        #expect(dirtStack.enchantments.isEmpty)
    }

    @Test("Parses 1.20.5+ data-component inventory items")
    func parsesComponentInventory() throws {
        let bow: NBTTag = .compound([
            "Slot": .byte(-106),
            "id": .string("minecraft:bow"),
            "count": .int(1),
            "components": .compound([
                "minecraft:damage": .int(3),
                "minecraft:custom_name": .string("{\"text\":\"Stolen Bow\"}"),
                "minecraft:enchantments": .compound([
                    "levels": .compound(["minecraft:power": .int(4)])
                ])
            ])
        ])
        let root: NBTTag = .compound(["Inventory": .list([bow])])
        let parsed = try PlayerDataParser.parse(
            uuid: "u", data: PlayerDataFixture.document(root: root),
            fileURL: URL(fileURLWithPath: "/tmp/x.dat"), fileModifiedAt: nil
        )
        let stack = try #require(parsed.mainInventory.first)
        #expect(stack.slot == -106)
        #expect(stack.damage == 3)
        #expect(stack.customName == "Stolen Bow")
        #expect(stack.enchantments == ["Power IV"])
    }

    @Test("Parses ender chest separately from main inventory")
    func parsesEnderChest() throws {
        let enderItem: NBTTag = .compound(["Slot": .byte(0), "id": .string("minecraft:ender_pearl"), "Count": .byte(16)])
        let root: NBTTag = .compound(["EnderItems": .list([enderItem])])
        let parsed = try PlayerDataParser.parse(
            uuid: "u", data: PlayerDataFixture.document(root: root),
            fileURL: URL(fileURLWithPath: "/tmp/x.dat"), fileModifiedAt: nil
        )
        #expect(parsed.mainInventory.isEmpty)
        #expect(parsed.enderChest.count == 1)
        #expect(parsed.enderChest[0].itemID == "minecraft:ender_pearl")
    }

    @Test("Falls back to a title-cased ID when no display or custom name is present")
    func fallsBackToFormattedID() throws {
        let item: NBTTag = .compound(["Slot": .byte(0), "id": .string("minecraft:golden_apple"), "Count": .byte(1)])
        let root: NBTTag = .compound(["Inventory": .list([item])])
        let parsed = try PlayerDataParser.parse(
            uuid: "u", data: PlayerDataFixture.document(root: root),
            fileURL: URL(fileURLWithPath: "/tmp/x.dat"), fileModifiedAt: nil
        )
        #expect(parsed.mainInventory[0].displayName == "Golden Apple")
    }

    @Test("An empty compound (no inventory tags at all) parses with empty containers rather than throwing")
    func emptyDocumentParses() throws {
        let root: NBTTag = .compound([:])
        let parsed = try PlayerDataParser.parse(
            uuid: "u", data: PlayerDataFixture.document(root: root),
            fileURL: URL(fileURLWithPath: "/tmp/x.dat"), fileModifiedAt: nil
        )
        #expect(parsed.mainInventory.isEmpty)
        #expect(parsed.enderChest.isEmpty)
        #expect(parsed.health == nil)
    }

    @Test("Throws a descriptive error on garbage bytes rather than crashing")
    func throwsOnGarbage() {
        let garbage = Data([0xFF, 0x01, 0x02, 0x03])
        #expect(throws: PlayerDataParserError.self) {
            try PlayerDataParser.parse(uuid: "u", data: garbage, fileURL: URL(fileURLWithPath: "/tmp/x.dat"), fileModifiedAt: nil)
        }
    }
}
