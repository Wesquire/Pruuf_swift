import SwiftUI

// MARK: - Schedule Break View

/// View for scheduling a new break period
/// Allows sender to set start date, end date, and optional notes
struct ScheduleBreakView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ScheduleBreakViewModel
    @State private var showConfirmation = false

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: ScheduleBreakViewModel(authService: authService))
    }

    var body: some View {
        NavigationView {
            ZStack {
                if showConfirmation {
                    confirmationView
                } else {
                    formContent
                }
            }
            .navigationTitle("Schedule Pruuf Pause")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Form Content

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header illustration
                headerSection

                // Date pickers
                datePickersSection

                // Notes field
                notesSection

                // Schedule button
                scheduleButton

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.purple)

            Text("Take a Pruuf Pause")
                .font(.title2)
                .fontWeight(.bold)

            Text("Schedule time off when you won't need to send a Pruuf. Your receivers will be notified.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Date Pickers Section

    private var datePickersSection: some View {
        VStack(spacing: 16) {
            // Start Date
            VStack(alignment: .leading, spacing: 8) {
                Text("Start Date")
                    .font(.headline)
                    .foregroundColor(.primary)

                DatePicker(
                    "Start Date",
                    selection: $viewModel.startDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accentColor(.purple)
                .labelsHidden()
                .onChange(of: viewModel.startDate) { newValue in
                    viewModel.validateDates()
                    // Ensure end date is not before start date
                    if viewModel.endDate < newValue {
                        viewModel.endDate = newValue
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // End Date
            VStack(alignment: .leading, spacing: 8) {
                Text("End Date")
                    .font(.headline)
                    .foregroundColor(.primary)

                DatePicker(
                    "End Date",
                    selection: $viewModel.endDate,
                    in: viewModel.startDate...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accentColor(.purple)
                .labelsHidden()
                .onChange(of: viewModel.endDate) { _ in
                    viewModel.validateDates()
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // Duration summary
            if viewModel.isValidDates {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.purple)

                    Text(viewModel.durationSummary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }

            // Validation error
            if let validationError = viewModel.validationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)

                    Text(validationError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 4)
            }

            // EC-7.5: Warning for long breaks (> 1 year)
            if let durationWarning = viewModel.durationWarning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text(durationWarning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (Optional)")
                .font(.headline)
                .foregroundColor(.primary)

            if #available(iOS 16.0, *) {
                TextField("e.g., Vacation, Medical, etc.", text: $viewModel.notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .lineLimit(3...6)
            } else {
                TextField("e.g., Vacation, Medical, etc.", text: $viewModel.notes)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Schedule Button

    private var scheduleButton: some View {
        Button {
            Task {
                let success = await viewModel.scheduleBreak()
                if success {
                    withAnimation {
                        showConfirmation = true
                    }
                }
            }
        } label: {
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "calendar.badge.plus")
                    Text("Schedule Pruuf Pause")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(viewModel.isValidDates ? Color.purple : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!viewModel.isValidDates || viewModel.isLoading)
        .padding(.top, 8)
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)

            Text("Pruuf Pause Scheduled!")
                .font(.title)
                .fontWeight(.bold)

            // Date range
            VStack(spacing: 8) {
                Text(viewModel.formattedDateRange)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(viewModel.durationSummary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Info card
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(icon: "bell.fill", text: "Your receivers have been notified")
                InfoRow(icon: "flame.fill", text: "Your streak will continue during this Pruuf Pause")
                InfoRow(icon: "hand.tap.fill", text: "You can still send a Pruuf voluntarily if you want")
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            Spacer()

            // Done button
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.purple)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Schedule Break View Model

@MainActor
final class ScheduleBreakViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var startDate: Date = Date()
    @Published var endDate: Date = Date()
    @Published var notes: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var validationError: String?
    @Published var isValidDates: Bool = true
    /// EC-7.5: Warning message for long breaks (> 1 year)
    @Published var durationWarning: String?

    // MARK: - Private Properties

    private let breakService: BreakService
    private let authService: AuthService
    private var createdBreak: Break?

    // MARK: - Computed Properties

    var durationSummary: String {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        let totalDays = days + 1 // Include both start and end days

        if totalDays == 1 {
            return "1 day"
        } else {
            return "\(totalDays) days"
        }
    }

    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        if calendar.isDate(startDay, inSameDayAs: endDay) {
            return formatter.string(from: startDate)
        } else {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }

    // MARK: - Initialization

    init(
        breakService: BreakService? = nil,
        authService: AuthService
    ) {
        self.breakService = breakService ?? BreakService.shared
        self.authService = authService
    }

    // MARK: - Validation

    func validateDates() {
        let result = breakService.validateBreakDates(startDate: startDate, endDate: endDate)
        isValidDates = result.isValid
        validationError = result.message
        // EC-7.5: Set warning for long breaks
        durationWarning = result.warning
    }

    // MARK: - Actions

    func scheduleBreak() async -> Bool {
        guard let userId = authService.currentPruufUser?.id else {
            errorMessage = "You must be logged in to schedule a break"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            createdBreak = try await breakService.scheduleBreak(
                senderId: userId,
                startDate: startDate,
                endDate: endDate,
                notes: notes.isEmpty ? nil : notes
            )

            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            return true
        } catch {
            errorMessage = error.localizedDescription

            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            return false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ScheduleBreakView_Previews: PreviewProvider {
    static var previews: some View {
        ScheduleBreakView(authService: AuthService())
    }
}
#endif
