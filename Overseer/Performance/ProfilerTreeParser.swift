//
//  ProfilerTreeParser.swift
//  Overseer
//
//  server/profiling.txt's main tree, between "--- BEGIN PROFILE DUMP ---"
//  and "--- END PROFILE DUMP ---" (the "-- Counter: … --" sections after
//  that marker are a different, simpler format and aren't read here).
//
//  Each line is depth-prefixed and indented with one "|   " group per
//  depth level, e.g.:
//
//    [00] tick(76/1) - 99.14%/99.14%
//    [01] |   levels(76/1) - 94.69%/93.87%
//    [06] |   |   |   |   |   |   minecraft:zombie(5784/76) - 14.73%/5.21%
//    [07] |   |   |   |   |   |   |   #tickNonPassenger 5784/76
//
//  Two line shapes appear at every depth: a percentage node
//  ("name(hits/samples) - self%/total%") and a bare counter mention
//  ("#counterName hits/samples", no percentages — a sample recorded at
//  that call site, aggregated separately in the Counter Dump section).
//  Only the former is structural profiler data; counter mentions are
//  skipped here.
//

import Foundation

enum ProfilerTreeParser {
    static func parse(_ text: String) -> [ProfilerNode] {
        guard let dumpBody = extractDumpBody(text) else { return [] }

        var nodes: [ProfilerNode] = []
        var ancestors: [String] = []

        // See SimpleCSV.rows for why `whereSeparator: \.isNewline` and
        // not `separator: "\n"` — this file is CRLF-terminated.
        for rawLine in dumpBody.split(whereSeparator: \.isNewline) {
            guard let (depth, content) = splitDepthAndContent(rawLine) else { continue }
            guard !content.hasPrefix("#") else { continue }
            guard let parsed = parseNodeContent(content) else { continue }

            while ancestors.count > depth { ancestors.removeLast() }
            let path = ancestors
            ancestors.append(parsed.name)

            nodes.append(ProfilerNode(
                depth: depth, name: parsed.name, path: path,
                hits: parsed.hits, samples: parsed.samples,
                selfPercent: parsed.selfPercent, totalPercent: parsed.totalPercent
            ))
        }

        return nodes
    }

    /// Sorted by self-time descending — the "what's actually expensive"
    /// view, since total% mostly just tracks tree depth near the root.
    static func topSelfTime(_ nodes: [ProfilerNode], limit: Int = 25) -> [ProfilerNode] {
        Array(nodes.sorted { $0.selfPercent > $1.selfPercent }.prefix(limit))
    }

    // MARK: - Line parsing

    private static func extractDumpBody(_ text: String) -> Substring? {
        guard let fullRange = text.range(of: "--- BEGIN PROFILE DUMP ---") else { return nil }
        let afterBegin = text[fullRange.upperBound...]
        guard let endRange = afterBegin.range(of: "--- END PROFILE DUMP ---") else { return afterBegin }
        return afterBegin[afterBegin.startIndex..<endRange.lowerBound]
    }

    /// `[07] |   |   |   |   |   |   |   #tickNonPassenger 5784/76`
    /// → depth 7, content "#tickNonPassenger 5784/76". The indent is
    /// exactly one space after "]", then `depth` repetitions of the
    /// 4-character "|   " group — stripped positionally rather than
    /// with a regex since the group count is already known from the
    /// bracketed depth number.
    private static func splitDepthAndContent(_ rawLine: Substring) -> (depth: Int, content: Substring)? {
        guard rawLine.first == "[", let closeBracket = rawLine.firstIndex(of: "]") else { return nil }
        let depthString = rawLine[rawLine.index(after: rawLine.startIndex)..<closeBracket]
        guard let depth = Int(depthString) else { return nil }

        var rest = rawLine[rawLine.index(after: closeBracket)...]
        guard rest.first == " " else { return nil }
        rest = rest.dropFirst()

        let indentGroup = "|   "
        for _ in 0..<depth {
            guard rest.hasPrefix(indentGroup) else { return nil }
            rest = rest.dropFirst(indentGroup.count)
        }
        return (depth, rest)
    }

    private struct NodeContent {
        var name: String
        var hits: Int
        var samples: Int
        var selfPercent: Double
        var totalPercent: Double
    }

    /// `ServerLevel[world] minecraft:overworld(76/1) - 73.28%/68.79%`
    /// → name up to the last "(", the two counts inside it, and the two
    /// percentages after " - ". Name uses the *last* "(" (rather than
    /// the first) since names like "ServerLevel[world] minecraft:end"
    /// contain their own bracket pairs before the count.
    private static func parseNodeContent(_ content: Substring) -> NodeContent? {
        guard let dashRange = content.range(of: " - ", options: .backwards) else { return nil }
        let head = content[content.startIndex..<dashRange.lowerBound]
        let tail = content[dashRange.upperBound...]

        guard let openParen = head.lastIndex(of: "("), head.hasSuffix(")") else { return nil }
        let name = head[head.startIndex..<openParen].trimmingCharacters(in: .whitespaces)
        let counts = head[head.index(after: openParen)..<head.index(before: head.endIndex)]
        let countParts = counts.split(separator: "/")
        guard countParts.count == 2, let hits = Int(countParts[0]), let samples = Int(countParts[1]) else { return nil }

        let percentParts = tail.split(separator: "/")
        guard percentParts.count == 2,
              let selfPercent = Double(percentParts[0].trimmingCharacters(in: CharacterSet(charactersIn: "%"))),
              let totalPercent = Double(percentParts[1].trimmingCharacters(in: CharacterSet(charactersIn: "%"))) else {
            return nil
        }

        guard !name.isEmpty else { return nil }
        return NodeContent(name: name, hits: hits, samples: samples, selfPercent: selfPercent, totalPercent: totalPercent)
    }
}
