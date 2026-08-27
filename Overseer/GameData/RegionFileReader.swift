//
//  RegionFileReader.swift
//  Overseer
//
//  Reads Minecraft's Anvil region file format (.mca) — verified against
//  minecraft.wiki/w/Region_file_format: an 8KB header (a 1024-entry
//  chunk-location table: 3-byte sector offset + 1-byte sector count,
//  big-endian, index = localX + localZ*32; then a 1024-entry timestamp
//  table this app doesn't use), followed by chunk payloads: a 4-byte
//  big-endian length, a 1-byte compression type, then that many bytes
//  of compressed NBT. Read-only — the app never writes to a region
//  file, it only mirrors a copy over SFTP (see SFTPSyncCoordinator).
//

import Foundation
import Compression

enum RegionFileError: Error, Equatable {
    case truncated
    case unsupportedCompression(UInt8)
    case decompressionFailed
}

enum RegionFileReader {
    struct ChunkEntry {
        var localX: Int
        var localZ: Int
        var nbt: Data
    }

    /// Every generated chunk's raw (already-decompressed) NBT bytes —
    /// pass each through `NBTParser.parse(data:)` for the tag tree.
    /// Chunks that were never generated (zero offset/size in the
    /// location table) or that fail to decompress are silently skipped
    /// rather than failing the whole region — a partially-explored
    /// region is the normal case, not an error.
    static func readChunks(from data: Data) throws -> [ChunkEntry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 8192 else { throw RegionFileError.truncated }

        var results: [ChunkEntry] = []
        for localZ in 0..<32 {
            for localX in 0..<32 {
                let entryOffset = (localX + localZ * 32) * 4
                let sectorOffset = (Int(bytes[entryOffset]) << 16) | (Int(bytes[entryOffset + 1]) << 8) | Int(bytes[entryOffset + 2])
                let sectorCount = Int(bytes[entryOffset + 3])
                guard sectorOffset > 0, sectorCount > 0 else { continue } // not generated

                let byteOffset = sectorOffset * 4096
                guard byteOffset + 5 <= bytes.count else { continue }
                let length = (Int(bytes[byteOffset]) << 24) | (Int(bytes[byteOffset + 1]) << 16)
                    | (Int(bytes[byteOffset + 2]) << 8) | Int(bytes[byteOffset + 3])
                guard length > 0, byteOffset + 4 + length <= bytes.count else { continue }
                let compressionType = bytes[byteOffset + 4]
                let payload = Array(bytes[(byteOffset + 5)..<(byteOffset + 4 + length)])

                guard let nbtData = try? decompress(payload, type: compressionType) else { continue }
                results.append(ChunkEntry(localX: localX, localZ: localZ, nbt: nbtData))
            }
        }
        return results
    }

    /// Parses "r.<x>.<z>.mca" into region coordinates, nil for anything
    /// else in the folder (there shouldn't be anything else, but SFTP
    /// listings are never assumed clean).
    static func regionCoordinates(fromFilename filename: String) -> (x: Int, z: Int)? {
        let parts = filename.split(separator: ".")
        guard parts.count == 4, parts[0] == "r", parts[3] == "mca",
              let x = Int(parts[1]), let z = Int(parts[2])
        else { return nil }
        return (x, z)
    }

    private static func decompress(_ payload: [UInt8], type: UInt8) throws -> Data {
        switch type {
        case 1: return try Gzip.decompress(Data(payload)) // rare in practice, but valid
        case 2: return try inflateZlib(payload) // standard compression type
        case 3: return Data(payload) // uncompressed
        case 4: return try inflateLZ4BlockStream(payload) // added in 24w04a, opt-in via server.properties
        default: throw RegionFileError.unsupportedCompression(type)
        }
    }

