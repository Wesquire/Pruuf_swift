import SwiftUI

// MARK: - Loading States & Empty States
// Section 4.5: Loading States & Empty States Implementation

// MARK: - Full Screen Loading

/// Full screen loading view with iOS spinner centered with blur background
/// Used for initial load states
struct FullScreenLoadingView: View {
    var message: String? = "Loading..."

    var body: some View {
        ZStack {
            // Blur background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // iOS native spinner
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.5)

                if let message = message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            )
        }
    }
}

/// View modifier to show full screen loading overlay with blur
struct FullScreenLoadingModifier: ViewModifier {
    let isLoading: Bool
    let message: String?

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
                .blur(radius: isLoading ? 2 : 0)

            if isLoading {
                ZStack {
                    // Semi-transparent overlay
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()

                    // Loading indicator
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.5)

                        if let message = message {
                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
    }
}

// MARK: - Skeleton Loading

/// Skeleton shimmer effect for loading states
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.4),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: phase * geometry.size.width * 2 - geometry.size.width)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// Skeleton placeholder view with shimmer effect
struct SkeletonView: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .modifier(ShimmerModifier())
    }
}

/// Skeleton card for loading sender/receiver cards
struct SkeletonCardView: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
                .modifier(ShimmerModifier())

            VStack(alignment: .leading, spacing: 8) {
                // Name skeleton
                SkeletonView(width: 120, height: 14)

                // Status skeleton
                SkeletonView(width: 180, height: 12)

                // Additional info skeleton
                SkeletonView(width: 100, height: 10)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

/// Skeleton for dashboard ping card
struct SkeletonPingCardView: View {
    var body: some View {
        VStack(spacing: 16) {
            // Icon skeleton
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 64, height: 64)
                .modifier(ShimmerModifier())

            // Title skeleton
            SkeletonView(width: 150, height: 20)

            // Subtitle skeleton
            SkeletonView(width: 100, height: 14)

            // Button skeleton
            SkeletonView(height: 50, cornerRadius: 12)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

/// Skeleton for activity/history calendar
struct SkeletonCalendarView: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { _ in
                VStack(spacing: 6) {
                    SkeletonView(width: 20, height: 10)

                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 12, height: 12)
                        .modifier(ShimmerModifier())

                    SkeletonView(width: 16, height: 12)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

/// Skeleton section for loading list sections
struct SkeletonSectionView: View {
    var title: String? = nil
    var cardCount: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    SkeletonView(width: 30, height: 20, cornerRadius: 10)
                }
            }

            ForEach(0..<cardCount, id: \.self) { _ in
                SkeletonCardView()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Empty States

/// Configuration for empty state views
struct EmptyStateConfiguration {
    let illustration: String // SF Symbol name
    let title: String
    let message: String
    let primaryButtonTitle: String?
    let primaryButtonAction: (() -> Void)?
    let secondaryButtonTitle: String?
    let secondaryButtonAction: (() -> Void)?

    init(
        illustration: String,
        title: String,
        message: String,
        primaryButtonTitle: String? = nil,
        primaryButtonAction: (() -> Void)? = nil,
        secondaryButtonTitle: String? = nil,
        secondaryButtonAction: (() -> Void)? = nil
    ) {
        self.illustration = illustration
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.primaryButtonAction = primaryButtonAction
        self.secondaryButtonTitle = secondaryButtonTitle
        self.secondaryButtonAction = secondaryButtonAction
    }
}

/// Generic empty state view
struct EmptyStateView: View {
    let config: EmptyStateConfiguration

    var body: some View {
        VStack(spacing: 20) {
            // Illustration
            Image(systemName: config.illustration)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            // Title
            Text(config.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Message
            Text(config.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Primary button
            if let primaryTitle = config.primaryButtonTitle,
               let primaryAction = config.primaryButtonAction {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }

            // Secondary button
            if let secondaryTitle = config.secondaryButtonTitle,
               let secondaryAction = config.secondaryButtonAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Specific Empty States

/// No Receivers empty state (for Sender)
struct NoReceiversEmptyState: View {
    let onInviteReceivers: () -> Void

    var body: some View {
        EmptyStateView(
            config: EmptyStateConfiguration(
                illustration: "tray",
                title: "No receivers yet",
                message: "Invite people to give them peace of mind",
                primaryButtonTitle: "Invite Receivers",
                primaryButtonAction: onInviteReceivers
            )
        )
    }
}

/// No Senders empty state (for Receiver)
struct NoSendersEmptyState: View {
    let uniqueCode: String
    let onCopyCode: () -> Void
    let onShareCode: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Illustration - waiting figure
            Image(systemName: "figure.stand")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            // Title
            Text("No senders yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Message with code
            VStack(spacing: 8) {
                Text("Share your code:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(uniqueCode)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .kerning(4)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onCopyCode) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline)
                        Text("Copy Code")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
                }

                Button(action: onShareCode) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                        Text("Share Code")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// No Activity empty state
struct NoActivityEmptyState: View {
    var body: some View {
        EmptyStateView(
            config: EmptyStateConfiguration(
                illustration: "calendar",
                title: "No activity yet",
                message: "Your ping history will appear here"
            )
        )
    }
}

/// Network Error empty state
struct NetworkErrorEmptyState: View {
    let onRetry: () -> Void

    var body: some View {
        EmptyStateView(
            config: EmptyStateConfiguration(
                illustration: "wifi.slash",
                title: "Connection lost",
                message: "Check your internet and try again",
                primaryButtonTitle: "Retry",
                primaryButtonAction: onRetry
            )
        )
    }
}

/// Generic error state with retry
struct ErrorStateView: View {
    let message: String
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.red)
                .padding(.bottom, 8)

            Text("Something went wrong")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Content State Enum

/// Enum to represent different content loading states
enum ContentState<T> {
    case loading
    case loaded(T)
    case empty
    case error(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var data: T? {
        if case .loaded(let data) = self { return data }
        return nil
    }

    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

// MARK: - View Extensions

extension View {
    /// Apply full screen loading overlay with blur
    func fullScreenLoading(isLoading: Bool, message: String? = nil) -> some View {
        modifier(FullScreenLoadingModifier(isLoading: isLoading, message: message))
    }

    /// Apply shimmer effect for skeleton loading
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Pull to Refresh Helper

/// Wrapper view that adds pull to refresh capability
struct RefreshableScrollView<Content: View>: View {
    let onRefresh: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
        }
        .refreshable {
            await onRefresh()
        }
    }
}

// MARK: - Inline Loading Indicator

/// Inline loading indicator for card content
struct InlineLoadingView: View {
    var message: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())

            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Preview

#if DEBUG
struct LoadingStates_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Full Screen Loading
            FullScreenLoadingView()
                .previewDisplayName("Full Screen Loading")

            // Skeleton Card
            VStack(spacing: 16) {
                SkeletonPingCardView()
                SkeletonCardView()
                SkeletonCardView()
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .previewDisplayName("Skeleton Cards")

            // Empty States
            ScrollView {
                VStack(spacing: 32) {
                    NoReceiversEmptyState(onInviteReceivers: {})
                        .background(Color(.systemBackground))
                        .cornerRadius(16)

                    NoSendersEmptyState(
                        uniqueCode: "123456",
                        onCopyCode: {},
                        onShareCode: {}
                    )
                    .background(Color(.systemBackground))
                    .cornerRadius(16)

                    NoActivityEmptyState()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)

                    NetworkErrorEmptyState(onRetry: {})
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .previewDisplayName("Empty States")
        }
    }
}
#endif
