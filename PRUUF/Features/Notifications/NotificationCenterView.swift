import SwiftUI

// MARK: - Notification Center View

/// In-app notification center showing the last 30 days of notifications
/// Supports mark as read, delete, and navigation to relevant screens
struct NotificationCenterView: View {
    @StateObject private var store = InAppNotificationStore.shared
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedNotifications: Set<UUID> = []
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var notificationToDelete: PruufNotification?

    var body: some View {
        NavigationView {
            ZStack {
                if store.isLoading && store.notifications.isEmpty {
                    ProgressView("Loading notifications...")
                } else if store.notifications.isEmpty {
                    emptyStateView
                } else {
                    notificationListView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.notifications.isEmpty {
                        Menu {
                            if store.unreadCount > 0 {
                                Button {
                                    Task {
                                        guard let userId = authService.currentPruufUser?.id else { return }
                                        _ = await store.markAllAsRead(userId: userId)
                                    }
                                } label: {
                                    Label("Mark All as Read", systemImage: "checkmark.circle")
                                }
                            }

                            Button {
                                withAnimation {
                                    isEditing.toggle()
                                    if !isEditing {
                                        selectedNotifications.removeAll()
                                    }
                                }
                            } label: {
                                Label(isEditing ? "Done Editing" : "Select", systemImage: isEditing ? "checkmark" : "checklist")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Delete Notification?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    notificationToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let notification = notificationToDelete {
                        Task {
                            guard let userId = authService.currentPruufUser?.id else { return }
                            _ = await store.deleteNotification(notificationId: notification.id, userId: userId)
                            notificationToDelete = nil
                        }
                    }
                }
            } message: {
                Text("This notification will be permanently deleted.")
            }
        }
        .task {
            guard let userId = authService.currentPruufUser?.id else { return }
            await store.fetchNotifications(userId: userId, forceRefresh: true)
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Notifications")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You haven't received any notifications\nin the last 30 days.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Notification List View

    private var notificationListView: some View {
        VStack(spacing: 0) {
            // Edit mode toolbar
            if isEditing && !selectedNotifications.isEmpty {
                editToolbar
            }

            List {
                // Group notifications by date
                ForEach(groupedNotifications.keys.sorted(by: >), id: \.self) { date in
                    Section(header: Text(formatSectionDate(date))) {
                        ForEach(groupedNotifications[date] ?? []) { notification in
                            NotificationRowView(
                                notification: notification,
                                isEditing: isEditing,
                                isSelected: selectedNotifications.contains(notification.id),
                                onTap: {
                                    handleNotificationTap(notification)
                                },
                                onToggleSelection: {
                                    toggleSelection(notification.id)
                                },
                                onDelete: {
                                    notificationToDelete = notification
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                guard let userId = authService.currentPruufUser?.id else { return }
                await store.fetchNotifications(userId: userId, forceRefresh: true)
            }
        }
    }

    // MARK: - Edit Toolbar

    private var editToolbar: some View {
        HStack {
            Button("Deselect All") {
                selectedNotifications.removeAll()
            }
            .font(.subheadline)

            Spacer()

            Text("\(selectedNotifications.count) selected")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button(role: .destructive) {
                Task {
                    guard let userId = authService.currentPruufUser?.id else { return }
                    _ = await store.deleteNotifications(
                        notificationIds: Array(selectedNotifications),
                        userId: userId
                    )
                    selectedNotifications.removeAll()
                    isEditing = false
                }
            } label: {
                Text("Delete")
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Helpers

    /// Group notifications by date (day)
    private var groupedNotifications: [Date: [PruufNotification]] {
        Dictionary(grouping: store.notifications) { notification in
            Calendar.current.startOfDay(for: notification.sentAt)
        }
    }

    /// Format section date header
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day,
                  daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Full day name
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    /// Handle notification tap
    private func handleNotificationTap(_ notification: PruufNotification) {
        if isEditing {
            toggleSelection(notification.id)
        } else {
            // Mark as read if unread
            if !notification.isRead {
                Task {
                    guard let userId = authService.currentPruufUser?.id else { return }
                    _ = await store.markAsRead(notificationId: notification.id, userId: userId)
                }
            }

            // Navigate to destination
            store.navigateToDestination(for: notification)
            dismiss()
        }
    }

    /// Toggle selection for edit mode
    private func toggleSelection(_ notificationId: UUID) {
        if selectedNotifications.contains(notificationId) {
            selectedNotifications.remove(notificationId)
        } else {
            selectedNotifications.insert(notificationId)
        }
    }
}

// MARK: - Notification Row View

/// Individual notification row in the list
struct NotificationRowView: View {
    let notification: PruufNotification
    let isEditing: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onToggleSelection: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection checkbox in edit mode
                if isEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .onTapGesture {
                            onToggleSelection()
                        }
                }

                // Notification icon
                notificationIcon

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.title)
                            .font(.subheadline)
                            .fontWeight(notification.isRead ? .regular : .semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(notification.timeSince)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(notification.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Unread indicator
                if !notification.isRead && !isEditing {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !notification.isRead {
                Button {
                    onTap() // Will mark as read
                } label: {
                    Label("Read", systemImage: "checkmark")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Notification Icon

    private var notificationIcon: some View {
        Circle()
            .fill(iconBackgroundColor.opacity(0.15))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: notification.type.iconName)
                    .font(.headline)
                    .foregroundColor(iconBackgroundColor)
            )
    }

    private var iconBackgroundColor: Color {
        switch notification.type {
        case .pingReminder, .deadlineWarning, .deadlineFinal:
            return .blue
        case .missedPing:
            return .red
        case .pingCompletedOnTime:
            return .green
        case .pingCompletedLate:
            return .orange
        case .breakStarted, .breakNotification:
            return .purple
        case .connectionRequest:
            return .blue
        case .paymentReminder, .trialEnding:
            return .orange
        case .dataExportReady, .dataExportEmailSent:
            return .green
        case .pingTimeChanged:
            return .blue
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NotificationCenterView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationCenterView()
            .environmentObject(AuthService())
    }
}
#endif