    /// Compression type 4 (added 24w04a) is NOT the standard LZ4 frame
    /// format — it's lz4-java's `LZ4BlockOutputStream` "block stream"
    /// format: an 8-byte "LZ4Block" magic, then a block header of
    /// [1-byte token][4-byte compressed length, LE][4-byte decompressed
    /// length, LE][4-byte XXHash32 checksum, LE], then that many bytes
    /// of payload if it's a data block (token's top nibble 0x10 =
    /// stored/uncompressed, 0x20 = raw/frameless LZ4), or nothing if
    /// it's a terminator (compressed/decompressed length both zero).
    ///
    /// The part not documented anywhere I could find (minecraft.wiki
    /// only names "LZ4" with no byte layout, and lz4-java's own spec
    /// describes a single continuous stream): on disk, each block —
    /// including the terminator — is its OWN independent
    /// magic-prefixed unit, not one continuous stream with one magic
    /// up front. A one-data-block chunk is therefore laid out as
    /// `[magic][data block][magic][terminator]`, not `[magic][data
    /// block][terminator]`. Verified byte offset-by-offset against a
    /// real compressionType=4 chunk before writing this — an assumed
    /// single-magic-stream implementation silently produced zero
    /// chunks for every LZ4-compressed region file.
    private static func inflateLZ4BlockStream(_ bytes: [UInt8]) throws -> Data {
        let magic: [UInt8] = Array("LZ4Block".utf8)
        var offset = 0
        var output: [UInt8] = []

        while offset < bytes.count {
            guard offset + 8 <= bytes.count, Array(bytes[offset..<(offset + 8)]) == magic else { break }
            offset += 8
            guard offset + 13 <= bytes.count else { throw RegionFileError.truncated }

            let token = bytes[offset]
            let compressedLength = Int(readUInt32LE(bytes, offset + 1))
            let decompressedLength = Int(readUInt32LE(bytes, offset + 5))
            offset += 13

            guard compressedLength > 0 || decompressedLength > 0 else { continue } // this unit was just a terminator

            guard offset + compressedLength <= bytes.count else { throw RegionFileError.truncated }
            let blockPayload = Array(bytes[offset..<(offset + compressedLength)])
            offset += compressedLength

            switch token & 0xF0 {
            case 0x10: // stored, no compression
                output.append(contentsOf: blockPayload)
            case 0x20: // raw (frameless) LZ4 block, decompressed size already known
                var decoded = [UInt8](repeating: 0, count: decompressedLength)
                let decodedCount = decoded.withUnsafeMutableBufferPointer { dst -> Int in
                    blockPayload.withUnsafeBufferPointer { src -> Int in
                        guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                        return compression_decode_buffer(dstBase, dst.count, srcBase, src.count, nil, COMPRESSION_LZ4_RAW)
                    }
                }
                guard decodedCount == decompressedLength else { throw RegionFileError.decompressionFailed }
                output.append(contentsOf: decoded)
            default:
                throw RegionFileError.decompressionFailed
            }
        }
        return Data(output)
    }

    private static func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { acc, i in acc | (UInt32(bytes[offset + i]) << (8 * i)) }
    }

    /// Strips the 2-byte zlib (RFC 1950) header and 4-byte Adler32
    /// trailer, inflating the raw DEFLATE payload between them — same
    /// `compression_decode_buffer`/COMPRESSION_ZLIB primitive Gzip.swift
    /// and ZipReader use (Apple's Compression framework names raw
    /// DEFLATE "ZLIB" regardless of the actual container). Unlike
    /// Gzip's trailer-encoded exact output size, chunk NBT has no
    /// declared decompressed size, so the output buffer grows until the
    /// decode clearly fits inside it rather than filling it exactly.
    private static func inflateZlib(_ bytes: [UInt8]) throws -> Data {
        guard bytes.count > 6 else { throw RegionFileError.truncated }
        let deflateBytes = Array(bytes[2..<(bytes.count - 4)])

        var capacity = max(deflateBytes.count * 8, 8192)
        let maxCapacity = 8 * 1024 * 1024 // a single chunk is well under this
        while capacity <= maxCapacity {
            var output = [UInt8](repeating: 0, count: capacity)
            let decodedCount = output.withUnsafeMutableBufferPointer { dst -> Int in
                deflateBytes.withUnsafeBufferPointer { src -> Int in
                    guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                    return compression_decode_buffer(dstBase, dst.count, srcBase, src.count, nil, COMPRESSION_ZLIB)
                }
            }
            if decodedCount > 0 && decodedCount < capacity {
                return Data(output[0..<decodedCount])
            }
            capacity *= 2
        }
        throw RegionFileError.decompressionFailed
    }
}
