//
//  BlockStateRotator.swift
//  Overseer
//
//  Rotates the block-state properties that encode a horizontal
//  direction, so a rotated schematic's stairs/logs/signs actually face
//  the right way instead of just moving to the right position.
//
//  Deliberately scoped to `facing`, `axis`, and `rotation` — the three
//  well-defined, unambiguous direction properties. Block-specific
//  shape/connection properties (rail `shape`, redstone wire's
//  north/south/east/west booleans, fence/wall connections, stairs'
//  inner/outer `shape`) are *not* rotated: stairs' `shape` is already
//  relative to their own `facing` so it doesn't need to change, but
//  rail shapes and wire connections genuinely do and aren't handled —
//  a real gap for schematics containing rotated rail/redstone, called
//  out here rather than silently guessed at.
//

import Foundation

enum BlockStateRotator {
    private static let facingCycle = ["north", "east", "south", "west"]

    /// Looks up each property's exact current value in a parsed
    /// dictionary and computes its replacement directly — never does
    /// sequential string substitution on raw blockstate text, which is
    /// the classic source of collision bugs (e.g. rewriting
    /// "north"->"east" and then a later rule matching that same now-
    /// "east" text and rewriting it again).
    static func rotate(properties: [String: String], rotation: Rotation) -> [String: String] {
        guard rotation != .none else { return properties }
        var result = properties

        if let facing = properties["facing"], let index = facingCycle.firstIndex(of: facing) {
            let steps = rotation.rawValue / 90
            result["facing"] = facingCycle[(index + steps) % facingCycle.count]
        }
        // facing values outside the cardinal cycle (up/down, on
        // droppers/observers/etc.) aren't in facingCycle, so the lookup
        // above simply leaves them untouched — correct, since a Y-axis
        // rotation never changes "up" or "down".

        if let axis = properties["axis"] {
            switch rotation {
            case .clockwise90, .clockwise270:
                if axis == "x" { result["axis"] = "z" }
                else if axis == "z" { result["axis"] = "x" }
            // "y" is left as-is at every rotation; horizontal axis
            // blocks (x/z) are direction-agnostic under a 180°
            // rotation, so nothing changes there either.
            case .none, .clockwise180:
                break
            }
        }

        if let rotationValue = properties["rotation"], let numeric = Int(rotationValue) {
            let steps = (rotation.rawValue / 90) * 4 // each 90° step is 4 of the 16-step dial
            result["rotation"] = String(((numeric + steps) % 16 + 16) % 16)
        }

        return result
    }
}
