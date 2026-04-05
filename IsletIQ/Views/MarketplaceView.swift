import SwiftUI

// MARK: - App Integration

struct AppIntegration: Identifiable {
    let id: String
    let name: String
    let icon: String
    let category: String
    let description: String
    let developer: String
    var isConnected: Bool
    var isPopular: Bool = false
}

let marketplaceApps: [AppIntegration] = [
    // CGM & Pump
    AppIntegration(id: "dexcom", name: "Dexcom", icon: "waveform.path.ecg.rectangle.fill", category: "CGM", description: "Real-time glucose data from Dexcom G6/G7 sensors", developer: "Dexcom, Inc.", isConnected: true, isPopular: true),
    AppIntegration(id: "libre", name: "FreeStyle Libre", icon: "sensor.tag.radiowaves.forward.fill", category: "CGM", description: "Flash glucose monitoring data import", developer: "Abbott", isConnected: false, isPopular: true),
    AppIntegration(id: "tslim", name: "t:connect", icon: "cross.vial.fill", category: "Pump", description: "Tandem t:slim X2 pump data sync", developer: "Tandem Diabetes", isConnected: true, isPopular: true),
    AppIntegration(id: "omnipod", name: "Omnipod 5", icon: "circle.hexagongrid.fill", category: "Pump", description: "Omnipod tubeless pump integration", developer: "Insulet Corp.", isConnected: false),
    AppIntegration(id: "medtronic", name: "CareLink", icon: "link.circle.fill", category: "Pump", description: "Medtronic pump & CGM data", developer: "Medtronic", isConnected: false),

    // Health & Fitness
    AppIntegration(id: "healthkit", name: "Apple Health", icon: "heart.fill", category: "Health", description: "Sync glucose, insulin, and activity data", developer: "Apple", isConnected: true, isPopular: true),
    AppIntegration(id: "fitbit", name: "Fitbit", icon: "figure.run", category: "Health", description: "Activity, sleep, and heart rate data", developer: "Google", isConnected: false),
    AppIntegration(id: "strava", name: "Strava", icon: "figure.hiking", category: "Health", description: "Exercise data to correlate with glucose", developer: "Strava, Inc.", isConnected: false),

    // Nutrition
    AppIntegration(id: "myfitnesspal", name: "MyFitnessPal", icon: "takeoutbag.and.cup.and.straw.fill", category: "Nutrition", description: "Carb and macro tracking auto-import", developer: "Under Armour", isConnected: false, isPopular: true),
    AppIntegration(id: "calorieking", name: "CalorieKing", icon: "leaf.fill", category: "Nutrition", description: "Food database for carb counting", developer: "CalorieKing", isConnected: false),
    AppIntegration(id: "fatsecret", name: "FatSecret", icon: "scalemass.fill", category: "Nutrition", description: "Nutrition tracking and food diary", developer: "FatSecret", isConnected: false),

    // Clinical
    AppIntegration(id: "glooko", name: "Glooko", icon: "chart.bar.doc.horizontal.fill", category: "Clinical", description: "Share reports with your healthcare team", developer: "Glooko, Inc.", isConnected: false),
    AppIntegration(id: "tidepool", name: "Tidepool", icon: "drop.triangle.fill", category: "Clinical", description: "Open-source diabetes data platform", developer: "Tidepool", isConnected: false, isPopular: true),
    AppIntegration(id: "sugarmate", name: "Sugarmate", icon: "bell.badge.fill", category: "Clinical", description: "Glucose alerts and smart notifications", developer: "Tandem Diabetes", isConnected: false),

    // Smart Home & Wearables
    AppIntegration(id: "nightscout", name: "Nightscout", icon: "moon.stars.fill", category: "DIY", description: "Open-source CGM in the cloud", developer: "Nightscout Foundation", isConnected: false, isPopular: true),
    AppIntegration(id: "loop", name: "Loop", icon: "arrow.triangle.2.circlepath", category: "DIY", description: "Automated insulin delivery system", developer: "LoopKit", isConnected: false),
]

// MARK: - Marketplace View

struct MarketplaceView: View {
    @State private var searchText = ""
    @State private var apps = marketplaceApps
    @State private var selectedCategory: String? = nil

    private var categories: [String] {
        Array(Set(apps.map(\.category))).sorted()
    }

    private var filteredApps: [AppIntegration] {
        var result = apps
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var connectedApps: [AppIntegration] {
        apps.filter(\.isConnected)
    }

    private var popularApps: [AppIntegration] {
        apps.filter(\.isPopular)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textTertiary)
                    TextField("Search integrations...", text: $searchText)
                        .font(.subheadline)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))

                // Connected apps
                if !connectedApps.isEmpty && searchText.isEmpty && selectedCategory == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Connected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(connectedApps.count) active")
                                .font(.caption)
                                .foregroundStyle(Theme.normal)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(connectedApps) { app in
                                    ConnectedAppCard(app: app)
                                }
                            }
                        }
                    }
                }

                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryPill(label: "All", isSelected: selectedCategory == nil) {
                            withAnimation { selectedCategory = nil }
                        }
                        ForEach(categories, id: \.self) { cat in
                            CategoryPill(label: cat, isSelected: selectedCategory == cat) {
                                withAnimation { selectedCategory = cat }
                            }
                        }
                    }
                }

                // Popular
                if selectedCategory == nil && searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Popular")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        ForEach(popularApps) { app in
                            if let idx = apps.firstIndex(where: { $0.id == app.id }) {
                                AppRow(app: $apps[idx])
                            }
                        }
                    }
                    .card()
                    .padding(.vertical, 4)
                }

                // All / Filtered
                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedCategory ?? "All Integrations")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if filteredApps.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                                .foregroundStyle(Theme.textTertiary)
                            Text("No integrations found")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        ForEach(filteredApps) { app in
                            if let idx = apps.firstIndex(where: { $0.id == app.id }) {
                                AppRow(app: $apps[idx])
                            }
                        }
                    }
                }
                .card()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationTitle("Marketplace")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

// MARK: - Connected App Card

struct ConnectedAppCard: View {
    let app: AppIntegration

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.primary.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: app.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
            }
            Text(app.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Theme.normal).frame(width: 5, height: 5)
                Text("Active")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.normal)
            }
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .card()
    }
}

// MARK: - Category Pill

struct CategoryPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Theme.primary : Theme.muted,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Row

struct AppRow: View {
    @Binding var app: AppIntegration

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(app.isConnected ? Theme.primary.opacity(0.08) : Theme.muted)
                    .frame(width: 40, height: 40)
                Image(systemName: app.icon)
                    .font(.body)
                    .foregroundStyle(app.isConnected ? Theme.primary : Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if app.isPopular {
                        Text("Popular")
                            .font(.system(size: 9).weight(.semibold))
                            .foregroundStyle(Theme.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                Text(app.description)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Text(app.developer)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    app.isConnected.toggle()
                }
            } label: {
                Text(app.isConnected ? "Connected" : "Connect")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(app.isConnected ? Theme.normal : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        app.isConnected ? Theme.normal.opacity(0.1) : Theme.primary,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        app.isConnected ? RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.normal.opacity(0.3), lineWidth: 1) : nil
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        MarketplaceView()
    }
}
