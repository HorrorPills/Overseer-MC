//
//  SummaryCard.swift
//  Overseer
//

import SwiftUI

/// Small metric tile used in the dashboard's summary row
/// (player count, ping, map name, uptime, ...).
struct SummaryCard: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview {
    HStack {
        SummaryCard(title: "Players", value: "12/40", systemImage: "person.3.fill", tint: .green)
        SummaryCard(title: "Ping", value: "38 ms", systemImage: "bolt.fill", tint: .orange)
    }
    .padding()
}
