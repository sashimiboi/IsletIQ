import SwiftUI

struct AuthView: View {
    @State private var authManager = AuthManager()
    @State private var isLogin = true
    @State private var accountType: Role = .patient
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var npi = ""
    @State private var organization = ""
    @State private var showPassword = false
    let onAuth: () -> Void

    private var canSubmit: Bool {
        if email.isEmpty || password.isEmpty || authManager.isLoading { return false }
        if !isLogin {
            if name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if accountType == .provider {
                if npi.trimmingCharacters(in: .whitespaces).isEmpty { return false }
                if organization.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            }
        }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                // Logo
                Image("IsletLogo")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Theme.primary.opacity(0.2), radius: 12, y: 4)

                VStack(spacing: 4) {
                    Text("IsletIQ")
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Diabetes Insights")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Sign In / Sign Up toggle
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isLogin = true }
                    } label: {
                        Text("Sign In")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isLogin ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isLogin ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isLogin = false }
                    } label: {
                        Text("Sign Up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(!isLogin ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(!isLogin ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 11))
                .buttonStyle(.plain)

                // Account type — sign-up only. Drives which fields appear and
                // which onboarding flow + home experience the user gets.
                if !isLogin {
                    accountTypePicker
                }

                // Fields
                VStack(spacing: 14) {
                    if !isLogin {
                        TextField("Full Name", text: $name)
                            .textContentType(.name)
                            .padding(14)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12))

                        if accountType == .provider {
                            TextField("NPI", text: $npi)
                                .textContentType(.none)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12))

                            TextField("Organization", text: $organization)
                                .textContentType(.organizationName)
                                .padding(14)
                                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 8) {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .autocorrectionDisabled()
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(isLogin ? .password : .newPassword)

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12))
                }

                // Error
                if let error = authManager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.high)
                        .padding(.horizontal, 8)
                }

                // Submit
                Button {
                    Task {
                        let success: Bool
                        if isLogin {
                            success = await authManager.login(email: email, password: password)
                        } else {
                            success = await authManager.register(
                                email: email,
                                password: password,
                                name: name,
                                role: accountType,
                                npi: accountType == .provider ? npi : nil,
                                organization: accountType == .provider ? organization : nil
                            )
                        }
                        if success { onAuth() }
                    }
                } label: {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text(isLogin ? "Sign In" : (accountType == .provider ? "Create Provider Account" : "Create Account"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.6)

                // Features — patient only. Providers see a different blurb.
                if isLogin || accountType == .patient {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("7-day free trial includes:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        FeatureRow(icon: "brain.head.profile.fill", text: "AI agents for glucose, nutrition, supplies")
                        FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Live CGM dashboard with Dexcom G7")
                        FeatureRow(icon: "camera.fill", text: "Photo-based meal estimation")
                        FeatureRow(icon: "shippingbox", text: "Supply tracking with alerts")
                        FeatureRow(icon: "applewatch", text: "Apple Watch companion app")
                    }
                    .padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Provider account includes:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        FeatureRow(icon: "person.2.fill", text: "Patient roster sorted by attention level")
                        FeatureRow(icon: "target", text: "TIR, hypo events, adherence, low supplies at a glance")
                        FeatureRow(icon: "lock.shield.fill", text: "HIPAA-compliant access, audit logged")
                    }
                    .padding(16)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .background(Theme.bg)
    }

    // MARK: - Account Type Picker

    private var accountTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("I am a")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                accountTypeCard(.patient,
                                title: "Patient",
                                subtitle: "Track CGM, meds, supplies",
                                icon: "drop.fill")
                accountTypeCard(.provider,
                                title: "Provider",
                                subtitle: "Endocrinologist or care team",
                                icon: "stethoscope")
            }
        }
    }

    @ViewBuilder
    private func accountTypeCard(_ role: Role, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = accountType == role
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                accountType = role
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.primary : Theme.textSecondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Theme.primary.opacity(0.08) : Theme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.primary : Theme.textTertiary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.primary)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
