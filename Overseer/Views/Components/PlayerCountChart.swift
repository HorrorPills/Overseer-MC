//
//  PlayerCountChart.swift
//  Overseer
//
//  Player count over time: LineMark + AreaMark gradient, single series
//  (so no legend is needed — the axis/title names it). Used both as the
//  dashboard's small trend sparkline and, with axes + selection enabled,
//  as the primary historical chart.
//

import SwiftUI
import Charts

struct PlayerCountChart: View {
    var points: [AnalyticsEngine.DownsampledPoint]
    var showAxes: Bool = true
    @Binding var selectedPoint: AnalyticsEngine.DownsampledPoint?

    init(points: [AnalyticsEngine.DownsampledPoint], showAxes: Bool = true, selectedPoint: Binding<AnalyticsEngine.DownsampledPoint?> = .constant(nil)) {
        self.points = points
        self.showAxes = showAxes
        self._selectedPoint = selectedPoint
    }

    private var seriesColor: Color { .accentColor }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Players", point.averagePlayers)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [seriesColor.opacity(0.35), seriesColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Players", point.averagePlayers)
            )
            .foregroundStyle(seriesColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)

            if let selectedPoint, selectedPoint.id == point.id {
                RuleMark(x: .value("Time", selectedPoint.timestamp))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                PointMark(
                    x: .value("Time", selectedPoint.timestamp),
                    y: .value("Players", selectedPoint.averagePlayers)
                )
                .foregroundStyle(seriesColor)
                .symbolSize(60)
            }
        }
        .chartXAxis(showAxes ? .automatic : .hidden)
        .chartYAxis(showAxes ? .automatic : .hidden)
        .chartOverlay { proxy in
            if showAxes {
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(at: value.location, proxy: proxy, geo: geo)
                                }
                                .onEnded { _ in selectedPoint = nil }
                        )
                }
            }
        }
        .chartBackground { proxy in
            if let selectedPoint {
                GeometryReader { geo in
                    if let anchor = proxy.position(forX: selectedPoint.timestamp) {
                        let frame = geo[proxy.plotFrame!]
                        tooltip(for: selectedPoint)
                            .position(x: min(max(anchor + frame.minX, 60), frame.maxX - 60), y: frame.minY + 24)
                    }
                }
            }
        }
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geo[plotFrame]
        guard frame.contains(location) else { return }
        let xPosition = location.x - frame.minX
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        selectedPoint = points.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(date)) < abs(rhs.timestamp.timeIntervalSince(date))
        }
    }

    @ViewBuilder
    private func tooltip(for point: AnalyticsEngine.DownsampledPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.timestamp, format: .dateTime.month().day().hour().minute())
                .font(.caption2.weight(.semibold))
            Text("\(Int(point.averagePlayers.rounded())) players")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
