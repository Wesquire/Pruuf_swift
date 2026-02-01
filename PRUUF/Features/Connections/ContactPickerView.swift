import SwiftUI
import MessageUI

// MARK: - SMS Composer View

/// A SwiftUI wrapper for MFMessageComposeViewController
/// Sends invitation SMS to selected contacts
struct SMSComposerView: UIViewControllerRepresentable {

    /// Binding to control presentation
    @Binding var isPresented: Bool

    /// Recipients (phone numbers)
    let recipients: [String]

    /// The message body
    let messageBody: String

    /// Callback when SMS is sent or cancelled
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = messageBody
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: SMSComposerView

        init(_ parent: SMSComposerView) {
            self.parent = parent
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.isPresented = false
            parent.onComplete(result == .sent)
        }
    }

    // MARK: - Availability Check

    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }
}

// MARK: - Invite Receivers Flow View

/// Complete flow for inviting receivers via address book and SMS
struct InviteReceiversFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    @State private var selectedContacts: [SelectedContact] = []
    @State private var senderInvitationCode: String?
    @State private var connectedPhoneNumbers: Set<String> = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showContactPicker = true
    @State private var showSMSComposer = false
    @State private var showConfirmation = false

    private let invitationService: InvitationService

    init(authService: AuthService, invitationService: InvitationService = .shared) {
        self.invitationService = invitationService
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if showConfirmation {
                    confirmationView
                } else if !selectedContacts.isEmpty {
                    selectedContactsView
                }
            }
            .navigationTitle("Invite Receivers")
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
        .sheet(isPresented: $showContactPicker) {
            if selectedContacts.isEmpty {
                dismiss()
            }
        } content: {
            ContactPickerView(selectedContacts: $selectedContacts)
        }
        .sheet(isPresented: $showSMSComposer) {
            if SMSComposerView.canSendText {
                SMSComposerView(
                    isPresented: $showSMSComposer,
                    recipients: selectedContacts.map { $0.phoneNumber },
                    messageBody: invitationMessage,
                    onComplete: { success in
                        if success {
                            Task {
                                await createInvitationsForSelectedContacts()
                                showConfirmation = true
                            }
                        }
                    }
                )
            }
        }
        .task {
            await loadData()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Computed Properties

    private var invitationMessage: String {
        let senderName = authService.currentPruufUser?.displayName ?? "Someone"
        let code = senderInvitationCode ?? "------"
        return invitationService.generateInvitationMessage(senderName: senderName, code: code)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            Text("Loading...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Selected Contacts View

    private var selectedContactsView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)

                Text("Ready to Invite")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("You've selected \(selectedContacts.count) contact(s) to invite as receivers.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            // Contact List
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(selectedContacts) { contact in
                        contactRow(contact)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 200)

            // Your Code Section
            if let code = senderInvitationCode {
                VStack(spacing: 8) {
                    Text("Your Connection Code")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(code)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }

            // Message Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Message Preview")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(invitationMessage)
                    .font(.footnote)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 16)

            Spacer()

            // Send Button
            Button {
                if SMSComposerView.canSendText {
                    showSMSComposer = true
                } else {
                    errorMessage = "SMS is not available on this device."
                    showError = true
                }
            } label: {
                HStack {
                    Image(systemName: "message.fill")
                    Text("Send Invitation via SMS")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Add More Button
            Button {
                showContactPicker = true
            } label: {
                Text("Add More Contacts")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Contact Row

    private func contactRow(_ contact: SelectedContact) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(contact.phoneNumber)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                selectedContacts.removeAll { $0.id == contact.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("Invitations Sent!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Your invitation was sent to \(selectedContacts.count) contact(s).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("They'll appear in your receivers list once they accept.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
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
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        guard let userId = authService.currentUser?.id else { return }

        // Load sender's invitation code
        await loadSenderInvitationCode(userId: userId)

        // Load already connected phone numbers
        await loadConnectedPhoneNumbers(userId: userId)
    }

    private func loadSenderInvitationCode(userId: UUID) async {
        do {
            let response: [SenderProfileCodeResponse] = try await SupabaseConfig.client.schema("public")
                .from("sender_profiles")
                .select("invitation_code")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            senderInvitationCode = response.first?.invitationCode
        } catch {
            print("Failed to load sender invitation code: \(error)")
        }
    }

    private func loadConnectedPhoneNumbers(userId: UUID) async {
        do {
            let connections: [ConnectionWithReceiverPhone] = try await SupabaseConfig.client.schema("public")
                .from("connections")
                .select("receiver:receiver_id(phone_number)")
                .eq("sender_id", value: userId.uuidString)
                .execute()
                .value

            let phoneNumbers = connections.compactMap { $0.receiver?.phoneNumber }
            connectedPhoneNumbers = Set(phoneNumbers)
        } catch {
            print("Failed to load connected phone numbers: \(error)")
        }
    }

    // MARK: - Create Invitations

    private func createInvitationsForSelectedContacts() async {
        guard let userId = authService.currentUser?.id else { return }

        isLoading = true
        defer { isLoading = false }

        for contact in selectedContacts {
            do {
                _ = try await invitationService.createInvitation(
                    senderId: userId,
                    recipientPhoneNumber: contact.phoneNumber,
                    recipientName: contact.name
                )
            } catch {
                print("Failed to create invitation for \(contact.name): \(error)")
            }
        }
    }
}

// MARK: - Helper Models

private struct SenderProfileCodeResponse: Codable {
    let invitationCode: String?

    enum CodingKeys: String, CodingKey {
        case invitationCode = "invitation_code"
    }
}

private struct ConnectionWithReceiverPhone: Codable {
    let receiver: ReceiverPhoneInfo?

    struct ReceiverPhoneInfo: Codable {
        let phoneNumber: String?

        enum CodingKeys: String, CodingKey {
            case phoneNumber = "phone_number"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct InviteReceiversFlowView_Previews: PreviewProvider {
    static var previews: some View {
        InviteReceiversFlowView(authService: AuthService())
    }
}
#endif
