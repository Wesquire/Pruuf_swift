import SwiftUI

// MARK: - Shared UI Components
// Reusable UI components used across the app

/// Primary action button with consistent styling
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isDisabled ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isDisabled || isLoading)
    }
}

/// Secondary action button with outline style
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.clear)
                .foregroundColor(isDisabled ? .gray : .blue)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDisabled ? Color.gray : Color.blue, lineWidth: 2)
                )
        }
        .disabled(isDisabled)
    }
}

/// Loading overlay view
struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text(message)
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
            .padding(24)
            .background(Color(.systemGray5).opacity(0.9))
            .cornerRadius(16)
        }
    }
}

/// Error banner view
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

/// Avatar image view with placeholder
struct AvatarView: View {
    let imageURL: URL?
    let size: CGFloat
    let initials: String

    var body: some View {
        Group {
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        initialsView
                    case .empty:
                        ProgressView()
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.2))
            Text(initials)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(.blue)
        }
    }
}
