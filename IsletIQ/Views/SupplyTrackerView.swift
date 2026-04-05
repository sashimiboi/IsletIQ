import SwiftUI

// Backend supply model
struct RemoteSupply: Identifiable {
    let id: Int
    let name: String
    let category: String
    let quantity: Int
    let usageRateDays: Double
    let alertDaysBefore: Int
    let notes: String

    var daysRemaining: Int { Int(Double(quantity) * usageRateDays) }
    var needsAlert: Bool { quantity <= 3 }

    var urgency: SupplyUrgency {
        if quantity == 0 { return .out }
        if quantity <= 1 { return .critical }
        if quantity <= 3 { return .low }
        return .good
    }

    var categoryIcon: String {
        switch category {
        case "pumpPod": "circle.hexagongrid.fill"
        case "cgmSensor": "sensor.tag.radiowaves.forward.fill"
        case "insulin": "cross.vial.fill"
        case "testStrips": "rectangle.stack.fill"
        case "ketoneStrips": "drop.triangle.fill"
        case "needles": "pin.fill"
        case "skinPrep": "bandage.fill"
        case "adhesive": "square.on.square.fill"
        default: "shippingbox.fill"
        }
    }
}

enum SupplyUrgency: String {
    case good, low, critical, out
}

struct SupplyTrackerView: View {
    @State private var supplies: [RemoteSupply] = []
    @State private var isLoading = true
    @State private var showAddSupply = false
    private let client = SupplyClient()

