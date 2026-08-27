//
//  PlayerDataFolderScannerTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("PlayerDataFolderScanner")
struct PlayerDataFolderScannerTests {

    @Test("Only .dat files are treated as player data")
    func filtersByExtension() {
        #expect(PlayerDataFolderScanner.isPlayerDataFile(URL(fileURLWithPath: "/x/069a79f4-44e9-4726-a5be-fca90e38aaf5.dat")))
        #expect(!PlayerDataFolderScanner.isPlayerDataFile(URL(fileURLWithPath: "/x/069a79f4-44e9-4726-a5be-fca90e38aaf5.dat_old")))
        #expect(!PlayerDataFolderScanner.isPlayerDataFile(URL(fileURLWithPath: "/x/.DS_Store")))
    }

    @Test("Valid entries parse into players; malformed entries fall into failures without stopping the batch")
    func partitionsSuccessesAndFailures() {
        let goodRoot: NBTTag = .compound(["Health": .float(20)])
        let goodData = minimalDocument(root: goodRoot)
        let entries = [
            PlayerDataScanEntry(uuid: "good-1", data: goodData, fileURL: URL(fileURLWithPath: "/x/good-1.dat"), modifiedAt: nil),
            PlayerDataScanEntry(uuid: "bad-1", data: Data([0x00, 0x01]), fileURL: URL(fileURLWithPath: "/x/bad-1.dat"), modifiedAt: nil)
        ]
        let result = PlayerDataFolderScanner.scan(entries: entries)
        #expect(result.players.count == 1)
        #expect(result.players[0].uuid == "good-1")
        #expect(result.failures.count == 1)
        #expect(result.failures[0].uuid == "bad-1")
    }

    @Test("Empty entry list scans to empty results, not an error")
    func emptyEntriesScanCleanly() {
        let result = PlayerDataFolderScanner.scan(entries: [])
        #expect(result.players.isEmpty)
        #expect(result.failures.isEmpty)
    }

    // Minimal standalone NBT encoder — just enough for a one-field root
    // compound, since these tests only need "parses" vs. "fails to parse".
    private func minimalDocument(root: NBTTag) -> Data {
        func int16Bytes(_ v: Int16) -> [UInt8] { let u = UInt16(bitPattern: v); return [UInt8(u >> 8), UInt8(u & 0xFF)] }
        func int32Bytes(_ v: Int32) -> [UInt8] {
            let u = UInt32(bitPattern: v)
            return [UInt8(u >> 24), UInt8((u >> 16) & 0xFF), UInt8((u >> 8) & 0xFF), UInt8(u & 0xFF)]
        }
        func encodeString(_ s: String) -> [UInt8] { let utf8 = Array(s.utf8); return int16Bytes(Int16(utf8.count)) + utf8 }
        guard case .compound(let dict) = root else { fatalError("root must be compound") }
        var bytes: [UInt8] = [10] // TAG_Compound
        bytes += encodeString("")
        for (key, value) in dict {
            if case .float(let v) = value {
                bytes.append(5) // TAG_Float
                bytes += encodeString(key)
                bytes += int32Bytes(Int32(bitPattern: v.bitPattern))
            }
        }
        bytes.append(0) // TAG_End
        return Data(bytes)
    }
}
