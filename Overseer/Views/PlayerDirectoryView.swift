//
//  PlayerDirectoryView.swift
//  Overseer
//
//  Full player roster — online and offline, most-recently-seen first —
//  so any player who has ever joined is reachable for their historical
//  stats page or a quick moderation action, not just whoever happens to
//  be online right now (that's PlayerRosterView's job, on the
//  Dashboard).
//

import SwiftUI
import SwiftData

struct PlayerDirectoryView: View {
    @Query(sort: \Player.lastSeen, order: .reverse) private var players: [Player]
    var rconCoordinator: RCONAutomationCoordinator
    var viewModel: DashboardViewModel

    @State private var searchText = ""
    @State private var onlyFlagged = false
    @State private var giveItemTarget: Player?
    @State private var reasonSheetTarget: ModerationReasonRequest?
    @State private var tempBanTarget: Player?

    private var filteredPlayers: [Player] {
        var result = players
        if onlyFlagged {
            result = result.filter { $0.investigationStatus != .clear }
        }
        guard !searchText.isEmpty else { return result }
        return result.filter { $0.username.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if players.isEmpty {
                ContentUnavailableView(
                    "No Players Yet",
                    systemImage: "person.3",
                    description: Text("Players appear here automatically the first time they join.")
                )
            } else {
                VStack(spacing: 0) {
                    Toggle("Flagged only", isOn: $onlyFlagged)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    List(filteredPlayers) { player in
                        NavigationLink(value: player) {
                            row(for: player)
                        }
                        .contextMenu {
                            PlayerContextMenuContent(player: player, coordinator: rconCoordinator, giveItemTarget: $giveItemTarget, reasonSheetTarget: $reasonSheetTarget, tempBanTarget: $tempBanTarget)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search players")
        .navigationTitle("Players (\(players.count))")
        .sheet(item: $giveItemTarget) { player in
            GiveItemSheet(
                username: player.username,
                coordinator: rconCoordinator,
                isPresented: Binding(get: { giveItemTarget != nil }, set: { if !$0 { giveItemTarget = nil } })
            )
        }
        .sheet(item: $reasonSheetTarget) { request in
            ModerationReasonSheet(
                username: request.player.username,
                action: request.action,
                coordinator: rconCoordinator,
                isPresented: Binding(get: { reasonSheetTarget != nil }, set: { if !$0 { reasonSheetTarget = nil } })
            )
        }
        .sheet(item: $tempBanTarget) { player in
            TempBanSheet(
                username: player.username,
                coordinator: rconCoordinator,
                isPresented: Binding(get: { tempBanTarget != nil }, set: { if !$0 { tempBanTarget = nil } })
            )
        }
    }

    private func row(for player: Player) -> some View {
        HStack(spacing: 12) {
            avatar(for: player)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.username).font(.body.weight(.medium))
                if player.isOnline {
                    Text("Online now").font(.caption).foregroundStyle(.green)
                } else {
                    Text("Last seen \(player.lastSeen, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if player.investigationStatus != .clear {
                Image(systemName: player.investigationStatus.systemImage)
                    .font(.caption)
                    .foregroundStyle(investigationTint(player.investigationStatus))
                    .help(player.investigationStatus.label)
            }
            if !player.notes.isEmpty {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(player.notes)
            }
            Text(formatDuration(player.playTimeSeconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func avatar(for player: Player) -> some View {
        if let image = viewModel.avatarImage(for: player) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
        }
    }
}
