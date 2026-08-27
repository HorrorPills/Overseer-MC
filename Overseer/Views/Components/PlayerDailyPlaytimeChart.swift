//
//  PlayerDailyPlaytimeChart.swift
//  Overseer
//
//  Single-series daily playtime bar chart for one player's detail page.
//  Mirrors PlayerCountChart's single-hue-no-legend approach.
//

import SwiftUI
import Charts

struct PlayerDailyPlaytimeChart: View {
    var points: [PlayerStatsEngine.DailyPlaytime]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Minutes", point.seconds / 60)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, points.count / 8))) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(date.formatted(.dateTime.month().day()))
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                if let minutes = value.as(Double.self) {
                    AxisValueLabel("\(Int(minutes))m")
                }
                AxisGridLine()
            }
        }
        .accessibilityLabel("Daily playtime over the last \(points.count) days")
    }
}
