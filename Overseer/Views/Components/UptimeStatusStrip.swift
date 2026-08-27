//
//  UptimeStatusStrip.swift
//  Overseer
//
//  GitHub-status-page-style hourly uptime strip: one bar per hour over
//  the last 24, colored by that hour's fraction of successful polls,
//  with an exact percentage on hover. Exists because a hidden-axis
//  sparkline can't answer "was the server actually up last night" at a
//  glance — this can, with a number attached to every bar.
//

import SwiftUI

struct UptimeStatusStrip: View {
    var buckets: [AnalyticsEngine.UptimeBucket]
    var summary: AnalyticsEngine.UptimeSummary

    private func color(for bucket: AnalyticsEngine.UptimeBucket) -> Color {
        guard bucket.hasData else { return .gray.opacity(0.25) }
        switch bucket.percentage {
        case 99...: return .green
        case 60..<99: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f%%", summary.percentage))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("uptime, last 24h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if summary.totalDowntimeSeconds > 0 {
                    Text("Longest outage: \(formatDuration(summary.longestOutageSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 3) {
                ForEach(buckets) { bucket in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(for: bucket))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .help(tooltip(for: bucket))
                }
            }

            HStack {
                Text("24h ago").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Now").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func tooltip(for bucket: AnalyticsEngine.UptimeBucket) -> String {
        let hourLabel = bucket.hourStart.formatted(.dateTime.hour().minute())
        guard bucket.hasData else { return "\(hourLabel) — no data" }
        return "\(hourLabel): \(String(format: "%.0f%%", bucket.percentage)) uptime"
    }
}

#Preview {
    UptimeStatusStrip(
        buckets: (0..<24).map { .init(hourStart: Date().addingTimeInterval(Double($0 - 24) * 3600), percentage: $0 == 5 ? 40 : 100, hasData: true) },
        summary: .init(percentage: 97.5, totalDowntimeSeconds: 900, longestOutageSeconds: 900)
    )
    .padding()
}
