//
//  EntityPositionParser.swift
//  Overseer
//
//  Parses vanilla's `/data get entity <player> Pos` RCON response, used
//  by the schematic builder's "Fetch Player Position" button.
//
//  Expected response shape (vanilla, `commands.data.entity.get`):
//    "Alice has the following entity data: [1234.5d, 65.0d, 5678.9d]"
//  `Pos` is stored as a 3-element NBT double list; vanilla's SNBT
//  stringification suffixes each with 'd', which this tolerates as
//  optional in case of any variation.
//
//  Pure and dependency-free so it's directly unit-testable.
//

import Foundation

enum EntityPositionParserError: Error, Equatable {
    case unrecognizedFormat
}

enum EntityPositionParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"\[\s*(-?[\d.]+)d?\s*,\s*(-?[\d.]+)d?\s*,\s*(-?[\d.]+)d?\s*\]"#
    )

    static func parse(_ response: String) throws -> (x: Double, y: Double, z: Double) {
        let range = NSRange(response.startIndex..<response.endIndex, in: response)
        guard let match = pattern.firstMatch(in: response, range: range),
              let xRange = Range(match.range(at: 1), in: response),
              let yRange = Range(match.range(at: 2), in: response),
              let zRange = Range(match.range(at: 3), in: response),
              let x = Double(response[xRange]),
              let y = Double(response[yRange]),
              let z = Double(response[zRange])
        else {
            throw EntityPositionParserError.unrecognizedFormat
        }
        return (x, y, z)
    }
}
