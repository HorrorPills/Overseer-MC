//
//  TempBan.swift
//  Overseer
//
//  Vanilla `/ban` has no expiry — a ban is permanent until `/pardon`.
//  This tracks an admin-intended expiry entirely app-side: on ban, the
//  app records one of these alongside the real `/ban`, and
//  RCONAutomationCoordinator's temp-ban scheduler loop (see
//  TempBanScheduler) issues the real `/pardon` once it lapses.
//
//  If the app isn't running when a temp-ban would have expired, it's
//  simply pardoned late the next time the scheduler loop runs — there's
//  no way around that without server-side support, but it's still
//  strictly better than a permanent ban nobody remembers to lift.
//

import Foundation
import SwiftData

@Model
final class TempBan {
    var username: String
    var reason: String
    var bannedAt: Date
    var expiresAt: Date

    /// True once auto- (or manually-) pardoned, so the scheduler loop
    /// doesn't keep reprocessing it after it's already been lifted.
    var pardoned: Bool

    init(
        username: String,
        reason: String = "",
        bannedAt: Date = .now,
        expiresAt: Date,
        pardoned: Bool = false
    ) {
        self.username = username
        self.reason = reason
        self.bannedAt = bannedAt
        self.expiresAt = expiresAt
        self.pardoned = pardoned
    }
}
