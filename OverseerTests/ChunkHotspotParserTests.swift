//
//  ChunkHotspotParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("ChunkHotspotParser")
struct ChunkHotspotParserTests {

    private let entityChunksCSV = """
    x,y,z,visibility,load_status,entity_count
    -18,0,12,TICKING,LOADED,40
    -34,7,15,TRACKED,LOADED,21
    -19,3,12,TICKING,LOADED,16
    """

    // Columns match the real chunks.csv shape: 16 columns, block_entity_count at index 11.
    private let chunksCSV = """
    x,z,level,in_memory,status,full_status,accessible_ready,ticking_ready,entity_ticking_ready,ticket,spawning,block_entity_count,ticking_ticket,ticking_level,block_ticks,fluid_ticks
    88,-170,31,true,minecraft:full,ENTITY_TICKING,done,done,done,no_ticket,true,125,no_ticket,25,11,3
    -19,12,31,true,minecraft:full,ENTITY_TICKING,done,done,done,no_ticket,true,59,no_ticket,24,2,0
    0,0,31,true,minecraft:full,ENTITY_TICKING,done,done,done,no_ticket,true,3,no_ticket,24,0,0
    """

    @Test("entityHotspots includes y and sorts by entity_count descending")
    func entityHotspotsIncludeYAndSort() {
        let spots = ChunkHotspotParser.entityHotspots(csv: entityChunksCSV)
        #expect(spots.map(\.value) == [40, 21, 16])
        #expect(spots[0].x == -18)
        #expect(spots[0].y == 0)
        #expect(spots[0].z == 12)
    }

    @Test("blockEntityHotspots has no y and sorts by block_entity_count descending")
    func blockEntityHotspotsHaveNoY() {
        let spots = ChunkHotspotParser.blockEntityHotspots(csv: chunksCSV)
        #expect(spots.map(\.value) == [125, 59, 3])
        #expect(spots[0].y == nil)
    }

    @Test("limit caps the number of returned hotspots")
    func limitCaps() {
        let spots = ChunkHotspotParser.entityHotspots(csv: entityChunksCSV, limit: 2)
        #expect(spots.count == 2)
        #expect(spots.map(\.value) == [40, 21])
    }

    @Test("totalLoadedChunks counts data rows, excluding the header")
    func totalLoadedChunksExcludesHeader() {
        #expect(ChunkHotspotParser.totalLoadedChunks(csv: chunksCSV) == 3)
        #expect(ChunkHotspotParser.totalLoadedChunks(csv: "") == 0)
    }

    @Test("sum totals an integer column by header name")
    func sumTotalsColumn() {
        #expect(ChunkHotspotParser.sum(csv: chunksCSV, column: "block_ticks") == 13)
        #expect(ChunkHotspotParser.sum(csv: chunksCSV, column: "fluid_ticks") == 3)
    }

    @Test("CRLF line endings parse the same as LF")
    func handlesCRLFLineEndings() {
        let csv = "x,y,z,visibility,load_status,entity_count\r\n-18,0,12,TICKING,LOADED,40\r\n-19,3,12,TICKING,LOADED,16\r\n"
        let spots = ChunkHotspotParser.entityHotspots(csv: csv)
        #expect(spots.map(\.value) == [40, 16])
    }

    @Test("Missing required columns yields an empty hotspot list rather than a crash")
    func missingColumnsYieldsEmpty() {
        #expect(ChunkHotspotParser.entityHotspots(csv: "x,z\n1,2").isEmpty)
    }
}
