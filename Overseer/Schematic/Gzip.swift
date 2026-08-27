//
//  Gzip.swift
//  Overseer
//
//  Minimal gzip (RFC 1952) container reader for .schem files, which are
//  always gzip-compressed NBT on disk (Java's GZIPOutputStream). Only
//  decompression is needed — the app never writes schematics.
//
//  Apple's Compression framework is deliberately named confusingly:
//  `COMPRESSION_ZLIB` implements raw DEFLATE (RFC 1951), *not* the zlib
//  container format (RFC 1950) and definitely not gzip (RFC 1952). So
//  the gzip header and 8-byte trailer are stripped by hand here, and
//  only the raw deflate payload in between is handed to
//  `compression_decode_buffer`.
//

import Foundation
import Compression

enum GzipError: Error, Equatable {
    case notGzipped
    case truncatedHeader
    case decompressionFailed
}

enum Gzip {
    static func isGzipped(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    /// Strips the gzip container and inflates the raw DEFLATE payload.
    /// Handles the optional FEXTRA/FNAME/FCOMMENT/FHCRC header fields,
    /// even though real-world schematic files essentially never set
    /// them (Java's GZIPOutputStream writes none by default).
    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b else {
            throw GzipError.notGzipped
        }
        guard bytes[2] == 8 else { throw GzipError.notGzipped } // CM must be DEFLATE

        let flags = bytes[3]
        var offset = 10 // magic(2) + CM(1) + FLG(1) + MTIME(4) + XFL(1) + OS(1)

        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw GzipError.truncatedHeader }
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            offset = try skipNullTerminated(bytes, from: offset)
        }
        if flags & 0x10 != 0 { // FCOMMENT
            offset = try skipNullTerminated(bytes, from: offset)
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        guard offset <= bytes.count - 8 else { throw GzipError.truncatedHeader }

        let deflateBytes = Array(bytes[offset..<(bytes.count - 8)])
        let trailer = Array(bytes.suffix(8))
        // Trailer is [CRC32(4, LE)][ISIZE(4, LE)] — ISIZE is the
        // original size mod 2^32, which is exactly the output buffer
        // size we need to give the decoder.
        let isize = (0..<4).reduce(0) { acc, i in acc | (Int(trailer[4 + i]) << (8 * i)) }

        var output = [UInt8](repeating: 0, count: max(isize, 1))
        let decodedCount = output.withUnsafeMutableBufferPointer { dst -> Int in
            deflateBytes.withUnsafeBufferPointer { src -> Int in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, dst.count, srcBase, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard decodedCount == isize else { throw GzipError.decompressionFailed }
        return Data(output)
    }

    private static func skipNullTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        var i = start
        while i < bytes.count {
            if bytes[i] == 0 { return i + 1 }
            i += 1
        }
        throw GzipError.truncatedHeader
    }
}
