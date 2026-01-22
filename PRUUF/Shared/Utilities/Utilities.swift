import Foundation
import Combine
import UIKit

// MARK: - App Constants

enum AppConstants {
    /// App bundle identifier
    static let bundleId = "com.pruuf.ios"

    /// App URL scheme for deep linking
    static let urlScheme = "pruuf"

    /// Supabase callback URL
    static let authCallbackURL = URL(string: "pruuf://auth/callback")!

    /// Maximum connections for free tier
    static let freeConnectionLimit = 1

    /// Maximum connections for basic tier
    static let basicConnectionLimit = 3

    /// Maximum connections for premium tier
    static let premiumConnectionLimit = 10

    /// Default ping window duration in minutes
    static let defaultPingWindowMinutes = 30

    /// Verification code expiration time in seconds
    static let verificationCodeExpirationSeconds = 600 // 10 minutes

    /// Maximum verification code resend attempts
    static let maxVerificationCodeResendAttempts = 3

    /// Debounce delay for search in milliseconds
    static let searchDebounceMilliseconds = 300
}

// MARK: - Logger

enum Logger {
    /// Log levels
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// Log a message with level
    static func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function): \(message)")
        #endif
    }

    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}

// MARK: - Debouncer

/// Utility for debouncing rapid function calls
final class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let workItem = DispatchWorkItem(block: action)
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// MARK: - Validation

enum Validation {
    /// Validate phone number
    static func isValidPhoneNumber(_ phone: String) -> Bool {
        let phoneRegex = "^\\+[1-9]\\d{6,14}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return predicate.evaluate(with: phone)
    }

    /// Validate verification code (6-digit numeric code)
    static func isValidVerificationCode(_ code: String) -> Bool {
        let codeRegex = "^\\d{6}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", codeRegex)
        return predicate.evaluate(with: code)
    }

    /// Backward compatibility alias for isValidVerificationCode
    @available(*, deprecated, renamed: "isValidVerificationCode")
    static func isValidOTPCode(_ code: String) -> Bool {
        return isValidVerificationCode(code)
    }

    /// Validate display name
    static func isValidDisplayName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 50
    }
}

// MARK: - Haptics

enum Haptics {
    /// Trigger success haptic feedback
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Trigger error haptic feedback
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    /// Trigger warning haptic feedback
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// Trigger impact haptic feedback
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    /// Trigger selection haptic feedback
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - UserDefaults Keys

enum UserDefaultsKeys {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let lastPingReminderDate = "lastPingReminderDate"
    static let notificationsEnabled = "notificationsEnabled"
    static let hapticFeedbackEnabled = "hapticFeedbackEnabled"
    static let preferredPingTime = "preferredPingTime"
}
