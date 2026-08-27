//
//  EntityCensusParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("EntityCensusParser")
struct EntityCensusParserTests {

    @Test("Counts rows per distinct type, sorted by count descending")
    func countsAndSortsDescending() {
        let csv = """
        x,y,z,uuid,type,alive,display_name,custom_name
        1,2,3,u1,minecraft:zombie,true,Zombie,[null]
        1,2,3,u2,minecraft:zombie,true,Zombie,[null]
        1,2,3,u3,minecraft:cow,true,Cow,[null]
        1,2,3,u4,minecraft:zombie,true,Zombie,[null]
        """
        let counts = EntityCensusParser.count(csv: csv)
        #expect(counts == [
            EntityTypeCount(type: "minecraft:zombie", count: 3),
            EntityTypeCount(type: "minecraft:cow", count: 1)
        ])
    }

    @Test("Reads the 'type' column by header name, not fixed position")
    func readsBlockEntityTypeColumn() {
        // block_entities.csv puts "type" last, not at index 4 like entities.csv.
        let csv = """
        x,y,z,type
        1,63,-2720,minecraft:furnace
        2,63,-2720,minecraft:furnace
        3,63,-2720,minecraft:hopper
        """
        let counts = EntityCensusParser.count(csv: csv)
        #expect(counts == [
            EntityTypeCount(type: "minecraft:furnace", count: 2),
            EntityTypeCount(type: "minecraft:hopper", count: 1)
        ])
    }

    @Test("Extra unexpected commas in a later column don't corrupt the type count, since type is an earlier column")
    func toleratesExtraCommasInLaterColumn() {
        let csv = """
        x,y,z,uuid,type,alive,display_name,custom_name
        1,2,3,u1,minecraft:zombie,true,Zombie,unexpected,extra,commas
        """
        let counts = EntityCensusParser.count(csv: csv)
        #expect(counts.first?.type == "minecraft:zombie")
        #expect(counts.first?.count == 1)
    }

    @Test("Ties break alphabetically for a stable order")
    func tiesBreakAlphabetically() {
        let csv = """
        type
        minecraft:zombie
        minecraft:cow
        """
        let counts = EntityCensusParser.count(csv: csv)
        #expect(counts.map(\.type) == ["minecraft:cow", "minecraft:zombie"])
    }

    @Test("CRLF line endings (what vanilla actually writes these CSVs with) parse the same as LF")
    func handlesCRLFLineEndings() {
        let csv = "type\r\nminecraft:zombie\r\nminecraft:zombie\r\nminecraft:cow\r\n"
        let counts = EntityCensusParser.count(csv: csv)
        #expect(counts == [
            EntityTypeCount(type: "minecraft:zombie", count: 2),
            EntityTypeCount(type: "minecraft:cow", count: 1)
        ])
    }

    @Test("CRLF doesn't corrupt a header whose last column is the one being looked up (block_entities.csv's 'type' is last)")
    func crlfDoesNotCorruptLastHeaderColumn() {
        // Regression: Swift's Character treats "\r\n" as one grapheme
        // cluster distinct from "\n" — splitting on a bare "\n" literal
        // wouldn't match at all here, silently collapsing the whole CSV
        // into a single "row" and making every lookup miss.
        let csv = "x,y,z,type\r\n1,63,-2720,minecraft:furnace\r\n2,63,-2720,minecraft:hopper\r\n"
        let counts = EntityCensusParser.count(csv: csv)
        #expect(counts == [
            EntityTypeCount(type: "minecraft:furnace", count: 1),
            EntityTypeCount(type: "minecraft:hopper", count: 1)
        ])
    }

    @Test("Missing 'type' column or empty CSV returns an empty list")
    func handlesMissingColumnAndEmptyInput() {
        #expect(EntityCensusParser.count(csv: "x,y,z\n1,2,3").isEmpty)
        #expect(EntityCensusParser.count(csv: "").isEmpty)
    }
}
