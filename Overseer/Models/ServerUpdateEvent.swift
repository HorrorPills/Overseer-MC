//
//  ServerUpdateEvent.swift
//  Overseer
//
//  Persisted audit trail for AutoUpdaterCoordinator's deploy attempts —
//  before this model existed, a deploy's only record was the in-memory
//  `updateLog` on AutoUpdaterCoordinator itself, which evaporated on
//  every relaunch. A feature that unattended-replaces server.jar and
//  stops the live server needs a durable "what happened and when," the
//  same way ModerationEvent/ConfigChangeEvent already give one to every
//  other kind of consequential automated action in this app.
//

import Foundation
import SwiftData

@Model
final class ServerUpdateEvent {
    var timestamp: Date
    var fromVersion: String
    var toVersion: String
    var succeeded: Bool

    /// Empty on success. On failure, the reason the deploy stopped
    /// (size mismatch, SFTP error, etc.) — see AutoUpdaterCoordinator.deploy.
    var detail: String

    init(timestamp: Date = .now, fromVersion: String, toVersion: String, succeeded: Bool, detail: String = "") {
        self.timestamp = timestamp
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.succeeded = succeeded
        self.detail = detail
    }
}
