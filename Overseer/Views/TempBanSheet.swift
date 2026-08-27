//
//  TempBanSheet.swift
//  Overseer
//
//  Reason + duration picker for RCONAutomationCoordinator.tempBan(_:reason:durationMinutes:),
//  reused by PlayerContextMenuContent and PlayerDetailView so a temp-ban
//  doesn't require going to the Access Control screen and retyping the
//  username.
//

import SwiftUI

struct TempBanSheet: View {
    var username: String
    var coordinator: RCONAutomationCoordinator
    @Binding var isPresented: Bool

    @State private var reason = ""
    @State private var durationMinutes: Double = 60

    private static let durationPresets: [(label: String, minutes: Double)] = [
        ("10 minutes", 10), ("30 minutes", 30), ("1 hour", 60),
        ("6 hours", 360), ("1 day", 1440), ("3 days", 4320), ("7 days", 10080)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Temp Ban — \(username)").font(.headline)
            Text("A real vanilla /ban, auto-/pardoned once the duration elapses.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Duration", selection: $durationMinutes) {
                ForEach(Self.durationPresets, id: \.minutes) { preset in
                    Text(preset.label).tag(preset.minutes)
                }
            }
            TextField("Reason (optional)", text: $reason)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirm)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Temp Ban", role: .destructive) { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func confirm() {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await coordinator.tempBan(username, reason: trimmed.isEmpty ? nil : trimmed, durationMinutes: durationMinutes) }
        isPresented = false
    }
}
