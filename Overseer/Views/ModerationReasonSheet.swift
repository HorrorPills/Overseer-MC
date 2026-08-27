//
//  ModerationReasonSheet.swift
//  Overseer
//
//  Shared reason-entry sheet for Kick/Ban, reused by
//  PlayerContextMenuContent (right-click) and PlayerDetailView so both
//  entry points let an admin attach a reason instead of firing a
//  bare `/kick`/`/ban`. Confirmation-dialog-style destructive framing
//  for Ban; a plain confirm for Kick.
//

import SwiftUI

struct ModerationReasonSheet: View {
    enum Action {
        case kick
        case ban

        var title: String {
            switch self {
            case .kick: return "Kick Player"
            case .ban: return "Ban Player"
            }
        }
        var confirmLabel: String {
            switch self {
            case .kick: return "Kick"
            case .ban: return "Ban"
            }
        }
        var message: String {
            switch self {
            case .kick: return "Immediately disconnects them; they can rejoin right away."
            case .ban: return "Immediately disconnects them and blocks future logins until pardoned."
            }
        }
    }

    var username: String
    var action: Action
    var coordinator: RCONAutomationCoordinator
    @Binding var isPresented: Bool

    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(action.title) — \(username)").font(.headline)
            Text(action.message).font(.caption).foregroundStyle(.secondary)
            TextField("Reason (optional)", text: $reason)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirm)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(action.confirmLabel, role: .destructive) { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func confirm() {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReason = trimmed.isEmpty ? nil : trimmed
        Task {
            switch action {
            case .kick: await coordinator.kick(username, reason: finalReason)
            case .ban: await coordinator.ban(username, reason: finalReason)
            }
        }
        isPresented = false
    }
}

/// `.sheet(item:)` payload for presenting ModerationReasonSheet from a
/// row-based context (PlayerRosterView, PlayerDirectoryView) where the
/// target player isn't already fixed the way it is on PlayerDetailView.
struct ModerationReasonRequest: Identifiable {
    var id: String { "\(player.username)-\(action == .kick ? "kick" : "ban")" }
    var player: Player
    var action: ModerationReasonSheet.Action
}
