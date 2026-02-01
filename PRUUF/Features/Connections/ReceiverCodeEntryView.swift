import SwiftUI

// MARK: - Receiver Code Entry View

/// Modal view for when a sender receives a code from someone
/// who wants to become one of their receivers
/// This handles the "reverse" connection flow
struct ReceiverCodeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AddConnectionViewModel
    @FocusState private var isCodeFieldFocused: Bool

    init(authService: AuthService) {
        _viewModel = StateObject(wrappedValue: AddConnectionViewModel(authService: authService))
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.connectionState == .success {
                    successView
                } else {
                    mainContent
                }
            }
            .navigationTitle("Enter Received Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            viewModel.checkClipboardForCode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isCodeFieldFocused = true
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 24) {
            // Explanation Header
            VStack(spacing: 12) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.purple)

                Text("Someone Shared Their Code?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("If someone wants you to be their Pruuf receiver, they may have shared their unique code with you. Enter it below to connect.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.top, 24)

            // Code Entry Field
            codeEntrySection

            // Clipboard Button (if code detected)
            if viewModel.clipboardCode != nil {
                clipboardButton
            }

            // Connect Button
            connectButton

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Code Entry Section

    private var codeEntrySection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    digitBox(at: index)
                }
            }

            // Hidden TextField for input
            TextField("", text: $viewModel.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFieldFocused)
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .onChange(of: viewModel.code) { newValue in
                    // Limit to 6 digits
                    if newValue.count > 6 {
                        viewModel.code = String(newValue.prefix(6))
                    }
                    // Filter non-numeric characters
                    viewModel.code = newValue.filter { $0.isNumber }
                }

            if viewModel.connectionState == .invalidCode {
                Text("Invalid code. Please check and try again.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .onTapGesture {
            isCodeFieldFocused = true
        }
    }

    // MARK: - Digit Box

    private func digitBox(at index: Int) -> some View {
        let digit = viewModel.digitAt(index: index)
        let isActive = viewModel.code.count == index

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 48, height: 56)

            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.purple : Color.clear, lineWidth: 2)
                .frame(width: 48, height: 56)

            Text(digit)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Clipboard Button

    private var clipboardButton: some View {
        Button {
            if let code = viewModel.clipboardCode {
                viewModel.code = code
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                Text("Paste from clipboard")
            }
            .font(.subheadline)
            .foregroundColor(.purple)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(20)
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            Task {
                await viewModel.connect()
            }
        } label: {
            HStack {
                if viewModel.connectionState == .connecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                } else {
                    Text("Connect")
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(viewModel.canConnect ? Color.purple : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!viewModel.canConnect)
        .padding(.top, 8)
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("Connected!")
                    .font(.title)
                    .fontWeight(.bold)

                if let name = viewModel.connectedReceiverName {
                    Text("You're now connected with \(name)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Connection established successfully")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
