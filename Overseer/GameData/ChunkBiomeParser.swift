//
//  ChunkBiomeParser.swift
//  Overseer
//
//  Extracts one representative biome per chunk column from a chunk's
//  decompressed NBT (see RegionFileReader) — verified against
//  minecraft.wiki/w/Chunk_format's post-1.18 `sections[].biomes`
//  paletted-container format: a `palette` list of biome resource
//  locations and, when there's more than one entry, a `data` LongArray
//  of packed indices — "not packed across multiple elements," i.e.
//  each long holds a whole number of entries with any remaining high
//  bits left as padding (unlike the older long-array packing scheme
//  that packs continuously across long boundaries).
//
//  Biome is sampled from ONE section (`sampleSectionY`, default 4 —
//  world Y 64...79, spanning sea level) rather than reconstructed
//  across the full column height: overworld biome is overwhelmingly
//  vertically uniform through a column, and the World Map feature only
//  needs a glanceable overview, not exact per-block biome truth.
//

import Foundation

enum ChunkBiomeParser {
    /// The most common biome (by cell count) in the sampled section's
    /// 4×4×4-celled, 64-entry paletted biome array — nil if that
    /// section isn't present (e.g. an unusually short/truncated chunk)
    /// or the data is malformed, in which case the caller should just
    /// treat this chunk as unknown rather than guess.
    static func representativeBiome(chunkNBT: NBTTag, sampleSectionY: Int = 4) -> String? {
        guard let sections = chunkNBT["sections"]?.asList,
              let section = sections.first(where: { $0["Y"]?.asInt == sampleSectionY })
        else { return nil }
        return biome(inSection: section)
    }

    static func biome(inSection section: NBTTag) -> String? {
        guard let biomes = section["biomes"],
              let palette = biomes["palette"]?.asList,
              !palette.isEmpty
        else { return nil }

        let names = palette.compactMap(\.asString)
        guard names.count == palette.count else { return nil } // a non-string palette entry -> malformed

        if names.count == 1 { return names[0] } // uniform section, no data array present

        guard case .longArray(let longs)? = biomes["data"] else { return nil }
        let bitsPerEntry = bitsNeeded(forCount: names.count)
        let indices = unpackIndices(longs: longs, bitsPerEntry: bitsPerEntry, entryCount: 64)
        guard !indices.isEmpty else { return nil }

        var counts: [Int: Int] = [:]
        for index in indices where index >= 0 && index < names.count {
            counts[index, default: 0] += 1
        }
        guard let mostCommon = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return names[mostCommon]
    }

    private static func bitsNeeded(forCount count: Int) -> Int {
        guard count > 1 else { return 0 }
        var bits = 1
        while (1 << bits) < count { bits += 1 }
        return bits
    }

    /// Indices are NOT packed across long boundaries — each 64-bit long
    /// holds `floor(64 / bitsPerEntry)` whole entries, with any leftover
    /// high bits unused padding, matching every post-1.18 paletted
    /// container (block states, biomes) rather than the older
    /// continuous-packing scheme.
    static func unpackIndices(longs: [Int64], bitsPerEntry: Int, entryCount: Int) -> [Int] {
        guard bitsPerEntry > 0 else { return [] }
        let entriesPerLong = 64 / bitsPerEntry
        let mask: Int64 = (1 << bitsPerEntry) - 1
        var indices: [Int] = []
        indices.reserveCapacity(entryCount)
        outer: for long in longs {
            for slot in 0..<entriesPerLong {
                guard indices.count < entryCount else { break outer }
                let shifted = (long >> Int64(slot * bitsPerEntry)) & mask
                indices.append(Int(shifted))
            }
        }
        return indices
    }
}
