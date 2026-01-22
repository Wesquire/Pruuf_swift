import SwiftUI

// MARK: - Breaks List View

/// View showing list of scheduled, active, and past breaks
/// Accessed via Settings > Breaks
struct BreaksListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BreaksListViewModel
    @State private var selectedBreak: Break?
    @State private var showBreakDetail = false
    @State private var showScheduleBreak = false
    @State private var selectedFilter: BreakFilter = .all

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: BreaksListViewModel(authService: authService))
    }

    /// Filter options for the break list
    enum BreakFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case scheduled = "Scheduled"
        case completed = "Completed"
        case canceled = "Canceled"
    }

    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isLoading && viewModel.allBreaks.isEmpty {
                    ProgressView("Loading breaks...")
                } else if viewModel.allBreaks.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 0) {
                        // Filter picker for US-7.3 requirement
                        filterPicker

                        // Filtered breaks list
                        filteredBreaksList
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Breaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showScheduleBreak = true
                    } label: {
                        Image(systemName: "plus")
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
        .task {
            await viewModel.loadBreaks()
        }
        .sheet(isPresented: $showBreakDetail) {
            if let breakItem = selectedBreak {
                BreakDetailView(
                    breakItem: breakItem,
                    authService: viewModel.authService,
                    onBreakUpdated: {
                        Task {
                            await viewModel.loadBreaks()
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showScheduleBreak) {
            ScheduleBreakView(authService: viewModel.authService)
        }
        .onChange(of: showScheduleBreak) { isShowing in
            if !isShowing {
                Task {
                    await viewModel.loadBreaks()
                }
            }
        }
    }

    // MARK: - Filter Picker

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BreakFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedFilter == filter ? .semibold : .regular)
                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedFilter == filter ? Color.purple : Color(.systemGray5))
                            .cornerRadius(20)
                    }
                    .accessibilityLabel("Filter by \(filter.rawValue)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Filtered Breaks List

    private var filteredBreaksList: some View {
        let filteredBreaks = filterBreaks()

        return Group {
            if filteredBreaks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No \(selectedFilter == .all ? "" : selectedFilter.rawValue.lowercased()) breaks")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredBreaks) { breakItem in
                        BreakRowView(breakItem: breakItem)
                            .onTapGesture {
                                selectedBreak = breakItem
                                showBreakDetail = true
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.loadBreaks()
                }
            }
        }
    }

    /// Filter breaks based on the selected filter
    private func filterBreaks() -> [Break] {
        switch selectedFilter {
        case .all:
            return viewModel.allBreaks
        case .active:
            if let active = viewModel.activeBreak {
                return [active]
            }
            return []
        case .scheduled:
            return viewModel.scheduledBreaks
        case .completed:
            return viewModel.pastBreaks.filter { $0.status == .completed }
        case .canceled:
            return viewModel.pastBreaks.filter { $0.status == .canceled }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Breaks")
                .font(.title2)
                .fontWeight(.bold)

            Text("You haven't scheduled any breaks yet.\nBreaks let you pause ping requirements temporarily.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showScheduleBreak = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Schedule a Break")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.purple)
                .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .padding()
    }

}

// MARK: - Break Row View

/// Row view for displaying a break in the list
struct BreakRowView: View {
    let breakItem: Break

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: breakItem.status.iconName)
                .font(.title3)
                .foregroundColor(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                // Date range
                Text(formattedDateRange)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                // Status and duration
                HStack(spacing: 8) {
                    Text(breakItem.status.displayName)
                        .font(.caption)
                        .foregroundColor(statusColor)

                    if !breakItem.durationString.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(breakItem.durationString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Notes (if any)
                if let notes = breakItem.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"

        let startString = formatter.string(from: breakItem.startDate)
        let endString = formatter.string(from: breakItem.endDate)

        let calendar = Calendar.current
        if calendar.isDate(breakItem.startDate, inSameDayAs: breakItem.endDate) {
            return startString
        } else {
            return "\(startString) - \(endString)"
        }
    }

    private var statusColor: Color {
        switch breakItem.status {
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

// MARK: - Breaks List ViewModel

@MainActor
final class BreaksListViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var activeBreak: Break?
    @Published private(set) var scheduledBreaks: [Break] = []
    @Published private(set) var pastBreaks: [Break] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Public Properties

    let authService: AuthService

    // MARK: - Computed Properties

    var allBreaks: [Break] {
        var all: [Break] = []
        if let active = activeBreak {
            all.append(active)
        }
        all.append(contentsOf: scheduledBreaks)
        all.append(contentsOf: pastBreaks)
        return all
    }

    // MARK: - Private Properties

    private let breakService: BreakService

    // MARK: - Initialization

    init(
        authService: AuthService,
        breakService: BreakService? = nil
    ) {
        self.authService = authService
        self.breakService = breakService ?? BreakService.shared
    }

    // MARK: - Data Loading

    func loadBreaks() async {
        guard let userId = authService.currentPruufUser?.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await breakService.fetchAllBreaks(senderId: userId)
            activeBreak = breakService.activeBreak
            scheduledBreaks = breakService.scheduledBreaks
            pastBreaks = breakService.breakHistory
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BreaksListView_Previews: PreviewProvider {
    static var previews: some View {
        BreaksListView(authService: AuthService())
    }
}
#endif
