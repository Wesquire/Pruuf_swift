import SwiftUI

// MARK: - Sender Code Badge

/// A reusable collapsible component that displays the sender's unique invitation code
/// Per Plan 4 Requirement 2: Sender's unique code should be visible on all screens
/// where sender selects receivers
struct SenderCodeBadge: View {
    /// The sender's 6-digit invitation code
    let code: String?

    /// Whether the badge is expanded to show the full code
    @State private var isExpanded: Bool = false

    /// Whether the "copied" toast should be shown
    @State private var showCopied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let code = code {
                DisclosureGroup(
                    isExpanded: $isExpanded,
                    content: {
                        expandedContent(code: code)
                    },
                    label: {
                        collapsedLabel
                    }
                )
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .overlay(
            // Toast for copied confirmation
            Group {
                if showCopied {
                    VStack {
                        Text("Code copied!")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(6)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showCopied)
        )
    }

    // MARK: - Collapsed Label

    private var collapsedLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.subheadline)
                .foregroundColor(.blue)

            Text("My Connection Code")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Expanded Content

    private func expandedContent(code: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Code display with copy button
            HStack {
                Text(code)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .tracking(4)

                Spacer()

                Button {
                    copyCode(code)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .padding(.top, 8)

            // Explanatory text
            Text("Share this code with people who want to receive your daily Pruuf. They'll enter it in their app to connect with you.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Show toast
        showCopied = true

        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SenderCodeBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SenderCodeBadge(code: "123456")
            SenderCodeBadge(code: nil)
        }
        .padding()
    }
}
#endif
