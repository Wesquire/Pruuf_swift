import SwiftUI

// MARK: - Break Detail View

/// Detailed view for a single break
/// Shows date range, status, notes and provides cancel/end early actions
struct BreakDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BreakDetailViewModel
    @State private var showCancelConfirmation = false
    @State private var showEndEarlyConfirmation = false

    let onBreakUpdated: () -> Void

    init(breakItem: Break, authService: AuthService, onBreakUpdated: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: BreakDetailViewModel(
            breakItem: breakItem,
            authService: authService
        ))
        self.onBreakUpdated = onBreakUpdated
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Header
                    statusHeader

                    // Date Range Card
                    dateRangeCard

                    // Notes Card (if any)
                    if let notes = viewModel.breakItem.notes, !notes.isEmpty {
                        notesCard(notes: notes)
                    }

                    // Info Card
                    infoCard

                    // Action Buttons (for active/scheduled breaks)
                    if viewModel.canCancel {
                        actionButtons
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Break Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Cancel Break?", isPresented: $showCancelConfirmation) {
                Button("Keep Break", role: .cancel) { }
                Button("Cancel Break", role: .destructive) {
                    Task {
                        await viewModel.cancelBreak()
                        if viewModel.errorMessage == nil {
                            onBreakUpdated()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to cancel this break? Your receivers will be notified that you ended your break early, and normal ping requirements will resume immediately.")
            }
            .alert("End Break Early?", isPresented: $showEndEarlyConfirmation) {
                Button("Keep Break", role: .cancel) { }
                Button("End Break", role: .destructive) {
                    Task {
                        await viewModel.endBreakEarly()
                        if viewModel.errorMessage == nil {
                            onBreakUpdated()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to end your break early? Your receivers will be notified, and you'll need to send your daily ping starting today.")
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

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 12) {
            // Status icon
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: viewModel.breakItem.status.iconName)
                        .font(.system(size: 36))
                        .foregroundColor(statusColor)
                )

            // Status label
            Text(viewModel.breakItem.status.displayName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(statusColor)

            // Time remaining (for active breaks)
            if viewModel.breakItem.status == .active {
                Text(viewModel.breakItem.timeRemainingString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Date Range Card

    private var dateRangeCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Date Range")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            HStack(spacing: 16) {
                // Start Date
                VStack(spacing: 4) {
                    Text("FROM")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text(formattedDate(viewModel.breakItem.startDate))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // End Date
                VStack(spacing: 4) {
                    Text("TO")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text(formattedDate(viewModel.breakItem.endDate))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Duration
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)

                Text("Duration: \(viewModel.breakItem.durationString)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Notes Card

    private func notesCard(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            Text(notes)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("During This Break")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            BreakInfoRow(
                icon: "bell.slash.fill",
                text: "No ping reminders will be sent"
            )

            BreakInfoRow(
                icon: "flame.fill",
                text: "Your streak will continue"
            )

            BreakInfoRow(
                icon: "person.2.fill",
                text: "Receivers will see you're on break"
            )

            BreakInfoRow(
                icon: "hand.tap.fill",
                text: "You can still ping voluntarily"
            )
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if viewModel.breakItem.status == .active {
                // End Break Early button for active breaks
                Button {
                    showEndEarlyConfirmation = true
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "xmark.circle.fill")
                            Text("End Break Early")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)
            } else if viewModel.breakItem.status == .scheduled {
                // Cancel Break button for scheduled breaks
                Button {
                    showCancelConfirmation = true
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .red))
                        } else {
                            Image(systemName: "trash.fill")
                            Text("Cancel Break")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)
            }

            Text("Your receivers will be notified of any changes")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private var statusColor: Color {
        switch viewModel.breakItem.status {
        case .active:
            return .purple
        case .scheduled:
            return .blue
        case .completed:
            return .green
        case .canceled:
            return .orange
        }
    }
}

// MARK: - Break Info Row

struct BreakInfoRow: View {
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
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Break Detail ViewModel

@MainActor
final class BreakDetailViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var breakItem: Break
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let authService: AuthService
    private let breakService: BreakService

    // MARK: - Computed Properties

    var canCancel: Bool {
        breakItem.status == .scheduled || breakItem.status == .active
    }

    // MARK: - Initialization

    init(
        breakItem: Break,
        authService: AuthService,
        breakService: BreakService? = nil
    ) {
        self.breakItem = breakItem
        self.authService = authService
        self.breakService = breakService ?? BreakService.shared
    }

    // MARK: - Actions

    /// Cancel a scheduled break
    func cancelBreak() async {
        guard let userId = authService.currentPruufUser?.id else {
            errorMessage = "User not found"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await breakService.cancelBreak(breakId: breakItem.id, senderId: userId)

            // Update local state
            breakItem.status = .canceled

            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription

            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    /// End an active break early
    func endBreakEarly() async {
        guard let userId = authService.currentPruufUser?.id else {
            errorMessage = "User not found"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await breakService.endBreakEarly(breakId: breakItem.id, senderId: userId)

            // Update local state
            breakItem.status = .canceled

            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription

            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BreakDetailView_Previews: PreviewProvider {
    static var previews: some View {
        BreakDetailView(
            breakItem: Break(
                id: UUID(),
                senderId: UUID(),
                startDate: Date(),
                endDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())!,
                createdAt: Date(),
                status: .active,
                notes: "Vacation to Hawaii"
            ),
            authService: AuthService()
        )
    }
}
#endif
