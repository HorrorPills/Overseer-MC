//
//  PlayerTimelineView.swift
//  Overseer
//
//  Gantt-style session history for a set of players. Identity is
//  carried by the row label (username), not by bar color, so every bar
//  shares one neutral hue — no categorical palette needed even as the
//  player count grows unbounded.
//

import SwiftUI
import Charts

struct PlayerTimelineView: View {
    var sessions: [PlayerSession]

    private var groupedByUsername: [(username: String, sessions: [PlayerSession])] {
        let grouped = Dictionary(grouping: sessions) { $0.player?.username ?? "Unknown" }
        return grouped
            .map { (username: $0.key, sessions: $0.value) }
            .sorted { $0.sessions.count > $1.sessions.count }
    }

    var body: some View {
        Chart {
            ForEach(groupedByUsername, id: \.username) { group in
                ForEach(group.sessions) { session in
                    BarMark(
                        xStart: .value("Start", session.startTime),
                        xEnd: .value("End", session.endTime ?? Date()),
                        y: .value("Player", group.username)
                    )
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(3)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6))
        }
        .accessibilityLabel("Player join and leave sessions over time")
    }
}
