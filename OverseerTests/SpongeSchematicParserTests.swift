//
//  SpongeSchematicParserTests.swift
//  OverseerTests
//
//  Synthetic .schem-shaped NBT documents for both root-level layouts
//  (v1/v2) and the nested v3 layout, so the parser is validated against
//  the actual structural difference between them rather than just one.
//

import Foundation
import Testing
@testable import Overseer

/// Minimal NBT encoder scoped to this file — just enough tag types to
/// build schematic-shaped fixtures (compound/short/int/string/byteArray).
/// Mirrors NBTParserTests' NBTFixture.
private enum SchematicFixture {
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
    static func encodeString(_ s: String) -> [UInt8] {
        let utf8 = Array(s.utf8)
        return int16Bytes(Int16(utf8.count)) + utf8
    }
    static func payload(for tag: NBTTag) -> [UInt8] {
        switch tag {
        case .byte(let v): return [UInt8(bitPattern: v)]
        case .short(let v): return int16Bytes(v)
        case .int(let v): return int32Bytes(v)
        case .byteArray(let arr):
            return int32Bytes(Int32(arr.count)) + arr.map { UInt8(bitPattern: $0) }
        case .string(let s):
            return encodeString(s)
        case .compound(let dict):
            var bytes: [UInt8] = []
            for (key, value) in dict {
                bytes.append(tagID(for: value))
                bytes += encodeString(key)
                bytes += payload(for: value)
            }
            bytes.append(0)
            return bytes
        default:
            fatalError("unused in these fixtures")
        }
    }
    static func document(root: NBTTag) -> Data {
        var bytes: [UInt8] = [tagID(for: root)]
        bytes += encodeString("")
        bytes += payload(for: root)
        return Data(bytes)
    }

    /// VarInt-encodes each palette index in order and packs the result
    /// as a signed-byte NBT array — exactly what BlockData/Data holds.
    static func blockData(_ indices: [Int32]) -> NBTTag {
        var bytes: [UInt8] = []
        for index in indices { bytes += VarInt.encode(index) }
        return .byteArray(bytes.map { Int8(bitPattern: $0) })
    }
}

@Suite("SpongeSchematicParser")
struct SpongeSchematicParserTests {

    @Test("Parses a v1/v2-shaped schematic (root-level Palette/BlockData)")
    func parsesRootLevelLayout() throws {
        // 2x1x1: stone at x=0, a rotated-looking oak_stairs at x=1.
        let root: NBTTag = .compound([
            "Version": .int(2),
            "Width": .short(2),
            "Height": .short(1),
            "Length": .short(1),
            "PaletteMax": .int(2),
            "Palette": .compound([
                "minecraft:stone": .int(0),
                "minecraft:oak_stairs[facing=north,half=bottom]": .int(1)
            ]),
            "BlockData": SchematicFixture.blockData([0, 1])
        ])

        let schematic = try SpongeSchematicParser.parse(data: SchematicFixture.document(root: root))
        #expect(schematic.width == 2)
        #expect(schematic.height == 1)
        #expect(schematic.length == 1)
        #expect(schematic.blocks.count == 2)

        let stone = schematic.blocks.first { $0.x == 0 }
        #expect(stone?.blockID == "minecraft:stone")
        #expect(stone?.properties.isEmpty == true)

        let stairs = schematic.blocks.first { $0.x == 1 }
        #expect(stairs?.blockID == "minecraft:oak_stairs")
        #expect(stairs?.properties == ["facing": "north", "half": "bottom"])
    }

