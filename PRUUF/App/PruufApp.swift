import SwiftUI

/// Main entry point for the PRUUF iOS application
/// Configures app-wide settings and handles deep linking for authentication
@main
struct PruufApp: App {

    // MARK: - App Delegate

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - State Objects

    @StateObject private var authService = AuthService()
    @StateObject private var notificationService = NotificationService()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(notificationService)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    // MARK: - Deep Link Handling

    /// Handle incoming deep links for authentication callbacks
    /// - Parameter url: The URL that triggered the app opening
    private func handleDeepLink(_ url: URL) {
        // Handle Supabase auth callback (e.g., pruuf://auth/callback)
        guard url.scheme == "pruuf" else { return }

        Task {
            do {
                try await SupabaseConfig.auth.session(from: url)
            } catch {
                print("Error handling auth callback: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Content View

/// Root content view that displays appropriate screen based on auth state
/// Uses AuthenticationCoordinatorView for routing between:
/// - Unauthenticated: Phone Number Entry → OTP Verification
/// - Needs Onboarding: Role Selection → Role-specific onboarding
/// - Authenticated: Dashboard (MainTabView)
struct ContentView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        AuthenticationCoordinatorView()
    }
}

// MARK: - Note
// MainTabView is now defined in DashboardFeature.swift
// Placeholder views removed - using real implementations from Features modules
