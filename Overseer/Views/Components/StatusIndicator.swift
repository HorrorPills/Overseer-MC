//
//  StatusIndicator.swift
//  Overseer
//

import SwiftUI

/// Green/red dot + label used on the dashboard header and menu bar.
struct StatusIndicator: View {
    var isOnline: Bool
    var label: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: (isOnline ? Color.green : Color.red).opacity(0.6), radius: 3)
            Text(label ?? (isOnline ? "Online" : "Offline"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        StatusIndicator(isOnline: true, label: "example.com")
        StatusIndicator(isOnline: false, label: "example.com")
    }
    .padding()
}
