//
//  SchematicTransformTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("SchematicTransform")
struct SchematicTransformTests {

    @Test("rotatedFootprint swaps width/length at 90°/270°, keeps them at 0°/180°")
    func rotatedFootprintSwapsAtQuarterTurns() {
        #expect(SchematicTransform.rotatedFootprint(width: 5, length: 3, rotation: .none) == .init(width: 5, length: 3))
        #expect(SchematicTransform.rotatedFootprint(width: 5, length: 3, rotation: .clockwise180) == .init(width: 5, length: 3))
        #expect(SchematicTransform.rotatedFootprint(width: 5, length: 3, rotation: .clockwise90) == .init(width: 3, length: 5))
        #expect(SchematicTransform.rotatedFootprint(width: 5, length: 3, rotation: .clockwise270) == .init(width: 3, length: 5))
    }

    @Test("rotateRelative is the identity at 0°")
    func rotateRelativeIdentityAtZero() {
        let result = SchematicTransform.rotateRelative(x: 2, z: 1, width: 4, length: 3, rotation: .none)
        #expect(result == (2, 1))
    }

    @Test("rotateRelative maps all four corners correctly at 90°")
    func rotateRelative90DegreeCorners() {
        // 4 (width) x 3 (length) footprint.
        #expect(SchematicTransform.rotateRelative(x: 0, z: 0, width: 4, length: 3, rotation: .clockwise90) == (2, 0))
        #expect(SchematicTransform.rotateRelative(x: 3, z: 0, width: 4, length: 3, rotation: .clockwise90) == (2, 3))
        #expect(SchematicTransform.rotateRelative(x: 0, z: 2, width: 4, length: 3, rotation: .clockwise90) == (0, 0))
        #expect(SchematicTransform.rotateRelative(x: 3, z: 2, width: 4, length: 3, rotation: .clockwise90) == (0, 3))
    }

    @Test("rotateRelative maps the far corner to the origin at 180°")
    func rotateRelative180Degrees() {
        #expect(SchematicTransform.rotateRelative(x: 0, z: 0, width: 4, length: 3, rotation: .clockwise180) == (3, 2))
        #expect(SchematicTransform.rotateRelative(x: 3, z: 2, width: 4, length: 3, rotation: .clockwise180) == (0, 0))
    }

    @Test("rotateRelative at 270° is the inverse of 90°")
    func rotateRelative270IsInverseOf90() {
        // Rotating 90° then 270° (or vice versa) should return to the
        // original relative position, going through the intermediate
        // (swapped) footprint correctly.
        let width = 4, length = 3
        let (rx, rz) = SchematicTransform.rotateRelative(x: 1, z: 2, width: width, length: length, rotation: .clockwise90)
        let footprint = SchematicTransform.rotatedFootprint(width: width, length: length, rotation: .clockwise90)
        let (backX, backZ) = SchematicTransform.rotateRelative(x: rx, z: rz, width: footprint.width, length: footprint.length, rotation: .clockwise270)
        #expect((backX, backZ) == (1, 2))
    }

    @Test("worldPosition with corner anchor places the min corner exactly on target")
    func worldPositionCornerAnchor() {
        let target = WorldPosition(x: 100, y: 64, z: -50)
        let result = SchematicTransform.worldPosition(
            relativeX: 0, relativeY: 0, relativeZ: 0,
            schematicWidth: 5, schematicLength: 5,
            rotation: .none, anchor: .corner, target: target
        )
        #expect(result == target)
    }

    @Test("worldPosition with center-bottom anchor centers X/Z but keeps Y at target")
    func worldPositionCenterBottomAnchor() {
        let target = WorldPosition(x: 100, y: 64, z: 200)
        // 4x4 footprint, corner block (0,0,0) should land offset by -2 in X/Z (width/2).
        let result = SchematicTransform.worldPosition(
            relativeX: 0, relativeY: 0, relativeZ: 0,
            schematicWidth: 4, schematicLength: 4,
            rotation: .none, anchor: .centerBottom, target: target
        )
        #expect(result == WorldPosition(x: 98, y: 64, z: 198))
    }

    @Test("worldPosition applies rotation before the anchor offset")
    func worldPositionAppliesRotationBeforeAnchor() {
        let target = WorldPosition(x: 0, y: 0, z: 0)
        // 2x1 footprint (width=2, length=1); relative (1,0,0) rotated 90°.
        let result = SchematicTransform.worldPosition(
            relativeX: 1, relativeY: 5, relativeZ: 0,
            schematicWidth: 2, schematicLength: 1,
            rotation: .clockwise90, anchor: .corner, target: target
        )
        // rotateRelative(x:1,z:0,width:2,length:1,.cw90) = (length-1-z, x) = (0, 1)
        #expect(result == WorldPosition(x: 0, y: 5, z: 1))
    }
}

