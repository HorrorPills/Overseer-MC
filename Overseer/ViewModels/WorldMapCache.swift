//
//  WorldMapCache.swift
//  Overseer
//
//  Keeps the parsed biome grid in memory for the app's lifetime instead
//  of re-reading and re-decompressing every mirrored .mca file (100+
//  regions, hundreds of MB, tens of thousands of chunks between them)
//  on every single visit to the World Map sidebar item — WorldMapView's
//  own @State didn't survive navigating away and back, since SwiftUI
//  tears down and recreates that whole view subtree each time the
//  sidebar switch picks a different case.
//
//  Kept as one sub-grid per region file (`RegionChunkGrid`) rather than
//  one flat dictionary for two reasons: refreshing only needs to
//  re-parse files that are new or have changed since the last build
//  (an unchanged region's sub-grid is just reused), and
//  WorldMapCanvasView can cull to only the regions actually visible in
//  the current viewport instead of iterating every chunk on every
//  frame during a pan/zoom gesture.
//

import Foundation

struct RegionChunkGrid: Identifiable {
    var filename: String
    var regionX: Int
    var regionZ: Int
    var chunks: [ChunkCoordinate: String]
    var id: String { filename }

    /// World-block bounding box this region covers (32x32 chunks, 16
    /// blocks each) — cheap to check against a viewport without
    /// touching `chunks` at all.
    var blockBounds: (minX: Int, maxX: Int, minZ: Int, maxZ: Int) {
        (regionX * 512, regionX * 512 + 512, regionZ * 512, regionZ * 512 + 512)
    }
}

@MainActor
@Observable
final class WorldMapCache {
    private(set) var regions: [RegionChunkGrid] = []
    private(set) var isLoading = false
    private(set) var lastBuiltAt: Date?

    private var fileModDates: [String: Date] = [:]

    var chunkCount: Int { regions.reduce(0) { $0 + $1.chunks.count } }

    /// Instant if already built this launch — only scans disk the
    /// first time a view asks for it.
    func ensureLoaded(directory: URL) async {
        guard regions.isEmpty else { return }
        await refresh(directory: directory)
    }

    /// Re-scans the mirror directory, but only re-parses region files
    /// that are new or whose modification date has advanced since the
    /// last build; everything else is reused from the existing cache
    /// untouched.
    func refresh(directory: URL) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let existingByFilename = Dictionary(uniqueKeysWithValues: regions.map { ($0.filename, $0) })
        let existingModDates = fileModDates

        let result = await Task.detached(priority: .userInitiated) { () -> ([RegionChunkGrid], [String: Date]) in
            let fileManager = FileManager.default
            guard let fileURLs = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
                return (Array(existingByFilename.values), existingModDates)
            }
            let regionURLs = fileURLs.filter { WorldMapEngine.isRegionFile($0) }
            var updated: [RegionChunkGrid] = []
            var updatedModDates: [String: Date] = [:]

            for url in regionURLs {
                let filename = url.lastPathComponent
                guard let coords = RegionFileReader.regionCoordinates(fromFilename: filename) else { continue }
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

                if let modDate, let cachedModDate = existingModDates[filename], cachedModDate >= modDate,
                   let cached = existingByFilename[filename] {
                    updated.append(cached) // unchanged since last build -> reuse as-is
                    updatedModDates[filename] = cachedModDate
                    continue
                }

                guard let data = try? Data(contentsOf: url) else { continue }
                let entry = RegionFileEntry(filename: filename, data: data)
                let chunks = WorldMapEngine.buildBiomeGrid(entries: [entry])
                updated.append(RegionChunkGrid(filename: filename, regionX: coords.x, regionZ: coords.z, chunks: chunks))
                if let modDate { updatedModDates[filename] = modDate }
            }

            return (updated, updatedModDates)
        }.value

        regions = result.0
        fileModDates = result.1
        lastBuiltAt = .now
    }
}
