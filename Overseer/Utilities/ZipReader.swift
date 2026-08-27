//
//  ZipReader.swift
//  Overseer
//
//  Minimal ZIP (PKWARE APPNOTE) central-directory reader — SFTP-synced
//  perf reports (debug/profiling/*.zip) and the full-history log
//  backfill (logs.zip) both arrive as ZIP archives, unlike the
//  gzip-only files Gzip.swift handles. Only reading is needed (the app
//  never writes archives); only STORED (method 0) and DEFLATE (method 8)
//  entries are supported — the two methods every common zipper
//  (Java's, macOS's `zip`/Archive Utility) actually produces.
//
//  Reads the End Of Central Directory record backwards from the end of
//  the file, then walks the central directory forward from there,
//  rather than scanning local file headers sequentially — the correct,
//  robust way to parse ZIP (central directory is authoritative; local
//  headers can lie about sizes when a data descriptor is used).
//

import Foundation
import Compression

enum ZipReaderError: Error, Equatable {
    case notAZipFile
    case truncated
    case unsupportedCompressionMethod(UInt16)
    case decompressionFailed
}

enum ZipReader {
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    private static let centralDirectoryHeaderSignature: UInt32 = 0x0201_4b50

    /// Every entry's path (using `/` separators, matching how the rest
    /// of the app already addresses perf-report files, e.g.
    /// "server/profiling.txt") mapped to its decompressed bytes.
    /// Directory entries (path ending in `/`) are skipped.
    static func extractAll(from data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipReaderError.notAZipFile }

        guard let eocdOffset = findEndOfCentralDirectory(in: bytes) else {
            throw ZipReaderError.notAZipFile
        }

        // End Of Central Directory record layout (fixed 22-byte prefix):
        // sig(4) diskNo(2) cdDisk(2) diskEntries(2) totalEntries(2)
        // cdSize(4) cdOffset(4) commentLen(2)
        guard eocdOffset + 22 <= bytes.count else { throw ZipReaderError.truncated }
        let totalEntries = readUInt16(bytes, at: eocdOffset + 10)
        let centralDirectoryOffset = Int(readUInt32(bytes, at: eocdOffset + 16))

        var result: [String: Data] = [:]
        var cursor = centralDirectoryOffset

        for _ in 0..<totalEntries {
            guard cursor + 46 <= bytes.count, readUInt32(bytes, at: cursor) == centralDirectoryHeaderSignature else {
                throw ZipReaderError.truncated
            }
            // Central directory header (fixed 46-byte prefix), fields we need:
            let compressionMethod = readUInt16(bytes, at: cursor + 10)
            let compressedSize = Int(readUInt32(bytes, at: cursor + 20))
            let uncompressedSize = Int(readUInt32(bytes, at: cursor + 24))
            let filenameLength = Int(readUInt16(bytes, at: cursor + 28))
            let extraLength = Int(readUInt16(bytes, at: cursor + 30))
            let commentLength = Int(readUInt16(bytes, at: cursor + 32))
            let localHeaderOffset = Int(readUInt32(bytes, at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + filenameLength <= bytes.count else { throw ZipReaderError.truncated }
            let filename = String(decoding: bytes[nameStart..<(nameStart + filenameLength)], as: UTF8.self)

            cursor = nameStart + filenameLength + extraLength + commentLength

            guard !filename.hasSuffix("/"), uncompressedSize > 0 else { continue } // directory entry

            let entryData = try readEntry(
                bytes,
                localHeaderOffset: localHeaderOffset,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize
            )
            result[filename] = entryData
        }

        return result
    }

    private static func readEntry(
        _ bytes: [UInt8],
        localHeaderOffset: Int,
        compressionMethod: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws -> Data {
        // Local file header (fixed 30-byte prefix) precedes the actual
        // data; its filename/extra lengths can differ in padding from
        // the central directory's, so they're read fresh here rather
        // than assumed equal.
        guard localHeaderOffset + 30 <= bytes.count else { throw ZipReaderError.truncated }
        let localFilenameLength = Int(readUInt16(bytes, at: localHeaderOffset + 26))
        let localExtraLength = Int(readUInt16(bytes, at: localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + localFilenameLength + localExtraLength
        guard dataStart + compressedSize <= bytes.count else { throw ZipReaderError.truncated }
        let compressedBytes = Array(bytes[dataStart..<(dataStart + compressedSize)])

        switch compressionMethod {
        case 0: // stored, no compression
            return Data(compressedBytes)
        case 8: // deflate
            return try inflate(compressedBytes, uncompressedSize: uncompressedSize)
        default:
            throw ZipReaderError.unsupportedCompressionMethod(compressionMethod)
        }
    }

    /// Raw DEFLATE (no zlib/gzip container, unlike Gzip.swift's input) —
    /// the same `compression_decode_buffer`/`COMPRESSION_ZLIB` primitive
    /// Gzip.swift uses, since Apple's Compression framework names raw
    /// DEFLATE "ZLIB" confusingly regardless of container.
    private static func inflate(_ compressedBytes: [UInt8], uncompressedSize: Int) throws -> Data {
        var output = [UInt8](repeating: 0, count: max(uncompressedSize, 1))
        let decodedCount = output.withUnsafeMutableBufferPointer { dst -> Int in
            compressedBytes.withUnsafeBufferPointer { src -> Int in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, dst.count, srcBase, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard decodedCount == uncompressedSize else { throw ZipReaderError.decompressionFailed }
        return Data(output)
    }

    /// Scans backwards from the end of the file for the EOCD signature
    /// — correct even when the archive carries a trailing comment
    /// (the fixed-size fields alone can't be trusted to locate it).
    private static func findEndOfCentralDirectory(in bytes: [UInt8]) -> Int? {
        let minOffset = max(0, bytes.count - 22 - 65536) // comment is at most 64KB
        var offset = bytes.count - 22
        while offset >= minOffset {
            if readUInt32(bytes, at: offset) == endOfCentralDirectorySignature {
                return offset
            }
            offset -= 1
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { acc, i in acc | (UInt32(bytes[offset + i]) << (8 * i)) }
    }
}