@Suite("BlockStateRotator")
struct BlockStateRotatorTests {

    @Test("No rotation leaves properties untouched")
    func noRotationIsIdentity() {
        let props = ["facing": "north", "half": "bottom"]
        #expect(BlockStateRotator.rotate(properties: props, rotation: .none) == props)
    }

    @Test("facing cycles through all four cardinal directions at 90° steps")
    func facingCyclesAtEachStep() {
        #expect(BlockStateRotator.rotate(properties: ["facing": "north"], rotation: .clockwise90)["facing"] == "east")
        #expect(BlockStateRotator.rotate(properties: ["facing": "east"], rotation: .clockwise90)["facing"] == "south")
        #expect(BlockStateRotator.rotate(properties: ["facing": "south"], rotation: .clockwise90)["facing"] == "west")
        #expect(BlockStateRotator.rotate(properties: ["facing": "west"], rotation: .clockwise90)["facing"] == "north")
    }

    @Test("facing rotates correctly at 180° and 270°")
    func facingAtLargerAngles() {
        #expect(BlockStateRotator.rotate(properties: ["facing": "north"], rotation: .clockwise180)["facing"] == "south")
        #expect(BlockStateRotator.rotate(properties: ["facing": "north"], rotation: .clockwise270)["facing"] == "west")
    }

    @Test("facing up/down (droppers, observers) is left untouched by Y-axis rotation")
    func facingUpDownUntouched() {
        #expect(BlockStateRotator.rotate(properties: ["facing": "up"], rotation: .clockwise90)["facing"] == "up")
        #expect(BlockStateRotator.rotate(properties: ["facing": "down"], rotation: .clockwise270)["facing"] == "down")
    }

    @Test("axis swaps x<->z at 90°/270°, is untouched at 180°, y never changes")
    func axisSwapsAtQuarterTurnsOnly() {
        #expect(BlockStateRotator.rotate(properties: ["axis": "x"], rotation: .clockwise90)["axis"] == "z")
        #expect(BlockStateRotator.rotate(properties: ["axis": "z"], rotation: .clockwise90)["axis"] == "x")
        #expect(BlockStateRotator.rotate(properties: ["axis": "x"], rotation: .clockwise270)["axis"] == "z")
        #expect(BlockStateRotator.rotate(properties: ["axis": "x"], rotation: .clockwise180)["axis"] == "x")
        #expect(BlockStateRotator.rotate(properties: ["axis": "z"], rotation: .clockwise180)["axis"] == "z")
        #expect(BlockStateRotator.rotate(properties: ["axis": "y"], rotation: .clockwise90)["axis"] == "y")
        #expect(BlockStateRotator.rotate(properties: ["axis": "y"], rotation: .clockwise180)["axis"] == "y")
    }

    @Test("rotation dial (signs/banners) advances by 4 per 90° step and wraps at 16")
    func rotationDialWrapsAt16() {
        #expect(BlockStateRotator.rotate(properties: ["rotation": "0"], rotation: .clockwise90)["rotation"] == "4")
        #expect(BlockStateRotator.rotate(properties: ["rotation": "0"], rotation: .clockwise180)["rotation"] == "8")
        #expect(BlockStateRotator.rotate(properties: ["rotation": "0"], rotation: .clockwise270)["rotation"] == "12")
        #expect(BlockStateRotator.rotate(properties: ["rotation": "14"], rotation: .clockwise90)["rotation"] == "2") // 14+4=18 mod 16=2
        #expect(BlockStateRotator.rotate(properties: ["rotation": "15"], rotation: .clockwise270)["rotation"] == "11") // 15+12=27 mod 16=11
    }

    @Test("Properties without facing/axis/rotation pass through unchanged")
    func unrelatedPropertiesPassThrough() {
        let props = ["waterlogged": "true", "half": "top"]
        #expect(BlockStateRotator.rotate(properties: props, rotation: .clockwise90) == props)
    }

    @Test("Multiple rotatable properties on the same block all rotate together")
    func multiplePropertiesRotateTogether() {
        let props = ["facing": "north", "half": "bottom", "shape": "straight"]
        let rotated = BlockStateRotator.rotate(properties: props, rotation: .clockwise90)
        #expect(rotated["facing"] == "east")
        #expect(rotated["half"] == "bottom") // untouched, not a direction property
        #expect(rotated["shape"] == "straight") // untouched — documented as out of scope
    }
}
