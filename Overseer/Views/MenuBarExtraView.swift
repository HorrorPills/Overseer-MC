//
//  MenuBarExtraView.swift
//  Overseer
//
//  Compact status widget: 🟢 [Count]/[Max] plus the active player
//  names, for the macOS menu bar.
//

import SwiftUI

struct MenuBarExtraLabel: View {
    var viewModel: DashboardViewModel

    var body: some View {
        let dot = viewModel.isOnline ? "🟢" : "🔴"
        Text("\(dot) \(viewModel.playerCount)/\(viewModel.maxPlayers)")
    }
}

struct MenuBarExtraContentView: View {
    var viewModel: DashboardViewModel
    var coordinator: PollingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusIndicator(isOnline: viewModel.isOnline, label: "Server")
                Spacer()
                Text("\(viewModel.playerCount)/\(viewModel.maxPlayers)")
                    .font(.headline)
                    .monospacedDigit()
            }

            Divider()

            if viewModel.onlineUsernames.isEmpty {
                Text("No players online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.onlineUsernames, id: \.self) { name in
                    Text(name).font(.callout)
                }
            }

            Divider()

            HStack {
                Button("Refresh") {
                    Task { await viewModel.refreshNow() }
                }
                Spacer()
                Button("Open Overseer") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows { window.makeKeyAndOrderFront(nil) }
                }
            }
            .font(.caption)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}

#if canImport(AppKit)
import AppKit
#endif
