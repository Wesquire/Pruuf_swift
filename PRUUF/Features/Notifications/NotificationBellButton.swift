import SwiftUI

// MARK: - Notification Bell Button

/// Bell icon button with badge count for accessing the notification center
/// Used in dashboard headers
struct NotificationBellButton: View {
    @ObservedObject private var store = InAppNotificationStore.shared
    @EnvironmentObject private var authService: AuthService

    @Binding var showNotificationCenter: Bool

    var body: some View {
        Button {
            showNotificationCenter = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)

                // Badge
                if store.unreadCount > 0 {
                    badgeView
                }
            }
        }
        .accessibilityLabel("Notifications, \(store.unreadCount) unread")
        .task {
            // Refresh unread count when component appears
            guard let userId = authService.currentPruufUser?.id else { return }
            await store.refreshUnreadCount(userId: userId)
        }
    }

    // MARK: - Badge View

    private var badgeView: some View {
        Group {
            if store.unreadCount <= 99 {
                Text("\(store.unreadCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, store.unreadCount < 10 ? 5 : 4)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .offset(x: 8, y: -8)
            } else {
                Text("99+")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .offset(x: 10, y: -8)
            }
        }
    }
}

// MARK: - Notification Bell Simple

/// Simplified bell button without the @EnvironmentObject dependency
/// For use in contexts where authService might not be available
struct NotificationBellSimple: View {
    @ObservedObject private var store = InAppNotificationStore.shared
    let userId: UUID
    @Binding var showNotificationCenter: Bool

    var body: some View {
        Button {
            showNotificationCenter = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)

                // Badge
                if store.unreadCount > 0 {
                    badgeView
                }
            }
        }
        .accessibilityLabel("Notifications, \(store.unreadCount) unread")
        .task {
            await store.refreshUnreadCount(userId: userId)
        }
    }

    private var badgeView: some View {
        Group {
            if store.unreadCount <= 99 {
                Text("\(store.unreadCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, store.unreadCount < 10 ? 5 : 4)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .offset(x: 8, y: -8)
            } else {
                Text("99+")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .offset(x: 10, y: -8)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NotificationBellButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            // With unread count
            NotificationBellButton(showNotificationCenter: .constant(false))
                .environmentObject(AuthService())

            // Simple version
            NotificationBellSimple(
                userId: UUID(),
                showNotificationCenter: .constant(false)
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
