//
//  PlayerRosterView.swift
//  Overseer
//
//  Live "who's online" list with 3D head avatars. Backed by SwiftData
//  directly (`@Query`) filtered to players with an open session, rather
//  than duplicating that state in a view model.
//

import SwiftUI
import SwiftData

struct PlayerRosterView: View {
    @Query private var players: [Player]
    var viewModel: DashboardViewModel
    var rconCoordinator: RCONAutomationCoordinator

    @State private var giveItemTarget: Player?
    @State private var reasonSheetTarget: ModerationReasonRequest?
    @State private var tempBanTarget: Player?

    init(viewModel: DashboardViewModel, rconCoordinator: RCONAutomationCoordinator) {
        self.viewModel = viewModel
        self.rconCoordinator = rconCoordinator
        // Players whose most recent session is still open.
        _players = Query(
            filter: #Predicate<Player> { player in
                player.sessions.contains { $0.endTime == nil }
            },
            sort: \Player.username
        )
    }

    var body: some View {
        Group {
            if players.isEmpty {
                ContentUnavailableView(
                    "No Players Online",
                    systemImage: "person.slash",
                    description: Text("The server is quiet right now.")
                )
            } else {
                List(players) { player in
                    NavigationLink(value: player) {
                        HStack(spacing: 12) {
                            avatar(for: player)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.username)
                                    .font(.body.weight(.medium))
                                if let session = player.sessions.first(where: { $0.endTime == nil }) {
                                    Text("Online for \(session.startTime, format: .relative(presentation: .named))")
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
                        }
                        .padding(.vertical, 2)
                    }
                    .contextMenu {
                        PlayerContextMenuContent(player: player, coordinator: rconCoordinator, giveItemTarget: $giveItemTarget, reasonSheetTarget: $reasonSheetTarget, tempBanTarget: $tempBanTarget)
                    }
                }
                .listStyle(.inset)
            }
        }
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
