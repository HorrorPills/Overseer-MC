//
//  RCONConsoleView.swift
//  Overseer
//
//  Terminal-style admin console: quick-action buttons for the common
//  Vanilla moderation/utility commands, a scrollable color-coded log of
//  raw RCON traffic, and a command line with Up/Down history recall.
//  Every button here is a thin wrapper around VanillaCommands — there
//  is no path in this view that can construct a Paper/Essentials
//  command.
//

import SwiftUI
import SwiftData

struct RCONConsoleView: View {
    var coordinator: RCONAutomationCoordinator

    @Query(sort: \CommandPreset.createdAt) private var presets: [CommandPreset]
    @Environment(\.modelContext) private var modelContext

    @State private var inputText = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @State private var showPanicConfirmation = false
    @State private var moderationTarget = ""
    @State private var moderationReason = ""
    @State private var showAddPreset = false

    var body: some View {
        VStack(spacing: 0) {
            quickActionBar
            Divider()
            presetsBar
            Divider()
            logView
            Divider()
            commandInputBar
        }
        .navigationTitle("RCON Console")
        .toolbar {
            if coordinator.queuedCommandCount > 0 {
                ToolbarItem {
                    Label("\(coordinator.queuedCommandCount) queued", systemImage: "tray.full")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Commands waiting for the in-flight one to finish — every scheduler and the console share one FIFO queue on the same RCON connection.")
                }
            }
            ToolbarItem {
                StatusIndicator(
                    isOnline: coordinator.isConnected,
                    label: coordinator.isConnected ? "RCON Connected" : "RCON Disconnected"
                )
            }
        }
    }

    // MARK: - Quick actions

    private var quickActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionButton("Day", systemImage: "sun.max.fill") { await coordinator.setTimeDay() }
                actionButton("Clear Weather", systemImage: "cloud.sun.fill") { await coordinator.clearWeather() }
                actionButton("Whitelist On", systemImage: "checkmark.shield.fill") { await coordinator.setWhitelist(enabled: true) }
                actionButton("Whitelist Off", systemImage: "xmark.shield") { await coordinator.setWhitelist(enabled: false) }
                actionButton("Reload Whitelist", systemImage: "arrow.clockwise") { await coordinator.reloadWhitelist() }

                Divider().frame(height: 20)

                moderationControls

                Divider().frame(height: 20)

                Button {
                    showPanicConfirmation = true
                } label: {
                    Label("Panic Mode", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(10)
        }
        .confirmationDialog(
            "Engage emergency lockdown?",
            isPresented: $showPanicConfirmation,
            titleVisibility: .visible
        ) {
            Button("Lock Down Server", role: .destructive) {
                Task { await coordinator.panicMode() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs: whitelist on → kick everyone without the 'admin' tag → gamerule keepInventory true → save-all. Use only during a griefing/exploit emergency. Tag trusted players first with the Tag Admin button.")
        }
    }

    // MARK: - Command presets

    /// User-defined one-click commands — the middle tier between the
    /// built-in quick actions above and typing a raw command below.
    /// Validated against VanillaCommands.isStrictlyVanilla when added
    /// (CommandPresetSheet); sendConsoleCommand enforces it again
    /// regardless, so a preset can never be a backdoor around it.
    private var presetsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    Button(preset.label) {
                        Task { await coordinator.sendConsoleCommand(preset.command) }
                    }
                    .buttonStyle(.bordered)
                    .help(preset.command)
                    .contextMenu {
                        Button("Delete", role: .destructive) { delete(preset) }
                    }
                }
                Button {
                    showAddPreset = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Add a command preset")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $showAddPreset) {
            CommandPresetSheet(isPresented: $showAddPreset)
        }
    }

    private func delete(_ preset: CommandPreset) {
        modelContext.delete(preset)
        try? modelContext.save()
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }

    private var moderationControls: some View {
        HStack(spacing: 6) {
            TextField("Player", text: $moderationTarget)
                .frame(width: 100)
                .textFieldStyle(.roundedBorder)
            TextField("Reason (optional)", text: $moderationReason)
                .frame(width: 130)
                .textFieldStyle(.roundedBorder)
            Button("Kick") {
                Task { await coordinator.kick(moderationTarget, reason: moderationReason.isEmpty ? nil : moderationReason) }
            }
            .buttonStyle(.bordered)
            Button("Ban") {
                Task { await coordinator.ban(moderationTarget, reason: moderationReason.isEmpty ? nil : moderationReason) }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            Button("Pardon") {
                Task { await coordinator.pardon(moderationTarget) }
            }
            .buttonStyle(.bordered)
            Button("Tag Admin") {
                Task { await coordinator.tagAdmin(moderationTarget) }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Log

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(coordinator.commandLog) { entry in
                        logLine(entry).id(entry.id)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.85))
            .onChange(of: coordinator.commandLog.count) { _, _ in
                guard let last = coordinator.commandLog.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func logLine(_ entry: RCONAutomationCoordinator.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .foregroundStyle(.gray)
            Text(prefix(for: entry.kind))
                .foregroundStyle(color(for: entry.kind))
            Text(entry.text)
                .foregroundStyle(color(for: entry.kind))
                .textSelection(.enabled)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func prefix(for kind: RCONAutomationCoordinator.LogEntry.Kind) -> String {
        switch kind {
        case .sent: return ">"
        case .received: return "<"
        case .error: return "!"
        case .system: return "*"
        }
    }

    private func color(for kind: RCONAutomationCoordinator.LogEntry.Kind) -> Color {
        switch kind {
        case .sent: return .cyan
        case .received: return .green
        case .error: return .red
        case .system: return .yellow
        }
    }

    // MARK: - Command line

    private var commandInputBar: some View {
        HStack {
            Text(">")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField("Enter a vanilla command…", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onSubmit(submit)
                .onKeyPress(.upArrow) {
                    navigateHistory(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateHistory(by: 1)
                    return .handled
                }
        }
        .padding(10)
        .background(.regularMaterial)
    }

    private func submit() {
        let command = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        history.append(command)
        historyIndex = nil
        inputText = ""
        Task { await coordinator.sendConsoleCommand(command) }
    }

    private func navigateHistory(by delta: Int) {
        guard !history.isEmpty else { return }
        let newIndex = (historyIndex ?? history.count) + delta
        if newIndex < 0 {
            historyIndex = 0
        } else if newIndex >= history.count {
            historyIndex = nil
            inputText = ""
            return
        } else {
            historyIndex = newIndex
        }
        if let historyIndex {
            inputText = history[historyIndex]
        }
    }
}
