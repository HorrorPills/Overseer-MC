//
//  NBT.swift
//  Overseer
//
//  Minecraft's Named Binary Tag format — the tag tree itself. See
//  NBTParser.swift for the byte-level decoder that produces these.
//

import Foundation

indirect enum NBTTag: Equatable {
    case byte(Int8)
    case short(Int16)
    case int(Int32)
    case long(Int64)
    case float(Float)
    case double(Double)
    case byteArray([Int8])
    case string(String)
    case list([NBTTag])
    case compound([String: NBTTag])
    case intArray([Int32])
    case longArray([Int64])
}

extension NBTTag {
    /// Child lookup by key — nil if this isn't a compound or the key
    /// is absent, rather than trapping, since schematic parsing treats
    /// "missing optional field" as a normal, common case.
    subscript(_ key: String) -> NBTTag? {
        if case .compound(let dict) = self { return dict[key] }
        return nil
    }

    var asString: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Widens any integer tag type to `Int` — schematics mix Short
    /// (Width/Height/Length) and Int (PaletteMax, palette indices)
    /// somewhat inconsistently across format versions, so callers that
    /// just want "the number" don't need to match on the exact tag.
    var asInt: Int? {
        switch self {
        case .byte(let value): return Int(value)
        case .short(let value): return Int(value)
        case .int(let value): return Int(value)
        case .long(let value): return Int(value)
        default: return nil
        }
    }

    var asByteArray: [Int8]? {
        if case .byteArray(let value) = self { return value }
        return nil
    }

    var asCompound: [String: NBTTag]? {
        if case .compound(let value) = self { return value }
        return nil
    }

    var asList: [NBTTag]? {
        if case .list(let value) = self { return value }
        return nil
    }
}
