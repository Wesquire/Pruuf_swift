import SwiftUI

// MARK: - Authentication Feature

/// Authentication feature namespace containing views and view models
/// for the phone number + APNs push verification flow
/// Note: This implementation uses APNs push notifications for verification instead of SMS
enum AuthenticationFeature {
    // Views:
    // - PhoneNumberEntryView
    // - VerificationCodeView (replaces OTPVerificationView)
    // - AuthenticationCoordinatorView
}

// MARK: - Authentication Coordinator View

/// Coordinates the authentication flow based on current auth state
/// Routes between phone entry, verification, onboarding, and main app
struct AuthenticationCoordinatorView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var notificationService: NotificationService

    var body: some View {
        Group {
            switch authService.authState {
            case .unknown, .loading:
                LoadingView()

            case .unauthenticated:
                NavigationView {
                    PhoneNumberEntryView()
                }
                .navigationViewStyle(.stack)

            case .verifying:
                NavigationView {
                    VerificationCodeView(phoneNumber: authService.pendingVerificationPhone ?? "")
                }
                .navigationViewStyle(.stack)

            case .needsOnboarding:
                // Redirect to Role Selection (Onboarding)
                OnboardingCoordinatorView()

            case .authenticated:
                // Redirect to Dashboard
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.authState)
    }
}

// MARK: - Loading View

/// Simple loading view shown during session check
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Text("PRUUF")
                .font(.largeTitle.bold())

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)

            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Phone Number Entry View

