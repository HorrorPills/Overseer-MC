//
//  PlayerLeaderRow.swift
//  Overseer
//
//  One ranked player row (avatar, username, a caller-supplied metric),
//  linking to PlayerDetailView. Shared by LeaderboardView (the full
//  rankings) and DashboardView (the Top Playtime preview) so the two
//  never drift apart in styling.
//

import SwiftUI

struct PlayerLeaderRow: View {
    var rank: Int
    var player: Player
    var value: String
    var viewModel: DashboardViewModel

    var body: some View {
        NavigationLink(value: player) {
            HStack(spacing: 12) {
                Text("#\(rank)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                avatar
                Text(player.username).font(.body.weight(.medium))
                Spacer()
                Text(value).font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = viewModel.avatarImage(for: player) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "person.fill").font(.caption).foregroundStyle(.secondary))
        }
    }
}
