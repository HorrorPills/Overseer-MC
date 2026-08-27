//
//  ZipReaderTests.swift
//  OverseerTests
//
//  Builds minimal ZIP archives by hand (STORED entries only — no CRC32
//  computed, since ZipReader never validates it) to test central-
//  directory parsing without depending on a fixture file.
//

import Foundation
import Testing
@testable import Overseer

@Suite("ZipReader")
struct ZipReaderTests {

    /// A single-entry, STORED (uncompressed) ZIP archive containing
    /// `filename` -> `contents`.
    private func makeZip(filename: String, contents: String) -> Data {
        var bytes: [UInt8] = []
        let nameBytes = Array(filename.utf8)
        let dataBytes = Array(contents.utf8)

        func appendUInt16(_ value: UInt16) { bytes.append(UInt8(value & 0xff)); bytes.append(UInt8((value >> 8) & 0xff)) }
        func appendUInt32(_ value: UInt32) {
            for i in 0..<4 { bytes.append(UInt8((value >> (8 * i)) & 0xff)) }
        }

        let localHeaderOffset = bytes.count

        // Local file header
        appendUInt32(0x0403_4b50)
        appendUInt16(20)      // version needed
        appendUInt16(0)       // flags
        appendUInt16(0)       // method: stored
        appendUInt16(0); appendUInt16(0) // mod time/date
        appendUInt32(0)       // crc32 (unchecked by ZipReader)
        appendUInt32(UInt32(dataBytes.count)) // compressed size
        appendUInt32(UInt32(dataBytes.count)) // uncompressed size
        appendUInt16(UInt16(nameBytes.count))
        appendUInt16(0)       // extra length
        bytes.append(contentsOf: nameBytes)
        bytes.append(contentsOf: dataBytes)

        let centralDirectoryOffset = bytes.count

        // Central directory header
        appendUInt32(0x0201_4b50)
        appendUInt16(20); appendUInt16(20) // version made by / needed
        appendUInt16(0)       // flags
        appendUInt16(0)       // method: stored
        appendUInt16(0); appendUInt16(0) // mod time/date
        appendUInt32(0)       // crc32
        appendUInt32(UInt32(dataBytes.count)) // compressed size
        appendUInt32(UInt32(dataBytes.count)) // uncompressed size
        appendUInt16(UInt16(nameBytes.count))
        appendUInt16(0)       // extra length
        appendUInt16(0)       // comment length
        appendUInt16(0)       // disk number start
        appendUInt16(0)       // internal attributes
        appendUInt32(0)       // external attributes
        appendUInt32(UInt32(localHeaderOffset))
        bytes.append(contentsOf: nameBytes)

        let centralDirectorySize = bytes.count - centralDirectoryOffset

        // End of central directory record
        appendUInt32(0x0605_4b50)
        appendUInt16(0); appendUInt16(0) // disk numbers
        appendUInt16(1); appendUInt16(1) // entries this disk / total
        appendUInt32(UInt32(centralDirectorySize))
        appendUInt32(UInt32(centralDirectoryOffset))
        appendUInt16(0) // comment length

        return Data(bytes)
    }

    @Test("Extracts a single STORED entry's exact contents")
    func extractsStoredEntry() throws {
        let zip = makeZip(filename: "system.txt", contents: "hello perf report")
        let entries = try ZipReader.extractAll(from: zip)
        #expect(entries["system.txt"] == "hello perf report".data(using: .utf8))
    }

    @Test("Rejects data that isn't a ZIP file")
    func rejectsNonZipData() {
        #expect(throws: ZipReaderError.self) {
            try ZipReader.extractAll(from: "not a zip".data(using: .utf8)!)
        }
    }

    @Test("Rejects truncated data too short to hold an EOCD record")
    func rejectsTooShortData() {
        #expect(throws: ZipReaderError.self) {
            try ZipReader.extractAll(from: Data([0x01, 0x02]))
        }
    }
}
