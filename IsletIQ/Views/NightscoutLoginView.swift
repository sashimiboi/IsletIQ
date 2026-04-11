import SwiftUI

struct NightscoutLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var siteURL = ""
    @State private var apiSecret = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var success = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.primary)
                    .padding(.top, 20)

                Text("Nightscout")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Connect to your Nightscout instance")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)

                VStack(spacing: 12) {
                    TextField("Site URL (e.g. https://my-ns.herokuapp.com)", text: $siteURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .padding(14)
                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))

                    SecureField("API Secret (optional)", text: $apiSecret)
                        .textContentType(.password)
                        .padding(14)
                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))

                    Text("API Secret is only needed if your Nightscout requires authentication")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
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
                        Text(isLoading ? "Verifying..." : "Connect")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(siteURL.isEmpty ? Theme.textTertiary : Theme.primary,
                               in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(siteURL.isEmpty || isLoading)
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
        let url = siteURL.hasPrefix("http") ? siteURL : "https://\(siteURL)"
        let secret = apiSecret.isEmpty ? nil : apiSecret
        let client = NightscoutClient(siteURL: url, apiSecret: secret)
        do {
            let ok = try await client.verifyConnection()
            guard ok else { throw NightscoutClient.NightscoutError.networkError("Could not reach Nightscout") }
            KeychainHelper.save(key: "nightscout_url", value: url)
            if let secret { KeychainHelper.save(key: "nightscout_secret", value: secret) }
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
