//
//  PlayerActiveHoursHeatmap.swift
//  Overseer
//
//  One player's own 168-hour login-time fingerprint — same visual
//  language as WeeklyHeatmapView (the server-wide traffic matrix), but
//  bucketed by this one player's session start times instead of
//  concurrent player counts. A rough, privacy-free stand-in for
//  "what timezone are they probably in": someone who only ever logs in
//  02:00–06:00 Warsaw time is very unlikely to be in Europe.
//

import SwiftUI
import Charts

struct PlayerActiveHoursHeatmap: View {
    var matrix: [PlayerStatsEngine.HourlyLoginFrequency]

    private let weekdaySymbols = AnalyticsEngine.warsawCalendar.shortWeekdaySymbols // index 0 = Sunday

    var body: some View {
        Chart(matrix) { cell in
            RectangleMark(
                x: .value("Hour", cell.hour),
                y: .value("Day", weekdaySymbols[cell.weekday - 1]),
                width: .ratio(0.92),
                height: .ratio(0.92)
            )
            .foregroundStyle(by: .value("Logins", cell.sessionCount))
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
            AxisMarks { _ in AxisValueLabel() }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Weekly login-time fingerprint, Poland time")
    }
}
