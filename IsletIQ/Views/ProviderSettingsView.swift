import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ProviderSettingsView: View {
    var isEmbedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var authManager = AuthManager()
    @State private var profile: AuthManager.UserProfile?
    @State private var isLoading = true
    @State private var showLogoutConfirm = false

    var body: some View {
        let content = ScrollView {
            VStack(spacing: 14) {
                profileCard
                accountCard
                supportCard
                aboutCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationTitle("Provider Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .task { await loadProfile() }

        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    // MARK: - Profile card

    private var profileCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.primary.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay(
                    Text(initials)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.primary)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(authManager.userName.isEmpty ? "Provider" : authManager.userName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(authManager.userEmail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("Provider account")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.primary.opacity(0.1), in: Capsule())
                    .padding(.top, 2)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    private var initials: String {
        let name = authManager.userName.isEmpty ? authManager.userEmail : authManager.userName
        let parts = name.split(separator: " ")
        if parts.count >= 2, let f = parts.first?.first, let l = parts.last?.first {
            return "\(f)\(l)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Account card (NPI + org)

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Credentials")
            if isLoading {
                HStack { ProgressView().controlSize(.small); Text("Loading...").font(.caption).foregroundStyle(Theme.textTertiary); Spacer() }
                    .padding(.horizontal, 20).padding(.vertical, 12)
            } else {
                infoRow(label: "NPI", value: profile?.npi ?? "Not on file", icon: "number")
                Divider().padding(.leading, 52)
                infoRow(label: "Organization", value: profile?.organization ?? "Not on file", icon: "building.2")
                Divider().padding(.leading, 52)
                infoRow(label: "Account tier", value: authManager.userTier.capitalized, icon: "creditcard")
            }
        }
        .card()
    }

    // MARK: - Support card

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Support")
            linkRow(label: "Privacy Policy", icon: "doc.text", url: "https://isletiq.com/privacy")
            Divider().padding(.leading, 52)
            linkRow(label: "Terms of Service", icon: "doc.plaintext", url: "https://isletiq.com/terms")
            Divider().padding(.leading, 52)
            actionRow(label: "Send feedback", icon: "envelope", action: openFeedbackEmail)
        }
        .card()
    }

    // MARK: - About + logout

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("About")
            infoRow(label: "Version", value: appVersion, icon: "info.circle")
            Divider().padding(.leading, 52)
            Button {
                showLogoutConfirm = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(Theme.high)
                        .frame(width: 28, height: 28)
                        .background(Theme.high.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    Text("Log out")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.high)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .card()
        .confirmationDialog("Log out of IsletIQ?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                authManager.logout()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Row helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.primary)
                .frame(width: 28, height: 28)
                .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func linkRow(label: String, icon: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openExternalURL(u) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 28, height: 28)
                    .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func actionRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 28, height: 28)
                    .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Profile load

    private func loadProfile() async {
        await authManager.fetchProfile()
        await fetchExtendedProfile()
        await MainActor.run { isLoading = false }
    }

    private func fetchExtendedProfile() async {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/me") else { return }
        var request = URLRequest(url: url)
        APIConfig.applyAuth(to: &request)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userDict = json["user"] as? [String: Any] {
                let id = userDict["id"] as? Int ?? 0
                let email = userDict["email"] as? String ?? ""
                let name = userDict["name"] as? String
                let tier = userDict["tier"] as? String ?? "trial"
                let cohort = userDict["cohort"] as? String
                let role = userDict["role"] as? String
                let trialEnds = userDict["trial_ends_at"] as? String
                let npi = userDict["npi"] as? String
                let org = userDict["organization"] as? String
                await MainActor.run {
                    self.profile = AuthManager.UserProfile(
                        id: id, email: email, name: name, tier: tier,
                        cohort: cohort, role: role,
                        npi: npi, organization: org,
                        devices: nil, trial_ends_at: trialEnds
                    )
                }
            }
        } catch {}
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func openFeedbackEmail() {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        let raw = "IsletIQ provider feedback (v\(version) build \(build))"
        let subject = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "IsletIQ"
        if let url = URL(string: "mailto:feedback@isletiq.com?subject=\(subject)") {
            openExternalURL(url)
        }
    }
}

private func openExternalURL(_ url: URL) {
    #if canImport(UIKit)
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    NSWorkspace.shared.open(url)
    #endif
}
