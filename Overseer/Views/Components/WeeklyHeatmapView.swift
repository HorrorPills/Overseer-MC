//
//  WeeklyHeatmapView.swift
//  Overseer
//
//  168-hour (7 day x 24 hour) traffic intensity matrix, in Europe/Warsaw
//  local time — the ad-intelligence centerpiece. One sequential hue,
//  light to dark, mapped continuously to average concurrent players
//  (never a rainbow).
//

import SwiftUI
import Charts

struct WeeklyHeatmapView: View {
    var matrix: [AnalyticsEngine.HourlyActivity]

    private let weekdaySymbols = AnalyticsEngine.warsawCalendar.shortWeekdaySymbols // index 0 = Sunday

    var body: some View {
        Chart(matrix) { cell in
            RectangleMark(
                x: .value("Hour", cell.hour),
                y: .value("Day", weekdaySymbols[cell.weekday - 1]),
                width: .ratio(0.92),
                height: .ratio(0.92)
            )
            .foregroundStyle(by: .value("Avg Players", cell.averagePlayers))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(range: Gradient(colors: [Color.accentColor.opacity(0.08), Color.accentColor]))
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, to: 24, by: 3))) { value in
                if let hour = value.as(Int.self) {
                    AxisValueLabel(String(format: "%02d:00", hour))
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel()
            }
        }
        .chartLegend(position: .bottom, alignment: .trailing) {
            HStack(spacing: 4) {
                Text("Quiet").font(.caption2).foregroundStyle(.secondary)
                LinearGradient(colors: [Color.accentColor.opacity(0.08), Color.accentColor], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 80, height: 8)
                    .clipShape(Capsule())
                Text("Peak").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Weekly traffic heatmap, Poland time")
    }
}
