import SwiftUI
#if canImport(Charts)
import Charts
#endif

// MARK: - Ping History Chart (iOS 16+)

/// A chart view displaying ping history with status breakdown
/// Uses SwiftUI Charts framework available in iOS 16+
@available(iOS 16.0, *)
struct PingHistoryChart: View {
    let data: [PingChartData]
    let showLegend: Bool

    init(data: [PingChartData], showLegend: Bool = true) {
        self.data = data
        self.showLegend = showLegend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if canImport(Charts)
            Chart {
                ForEach(data) { item in
                    // On-time pings (green)
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Count", item.onTime)
                    )
                    .foregroundStyle(Color.pingOnTime)
                    .position(by: .value("Status", "On Time"))

                    // Late pings (orange)
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Count", item.late)
                    )
                    .foregroundStyle(Color.pingLate)
                    .position(by: .value("Status", "Late"))

                    // Missed pings (red)
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Count", item.missed)
                    )
                    .foregroundStyle(Color.pingMissed)
                    .position(by: .value("Status", "Missed"))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 200)
            #endif

            if showLegend {
                chartLegend
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    private var chartLegend: some View {
        HStack(spacing: 16) {
            legendItem(color: .pingOnTime, label: "On Time")
            legendItem(color: .pingLate, label: "Late")
            legendItem(color: .pingMissed, label: "Missed")
        }
        .font(.caption)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Completion Rate Chart (iOS 16+)

/// A chart showing ping completion rate over time
@available(iOS 16.0, *)
struct CompletionRateChart: View {
    let data: [PingChartData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Completion Rate")
                .font(.headline)

            #if canImport(Charts)
            Chart(data) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Rate", item.completionRate)
                )
                .foregroundStyle(Color.appPrimary)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Rate", item.completionRate)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.appPrimary.opacity(0.3), Color.appPrimary.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)%")
                        }
                    }
                }
            }
            .frame(height: 150)
            #endif
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Streak Chart (iOS 16+)

/// A chart showing ping streak over time
@available(iOS 16.0, *)
struct StreakChart: View {
    let streakData: [ChartDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Streak History")
                .font(.headline)

            #if canImport(Charts)
            Chart(streakData) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Streak", item.value)
                )
                .foregroundStyle(Color.appPrimary.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 120)
            #endif
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Chart Container with iOS 15 Fallback

/// A container that displays charts on iOS 16+ or a fallback on iOS 15
struct ChartContainerView<ChartContent: View, FallbackContent: View>: View {
    let chartContent: () -> ChartContent
    let fallbackContent: () -> FallbackContent

    init(
        @ViewBuilder chart: @escaping () -> ChartContent,
        @ViewBuilder fallback: @escaping () -> FallbackContent
    ) {
        self.chartContent = chart
        self.fallbackContent = fallback
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            chartContent()
        } else {
            fallbackContent()
        }
    }
}

// MARK: - Simple Ping Status Dots (iOS 15 compatible)

/// A simple visual representation of ping history using colored dots
/// Works on all iOS versions including iOS 15
struct PingStatusDotsView: View {
    let history: [PingHistoryItem]
    let maxDays: Int

    init(history: [PingHistoryItem], maxDays: Int = 7) {
        self.history = Array(history.prefix(maxDays))
        self.maxDays = maxDays
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(history) { item in
                VStack(spacing: 4) {
                    Circle()
                        .fill(colorForStatus(item.status))
                        .frame(width: 12, height: 12)
                    Text(item.date.chartAxisLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if history.count < maxDays {
                ForEach(0..<(maxDays - history.count), id: \.self) { _ in
                    VStack(spacing: 4) {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            .frame(width: 12, height: 12)
                        Text("--")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func colorForStatus(_ status: PingStatus) -> Color {
        switch status {
        case .completed:
            return .pingOnTime
        case .pending:
            return .pingLate
        case .missed:
            return .pingMissed
        case .onBreak:
            return .pingOnBreak
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
@available(iOS 16.0, *)
struct ChartsComponents_Previews: PreviewProvider {
    static var sampleData: [PingChartData] {
        let calendar = Calendar.current
        return (0..<7).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            return PingChartData(
                date: date,
                onTime: Int.random(in: 3...8),
                late: Int.random(in: 0...2),
                missed: Int.random(in: 0...1),
                onBreak: 0
            )
        }.reversed()
    }

    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                PingHistoryChart(data: sampleData)
                CompletionRateChart(data: sampleData)
            }
            .padding()
        }
        .background(Color.appBackground)
    }
}
#endif
