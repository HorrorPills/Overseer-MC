//
//  WorldMapEngine.swift
//  Overseer
//
//  Turns a folder of mirrored .mca region files (see
//  SFTPSyncCoordinator's world/region sync) into a chunk-coordinate ->
//  biome-ID grid for WorldMapView to render. Bytes-in, same split as
//  every other folder scanner in this app (PlayerDataFolderScanner,
//  ServerLogFolderScanner, ...): the view owns directory enumeration
//  and file reads, this stays pure and unit-testable.
//
//  Real generated terrain only — never a from-scratch simulation of
//  the world seed. Reimplementing Mojang's exact terrain-generation
//  algorithm (itself substantially reverse-engineered work, e.g.
//  Chunkbase/Amidst) for a hypothetical future snapshot with no public
//  specification would risk rendering biomes that are simply wrong —
//  a bad failure mode for a tool used to reason about real coordinates
//  during a griefing investigation. Unexplored chunks just render blank.
//

import Foundation

struct ChunkCoordinate: Hashable, Sendable {
    var x: Int
    var z: Int
}

struct RegionFileEntry {
    var filename: String
    var data: Data
}

enum WorldMapEngine {
    static func isRegionFile(_ url: URL) -> Bool {
        RegionFileReader.regionCoordinates(fromFilename: url.lastPathComponent) != nil
    }

    /// One representative biome per generated chunk column, keyed by
    /// absolute chunk coordinate (world block coordinate / 16). Chunks
    /// that fail to parse (truncated download, unrecognized NBT shape)
    /// are silently omitted rather than shown incorrectly.
    static func buildBiomeGrid(entries: [RegionFileEntry]) -> [ChunkCoordinate: String] {
        var grid: [ChunkCoordinate: String] = [:]
        for entry in entries {
            guard let region = RegionFileReader.regionCoordinates(fromFilename: entry.filename) else { continue }
            guard let chunks = try? RegionFileReader.readChunks(from: entry.data) else { continue }
            for chunk in chunks {
                guard let (_, tag) = try? NBTParser.parse(data: chunk.nbt),
                      let biome = ChunkBiomeParser.representativeBiome(chunkNBT: tag)
                else { continue }
                let chunkX = region.x * 32 + chunk.localX
                let chunkZ = region.z * 32 + chunk.localZ
                grid[ChunkCoordinate(x: chunkX, z: chunkZ)] = biome
            }
        }
        return grid
    }
}
