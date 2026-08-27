//
//  PingChart.swift
//  Overseer
//
//  Latency over time, as its own chart with its own y-axis rather than
//  a second axis bolted onto the player-count chart — two measures on
//  different scales get two charts, stacked and time-aligned, not a
//  dual-axis chart.
//

import SwiftUI
import Charts

struct PingChart: View {
    var points: [AnalyticsEngine.DownsampledPoint]

    private var latencyColor: Color { .orange }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Ping (ms)", point.averagePing)
            )
            .foregroundStyle(latencyColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)
        }
        .chartYAxisLabel("ms")
    }
}
