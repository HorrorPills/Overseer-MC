//
//  MSPTChart.swift
//  Overseer
//
//  Milliseconds-per-tick over time, from vanilla `/tick query` samples
//  — the strictly-vanilla stand-in for a plugin's /tps graph. Own
//  y-axis, own chart (never bolted onto the ping or player-count chart
//  as a second axis), so it reads correctly alongside them in
//  ServerHistoryView and DashboardView.
//
//  A dashed reference line at 50ms marks the point beyond which the
//  server can no longer hold 20 TPS — the "physically lagging" signal
//  network ping alone can't show.
//

import SwiftUI
import Charts

struct MSPTChart: View {
    var samples: [TickSample]

    private var color: Color { .purple }
    private let lagThresholdMSPT: Double = 50

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("MSPT", sample.mspt)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("20 TPS floor", lagThresholdMSPT))
                .foregroundStyle(.red.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("50ms (20 TPS floor)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        .chartYAxisLabel("ms/tick")
    }
}
