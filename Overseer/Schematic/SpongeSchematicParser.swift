//
//  SpongeSchematicParser.swift
//  Overseer
//
//  Parses the Sponge Schematic Format (.schem — the format WorldEdit/
//  FAWE write), versions 1 through 3. Structure verified against the
//  canonical spec (github.com/SpongePowered/Schematic-Specification),
//  not just recalled, since getting the block-index iteration order or
//  the version-3 nesting wrong would silently misplace every block
//  rather than fail loudly:
//
//   - v1/v2: Version/Width/Height/Palette/BlockData are direct children
//     of the document's root compound.
//   - v3: everything is nested one level deeper, inside a child
//     compound literally named "Schematic" (root -> "Schematic" ->
//     Version/Width/Height/Blocks); Palette and the block-index array
//     move again, into a "Blocks" compound, and the array itself is
//     renamed "Data" (v1/v2 call it "BlockData").
//   - Palette (all versions): NBT Compound mapping a blockstate string
//     ("minecraft:oak_stairs[facing=north]") to its integer index.
//   - The index array is `Width * Height * Length` Minecraft-protocol
//     VarInts (reusing VarInt.swift, already used for SLP), one per
//     block, ordered `index = x + z*Width + y*Width*Length` — i.e. X
//     innermost, then Z, then Y outermost.
//

import Foundation

enum SpongeSchematicError: Error, Equatable, LocalizedError {
    case notACompound
    case missingDimensions
    case missingPalette
    case missingBlockData
    case invalidPaletteIndex(Int)
    case corruptBlockData

    var errorDescription: String? {
        switch self {
        case .notACompound: return "This doesn't look like a valid NBT schematic file."
        case .missingDimensions: return "Missing Width/Height/Length — this may not be a Sponge Schematic file."
        case .missingPalette: return "Missing the block Palette — this may not be a Sponge Schematic file."
        case .missingBlockData: return "Missing block data — this may not be a Sponge Schematic file."
        case .invalidPaletteIndex(let index): return "Block data references palette index \(index), which isn't in the palette. The file may be corrupt."
        case .corruptBlockData: return "Block data is corrupt or truncated."
        }
    }
}

enum SpongeSchematicParser {
    static func parse(data: Data) throws -> ParsedSchematic {
        let (_, root) = try NBTParser.parse(data: data)
        guard case .compound = root else { throw SpongeSchematicError.notACompound }

        // v3 wraps every field one level deeper, inside a child
        // compound named "Schematic"; v1/v2 don't.
        let schematic = root["Schematic"] ?? root

        guard let width = schematic["Width"]?.asInt,
              let height = schematic["Height"]?.asInt,
              let length = schematic["Length"]?.asInt,
              width > 0, height > 0, length > 0
        else {
            throw SpongeSchematicError.missingDimensions
        }

        // v3 additionally nests Palette + the block-index array under
        // a "Blocks" compound, and calls the array "Data" instead of
        // "BlockData".
        let blockContainer = schematic["Blocks"] ?? schematic
        guard let paletteCompound = blockContainer["Palette"]?.asCompound else {
            throw SpongeSchematicError.missingPalette
        }
        guard let blockDataArray = (blockContainer["BlockData"] ?? blockContainer["Data"])?.asByteArray else {
            throw SpongeSchematicError.missingBlockData
        }

        var indexToBlockState: [Int: String] = [:]
        indexToBlockState.reserveCapacity(paletteCompound.count)
        for (blockState, indexTag) in paletteCompound {
            guard let index = indexTag.asInt else { continue }
            indexToBlockState[index] = blockState
        }

        // Cache each palette entry's parsed (blockID, properties) once
        // rather than re-parsing the blockstate string on every one of
        // the (often many thousands of) repeated block occurrences.
        var parsedPalette: [Int: (blockID: String, properties: [String: String])] = [:]
        parsedPalette.reserveCapacity(indexToBlockState.count)
        for (index, blockState) in indexToBlockState {
            parsedPalette[index] = BlockStateStringParser.parse(blockState)
        }

        let bytes = blockDataArray.map { UInt8(bitPattern: $0) }
        var offset = 0
        var blocks: [SchematicBlock] = []
        blocks.reserveCapacity(width * height * length)

        for y in 0..<height {
            for z in 0..<length {
                for x in 0..<width {
                    guard offset < bytes.count else { throw SpongeSchematicError.corruptBlockData }
                    let paletteIndex: Int
                    do {
                        paletteIndex = Int(try VarInt.decode(bytes, offset: &offset))
                    } catch {
                        throw SpongeSchematicError.corruptBlockData
                    }
                    guard let entry = parsedPalette[paletteIndex] else {
                        throw SpongeSchematicError.invalidPaletteIndex(paletteIndex)
                    }
                    blocks.append(SchematicBlock(x: x, y: y, z: z, blockID: entry.blockID, properties: entry.properties))
                }
            }
        }

        return ParsedSchematic(width: width, height: height, length: length, blocks: blocks)
    }
}
