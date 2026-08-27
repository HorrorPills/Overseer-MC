//
//  PlayerContextMenu.swift
//  Overseer
//
//  Shared right-click menu for a `Player` row — reused by PlayerRosterView
//  (dashboard's "Online Now" list) and PlayerDirectoryView (full roster),
//  so moderation actions are available from wherever an admin spots a
//  name, not just the RCON Console. Every action here is a thin wrapper
//  around RCONAutomationCoordinator, which does the actual command
//  dispatch + ModerationEvent logging — this view has zero RCON/vanilla
//  command knowledge of its own.
//
//  Actions that require the target resolvable in-world (gamemode, give,
//  clear inventory) are only offered while the player has an open
//  session; Kick/Ban/Pardon/Tag Admin are always available since a kick/
//  ban is meaningful (or a no-op) either way.
//

import SwiftUI

struct PlayerContextMenuContent: View {
    var player: Player
    var coordinator: RCONAutomationCoordinator
    @Binding var giveItemTarget: Player?
    @Binding var reasonSheetTarget: ModerationReasonRequest?
    @Binding var tempBanTarget: Player?

    var body: some View {
        NavigationLink(value: player) {
            Label("View Profile", systemImage: "person.text.rectangle")
        }

        Divider()

        if player.isOnline {
            Button {
                reasonSheetTarget = ModerationReasonRequest(player: player, action: .kick)
            } label: {
                Label("Kick", systemImage: "arrow.right.circle")
            }

            Button(role: .destructive) {
                reasonSheetTarget = ModerationReasonRequest(player: player, action: .ban)
            } label: {
                Label("Ban", systemImage: "hand.raised.fill")
            }

            Button {
                tempBanTarget = player
            } label: {
                Label("Temp Ban…", systemImage: "hourglass")
            }

            Menu {
                ForEach(VanillaCommands.GameMode.allCases) { mode in
                    Button(mode.displayName) {
                        Task { await coordinator.setGamemode(mode, for: player.username) }
                    }
                }
            } label: {
                Label("Set Gamemode", systemImage: "person.fill.viewfinder")
            }

            Button {
                giveItemTarget = player
            } label: {
                Label("Give Item…", systemImage: "shippingbox.fill")
            }

            Button(role: .destructive) {
                Task { await coordinator.clearInventory(player.username) }
            } label: {
                Label("Clear Inventory", systemImage: "trash.fill")
            }

            Divider()

            Button {
                Task { await coordinator.tagAdmin(player.username) }
            } label: {
                Label("Tag Admin", systemImage: "star.fill")
            }
        } else {
            Button {
                Task { await coordinator.pardon(player.username) }
            } label: {
                Label("Pardon (Unban)", systemImage: "checkmark.circle")
            }
        }
    }
}
