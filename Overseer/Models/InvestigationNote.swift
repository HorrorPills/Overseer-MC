//
//  InvestigationNote.swift
//  Overseer
//
//  A timestamped evidence entry, distinct from `Player.notes` (a single
//  freeform pinned summary that just holds whatever it was last edited
//  to). This is an append-only log — "what was found, and when" —
//  populated either manually from a player's detail page, or
//  automatically ("Add to Investigation") from the Suspicious Inventory
//  flag or a Performance report diff.
//
//  `username` is optional: a perf-report diff finding (a chunk's
//  block-entity count dropped) isn't attributable to one player, so it
//  gets logged as a general note (nil username) rather than forced onto
//  someone's page.
//

import Foundation
import SwiftData

@Model
final class InvestigationNote {
    var timestamp: Date
    var username: String?
    var text: String
    /// "manual", "inventory", or "perf-diff" — which tool produced this
    /// entry, for a small icon in the timeline. Not branched on for
    /// any logic beyond display.
    var source: String

    init(username: String? = nil, text: String, source: String = "manual", timestamp: Date = .now) {
        self.username = username
        self.text = text
        self.source = source
        self.timestamp = timestamp
    }
}
