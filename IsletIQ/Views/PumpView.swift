import SwiftUI

struct PumpView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Device header
                deviceCard
                // Delivery
                deliveryCard
                // Reservoir
                reservoirCard
                // Recent boluses
                bolusHistoryCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationTitle("Pump")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    private var deviceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.primary.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: "medical.thermometer.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(MockData.pumpModel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Circle().fill(Theme.normal).frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "battery.75")
                        .font(.caption)
                        .foregroundStyle(Theme.normal)
                    Text("\(MockData.pumpBattery)%")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(20)
        .card()
    }

    private var deliveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Insulin Delivery")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 0) {
                DeliveryItem(label: "Basal Rate", value: "\(MockData.activeBasalRate) u/hr", icon: "waveform.path", color: Theme.primary)
                Divider().frame(height: 40).padding(.horizontal, 8)
                DeliveryItem(label: "IOB", value: String(format: "%.1f u", MockData.iob), icon: "drop.fill", color: Theme.teal)
                Divider().frame(height: 40).padding(.horizontal, 8)
                DeliveryItem(label: "Daily Total", value: "18.2 u", icon: "chart.bar.fill", color: Theme.primary)
            }
        }
        .padding(20)
        .card()
    }

    private var reservoirCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reservoir")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 16) {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Theme.border, lineWidth: 6)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: MockData.reservoirUnits / MockData.reservoirMax)
                        .stroke(Theme.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(MockData.reservoirUnits))")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(MockData.reservoirUnits)) of \(Int(MockData.reservoirMax)) units")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Est. ~2.8 days remaining")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Last changed 4 days ago")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()
            }
        }
        .padding(20)
        .card()
    }

    private var bolusHistoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Boluses")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(mockBoluses, id: \.time) { bolus in
                HStack {
                    Image(systemName: "syringe.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.teal)
                        .frame(width: 16)
                    Text(String(format: "%.1f u", bolus.units))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    if !bolus.type.isEmpty {
                        Text(bolus.type)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.primary.opacity(0.08), in: Capsule())
                    }
                    Spacer()
                    Text(bolus.time)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 3)
                if bolus.time != mockBoluses.last?.time {
                    Divider()
                }
            }
        }
        .padding(20)
        .card()
    }

    private var mockBoluses: [(units: Double, type: String, time: String)] {
        [
            (3.5, "Meal", "1h 30m ago"),
            (1.2, "Correction", "4h ago"),
            (4.0, "Meal", "7h ago"),
            (0.8, "Correction", "10h ago"),
        ]
    }
}

struct DeliveryItem: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10).weight(.medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        PumpView()
    }
}
