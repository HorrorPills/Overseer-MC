//
//  NBTParser.swift
//  Overseer
//
//  Byte-level decoder for Minecraft's NBT format — big-endian
//  throughout (unlike RCON, which is little-endian; see RCONClient.swift's
//  note on the same distinction for GS4/SLP). Transparently gunzips
//  first if the input looks gzip-compressed (see Gzip.swift), since
//  every .schem file on disk is.
//
//  Pure and dependency-free (beyond Gzip) so it's directly unit-testable
//  against synthetic byte buffers, same as RCONPacketDecoder/GS4Protocol.
//
//  Tag type IDs (fixed by the NBT spec):
//    0 End, 1 Byte, 2 Short, 3 Int, 4 Long, 5 Float, 6 Double,
//    7 Byte_Array, 8 String, 9 List, 10 Compound, 11 Int_Array, 12 Long_Array
//

import Foundation

enum NBTParserError: Error, Equatable {
    case truncated
    case invalidRootTag
    case unsupportedTagType(UInt8)
}

enum NBTParser {
    /// Parses a complete NBT document: a single root TAG_Compound
    /// (its name is usually empty and is discarded by every caller in
    /// this app, but returned for completeness/debugging).
    static func parse(data: Data) throws -> (name: String, tag: NBTTag) {
        let raw = Gzip.isGzipped(data) ? try Gzip.decompress(data) : data
        var reader = Reader(bytes: [UInt8](raw))
        let typeID = try reader.readUInt8()
        guard typeID == 10 else { throw NBTParserError.invalidRootTag } // must start with TAG_Compound
        let name = try reader.readString()
        let tag = try readCompoundBody(&reader)
        return (name, tag)
    }

    private static func readTagBody(type: UInt8, _ reader: inout Reader) throws -> NBTTag {
        switch type {
        case 1: return .byte(Int8(bitPattern: try reader.readUInt8()))
        case 2: return .short(try reader.readInt16())
        case 3: return .int(try reader.readInt32())
        case 4: return .long(try reader.readInt64())
        case 5: return .float(try reader.readFloat())
        case 6: return .double(try reader.readDouble())
        case 7:
            let count = try reader.readInt32()
            guard count >= 0 else { throw NBTParserError.truncated }
            var array: [Int8] = []
            array.reserveCapacity(Int(count))
            for _ in 0..<count { array.append(Int8(bitPattern: try reader.readUInt8())) }
            return .byteArray(array)
        case 8:
            return .string(try reader.readString())
        case 9:
            let elementType = try reader.readUInt8()
            let count = try reader.readInt32()
            guard count >= 0 else { throw NBTParserError.truncated }
            var items: [NBTTag] = []
            items.reserveCapacity(Int(count))
            for _ in 0..<count {
                items.append(try readTagBody(type: elementType, &reader))
            }
            return .list(items)
        case 10:
            return try readCompoundBody(&reader)
        case 11:
            let count = try reader.readInt32()
            guard count >= 0 else { throw NBTParserError.truncated }
            var array: [Int32] = []
            array.reserveCapacity(Int(count))
            for _ in 0..<count { array.append(try reader.readInt32()) }
            return .intArray(array)
        case 12:
            let count = try reader.readInt32()
            guard count >= 0 else { throw NBTParserError.truncated }
            var array: [Int64] = []
            array.reserveCapacity(Int(count))
            for _ in 0..<count { array.append(try reader.readInt64()) }
            return .longArray(array)
        default:
            throw NBTParserError.unsupportedTagType(type)
        }
    }

    private static func readCompoundBody(_ reader: inout Reader) throws -> NBTTag {
        var dict: [String: NBTTag] = [:]
        while true {
            let type = try reader.readUInt8()
            if type == 0 { break } // TAG_End closes the compound
            let name = try reader.readString()
            dict[name] = try readTagBody(type: type, &reader)
        }
        return .compound(dict)
    }

    /// Sequential big-endian byte reader, cursor-based. Private to this
    /// file — `NBTTag`/`NBTParser.parse` are the only public surface.
    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func readUInt8() throws -> UInt8 {
            guard offset < bytes.count else { throw NBTParserError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func readInt16() throws -> Int16 {
            let hi = try readUInt8(); let lo = try readUInt8()
            return Int16(bitPattern: (UInt16(hi) << 8) | UInt16(lo))
        }

        mutating func readInt32() throws -> Int32 {
            var result: UInt32 = 0
            for _ in 0..<4 { result = (result << 8) | UInt32(try readUInt8()) }
            return Int32(bitPattern: result)
        }

        mutating func readInt64() throws -> Int64 {
            var result: UInt64 = 0
            for _ in 0..<8 { result = (result << 8) | UInt64(try readUInt8()) }
            return Int64(bitPattern: result)
        }

        mutating func readFloat() throws -> Float {
            Float(bitPattern: UInt32(bitPattern: try readInt32()))
        }

        mutating func readDouble() throws -> Double {
            Double(bitPattern: UInt64(bitPattern: try readInt64()))
        }

        mutating func readString() throws -> String {
            let length = try readInt16()
            guard length >= 0 else { throw NBTParserError.truncated }
            let end = offset + Int(length)
            guard end <= bytes.count else { throw NBTParserError.truncated }
            let slice = bytes[offset..<end]
            offset = end
            return String(decoding: slice, as: UTF8.self)
        }
    }
}
