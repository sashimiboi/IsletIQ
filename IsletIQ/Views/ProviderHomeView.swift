import SwiftUI

struct ProviderHomeView: View {
    @State private var patients: [PatientRosterEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selection: PatientRosterEntry?
    @State private var authManager = AuthManager()
    private let client = RosterClient()

    var body: some View {
        NavigationSplitView {
            rosterSidebar
        } detail: {
            if let patient = selection {
                PatientDetailView(patient: patient)
            } else {
                placeholderDetail
            }
        }
        .tint(Theme.primary)
        .task { await loadRoster() }
    }

    private var rosterSidebar: some View {
        Group {
            if isLoading && patients.isEmpty {
                ProgressView("Loading roster...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if patients.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    Section {
                        rosterSummaryRow
                    }
                    ForEach(groupedByPriority(), id: \.0) { bucket, entries in
                        Section(bucket.label) {
                            ForEach(entries) { p in
                                RosterRow(patient: p)
                                    .tag(p)
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.sidebar)
                #endif
            }
        }
        .navigationTitle("Roster")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadRoster() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primary)
                }
                .disabled(isLoading)
            }
        }
        .refreshable { await loadRoster() }
        .background(Theme.bg)
    }

    private var rosterSummaryRow: some View {
        let critical = patients.filter { $0.priorityBucket == .critical }.count
        let watch = patients.filter { $0.priorityBucket == .watch }.count
        return HStack(spacing: 12) {
            summaryStat(label: "Critical", value: critical, color: Theme.high)
            Divider().frame(height: 28)
            summaryStat(label: "Watch", value: watch, color: Theme.elevated)
            Divider().frame(height: 28)
            summaryStat(label: "Total", value: patients.count, color: Theme.primary)
        }
        .padding(.vertical, 4)
    }

    private func summaryStat(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholderDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text("Select a patient")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text("Pick a patient from your roster to see their recent glucose, adherence, and supply signals.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("No patients linked yet")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text("Once patients are linked to your provider account, they'll appear here sorted by attention level.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.high)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupedByPriority() -> [(PatientPriority, [PatientRosterEntry])] {
        let order: [PatientPriority] = [.critical, .watch, .ok]
        return order.compactMap { bucket in
            let entries = patients.filter { $0.priorityBucket == bucket }
            return entries.isEmpty ? nil : (bucket, entries)
        }
    }

    private func loadRoster() async {
        isLoading = true
        error = nil
        let fetched = await client.fetchRoster()
        await MainActor.run {
            self.patients = fetched
            self.isLoading = false
            if fetched.isEmpty && !authManager.userRole.isProvider {
                self.error = "Your account is not a provider. Contact support."
            }
        }
    }
}

private struct RosterRow: View {
    let patient: PatientRosterEntry

    var body: some View {
        HStack(spacing: 12) {
            priorityDot
            VStack(alignment: .leading, spacing: 3) {
                Text(patient.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let tir = patient.tir_pct {
                        signalChip(icon: "target", text: "TIR \(Int(tir))%", color: tirColor(tir))
                    }
                    if patient.hypo_events_14d > 0 {
                        signalChip(icon: "arrow.down.right", text: "\(patient.hypo_events_14d) hypo", color: Theme.low)
                    }
                    if patient.low_supplies > 0 {
                        signalChip(icon: "shippingbox", text: "\(patient.low_supplies) low", color: Theme.elevated)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var priorityDot: some View {
        Circle()
            .fill(priorityColor)
            .frame(width: 10, height: 10)
    }

    private var priorityColor: Color {
        switch patient.priorityBucket {
        case .critical: Theme.high
        case .watch:    Theme.elevated
        case .ok:       Theme.normal
        }
    }

    private func tirColor(_ pct: Double) -> Color {
        if pct < 50 { return Theme.high }
        if pct < 65 { return Theme.elevated }
        return Theme.normal
    }

    private func signalChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.medium).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
    }
}

private struct PatientDetailView: View {
    let patient: PatientRosterEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                signalGrid
                Text("Per-patient insight pane coming in the next phase — recent glucose chart, adherence timeline, supply status, and an insight summary land here.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationTitle(patient.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.primary.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(initials)
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(patient.email)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    private var signalGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                signalBox("Time in Range (14d)", value: patient.tir_pct.map { "\(Int($0))%" } ?? "—", color: Theme.primary)
                signalBox("Hypos (14d)", value: "\(patient.hypo_events_14d)", color: patient.hypo_events_14d > 3 ? Theme.high : Theme.normal)
            }
            HStack(spacing: 12) {
                signalBox("Adherence (7d)", value: patient.adherence_pct_7d.map { "\(Int($0))%" } ?? "—", color: Theme.accent)
                signalBox("Low Supplies", value: "\(patient.low_supplies)", color: patient.low_supplies > 0 ? Theme.elevated : Theme.normal)
            }
        }
    }

    private func signalBox(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .card()
    }

    private var initials: String {
        let name = patient.displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2, let f = parts.first?.first, let l = parts.last?.first {
            return "\(f)\(l)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
