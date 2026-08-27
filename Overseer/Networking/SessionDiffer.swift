//
//  SessionDiffer.swift
//  Overseer
//
//  Pure set-diff between "who has an open session" and "who the latest
//  poll says is online". Factored out of PollingCoordinator so the
//  session-boundary rule itself — the trickiest part of the persistence
//  pipeline — is unit-testable without a ModelContext.
//

import Foundation

struct SessionDiff: Equatable {
    /// Online now, no open session -> start a new PlayerSession.
    var toOpen: Set<String>
    /// Online now, already has an open session -> bump Player.lastSeen.
    var toBumpLastSeen: Set<String>
    /// Has an open session, absent from this poll -> close it.
    var toClose: Set<String>
}

enum SessionDiffer {
    static func diff(activeUsernames: Set<String>, onlineNames: Set<String>) -> SessionDiff {
        SessionDiff(
            toOpen: onlineNames.subtracting(activeUsernames),
            toBumpLastSeen: activeUsernames.intersection(onlineNames),
            toClose: activeUsernames.subtracting(onlineNames)
        )
    }
}
