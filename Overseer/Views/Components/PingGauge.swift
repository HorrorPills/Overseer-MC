//
//  PingGauge.swift
//  Overseer
//

import SwiftUI

/// Compact ring gauge for current ping latency, color-coded so lag
/// under load is visible at a glance on the dashboard.
struct PingGauge: View {
    var pingMs: Int?

    private var normalized: Double {
        guard let pingMs else { return 0 }
        return min(Double(pingMs) / 300.0, 1.0)
    }

    private var color: Color {
        guard let pingMs else { return .gray }
        switch pingMs {
        case ..<80: return .green
        case ..<180: return .yellow
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: normalized)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: normalized)
            VStack(spacing: 0) {
                Text(pingMs.map(String.init) ?? "—")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
    }
}

#Preview {
    HStack(spacing: 20) {
        PingGauge(pingMs: 32)
        PingGauge(pingMs: 140)
        PingGauge(pingMs: 260)
        PingGauge(pingMs: nil)
    }
    .padding()
}
