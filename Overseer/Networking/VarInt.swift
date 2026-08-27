//
//  VarInt.swift
//  Overseer
//
//  Minecraft's modern protocol (Server List Ping / SLP) frames every
//  packet and string with a VarInt length prefix, LEB128-encoded with
//  the MSB as a continuation flag, 7 bits of payload per byte, max 5
//  bytes for a 32-bit value. Pure and dependency-free so it is directly
//  unit-testable without a live socket.
//

import Foundation

enum VarIntError: Error, Equatable {
    case tooLong
    case truncated
}

enum VarInt {
    /// Encodes `value` into Minecraft's VarInt wire format.
    static func encode(_ value: Int32) -> [UInt8] {
        var v = UInt32(bitPattern: value)
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while v != 0
        return bytes
    }

    /// Decodes a VarInt starting at `offset` in `bytes`, advancing
    /// `offset` past the bytes consumed. Throws `.truncated` if the
    /// buffer ends mid-value, `.tooLong` if it exceeds 5 bytes
    /// (32-bit VarInts never need more).
    static func decode(_ bytes: [UInt8], offset: inout Int) throws -> Int32 {
        var result: Int32 = 0
        var shift: Int32 = 0
        var bytesRead = 0
        while true {
            guard offset < bytes.count else { throw VarIntError.truncated }
            let byte = bytes[offset]
            offset += 1
            bytesRead += 1
            result |= Int32(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            if bytesRead >= 5 { throw VarIntError.tooLong }
        }
        return result
    }

    /// Encodes a UTF-8 string as Minecraft's String type: VarInt byte
    /// length followed by raw UTF-8 bytes (no null terminator).
    static func encodeString(_ string: String) -> [UInt8] {
        let utf8 = Array(string.utf8)
        return encode(Int32(utf8.count)) + utf8
    }

    /// Decodes a Minecraft String starting at `offset`, advancing it
    /// past the bytes consumed.
    static func decodeString(_ bytes: [UInt8], offset: inout Int) throws -> String {
        let length = try decode(bytes, offset: &offset)
        guard length >= 0 else { throw VarIntError.truncated }
        let end = offset + Int(length)
        guard end <= bytes.count else { throw VarIntError.truncated }
        let slice = bytes[offset..<end]
        offset = end
        return String(decoding: slice, as: UTF8.self)
    }
}
