import Foundation
import SwiftUI
#if canImport(Charts)
import Charts
#endif

// MARK: - Date Extensions

extension Date {
    /// Format date for display in the app
    func formatted(style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    /// Format time for display in the app
    func formattedTime(style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = style
        return formatter.string(from: self)
    }

    /// Relative time string (e.g., "2 hours ago")
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Check if date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Check if date is in the past
    var isPast: Bool {
        self < Date()
    }

    /// Start of day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// End of day
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay)!
    }
}

// MARK: - String Extensions

extension String {
    /// Validate phone number format
    var isValidPhoneNumber: Bool {
        let phoneRegex = "^\\+[1-9]\\d{1,14}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return predicate.evaluate(with: self)
    }

    /// Format phone number for display
    var formattedPhoneNumber: String {
        // Simple formatting - can be enhanced for specific country formats
        guard self.count >= 10 else { return self }

        let cleaned = self.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return cleaned
    }

    /// Get initials from name
    var initials: String {
        let words = self.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first?.uppercased() }
        return initials.joined()
    }

    /// Trim whitespace
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply conditional modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Hide keyboard
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Apply corner radius to specific corners
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

/// Custom shape for specific corner radius
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Optional Extensions

extension Optional where Wrapped == String {
    /// Return empty string if nil
    var orEmpty: String {
        self ?? ""
    }

    /// Check if string is nil or empty
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

// MARK: - Array Extensions

extension Array {
    /// Safe subscript access
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Color Extensions

extension Color {
    /// App primary color - Uses iOS system blue for dark mode support
    static let appPrimary = Color(UIColor.systemBlue)

    /// App secondary color - Uses iOS system gray for dark mode support
    static let appSecondary = Color(UIColor.secondaryLabel)

    /// Success color - Uses iOS system green for dark mode support
    static let success = Color(UIColor.systemGreen)

    /// Warning color - Uses iOS system orange for dark mode support
    static let warning = Color(UIColor.systemOrange)

    /// Danger color - Uses iOS system red for dark mode support
    static let danger = Color(UIColor.systemRed)

    /// Background color - Uses iOS grouped background for dark mode support
    static let appBackground = Color(UIColor.systemGroupedBackground)

    /// Card background color - Uses iOS secondary grouped background for dark mode support
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)

    /// Primary text color - Uses iOS label for dark mode support
    static let textPrimary = Color(UIColor.label)

    /// Secondary text color - Uses iOS secondary label for dark mode support
    static let textSecondary = Color(UIColor.secondaryLabel)
}

// MARK: - SwiftUI Charts Support (iOS 16+)

/// Data point for charts
/// Used in the analytics dashboard for ping history visualization
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let category: String

    init(date: Date, value: Double, category: String = "default") {
        self.date = date
        self.value = value
        self.category = category
    }
}

/// Ping chart data for analytics visualization
struct PingChartData: Identifiable {
    let id = UUID()
    let date: Date
    let onTime: Int
    let late: Int
    let missed: Int
    let onBreak: Int

    var total: Int {
        onTime + late + missed + onBreak
    }

    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(onTime + late) / Double(total) * 100
    }
}

/// Chart availability wrapper for backwards compatibility with iOS 15
/// SwiftUI Charts is available starting iOS 16
@available(iOS 16.0, *)
struct ChartsAvailability {
    /// Check if Charts framework is available
    static var isAvailable: Bool {
        return true
    }
}

/// Fallback view for iOS 15 when Charts is not available
struct ChartsFallbackView: View {
    let message: String

    init(message: String = "Charts require iOS 16 or later") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
}

/// Protocol for chart data sources
protocol ChartDataSource {
    associatedtype DataType
    var data: [DataType] { get }
    var isEmpty: Bool { get }
}

extension Array: ChartDataSource where Element: Identifiable {
    typealias DataType = Element
    var data: [Element] { self }
}

// MARK: - Chart Color Scheme

extension Color {
    /// Colors for ping status in charts
    static let pingOnTime = Color.success
    static let pingLate = Color.warning
    static let pingMissed = Color.danger
    static let pingOnBreak = Color.secondary
}

// MARK: - Date Helpers for Charts

extension Date {
    /// Format date for chart axis labels
    var chartAxisLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }

    /// Format date for chart tooltips
    var chartTooltipLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }
}
