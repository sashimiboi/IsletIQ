#if os(iOS)
import SwiftUI

/// Per-session medical disclaimer presented before the user can interact
/// with any view that may produce insulin-dose calculations or AI-generated
/// dosing suggestions. Required by App Store Review Guideline 1.4.1 for
/// non-FDA-cleared apps that perform dose math.
struct BolusDisclaimerSheet: View {
    let onAcknowledge: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Warning icon
                    ZStack {
                        Circle()
                            .fill(Theme.elevated.opacity(0.15))
                            .frame(width: 88, height: 88)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.elevated)
                    }
                    .padding(.top, 24)

                    Text("Informational Only")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("IsletIQ is not a medical device.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.elevated)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 14) {
                        bullet(
                            icon: "function",
                            color: Theme.primary,
                            title: "Dose math is informational",
                            body: "Any insulin dose, correction, or carb-based calculation IsletIQ shows is for informational and educational purposes only. It has not been cleared by the FDA and is not a substitute for medical advice."
                        )
                        bullet(
                            icon: "stethoscope",
                            color: Theme.primary,
                            title: "Verify with your care team",
                            body: "Always confirm doses with your endocrinologist or diabetes care team before acting on them. Never change basal rates, ratios, or correction factors based on IsletIQ alone."
                        )
                        bullet(
                            icon: "drop.fill",
                            color: Theme.high,
                            title: "Verify glucose with a fingerstick",
                            body: "Verify CGM readings with a fingerstick blood glucose meter before making any treatment decision."
                        )
                        bullet(
                            icon: "phone.fill.arrow.up.right",
                            color: Theme.high,
                            title: "Emergencies: call 911",
                            body: "For severe hypoglycemia, suspected DKA, or any medical emergency, call 911 immediately. Do not rely on this app."
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    Spacer(minLength: 20)
                }
            }
            .background(Theme.bg)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Toggle(isOn: $accepted) {
                        Text("I understand this is not medical advice and will not act on dose calculations without consulting my care team.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)

                    Button {
                        onAcknowledge()
                        dismiss()
                    } label: {
                        Text("I Understand, Continue")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                accepted ? Theme.primary : Theme.textTertiary,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .disabled(!accepted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(Theme.cardBg)
            }
            .navigationTitle("Health Notice")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
    }

    @ViewBuilder
    private func bullet(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 26)
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
#endif
