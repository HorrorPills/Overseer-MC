//
//  ChunkBiomeParserTests.swift
//  OverseerTests
//
//  Builds NBTTag values directly (rather than raw bytes) since
//  ChunkBiomeParser operates on the already-decoded tag tree —
//  NBTParser's own byte-level decoding is exercised by its own test
//  suite already.
//

import Foundation
import Testing
@testable import Overseer

@Suite("ChunkBiomeParser")
struct ChunkBiomeParserTests {

    private func section(y: Int, biomes: NBTTag) -> NBTTag {
        .compound(["Y": .byte(Int8(y)), "biomes": biomes])
    }

    @Test("A uniform section (single-entry palette) reads its one biome with no data array needed")
    func uniformSectionNoDataArray() {
        let biomes: NBTTag = .compound(["palette": .list([.string("minecraft:plains")])])
        #expect(ChunkBiomeParser.biome(inSection: section(y: 4, biomes: biomes)) == "minecraft:plains")
    }

    @Test("A mixed section picks the most common biome by packed index count")
    func mixedSectionPicksMostCommon() {
        // 2-entry palette needs 1 bit/entry. Pack indices [1,1,1,0,...]
        // (three 1s, one 0) into a single long, entries 4..63 default 0
        // (i.e. mostly palette[0]) — deliberately construct so
        // palette[0] still wins overall despite the first four slots
        // favoring index 1, exercising the "majority across the whole
        // 64-cell section" behavior, not just the first long.
        // 1 bit/entry -> a single long holds all 64 entries. Bits 0-2 set
        // (index 1, three times); bits 3-63 stay 0 (index 0, 61 times).
        var long: Int64 = 0
        long |= 1 << 0
        long |= 1 << 1
        long |= 1 << 2

        let biomes: NBTTag = .compound([
            "palette": .list([.string("minecraft:ocean"), .string("minecraft:river")]),
            "data": .longArray([long])
        ])
        let result = ChunkBiomeParser.biome(inSection: section(y: 4, biomes: biomes))
        #expect(result == "minecraft:ocean") // index 0 dominates across the full 64 entries
    }

    @Test("representativeBiome finds the section matching sampleSectionY among several")
    func representativeBiomeFindsMatchingSection() {
        let wrongSection = section(y: 0, biomes: .compound(["palette": .list([.string("minecraft:the_void")])]))
        let rightSection = section(y: 4, biomes: .compound(["palette": .list([.string("minecraft:forest")])]))
        let chunk: NBTTag = .compound(["sections": .list([wrongSection, rightSection])])
        #expect(ChunkBiomeParser.representativeBiome(chunkNBT: chunk) == "minecraft:forest")
    }

    @Test("representativeBiome returns nil when no section matches sampleSectionY")
    func representativeBiomeNilWhenSectionMissing() {
        let chunk: NBTTag = .compound(["sections": .list([section(y: 10, biomes: .compound(["palette": .list([.string("minecraft:plains")])]))])])
        #expect(ChunkBiomeParser.representativeBiome(chunkNBT: chunk, sampleSectionY: 4) == nil)
    }

    @Test("biome(inSection:) returns nil for a missing or empty palette")
    func nilForMissingPalette() {
        #expect(ChunkBiomeParser.biome(inSection: .compound([:])) == nil)
        #expect(ChunkBiomeParser.biome(inSection: .compound(["biomes": .compound(["palette": .list([])])])) == nil)
    }

    @Test("unpackIndices reads bitsPerEntry-sized fields without crossing long boundaries")
    func unpackIndicesRespectsLongBoundaries() {
        // 3 bits/entry -> 21 entries fit in one 64-bit long (63 bits used, 1 padding bit).
        var long: Int64 = 0
        long |= 0b101 << 0  // entry 0 = 5
        long |= 0b011 << 3  // entry 1 = 3
        let indices = ChunkBiomeParser.unpackIndices(longs: [long], bitsPerEntry: 3, entryCount: 2)
        #expect(indices == [5, 3])
    }
}
