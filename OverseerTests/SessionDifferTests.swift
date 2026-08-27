//
//  SessionDifferTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("SessionDiffer")
struct SessionDifferTests {

    @Test("New online player with no open session should open one")
    func opensNewSession() {
        let diff = SessionDiffer.diff(activeUsernames: [], onlineNames: ["Alice"])
        #expect(diff.toOpen == ["Alice"])
        #expect(diff.toBumpLastSeen.isEmpty)
        #expect(diff.toClose.isEmpty)
    }

    @Test("Player still online with an open session should just bump lastSeen")
    func bumpsExistingSession() {
        let diff = SessionDiffer.diff(activeUsernames: ["Alice"], onlineNames: ["Alice"])
        #expect(diff.toOpen.isEmpty)
        #expect(diff.toBumpLastSeen == ["Alice"])
        #expect(diff.toClose.isEmpty)
    }

    @Test("Open session for a player no longer online should close")
    func closesMissingSession() {
        let diff = SessionDiffer.diff(activeUsernames: ["Alice"], onlineNames: [])
        #expect(diff.toOpen.isEmpty)
        #expect(diff.toBumpLastSeen.isEmpty)
        #expect(diff.toClose == ["Alice"])
    }

    @Test("Mixed roster: joins, stays, and leaves are classified independently")
    func mixedRoster() {
        let diff = SessionDiffer.diff(
            activeUsernames: ["Alice", "Bob"],
            onlineNames: ["Bob", "Steve"]
        )
        #expect(diff.toOpen == ["Steve"])
        #expect(diff.toBumpLastSeen == ["Bob"])
        #expect(diff.toClose == ["Alice"])
    }

    @Test("Empty everything is a no-op")
    func emptyIsNoOp() {
        let diff = SessionDiffer.diff(activeUsernames: [], onlineNames: [])
        #expect(diff == SessionDiff(toOpen: [], toBumpLastSeen: [], toClose: []))
    }
}
