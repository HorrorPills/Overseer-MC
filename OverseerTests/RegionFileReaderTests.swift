//
//  RegionFileReaderTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("RegionFileReader")
struct RegionFileReaderTests {

    @Test("Parses region coordinates from a well-formed filename")
    func parsesRegionCoordinates() {
        let coords = RegionFileReader.regionCoordinates(fromFilename: "r.2.-3.mca")
        #expect(coords?.x == 2)
        #expect(coords?.z == -3)
    }

    @Test("Rejects filenames that aren't region files")
    func rejectsNonRegionFilenames() {
        #expect(RegionFileReader.regionCoordinates(fromFilename: "level.dat") == nil)
        #expect(RegionFileReader.regionCoordinates(fromFilename: "r.1.2.mcc") == nil)
        #expect(RegionFileReader.regionCoordinates(fromFilename: "r.notanumber.2.mca") == nil)
    }

    @Test("A region file shorter than the 8KB header is truncated")
    func rejectsTruncatedHeader() {
        #expect(throws: RegionFileError.self) {
            try RegionFileReader.readChunks(from: Data([0x00, 0x01, 0x02]))
        }
    }

    @Test("An all-zero header (no chunks generated) parses to an empty chunk list, not an error")
    func emptyHeaderYieldsNoChunks() throws {
        let data = Data(repeating: 0, count: 8192)
        let chunks = try RegionFileReader.readChunks(from: data)
        #expect(chunks.isEmpty)
    }
}

@Suite("WorldMapEngine")
struct WorldMapEngineTests {

    @Test("isRegionFile recognizes r.<x>.<z>.mca and rejects everything else")
    func recognizesRegionFiles() {
        #expect(WorldMapEngine.isRegionFile(URL(fileURLWithPath: "/world/region/r.0.0.mca")))
        #expect(WorldMapEngine.isRegionFile(URL(fileURLWithPath: "/world/region/r.-1.4.mca")))
        #expect(!WorldMapEngine.isRegionFile(URL(fileURLWithPath: "/world/region/session.lock")))
    }

    @Test("buildBiomeGrid skips entries whose filename isn't a valid region coordinate")
    func skipsInvalidFilenames() {
        let entries = [RegionFileEntry(filename: "not-a-region-file.mca", data: Data(repeating: 0, count: 8192))]
        #expect(WorldMapEngine.buildBiomeGrid(entries: entries).isEmpty)
    }

    @Test("buildBiomeGrid skips entries with no generated chunks without throwing")
    func skipsEmptyRegions() {
        let entries = [RegionFileEntry(filename: "r.0.0.mca", data: Data(repeating: 0, count: 8192))]
        #expect(WorldMapEngine.buildBiomeGrid(entries: entries).isEmpty)
    }
}