    private var alertCount: Int { supplies.filter(\.needsAlert).count }
    private var criticalSupplies: [RemoteSupply] { supplies.filter { $0.urgency == .critical || $0.urgency == .out } }
    private var lowSupplies: [RemoteSupply] { supplies.filter { $0.urgency == .low } }
    private var goodSupplies: [RemoteSupply] { supplies.filter { $0.urgency == .good } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if alertCount > 0 { alertBanner }
                overviewCard

                if !criticalSupplies.isEmpty {
                    supplySection(title: "Needs Attention", items: criticalSupplies, color: Theme.high)
                }
                if !lowSupplies.isEmpty {
                    supplySection(title: "Running Low", items: lowSupplies, color: Theme.elevated)
                }
                if !goodSupplies.isEmpty {
                    supplySection(title: "Stocked", items: goodSupplies, color: Theme.normal)
                }
                if supplies.isEmpty && !isLoading {
                    emptyState
                }
                if isLoading {
                    ProgressView("Loading supplies...")
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationTitle("Supplies")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSupply = true } label: {
                    Image(systemName: "plus").font(.body.weight(.medium))
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .sheet(isPresented: $showAddSupply) {
            AddSupplySheet(onSave: { Task { await loadSupplies() } })
        }
        .task { await loadSupplies() }
        .refreshable { await loadSupplies() }
    }

    private func loadSupplies() async {
        isLoading = true
        let remote = await client.fetchSupplies()
        supplies = remote.map { r in
            RemoteSupply(
                id: r.id, name: r.name, category: r.category,
                quantity: r.quantity, usageRateDays: r.usage_rate_days,
                alertDaysBefore: r.alert_days_before, notes: r.notes ?? ""
            )
        }
        isLoading = false

        // Check supply alerts
        let notifs = NotificationManager()
        await notifs.checkAuthorization()
        notifs.checkSupplies(supplies)
    }

    // MARK: - Alert Banner

    private var alertBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.high)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(alertCount) supply alert\(alertCount == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Some supplies are running low - time to reorder")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.high.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.high.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Overview

    private var overviewCard: some View {
        HStack(spacing: 0) {
            OverviewStat(value: "\(supplies.count)", label: "Items", color: Theme.primary)
            Spacer()
            OverviewStat(value: "\(goodSupplies.count)", label: "Stocked", color: Theme.normal)
            Spacer()
            OverviewStat(value: "\(alertCount)", label: "Alerts", color: alertCount > 0 ? Theme.high : Theme.textTertiary)
            Spacer()
            OverviewStat(value: nearestRunout, label: "Next Runout", color: Theme.elevated)
        }
        .padding(20)
        .card()
    }

    private var nearestRunout: String {
        guard let nearest = supplies.filter({ $0.quantity > 0 }).min(by: { $0.daysRemaining < $1.daysRemaining }) else { return "--" }
        let days = nearest.daysRemaining
        if days == 0 { return "Today" }
        if days == 1 { return "1 day" }
        return "\(days)d"
    }

    // MARK: - Supply Section

    private func supplySection(title: String, items: [RemoteSupply], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, supply in
                    RemoteSupplyRow(supply: supply, onUse: {
                        Task {
                            _ = await client.useSupply(id: supply.id)
                            await loadSupplies()
                        }
                    }, onDelete: {
                        Task {
                            _ = await client.deleteSupply(id: supply.id)
                            await loadSupplies()
                        }
                    }, onUpdateQuantity: { newQty in
                        Task {
                            _ = await client.setQuantity(id: supply.id, quantity: newQty)
                            await loadSupplies()
                        }
                    })
                    if i < items.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, 4)
            .card()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("No Supplies Tracked")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Add supplies manually or tell the agent what you have")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            Button { showAddSupply = true } label: {
                Text("Add Supply")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Overview Stat

struct OverviewStat: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Supply Row

struct RemoteSupplyRow: View {
    let supply: RemoteSupply
    let onUse: () -> Void
    let onDelete: () -> Void
    let onUpdateQuantity: (Int) -> Void
    @State private var showDeleteConfirm = false
    @State private var showAdjuster = false

    private var urgencyColor: Color {
        switch supply.urgency {
        case .good: Theme.normal
        case .low: Theme.elevated
        case .critical: Theme.high
        case .out: Theme.textTertiary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.25)) { showAdjuster.toggle() }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(urgencyColor.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: supply.categoryIcon)
                            .font(.subheadline)
                            .foregroundStyle(urgencyColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(supply.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 8) {
                            Text("\(supply.quantity) left")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(urgencyColor)
                            if supply.quantity > 0 {
                                Text("·").foregroundStyle(Theme.textTertiary)
                                Text("\(supply.daysRemaining)d supply")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if supply.urgency == .critical || supply.urgency == .out {
                            Text(supply.urgency == .out ? "Out - reorder now" : "Runs out in \(supply.daysRemaining) days")
                                .font(.caption2.weight(.medium)).foregroundStyle(Theme.high)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if supply.quantity > 0 {
                            Button(action: onUse) {
                                Text("Use")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Theme.primary.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Button { showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Quantity adjuster
            if showAdjuster {
                HStack(spacing: 16) {
                    Text("Adjust quantity")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()

                    Button { onUpdateQuantity(max(0, supply.quantity - 1)) } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Theme.high.opacity(supply.quantity > 0 ? 1 : 0.3), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(supply.quantity <= 0)

                    Text("\(supply.quantity)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(minWidth: 30)

                    Button { onUpdateQuantity(supply.quantity + 1) } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Theme.normal, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)

                    // Quick add amounts
                    ForEach([5, 10], id: \.self) { amt in
                        Button { onUpdateQuantity(supply.quantity + amt) } label: {
                            Text("+\(amt)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Theme.muted)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .alert("Delete Supply", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Remove \"\(supply.name)\" from your supplies?")
        }
    }
}

// MARK: - Add Supply Sheet

struct AddSupplySheet: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let client = SupplyClient()

    @State private var name = ""
    @State private var category = "pumpPod"
    @State private var quantity = ""
    @State private var usageRate = ""
    @State private var notes = ""

    let categories = [
        ("pumpPod", "Pump Pods"),
        ("cgmSensor", "CGM Sensors"),
        ("insulin", "Insulin"),
        ("testStrips", "Test Strips"),
        ("ketoneStrips", "Ketone Strips"),
        ("needles", "Pen Needles"),
        ("skinPrep", "Skin Prep"),
        ("adhesive", "Adhesive/Patches"),
        ("other", "Other"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Supply Info")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        TextField("Supply name", text: $name)
                            .font(.subheadline)
                            .padding(12)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))

                        Picker("Category", selection: $category) {
                            ForEach(categories, id: \.0) { cat in
                                Text(cat.1).tag(cat.0)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.primary)

                        HStack {
                            Text("Quantity").font(.subheadline).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            TextField("0", text: $quantity)
                                .font(.subheadline.weight(.medium).monospacedDigit())
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                        }

                        HStack {
                            Text("Days per unit").font(.subheadline).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            TextField("1", text: $usageRate)
                                .font(.subheadline.weight(.medium).monospacedDigit())
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("days").font(.caption).foregroundStyle(Theme.textTertiary)
                        }

                        TextField("Notes (optional)", text: $notes)
                            .font(.subheadline)
                            .padding(12)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(20)
                    .card()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.bg)
            .navigationTitle("Add Supply")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            _ = await client.createSupply(
                                name: name,
                                category: category,
                                quantity: Int(quantity) ?? 0,
                                usageRateDays: Double(usageRate) ?? 1.0,
                                notes: notes
                            )
                            onSave()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(name.isEmpty ? Theme.textTertiary : Theme.primary)
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SupplyTrackerView()
    }
}
