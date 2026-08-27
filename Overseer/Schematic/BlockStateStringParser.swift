//
//  BlockStateStringParser.swift
//  Overseer
//
//  Splits a vanilla blockstate string into its block ID and property
//  dictionary, e.g. "minecraft:oak_stairs[facing=north,half=bottom]"
//  -> ("minecraft:oak_stairs", ["facing": "north", "half": "bottom"]).
//  Used to decode Sponge Schematic Palette keys. Pure string parsing,
//  no dependency on NBT.
//

import Foundation

enum BlockStateStringParser {
    /// The inverse of `parse` — reassembles a blockstate string from a
    /// block ID and property dictionary, e.g. for feeding a rotated
    /// block back into `/setblock`/`/fill`. Shared by SchematicBlock
    /// and PlacedBlock's `blockStateString` so the two never drift.
    static func format(blockID: String, properties: [String: String]) -> String {
        guard !properties.isEmpty else { return blockID }
        let propertyList = properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "\(blockID)[\(propertyList)]"
    }

    static func parse(_ blockState: String) -> (blockID: String, properties: [String: String]) {
        guard let bracketIndex = blockState.firstIndex(of: "[") else {
            return (blockState, [:])
        }
        let blockID = String(blockState[blockState.startIndex..<bracketIndex])
        guard blockState.hasSuffix("]") else { return (blockID, [:]) }

        let propsStart = blockState.index(after: bracketIndex)
        let propsEnd = blockState.index(before: blockState.endIndex)
        guard propsStart <= propsEnd else { return (blockID, [:]) }

        let propsString = blockState[propsStart..<propsEnd]
        guard !propsString.isEmpty else { return (blockID, [:]) }

        var properties: [String: String] = [:]
        for pair in propsString.split(separator: ",") {
            let keyValue = pair.split(separator: "=", maxSplits: 1)
            guard keyValue.count == 2 else { continue }
            properties[String(keyValue[0])] = String(keyValue[1])
        }
        return (blockID, properties)
    }
}
