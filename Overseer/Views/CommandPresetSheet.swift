//
//  CommandPresetSheet.swift
//  Overseer
//
//  Add-preset form for RCONConsoleView's presets bar. Validated against
//  VanillaCommands.isStrictlyVanilla on save, same guard rail the
//  console's free-text input now enforces — a saved preset shouldn't be
//  a backdoor around it.
//

import SwiftUI
import SwiftData

struct CommandPresetSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var label = ""
    @State private var command = ""

    private var trimmedCommand: String { command.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isVanilla: Bool { VanillaCommands.isStrictlyVanilla(trimmedCommand) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Command Preset").font(.headline)
            TextField("Button label (e.g. \"Clear Weather + Day\")", text: $label)
                .textFieldStyle(.roundedBorder)
            TextField("Command (e.g. /weather clear)", text: $command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            if !trimmedCommand.isEmpty && !isVanilla {
                Label("This looks like a Paper/Spigot/Essentials command, not vanilla — rejected.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedLabel.isEmpty || trimmedCommand.isEmpty || !isVanilla)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        modelContext.insert(CommandPreset(label: trimmedLabel, command: trimmedCommand))
        try? modelContext.save()
        isPresented = false
    }
}
