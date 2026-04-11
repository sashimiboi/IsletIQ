#if os(iOS)
import SwiftUI

// MARK: - First Launch Compliance (consent + disclaimer)

struct FirstLaunchView: View {
    @Binding var isComplete: Bool
    @State private var page = 0

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                switch page {
                case 0: MedicalDisclaimerPage { page = 1 }
                case 1: DataConsentPage {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    isComplete = true
                }
                default: EmptyView()
                }
            }
        }
    }
}

// MARK: - Medical Disclaimer

struct MedicalDisclaimerPage: View {
    let onAccept: () -> Void
    @State private var accepted = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image("IsletLogo")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 30)
                        .frame(maxWidth: .infinity)

                    Text("Important Health Notice")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 14) {
                        disclaimerItem(
                            icon: "exclamationmark.triangle.fill",
                            color: Theme.elevated,
                            title: "Not Medical Advice",
                            body: "IsletIQ is an informational tool only. It does not provide medical advice, diagnosis, or treatment. All glucose analysis, insulin calculations, and recommendations are for informational purposes."
                        )
                        disclaimerItem(
                            icon: "stethoscope",
                            color: Theme.primary,
                            title: "Consult Your Doctor",
                            body: "Always consult your endocrinologist or healthcare provider before making changes to your insulin doses, basal rates, or diabetes management plan."
                        )
                        disclaimerItem(
                            icon: "bolt.heart.fill",
                            color: Theme.high,
                            title: "Emergency Situations",
                            body: "In case of severe hypoglycemia, diabetic ketoacidosis, or any medical emergency, call 911 or your local emergency number immediately. Do not rely on this app."
                        )
                        disclaimerItem(
                            icon: "checkmark.shield.fill",
                            color: Theme.normal,
                            title: "Data Accuracy",
                            body: "IsletIQ displays data from your CGM and insulin pump. Always verify readings with a fingerstick blood glucose meter when making treatment decisions."
                        )
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            VStack(spacing: 12) {
                Toggle(isOn: $accepted) {
                    Text("I understand that IsletIQ is not a substitute for professional medical advice")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 24)

                Button {
                    onAccept()
                } label: {
                    Text("Continue")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accepted ? Theme.primary : Theme.textTertiary, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!accepted)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .background(Theme.cardBg)
        }
    }

    @ViewBuilder
    private func disclaimerItem(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Data Consent

struct DataConsentPage: View {
    let onAccept: () -> Void
    @State private var consentGiven = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("How Your Data Is Used")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)

                    Text("IsletIQ connects to the following services to provide its features. Your data is never sold or used for advertising.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Required Services")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)

                        dataCard(
                            title: "IsletIQ Cloud",
                            icon: "cloud.fill",
                            data: "CGM readings, insulin data, meal logs, chat messages",
                            purpose: "Stores your health data securely and powers the AI assistant"
                        )
                        dataCard(
                            title: "Anthropic (Claude AI)",
                            icon: "brain",
                            data: "Chat messages with health context (glucose, insulin, meals)",
                            purpose: "Generates personalized diabetes insights and answers"
                        )
                        dataCard(
                            title: "Apple HealthKit",
                            icon: "heart.fill",
                            data: "Glucose, insulin, meals, sleep, activity",
                            purpose: "Reads and writes health data to Apple Health"
                        )
                    }
                    .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Optional (consent requested when enabled)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)

                        dataCard(
                            title: "ElevenLabs (Voice Mode)",
                            icon: "waveform",
                            data: "AI responses (text only, not your voice recordings)",
                            purpose: "Converts agent responses to natural speech"
                        )
                        dataCard(
                            title: "Dexcom / LibreLink / Nightscout / Tidepool",
                            icon: "waveform.path.ecg",
                            data: "Account credentials (stored in Keychain)",
                            purpose: "Fetches your CGM glucose readings"
                        )
                    }
                    .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Rights")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("You can delete your account and all associated data at any time from Settings. Health data stored in Apple Health is managed by Apple and not affected by account deletion.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            VStack(spacing: 12) {
                Toggle(isOn: $consentGiven) {
                    Text("I consent to my data being processed as described above")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    Button {
                        if let url = URL(string: "https://isletiq.com/privacy") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Privacy Policy")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.primary)
                    }

                    Button {
                        onAccept()
                    } label: {
                        Text("Accept & Continue")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(consentGiven ? Theme.primary : Theme.textTertiary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!consentGiven)
                }
                .padding(.bottom, 30)
            }
            .background(Theme.cardBg)
        }
    }

    @ViewBuilder
    private func dataCard(title: String, icon: String, data: String, purpose: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 4) {
                    Text("Data:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                    Text(data)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(alignment: .top, spacing: 4) {
                    Text("Why:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                    Text(purpose)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.leading, 32)
        }
        .padding(14)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Checkbox Toggle Style

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Theme.primary : Theme.textTertiary)
                    .font(.system(size: 20))
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}
#endif