/// First screen of authentication - user enters their phone number
/// Verification code is sent via APNs push notification
struct PhoneNumberEntryView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var notificationService: NotificationService
    @State private var phoneNumber: String = ""
    @State private var countryCode: String = "+1"
    @State private var showVerificationView: Bool = false
    @State private var errorMessage: String?
    @State private var isValidPhoneNumber: Bool = false
    @State private var showPermissionAlert: Bool = false

    /// Combined full phone number with country code
    private var fullPhoneNumber: String {
        countryCode + phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo and title
            VStack(spacing: 16) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                Text("PRUUF")
                    .font(.largeTitle.bold())

                Text("Proof of life, peace of mind")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Phone number input section
            VStack(spacing: 20) {
                Text("Enter your phone number")
                    .font(.headline)

                Text("We'll send you a verification code via notification")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    // Country code picker
                    CountryCodePicker(selectedCode: $countryCode)

                    // Phone number text field
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.title3)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .onChange(of: phoneNumber) { newValue in
                            validatePhoneNumber(newValue)
                        }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Continue button
            Button {
                Task {
                    await startVerification()
                }
            } label: {
                HStack {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isValidPhoneNumber ? Color.blue : Color.gray)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(!isValidPhoneNumber || authService.isLoading)
            .padding(.horizontal)
            .padding(.bottom, 32)

            // Hidden NavigationLink for programmatic navigation
            NavigationLink(
                destination: VerificationCodeView(phoneNumber: fullPhoneNumber),
                isActive: $showVerificationView
            ) {
                EmptyView()
            }
            .hidden()
        }
        .alert("Enable Notifications", isPresented: $showPermissionAlert) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Push notifications are required for verification. Please enable them in Settings.")
        }
    }

    // MARK: - Private Methods

    private func validatePhoneNumber(_ number: String) {
        let digitsOnly = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        // Basic validation: at least 10 digits for US numbers
        isValidPhoneNumber = digitsOnly.count >= 10
    }

    private func startVerification() async {
        errorMessage = nil

        // Get device token or use placeholder for DEBUG testing
        var deviceToken = notificationService.deviceToken

        #if DEBUG
        // In DEBUG mode, allow testing without a real device token
        // The verification code will be logged to console instead
        if deviceToken == nil {
            #if targetEnvironment(simulator)
            deviceToken = "SIMULATOR_TOKEN"
            #else
            // On real device in DEBUG mode, request permission but use placeholder if unavailable
            await notificationService.requestPermission()
            // Wait a moment for the token to be set
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            if notificationService.deviceToken == nil {
                // Use placeholder token for DEBUG testing
                // This allows testing on devices without working APNs provisioning
                deviceToken = "DEBUG_DEVICE_TOKEN"
                print("========================================")
                print("DEBUG: Using placeholder device token")
                print("Push notifications may not work without proper provisioning")
                print("========================================")
            } else {
                deviceToken = notificationService.deviceToken
            }
            #endif
        }
        #else
        // RELEASE mode - require actual device token
        if deviceToken == nil {
            // Request notification permission first
            await notificationService.requestPermission()
            // Wait a moment for the token to be set
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            if notificationService.deviceToken == nil {
                showPermissionAlert = true
                return
            }
            deviceToken = notificationService.deviceToken
        }
        #endif

        guard let token = deviceToken else {
            showPermissionAlert = true
            return
        }

        do {
            try await authService.startPhoneVerification(
                phoneNumber: fullPhoneNumber,
                deviceToken: token
            )
            showVerificationView = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Country Code Picker

/// Simple country code picker for phone number entry
struct CountryCodePicker: View {
    @Binding var selectedCode: String

    private let countryCodes = [
        ("+1", "🇺🇸", "US"),
        ("+44", "🇬🇧", "UK"),
        ("+61", "🇦🇺", "AU"),
        ("+81", "🇯🇵", "JP"),
        ("+86", "🇨🇳", "CN"),
        ("+91", "🇮🇳", "IN"),
        ("+49", "🇩🇪", "DE"),
        ("+33", "🇫🇷", "FR"),
        ("+55", "🇧🇷", "BR"),
        ("+52", "🇲🇽", "MX")
    ]

    var body: some View {
        Menu {
            ForEach(countryCodes, id: \.0) { code, flag, name in
                Button {
                    selectedCode = code
                } label: {
                    Text("\(flag) \(code) (\(name))")
                }
            }
        } label: {
            HStack {
                Text(currentFlag)
                Text(selectedCode)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .foregroundStyle(.primary)
    }

    private var currentFlag: String {
        countryCodes.first { $0.0 == selectedCode }?.1 ?? "🌍"
    }
}

// MARK: - Verification Code View

/// Second screen of authentication - user enters the verification code from push notification
struct VerificationCodeView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var notificationService: NotificationService
    @Environment(\.dismiss) private var dismiss

    let phoneNumber: String

    @State private var verificationCode: String = ""
    @State private var errorMessage: String?
    @State private var resendCountdown: Int = 0
    @State private var resendTimer: Timer?
    @FocusState private var isCodeFieldFocused: Bool

    private let codeLength = 6

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Header
            VStack(spacing: 16) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Check Your Notifications")
                    .font(.title.bold())

                Text("Enter the 6-digit code from the notification sent to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(formattedPhoneNumber)
                    .font(.headline)
            }

            Spacer()

            // Verification Code Input
            VStack(spacing: 20) {
                VerificationCodeInputView(code: $verificationCode, length: codeLength)
                    .focused($isCodeFieldFocused)

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            // Resend code button
            VStack(spacing: 16) {
                if resendCountdown > 0 {
                    Text("Resend code in \(resendCountdown)s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Resend Code") {
                        Task {
                            await resendCode()
                        }
                    }
                    .font(.subheadline)
                    .disabled(authService.isLoading)
                }

                // Verify button
                Button {
                    Task {
                        await verifyCode()
                    }
                } label: {
                    HStack {
                        if authService.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Verify")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(verificationCode.count == codeLength ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(verificationCode.count != codeLength || authService.isLoading)
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
        .navigationBarBackButtonHidden(authService.isLoading)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !authService.isLoading {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
        .onAppear {
            startResendCountdown()
            isCodeFieldFocused = true
        }
        .onDisappear {
            resendTimer?.invalidate()
        }
    }

    // MARK: - Private Methods

    private var formattedPhoneNumber: String {
        // Format phone number for display (e.g., +1 (555) 123-4567)
        phoneNumber
    }

    private func startResendCountdown() {
        resendCountdown = 60
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                resendTimer?.invalidate()
            }
        }
    }

    private func verifyCode() async {
        errorMessage = nil

        do {
            try await authService.verifyPhoneCode(verificationCode)
            // Navigation is handled automatically by AuthenticationCoordinatorView
            // based on authState changes
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resendCode() async {
        errorMessage = nil

        guard let deviceToken = notificationService.deviceToken else {
            errorMessage = "Push notifications are required for verification"
            return
        }

        do {
            try await authService.resendVerificationCode(deviceToken: deviceToken)
            startResendCountdown()
        } catch {
            errorMessage = "Failed to resend code. Please try again."
        }
    }
}

// MARK: - Verification Code Input View

/// Custom verification code input with individual digit boxes
struct VerificationCodeInputView: View {
    @Binding var code: String
    let length: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden text field for keyboard input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0)
                .onChange(of: code) { newValue in
                    // Limit to code length and digits only
                    let filtered = String(newValue.filter { $0.isNumber }.prefix(length))
                    if filtered != newValue {
                        code = filtered
                    }
                }

            // Visual digit boxes
            HStack(spacing: 12) {
                ForEach(0..<length, id: \.self) { index in
                    CodeDigitBox(
                        digit: getDigit(at: index),
                        isActive: index == code.count && isFocused
                    )
                }
            }
            .onTapGesture {
                isFocused = true
            }
        }
    }

    private func getDigit(at index: Int) -> String {
        guard index < code.count else { return "" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }
}

/// Individual digit box in the verification code input
struct CodeDigitBox: View {
    let digit: String
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.blue : Color(.systemGray4), lineWidth: isActive ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .frame(width: 48, height: 56)

            Text(digit)
                .font(.title)
                .fontWeight(.semibold)
        }
    }
}

// Note: OnboardingCoordinatorView is now implemented in OnboardingFeature.swift (Section 3.2)
