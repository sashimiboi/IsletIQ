import SwiftUI

struct AuthView: View {
    @State private var authManager = AuthManager()
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    let onAuth: () -> Void

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

                // Toggle
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

                // Fields
                VStack(spacing: 14) {
                    if !isLogin {
                        TextField("Full Name", text: $name)
                            .textContentType(.name)
                            .padding(14)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12))
                    }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .background(Theme.muted, in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(isLogin ? .password : .newPassword)
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
                            success = await authManager.register(email: email, password: password, name: name)
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
                        Text(isLogin ? "Sign In" : "Create Account")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
                .buttonStyle(.plain)
                .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)

                // Features
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

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .background(Theme.bg)
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
