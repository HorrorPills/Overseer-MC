//
//  ProfilerTreeParserTests.swift
//  OverseerTests
//
//  Fixture text mirrors a real /perf report's profiling.txt exactly
//  (indentation, depth numbering, counter-mention lines) — captured
//  from an actual snapshot run rather than guessed from memory.
//

import Foundation
import Testing
@testable import Overseer

@Suite("ProfilerTreeParser")
struct ProfilerTreeParserTests {

    private let sample = """
    ---- Minecraft Profiler Results ----

    Version: 26.3-snapshot-8
    Time span: 10054 ms
    Tick span: 76 ticks

    --- BEGIN PROFILE DUMP ---

    [00] tick(76/1) - 99.14%/99.14%
    [01] |   levels(76/1) - 94.69%/93.87%
    [02] |   |   ServerLevel[world] minecraft:overworld(76/1) - 73.28%/68.79%
    [03] |   |   |   tick(76/1) - 99.66%/68.56%
    [04] |   |   |   |   entities(76/1) - 53.69%/36.81%
    [05] |   |   |   |   |   tick(53440/703) - 96.18%/35.40%
    [06] |   |   |   |   |   |   minecraft:zombie(5784/76) - 14.73%/5.21%
    [07] |   |   |   |   |   |   |   #tickNonPassenger 5784/76
    [07] |   |   |   |   |   |   |   ai(5781/76) - 39.88%/2.08%
    [06] |   |   |   |   |   |   minecraft:cow(76/76) - 1.00%/0.35%
    --- END PROFILE DUMP ---

    --- BEGIN COUNTER DUMP ---

    -- Counter: tickNonPassenger --
    [00] root total:0/760 average: 0/10
    --- END COUNTER DUMP ---
    """

    @Test("Parses every percentage node, skipping counter-mention (#) lines")
    func parsesNodesAndSkipsCounterMentions() {
        let nodes = ProfilerTreeParser.parse(sample)
        // 8 percentage nodes: tick, levels, ServerLevel[...], tick, entities, tick, zombie, ai, cow = 9
        #expect(nodes.count == 9)
        #expect(!nodes.contains { $0.name.hasPrefix("#") })
    }

    @Test("Depth, hits, samples, and percentages are read correctly for a leaf node")
    func parsesLeafNodeFields() {
        let nodes = ProfilerTreeParser.parse(sample)
        let zombie = try! #require(nodes.first { $0.name == "minecraft:zombie" })
        #expect(zombie.depth == 6)
        #expect(zombie.hits == 5784)
        #expect(zombie.samples == 76)
        #expect(zombie.selfPercent == 14.73)
        #expect(zombie.totalPercent == 5.21)
    }

    @Test("Ancestor path is built correctly and survives a sibling backtrack")
    func buildsAncestorPath() {
        let nodes = ProfilerTreeParser.parse(sample)
        let zombie = try! #require(nodes.first { $0.name == "minecraft:zombie" })
        #expect(zombie.path == ["tick", "levels", "ServerLevel[world] minecraft:overworld", "tick", "entities", "tick"])

        // cow is a sibling of zombie (both depth 6, same parent "tick" at depth 5) —
        // its path must match zombie's exactly, not include zombie's "ai" child.
        let cow = try! #require(nodes.first { $0.name == "minecraft:cow" })
        #expect(cow.path == zombie.path)
    }

    @Test("breadcrumb joins path and name with the arrow separator")
    func breadcrumbFormatsCorrectly() {
        let nodes = ProfilerTreeParser.parse(sample)
        let cow = try! #require(nodes.first { $0.name == "minecraft:cow" })
        #expect(cow.breadcrumb == "tick › levels › ServerLevel[world] minecraft:overworld › tick › entities › tick › minecraft:cow")
    }

    @Test("Names containing brackets (dimension nodes) parse using the last '(' as the count delimiter")
    func parsesBracketedDimensionName() {
        let nodes = ProfilerTreeParser.parse(sample)
        let dim = try! #require(nodes.first { $0.name == "ServerLevel[world] minecraft:overworld" })
        #expect(dim.hits == 76)
        #expect(dim.samples == 1)
        #expect(dim.totalPercent == 68.79)
    }

    @Test("topSelfTime sorts by selfPercent descending and respects the limit")
    func topSelfTimeSortsAndLimits() {
        let nodes = ProfilerTreeParser.parse(sample)
        let top3 = ProfilerTreeParser.topSelfTime(nodes, limit: 3)
        #expect(top3.count == 3)
        #expect(top3.map(\.selfPercent) == top3.map(\.selfPercent).sorted(by: >))
        #expect(top3.first?.selfPercent ?? 0 >= (top3.last?.selfPercent ?? 0))
    }

    @Test("Text with no BEGIN PROFILE DUMP marker parses to an empty list rather than crashing")
    func noMarkerYieldsEmpty() {
        #expect(ProfilerTreeParser.parse("nothing here").isEmpty)
    }

    @Test("CRLF line endings parse the same as LF")
    func handlesCRLFLineEndings() {
        let text = "--- BEGIN PROFILE DUMP ---\r\n\r\n[00] tick(76/1) - 99.14%/99.14%\r\n[01] |   levels(76/1) - 94.69%/93.87%\r\n--- END PROFILE DUMP ---\r\n"
        let nodes = ProfilerTreeParser.parse(text)
        #expect(nodes.count == 2)
        #expect(nodes[1].name == "levels")
        #expect(nodes[1].path == ["tick"])
    }
}
