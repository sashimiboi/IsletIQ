import SwiftUI

struct TidepoolLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var success = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "drop.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.primary)
                    .padding(.top, 20)

                Text("Tidepool")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Sign in with your Tidepool account")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)

                Text("Tidepool supports 85+ devices including Dexcom, Libre, Tandem, Medtronic, and Omnipod")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .padding(14)
                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(14)
                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.high)
                        .padding(.horizontal, 24)
                }

                if success {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.normal)
                        Text("Connected successfully")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.normal)
                    }
                }

                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        }
                        Text(isLoading ? "Connecting..." : "Connect")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(email.isEmpty || password.isEmpty ? Theme.textTertiary : Theme.primary,
                               in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .padding(.horizontal, 24)

                Spacer()
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func connect() async {
        isLoading = true
        error = nil
        let client = TidepoolClient()
        do {
            let token = try await client.login(email: email, password: password)
            KeychainHelper.save(key: "tidepool_token", value: token)
            KeychainHelper.save(key: "tidepool_email", value: email)
            KeychainHelper.save(key: "tidepool_password", value: password)
            await MainActor.run {
                success = true
                isLoading = false
            }
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
}
