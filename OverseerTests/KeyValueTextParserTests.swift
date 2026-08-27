//
//  KeyValueTextParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("KeyValueTextParser")
struct KeyValueTextParserTests {

    @Test("Parses colon-separated system.txt-style lines")
    func parsesColonSeparated() {
        let text = """
        Minecraft Version: 26.3 Snapshot 8
        CPUs: 60
        Frequency (GHz): -0.00
        """
        let pairs = KeyValueTextParser.parse(text, separator: ":")
        #expect(pairs.count == 3)
        #expect(pairs[0].key == "Minecraft Version")
        #expect(pairs[0].value == "26.3 Snapshot 8")
        #expect(pairs[2].key == "Frequency (GHz)")
        #expect(pairs[2].value == "-0.00")
    }

    @Test("A line with nothing after the separator still parses, with an empty value, since it has no space to fail a \": \" match on")
    func lineWithNoValueParsesAsEmptyString() {
        let pairs = KeyValueTextParser.parse("Graphics card #0 name:", separator: ":")
        #expect(pairs == [KeyValuePair(key: "Graphics card #0 name", value: "")])
    }

    @Test("Parses equals-separated gamerules/server.properties-style lines")
    func parsesEqualsSeparated() {
        let text = """
        minecraft:mob_griefing=true
        minecraft:random_tick_speed=3
        """
        let pairs = KeyValueTextParser.parse(text, separator: "=")
        #expect(pairs == [
            KeyValuePair(key: "minecraft:mob_griefing", value: "true"),
            KeyValuePair(key: "minecraft:random_tick_speed", value: "3")
        ])
    }

    @Test("Only splits on the first separator occurrence, so a value containing the separator survives whole")
    func splitsOnlyOnFirstOccurrence() {
        let pairs = KeyValueTextParser.parse("distance_manager: player ticket throttler=[], s=true", separator: ":")
        #expect(pairs.count == 1)
        #expect(pairs[0].value == "player ticket throttler=[], s=true")
    }

    @Test("CRLF line endings parse the same as LF")
    func handlesCRLFLineEndings() {
        let pairs = KeyValueTextParser.parse("CPUs: 60\r\nCores: 12\r\n", separator: ":")
        #expect(pairs == [KeyValuePair(key: "CPUs", value: "60"), KeyValuePair(key: "Cores", value: "12")])
    }

    @Test("Blank lines and comment lines are ignored")
    func ignoresBlankAndCommentLines() {
        let text = """

        // a comment
        key=value

        """
        let pairs = KeyValueTextParser.parse(text, separator: "=")
        #expect(pairs == [KeyValuePair(key: "key", value: "value")])
    }
}
