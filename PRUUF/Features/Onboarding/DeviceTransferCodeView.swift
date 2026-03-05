import SwiftUI

// MARK: - Device Transfer Code View

/// View for setting up a 4-digit device transfer PIN during onboarding
/// Users enter the PIN twice to confirm, then it's saved for account recovery on new devices
struct DeviceTransferCodeView: View {
    @EnvironmentObject private var authService: AuthService

    let onComplete: () -> Void

    @State private var firstEntry: String = ""
    @State private var confirmEntry: String = ""
    @State private var isConfirmPhase: Bool = false
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    @FocusState private var isFirstFocused: Bool
    @FocusState private var isConfirmFocused: Bool

    private let pinLength = 4

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Header
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Set Your Transfer PIN")
                    .font(.title.bold())

                Text(isConfirmPhase
                    ? "Enter your PIN again to confirm"
                    : "This 4-digit PIN will let you recover your account on a new device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // PIN Input
            VStack(spacing: 20) {
                if isConfirmPhase {
                    // Confirm phase
                    PINInputView(code: $confirmEntry, length: pinLength, isSecure: true)
                        .focused($isConfirmFocused)
                        .onChange(of: confirmEntry) { newValue in
                            errorMessage = nil
                            if newValue.count == pinLength {
                                validateAndSave()
                            }
                        }
                } else {
                    // First entry phase
                    PINInputView(code: $firstEntry, length: pinLength, isSecure: true)
                        .focused($isFirstFocused)
                        .onChange(of: firstEntry) { newValue in
                            errorMessage = nil
                            if newValue.count == pinLength {
                                // Auto-advance to confirm phase
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isConfirmPhase = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    isConfirmFocused = true
                                }
                            }
                        }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                // Step indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConfirmPhase ? Color.blue.opacity(0.3) : Color.blue)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(isConfirmPhase ? Color.blue : Color.blue.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                if isConfirmPhase {
                    Button {
                        // Go back to first entry
                        withAnimation {
                            isConfirmPhase = false
                            confirmEntry = ""
                            firstEntry = ""
                            errorMessage = nil
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isFirstFocused = true
                        }
                    } label: {
                        Text("Start Over")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }

                Button {
                    if isConfirmPhase {
                        validateAndSave()
                    }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text(isConfirmPhase ? "Confirm PIN" : "Enter 4 digits above")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canConfirm ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(!canConfirm || isSaving)
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFirstFocused = true
            }
        }
    }

    // MARK: - Computed Properties

    private var canConfirm: Bool {
        isConfirmPhase && confirmEntry.count == pinLength
    }

    // MARK: - Methods

    private func validateAndSave() {
        guard firstEntry == confirmEntry else {
            errorMessage = "PINs don't match. Please try again."
            confirmEntry = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isConfirmFocused = true
            }
            return
        }

        isSaving = true
        Task {
            do {
                guard let userId = authService.currentPruufUser?.id ?? authService.currentUser?.id else {
                    errorMessage = "Unable to save PIN. Please try again."
                    isSaving = false
                    return
                }

                // Save to database
                let database = SupabaseConfig.client.schema("public")
                let _: PruufUser = try await database
                    .from("users")
                    .update(["device_transfer_code": firstEntry])
                    .eq("id", value: userId.uuidString)
                    .select()
                    .single()
                    .execute()
                    .value

                isSaving = false
                onComplete()
            } catch {
                errorMessage = "Failed to save PIN: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

// MARK: - PIN Input View

/// Custom PIN input with individual digit boxes (secure/masked)
struct PINInputView: View {
    @Binding var code: String
    let length: Int
    var isSecure: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden text field for keyboard input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .opacity(0)
                .onChange(of: code) { newValue in
                    let filtered = String(newValue.filter { $0.isNumber }.prefix(length))
                    if filtered != newValue {
                        code = filtered
                    }
                }

            // Visual digit boxes
            HStack(spacing: 16) {
                ForEach(0..<length, id: \.self) { index in
                    PINDigitBox(
                        digit: getDigit(at: index),
                        isActive: index == code.count && isFocused,
                        isFilled: index < code.count,
                        isSecure: isSecure
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

// MARK: - PIN Digit Box

/// Individual digit box for the PIN input
struct PINDigitBox: View {
    let digit: String
    let isActive: Bool
    let isFilled: Bool
    var isSecure: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.blue : Color(.systemGray4), lineWidth: isActive ? 2 : 1)
                .frame(width: 56, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )

            if isFilled {
                if isSecure {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 14, height: 14)
                } else {
                    Text(digit)
                        .font(.title.bold().monospacedDigit())
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: isFilled)
    }
}
