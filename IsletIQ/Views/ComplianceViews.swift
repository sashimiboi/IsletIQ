import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - First Launch Compliance (consent + disclaimer)

struct FirstLaunchView: View {
    @Binding var isComplete: Bool
    @State private var page = 0
    @State private var authManager = AuthManager()

    private var isProvider: Bool { authManager.userRole.isProvider }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if isProvider {
                    // Provider flow: no cohort, no HealthKit, no device pairing.
                    // Just the compliance gates, then straight to the roster.
                    switch page {
                    case 0: MedicalDisclaimerPage { page = 1 }
                    case 1:
                        DataConsentPage {
                            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                            isComplete = true
                        }
                    default: EmptyView()
                    }
                } else {
                    // Patient flow.
                    switch page {
                    case 0: CohortPickerPage { picked in
                        Task { _ = await authManager.updateCohort(picked) }
                        page = 1
                    }
                    case 1: MedicalDisclaimerPage { page = 2 }
                    case 2: DataConsentPage { page = 3 }
                    #if os(iOS)
                    case 3: HealthKitConsentPage { page = 4 }
                    case 4:
                        // Pump / CGM connection is only meaningful for T1D users.
                        // T2D and GLP-1 users skip straight to completion and can
                        // wire up a CGM later from Settings if they have one.
                        if authManager.userCohort == .t1d {
                            DeviceConnectPage {
                                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                                isComplete = true
                            }
                        } else {
                            Color.clear
                                .onAppear {
                                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                                    isComplete = true
                                }
                        }
                    #else
                    case 3:
                        // HealthKit + device connect are iOS-only. macOS skips
                        // straight to completion.
                        Color.clear
                            .onAppear {
                                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                                isComplete = true
                            }
                    #endif
                    default: EmptyView()
                    }
                }
            }
        }
    }
}

// MARK: - Cohort Picker (first onboarding page)

struct CohortPickerPage: View {
    let onSelect: (Cohort) -> Void
    @State private var selected: Cohort? = nil

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

                    Text("Which describes you best?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)

                    Text("This shapes which cards and tools IsletIQ shows you. You can change it later from Settings.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)

                    VStack(spacing: 10) {
                        ForEach(Cohort.allCases) { cohort in
                            cohortCard(cohort)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            VStack(spacing: 12) {
                Button {
                    if let selected { onSelect(selected) }
                } label: {
                    Text("Continue")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            selected != nil ? Theme.primary : Theme.textTertiary,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                .disabled(selected == nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .background(Theme.cardBg)
        }
    }

    @ViewBuilder
    private func cohortCard(_ cohort: Cohort) -> some View {
        let isSelected = selected == cohort
        Button {
            selected = cohort
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: cohort.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Theme.primary : Theme.textSecondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cohort.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(cohort.tagline)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(14)
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
                            title: "Not a Medical Device",
                            body: "IsletIQ is an insights tool. It surfaces patterns from your CGM, pump, and meal data. It does not provide medical advice, diagnosis, treatment, or insulin dosing recommendations."
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
                            #if canImport(UIKit)
                            UIApplication.shared.open(url)
                            #elseif canImport(AppKit)
                            NSWorkspace.shared.open(url)
                            #endif
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

#if !os(macOS)
// macOS already provides a native `.checkbox` ToggleStyle; defining one here
// would create an ambiguity at call sites. iOS doesn't have it, so the custom
// style is exposed only on non-macOS platforms.
extension ToggleStyle where Self == CheckboxToggleStyle {
    static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}
#endif

#if os(iOS)
// MARK: - HealthKit Consent

struct HealthKitConsentPage: View {
    let onContinue: () -> Void
    @State private var isRequesting = false
    @State private var didRequest = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.primary)
                        .padding(.top, 30)
                        .frame(maxWidth: .infinity)

                    Text("Connect Apple Health")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)

                    Text("IsletIQ reads from and writes to Apple Health so your CGM, insulin, meals, sleep, heart rate, and activity all stay in one place.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Glucose, insulin, and carbs from your CGM and pump")
                        bullet("Meals, sleep, heart rate, HRV, and steps")
                        bullet("Meals and insulin you log inside IsletIQ are written back so other apps see them too")
                    }
                    .padding(.top, 4)

                    Text("You can change these permissions any time in Settings → Privacy & Security → Health → IsletIQ.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            VStack(spacing: 12) {
                Button {
                    isRequesting = true
                    Task {
                        let manager = HealthKitManager()
                        await manager.requestAuthorization()
                        await MainActor.run {
                            isRequesting = false
                            didRequest = true
                            onContinue()
                        }
                    }
                } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text(didRequest ? "Continue" : "Connect Apple Health")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(isRequesting)

                Button("Skip for now") {
                    onContinue()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.normal)
                .font(.callout)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
    }
}

// MARK: - Device Connect

struct DeviceConnectPage: View {
    let onContinue: () -> Void
    @State private var dexcomManager = DexcomManager()
    @State private var showDexcomLogin = false
    @State private var showLibreLogin = false
    @State private var showNightscoutLogin = false
    @State private var showGlookoLogin = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.primary)
                        .padding(.top, 30)
                        .frame(maxWidth: .infinity)

                    Text("Connect a CGM or Pump")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)

                    Text("Pick the source you want IsletIQ to pull from. You can connect more later in Settings → Devices.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 4)

                    VStack(spacing: 10) {
                        connectRow(name: "Dexcom Share", subtitle: "G6 / G7 live readings", icon: "drop.circle.fill") {
                            showDexcomLogin = true
                        }
                        connectRow(name: "FreeStyle Libre", subtitle: "LibreLinkUp", icon: "circle.dashed.inset.filled") {
                            showLibreLogin = true
                        }
                        connectRow(name: "Nightscout", subtitle: "Self-hosted CGM relay", icon: "moon.stars.fill") {
                            showNightscoutLogin = true
                        }
                        connectRow(name: "Glooko", subtitle: "Pump and meter import", icon: "arrow.down.circle.fill") {
                            showGlookoLogin = true
                        }
                    }
                    .padding(.top, 4)

                    Text("Apple Health alone is also enough — IsletIQ will read whatever your other apps and devices already write there.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            Button("Done") {
                onContinue()
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $showDexcomLogin) {
            DexcomLoginView(dexcomManager: dexcomManager)
        }
        .sheet(isPresented: $showLibreLogin) {
            LibreLinkLoginView()
        }
        .sheet(isPresented: $showNightscoutLogin) {
            NightscoutLoginView()
        }
        .sheet(isPresented: $showGlookoLogin) {
            GlookoLoginView()
        }
    }

    @ViewBuilder
    private func connectRow(name: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
#endif
