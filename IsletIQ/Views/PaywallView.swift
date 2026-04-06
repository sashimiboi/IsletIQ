import SwiftUI
import StoreKit

struct PaywallView: View {
    var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image("IsletLogo")
                            .resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        Text("Upgrade to IsletIQ Pro")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text("Your free trial has ended. Subscribe to continue using all features.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    // Features
                    VStack(alignment: .leading, spacing: 10) {
                        PaywallFeature(icon: "brain.head.profile.fill", title: "AI Agents", desc: "Unlimited conversations with 5 specialized agents")
                        PaywallFeature(icon: "camera.fill", title: "Photo Analysis", desc: "Snap food or supplies - AI reads and logs automatically")
                        PaywallFeature(icon: "shippingbox", title: "Supply Tracking", desc: "Never run out of pods, sensors, or insulin")
                        PaywallFeature(icon: "applewatch", title: "Apple Watch", desc: "Live glucose, supplies, and quick log on your wrist")
                        PaywallFeature(icon: "bell.badge.fill", title: "Smart Alerts", desc: "CGM, pump, supply, and meal notifications")
                        PaywallFeature(icon: "chart.line.uptrend.xyaxis", title: "Advanced Charts", desc: "AGP, trend analysis, sleep stages, activity")
                    }
                    .padding(16)
                    .background(Theme.muted, in: RoundedRectangle(cornerRadius: 14))

                    // Products
                    if storeManager.isLoading {
                        ProgressView()
                            .padding()
                    } else if storeManager.products.isEmpty {
                        // Fallback when products aren't configured in App Store Connect yet
                        VStack(spacing: 12) {
                            PriceTile(name: "Pro", price: "$14.99/mo", desc: "Full platform access", highlighted: true) {}
                            PriceTile(name: "Pro+", price: "$19.99/mo", desc: "Unlimited AI + priority", highlighted: false) {}
                            PriceTile(name: "Family", price: "$24.99/mo", desc: "Up to 3 members", highlighted: false) {}
                            PriceTile(name: "Annual", price: "$119/yr", desc: "Pro features, save 34%", highlighted: false) {}
                        }

                        Text("Subscriptions will be available when the app is on the App Store")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                    } else {
                        ForEach(storeManager.products, id: \.id) { product in
                            Button {
                                Task { await storeManager.purchase(product) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(product.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(product.description)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.primary)
                                }
                                .padding(16)
                                .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Restore
                    Button {
                        Task { await storeManager.restore() }
                    } label: {
                        Text("Restore Purchases")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.primary)
                    }

                    // Terms
                    VStack(spacing: 4) {
                        Text("7-day free trial, then auto-renews monthly.")
                        Text("Cancel anytime in Settings > Subscriptions.")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

struct PaywallFeature: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

struct PriceTile: View {
    let name: String
    let price: String
    let desc: String
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(price)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.primary)
            }
            .padding(16)
            .background(highlighted ? Theme.primary.opacity(0.05) : Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlighted ? Theme.primary : Theme.border, lineWidth: highlighted ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}