    @Test("Parses a v3-shaped schematic (nested under Schematic -> Blocks, field named Data)")
    func parsesV3NestedLayout() throws {
        let root: NBTTag = .compound([
            "Schematic": .compound([
                "Version": .int(3),
                "DataVersion": .int(3700),
                "Width": .short(1),
                "Height": .short(2),
                "Length": .short(1),
                "Blocks": .compound([
                    "Palette": .compound([
                        "minecraft:dirt": .int(0),
                        "minecraft:oak_log[axis=y]": .int(1)
                    ]),
                    "Data": SchematicFixture.blockData([0, 1]) // y=0 dirt, y=1 log
                ])
            ])
        ])

        let schematic = try SpongeSchematicParser.parse(data: SchematicFixture.document(root: root))
        #expect(schematic.width == 1)
        #expect(schematic.height == 2)
        #expect(schematic.blocks.count == 2)

        let bottom = schematic.blocks.first { $0.y == 0 }
        #expect(bottom?.blockID == "minecraft:dirt")
        let top = schematic.blocks.first { $0.y == 1 }
        #expect(top?.blockID == "minecraft:oak_log")
        #expect(top?.properties == ["axis": "y"])
    }

    @Test("Decodes block positions in x-innermost, z, y-outermost order")
    func decodesIterationOrderCorrectly() throws {
        // 2x1x2 (W x H x L): four distinct blocks so every position is
        // uniquely identifiable by which block ended up where.
        let root: NBTTag = .compound([
            "Width": .short(2),
            "Height": .short(1),
            "Length": .short(2),
            "Palette": .compound([
                "minecraft:a": .int(0),
                "minecraft:b": .int(1),
                "minecraft:c": .int(2),
                "minecraft:d": .int(3)
            ]),
            // Spec order: index = x + z*Width + y*Width*Length.
            // (x=0,z=0)=a, (x=1,z=0)=b, (x=0,z=1)=c, (x=1,z=1)=d
            "BlockData": SchematicFixture.blockData([0, 1, 2, 3])
        ])
        let schematic = try SpongeSchematicParser.parse(data: SchematicFixture.document(root: root))
        func blockID(x: Int, z: Int) -> String? {
            schematic.blocks.first { $0.x == x && $0.y == 0 && $0.z == z }?.blockID
        }
        #expect(blockID(x: 0, z: 0) == "minecraft:a")
        #expect(blockID(x: 1, z: 0) == "minecraft:b")
        #expect(blockID(x: 0, z: 1) == "minecraft:c")
        #expect(blockID(x: 1, z: 1) == "minecraft:d")
    }

    @Test("Throws when dimensions are missing")
    func throwsOnMissingDimensions() {
        let root: NBTTag = .compound(["Palette": .compound([:]), "BlockData": .byteArray([])])
        #expect(throws: SpongeSchematicError.missingDimensions) {
            _ = try SpongeSchematicParser.parse(data: SchematicFixture.document(root: root))
        }
    }

    @Test("Throws when the palette is missing")
    func throwsOnMissingPalette() {
        let root: NBTTag = .compound(["Width": .short(1), "Height": .short(1), "Length": .short(1)])
        #expect(throws: SpongeSchematicError.missingPalette) {
            _ = try SpongeSchematicParser.parse(data: SchematicFixture.document(root: root))
        }
    }

    @Test("Throws when block data references a palette index that doesn't exist")
    func throwsOnInvalidPaletteIndex() {
        let root: NBTTag = .compound([
            "Width": .short(1), "Height": .short(1), "Length": .short(1),
            "Palette": .compound(["minecraft:stone": .int(0)]),
            "BlockData": SchematicFixture.blockData([5]) // no palette entry for index 5
        ])
        #expect(throws: SpongeSchematicError.invalidPaletteIndex(5)) {
            _ = try SpongeSchematicParser.parse(data: SchematicFixture.document(root: root))
        }
    }

    @Test("Throws on truncated block data rather than crashing")
    func throwsOnTruncatedBlockData() {
        let root: NBTTag = .compound([
            "Width": .short(2), "Height": .short(1), "Length": .short(1), // needs 2 entries
            "Palette": .compound(["minecraft:stone": .int(0)]),
            "BlockData": SchematicFixture.blockData([0]) // only 1
        ])
        #expect(throws: SpongeSchematicError.corruptBlockData) {
            _ = try SpongeSchematicParser.parse(data: SchematicFixture.document(root: root))
        }
    }
}
