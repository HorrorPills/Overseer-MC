//
//  ModerationEvent.swift
//  Overseer
//
//  Audit trail for every moderation/admin action the app dispatches on a
//  player's behalf (kick, ban, pardon, give item, gamemode change, clear
//  inventory, tag admin) — regardless of whether it was triggered from
//  the RCON Console's quick actions, a player's context menu, or their
//  detail page. Logged centrally in RCONAutomationCoordinator, right
//  alongside the command dispatch, so the trail can never drift from
//  what was actually sent.
//
//  Keyed by `username` (not a SwiftData relationship to `Player`) for
//  the same reason `Player.username` is the natural key elsewhere: GS4/
//  RCON only ever deal in usernames, and an event should still be
//  readable even if the `Player` row it refers to were ever deleted.
//

import Foundation
import SwiftData

@Model
final class ModerationEvent {
    enum Kind: String, Codable, CaseIterable {
        case kick
        case ban
        case pardon
        case giveItem = "give_item"
        case gamemodeChange = "gamemode_change"
        case clearInventory = "clear_inventory"
        case tagAdmin = "tag_admin"

        var label: String {
            switch self {
            case .kick: return "Kicked"
            case .ban: return "Banned"
            case .pardon: return "Pardoned"
            case .giveItem: return "Given Item"
            case .gamemodeChange: return "Gamemode Changed"
            case .clearInventory: return "Inventory Cleared"
            case .tagAdmin: return "Tagged Admin"
            }
        }

        var systemImage: String {
            switch self {
            case .kick: return "arrow.right.circle.fill"
            case .ban: return "hand.raised.fill"
            case .pardon: return "checkmark.circle.fill"
            case .giveItem: return "shippingbox.fill"
            case .gamemodeChange: return "person.fill.viewfinder"
            case .clearInventory: return "trash.fill"
            case .tagAdmin: return "star.fill"
            }
        }
    }

    var timestamp: Date
    var username: String
    private var kindRaw: String

    /// Human-readable extra context: a ban/kick reason, "3x minecraft:diamond",
    /// the new gamemode name, etc. Empty string when there's nothing to add.
    var detail: String

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .kick }
        set { kindRaw = newValue.rawValue }
    }

    init(username: String, kind: Kind, detail: String = "", timestamp: Date = .now) {
        self.username = username
        self.kindRaw = kind.rawValue
        self.detail = detail
        self.timestamp = timestamp
    }
}
