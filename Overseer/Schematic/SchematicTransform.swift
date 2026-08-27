//
//  SchematicTransform.swift
//  Overseer
//
//  Coordinate math for placing a parsed schematic in the world: Y-axis
//  rotation of each block's relative position, followed by an anchor
//  offset onto the target world coordinates. Pure and dependency-free.
//

import Foundation

enum Rotation: Int, CaseIterable, Identifiable {
    case none = 0
    case clockwise90 = 90
    case clockwise180 = 180
    case clockwise270 = 270

    var id: Int { rawValue }
    var displayName: String { "\(rawValue)°" }
}

enum AnchorPoint: String, CaseIterable, Identifiable {
    case corner = "Corner (Min X, Y, Z)"
    case centerBottom = "Center-Bottom"

    var id: String { rawValue }
}

struct WorldPosition: Equatable, Hashable {
    var x: Int
    var y: Int
    var z: Int
}

enum SchematicTransform {
    struct Footprint: Equatable {
        var width: Int
        var length: Int
    }

    /// A 90°/270° rotation swaps which axis is "wide" — a 3-long,
    /// 5-wide structure rotated 90° occupies a 5-long, 3-wide footprint.
    static func rotatedFootprint(width: Int, length: Int, rotation: Rotation) -> Footprint {
        switch rotation {
        case .none, .clockwise180: return Footprint(width: width, length: length)
        case .clockwise90, .clockwise270: return Footprint(width: length, length: width)
        }
    }

    /// Rotates a relative (x,z) position within its own `width x
    /// length` footprint about the Y axis, returning the new relative
    /// position within the *rotated* footprint — still zero-based and
    /// non-negative, i.e. re-anchored to the rotated bounding box's own
    /// min corner (the standard convention: rotate, then re-place at
    /// the origin, rather than rotating about a fixed pivot that would
    /// let coordinates go negative).
    static func rotateRelative(x: Int, z: Int, width: Int, length: Int, rotation: Rotation) -> (x: Int, z: Int) {
        switch rotation {
        case .none: return (x, z)
        case .clockwise90: return (length - 1 - z, x)
        case .clockwise180: return (width - 1 - x, length - 1 - z)
        case .clockwise270: return (z, width - 1 - x)
        }
    }

    /// Full placement transform for one block: rotate its relative
    /// position, then anchor it onto `target`.
    ///  - `.corner`: the rotated bounding box's (0,0,0) lands exactly
    ///    on `target`.
    ///  - `.centerBottom`: X/Z are centered on `target`; Y still
    ///    anchors at the bottom (`target.y` = the schematic's y=0
    ///    layer), matching how most in-game structure placement tools
    ///    present "center" (you rarely want to center vertically too).
    static func worldPosition(
        relativeX: Int,
        relativeY: Int,
        relativeZ: Int,
        schematicWidth: Int,
        schematicLength: Int,
        rotation: Rotation,
        anchor: AnchorPoint,
        target: WorldPosition
    ) -> WorldPosition {
        let (rx, rz) = rotateRelative(x: relativeX, z: relativeZ, width: schematicWidth, length: schematicLength, rotation: rotation)
        switch anchor {
        case .corner:
            return WorldPosition(x: target.x + rx, y: target.y + relativeY, z: target.z + rz)
        case .centerBottom:
            let footprint = rotatedFootprint(width: schematicWidth, length: schematicLength, rotation: rotation)
            return WorldPosition(
                x: target.x + rx - footprint.width / 2,
                y: target.y + relativeY,
                z: target.z + rz - footprint.length / 2
            )
        }
    }
}
