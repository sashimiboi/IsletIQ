import SwiftUI

struct DexcomLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State var dexcomManager: DexcomManager

    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 10) {
                        Image("IsletLogo")
                            .resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text("Connect Dexcom G7")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text("Sign in with your Dexcom Share credentials to get live CGM data.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Form
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email or Phone")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            TextField("dexcom@email.com", text: $username)
                                .font(.subheadline)
                                .textContentType(.username)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                #endif
                                .padding(12)
                                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            HStack {
                                if showPassword {
                                    TextField("Password", text: $password)
                                        .font(.subheadline)
                                        .textContentType(.password)
                                } else {
                                    SecureField("Password", text: $password)
                                        .font(.subheadline)
                                        .textContentType(.password)
                                }
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(12)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(20)
                    .card()

                    // Error
                    if let error = dexcomManager.error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.high)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.high)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.high.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Login button
                    Button {
                        Task {
                            await dexcomManager.login(username: username, password: password)
                            if dexcomManager.isLoggedIn {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if dexcomManager.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text(dexcomManager.isLoading ? "Connecting..." : "Connect Dexcom")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            (username.isEmpty || password.isEmpty) ? Theme.textTertiary : Theme.primary,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .disabled(username.isEmpty || password.isEmpty || dexcomManager.isLoading)
                    .buttonStyle(.plain)

                    // Info
                    VStack(spacing: 6) {
                        Text("Requirements")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Text("• Share must be enabled in your Dexcom G7 app")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                        Text("• At least one follower must be added")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                        Text("• Credentials are stored securely in your Keychain")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Theme.bg)
            .navigationTitle("Dexcom")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

#Preview {
    DexcomLoginView(dexcomManager: DexcomManager())
}
