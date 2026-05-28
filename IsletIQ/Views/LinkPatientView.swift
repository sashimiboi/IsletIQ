import SwiftUI

struct LinkPatientView: View {
    @Environment(\.dismiss) private var dismiss
    let onLinked: () -> Void

    @State private var email: String = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var successText: String?
    private let client = RosterClient()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.primary)
                            .padding(.top, 24)
                        Text("Link a patient to your roster")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Enter the email of an existing IsletIQ patient. They'll appear in your roster immediately. In a future release the patient will need to confirm consent before data syncs.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Patient email")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        TextField("patient@example.com", text: $email)
                            .textContentType(.emailAddress)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 8)

                    if let errorText {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.high)
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(Theme.high)
                        }
                    }
                    if let successText {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.normal)
                            Text(successText)
                                .font(.caption)
                                .foregroundStyle(Theme.normal)
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text(isSubmitting ? "Linking..." : "Link Patient")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? Theme.primary : Theme.textTertiary, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationTitle("Add Patient")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !isSubmitting && email.contains("@") && email.contains(".")
    }

    private func submit() async {
        isSubmitting = true
        errorText = nil
        successText = nil
        let result = await client.linkPatient(email: email.trimmingCharacters(in: .whitespaces))
        await MainActor.run {
            isSubmitting = false
            if result.success {
                successText = "Linked. Closing..."
                onLinked()
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    await MainActor.run { dismiss() }
                }
            } else {
                errorText = result.error ?? "Couldn't link patient"
            }
        }
    }
}
