import SwiftUI
import Charts

struct ProviderHomeView: View {
    var body: some View {
        #if os(macOS)
        // macOS: roster owns the full split-view window;
        // Agent and Profile are toolbar sheets so there's no nested sidebar.
        ProviderMacLayout()
        #else
        // iOS: standard bottom tab bar.
        TabView {
            ProviderRosterTab()
                .tabItem { Label("Roster", systemImage: "person.2.fill") }

            NavigationStack {
                ProviderChatView(isEmbedded: true)
            }
            .tabItem { Label("Agent", systemImage: "sparkles") }

            NavigationStack {
                ProviderSettingsView(isEmbedded: true)
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Theme.primary)
        #endif
    }
}

#if os(macOS)
private struct ProviderMacLayout: View {
    @State private var patients: [PatientRosterEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selection: PatientRosterEntry?
    @State private var showingLinkPatient = false
    @State private var showingAgent = false
    @State private var showingProfile = false
    @State private var searchText = ""
    @State private var cohortFilter: ProviderCohortFilter = .all
    private let client = RosterClient()

    var body: some View {
        NavigationSplitView {
            rosterList
        } detail: {
            if let patient = selection {
                PatientDetailView(patient: patient)
            } else {
                macPlaceholder
            }
        }
        .tint(Theme.primary)
        .frame(minWidth: 960, minHeight: 600)
        .task { await loadRoster() }
        .sheet(isPresented: $showingLinkPatient) {
            LinkPatientView { Task { await loadRoster() } }
        }
        .sheet(isPresented: $showingAgent) {
            ProviderChatView()
                .frame(minWidth: 680, minHeight: 520)
        }
        .sheet(isPresented: $showingProfile) {
            ProviderSettingsView()
                .frame(minWidth: 480, minHeight: 420)
        }
    }

    private var rosterList: some View {
        Group {
            if isLoading && patients.isEmpty {
                ProgressView("Loading roster...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if patients.isEmpty {
                macEmptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        searchAndFilterBar
                        summaryRow
                        let groups = groupedByPriority()
                        ForEach(groups, id: \.0) { bucket, entries in
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader(bucket)
                                ForEach(entries) { p in
                                    Button { selection = p } label: {
                                        RosterRow(patient: p, isSelected: selection?.id == p.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Roster")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAgent = true } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.primary)
                }
                .help("Cohort Agent")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingLinkPatient = true } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Theme.primary)
                }
                .help("Link a patient")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await loadRoster() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Theme.primary)
                }
                .help("Refresh")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button { showingProfile = true } label: {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(Theme.primary)
                }
                .help("Profile")
            }
        }
        .background(Theme.bg)
    }

    private var searchAndFilterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                TextField("Search by name or email", text: $searchText)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 11))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProviderCohortFilter.allCases) { f in
                        Button { cohortFilter = f } label: {
                            Text(f.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(cohortFilter == f ? .white : Theme.textSecondary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(cohortFilter == f ? Theme.primary : Theme.muted, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var summaryRow: some View {
        let critical = patients.filter { $0.priorityBucket == .critical }.count
        let watch = patients.filter { $0.priorityBucket == .watch }.count
        return HStack(spacing: 12) {
            stat("Critical", value: critical, color: Theme.high)
            Divider().frame(height: 36)
            stat("Watch", value: watch, color: Theme.elevated)
            Divider().frame(height: 36)
            stat("Total", value: patients.count, color: Theme.primary)
        }
        .padding(.vertical, 12).padding(.horizontal, 8).card()
    }

    private func stat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ bucket: PatientPriority) -> some View {
        let color: Color = bucket == .critical ? Theme.high : bucket == .watch ? Theme.elevated : Theme.normal
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(bucket.label.uppercased())
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.textSecondary).tracking(0.5)
            Spacer()
        }.padding(.horizontal, 4).padding(.top, 4)
    }

    private var macPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 48)).foregroundStyle(Theme.textTertiary)
            Text(patients.isEmpty ? "No patients yet" : "Select a patient")
                .font(.headline).foregroundStyle(Theme.textSecondary)
            Text(patients.isEmpty
                 ? "Link a patient to see their signals here."
                 : "Pick a patient from your roster to see their recent data.")
                .font(.subheadline).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button { showingLinkPatient = true } label: {
                Label("Add Patient", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.primary, in: Capsule())
            }.buttonStyle(.plain).padding(.top, 4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
    }

    private var macEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.badge.plus").font(.system(size: 52)).foregroundStyle(Theme.primary)
            Text("Build your roster").font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text("Link patients by email to see their TIR, hypos, adherence, and supply signals.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            Button { showingLinkPatient = true } label: {
                Label("Link your first patient", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Theme.primary, in: Capsule())
            }.buttonStyle(.plain).padding(.top, 4)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredPatients: [PatientRosterEntry] {
        patients.filter { p in
            let matchesSearch = searchText.isEmpty ||
                p.displayName.localizedCaseInsensitiveContains(searchText) ||
                p.email.localizedCaseInsensitiveContains(searchText)
            let matchesCohort = cohortFilter == .all || (p.cohort ?? "") == cohortFilter.rawValue
            return matchesSearch && matchesCohort
        }
    }

    private func groupedByPriority() -> [(PatientPriority, [PatientRosterEntry])] {
        let order: [PatientPriority] = [.critical, .watch, .ok]
        return order.compactMap { bucket in
            let entries = filteredPatients.filter { $0.priorityBucket == bucket }
            return entries.isEmpty ? nil : (bucket, entries)
        }
    }

    private func loadRoster() async {
        isLoading = true
        error = nil
        let fetched = await client.fetchRoster()
        await MainActor.run { patients = fetched; isLoading = false }
    }
}
#endif

// MARK: - Shared cohort filter (used by iOS roster tab and macOS layout)

enum ProviderCohortFilter: String, CaseIterable, Identifiable {
    case all, t1d, t2d, glp1, gdm
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:  return "All"
        case .t1d:  return "T1D"
        case .t2d:  return "T2D"
        case .glp1: return "GLP-1"
        case .gdm:  return "GDM"
        }
    }
}

// MARK: - Roster tab (extracted so ProviderHomeView stays thin)

private struct ProviderRosterTab: View {
    @State private var patients: [PatientRosterEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selection: PatientRosterEntry?
    @State private var showingLinkPatient = false
    @State private var searchText: String = ""
    @State private var cohortFilter: ProviderCohortFilter = .all
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

    private var filteredPatients: [PatientRosterEntry] {
        patients.filter { p in
            let matchesSearch = searchText.isEmpty ||
                p.displayName.localizedCaseInsensitiveContains(searchText) ||
                p.email.localizedCaseInsensitiveContains(searchText)
            let matchesCohort = (cohortFilter == .all) || (cohortKey(for: p) == cohortFilter.rawValue)
            return matchesSearch && matchesCohort
        }
    }

    private func cohortKey(for entry: PatientRosterEntry) -> String {
        entry.cohort ?? ""
    }

    private var rosterSidebar: some View {
        Group {
            if isLoading && patients.isEmpty {
                ProgressView("Loading roster...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if patients.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        searchAndFilterBar
                        rosterSummaryCard
                        let groups = groupedByPriority()
                        if groups.isEmpty {
                            noMatchesPlaceholder
                        } else {
                            ForEach(groups, id: \.0) { bucket, entries in
                                VStack(alignment: .leading, spacing: 8) {
                                    sectionHeader(bucket)
                                    VStack(spacing: 10) {
                                        ForEach(entries) { p in
                                            Button {
                                                selection = p
                                            } label: {
                                                RosterRow(patient: p, isSelected: selection?.id == p.id)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Roster")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLinkPatient = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primary)
                }
                .help("Link a patient to your roster")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadRoster() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primary)
                }
                .help("Refresh roster")
            }
        }
        .refreshable { await loadRoster() }
        .background(Theme.bg)
        .sheet(isPresented: $showingLinkPatient) {
            LinkPatientView {
                Task { await loadRoster() }
            }
        }
    }

    private var searchAndFilterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search by name or email", text: $searchText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProviderCohortFilter.allCases) { f in
                        Button {
                            cohortFilter = f
                        } label: {
                            Text(f.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(cohortFilter == f ? .white : Theme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    cohortFilter == f ? Theme.primary : Theme.muted,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var noMatchesPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(Theme.textTertiary)
            Text("No patients match")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Try a different search or filter.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var rosterSummaryCard: some View {
        let critical = patients.filter { $0.priorityBucket == .critical }.count
        let watch = patients.filter { $0.priorityBucket == .watch }.count
        return HStack(spacing: 12) {
            summaryStat(label: "Critical", value: critical, color: Theme.high)
            Divider().frame(height: 36)
            summaryStat(label: "Watch", value: watch, color: Theme.elevated)
            Divider().frame(height: 36)
            summaryStat(label: "Total", value: patients.count, color: Theme.primary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .card()
    }

    private func summaryStat(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ bucket: PatientPriority) -> some View {
        let color: Color = {
            switch bucket {
            case .critical: return Theme.high
            case .watch:    return Theme.elevated
            case .ok:       return Theme.normal
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(bucket.label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var placeholderDetail: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text(patients.isEmpty ? "No patients yet" : "Select a patient")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text(patients.isEmpty
                 ? "Link a patient to see their recent glucose, adherence, and supplies here."
                 : "Pick a patient from your roster to see their recent glucose, adherence, and supplies.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 10) {
                Button {
                    showingLinkPatient = true
                } label: {
                    Label("Add Patient", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                Label("Use Agent tab to ask about your panel", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Theme.primary)
            Text("Build your roster")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Link patients by email to see their TIR, hypos, adherence, and supply signals at a glance. Patients can keep using IsletIQ on their phone exactly as before.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                showingLinkPatient = true
            } label: {
                Label("Link your first patient", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.high)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupedByPriority() -> [(PatientPriority, [PatientRosterEntry])] {
        let order: [PatientPriority] = [.critical, .watch, .ok]
        let pool = filteredPatients
        return order.compactMap { bucket in
            let entries = pool.filter { $0.priorityBucket == bucket }
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
        }
    }
}

private struct RosterRow: View {
    let patient: PatientRosterEntry
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(patient.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    cohortBadge
                }
                HStack(spacing: 6) {
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
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(isSelected ? Theme.primary.opacity(0.10) : Color.clear)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(isSelected ? Theme.primary.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        Circle()
            .fill(priorityColor.opacity(0.12))
            .frame(width: 38, height: 38)
            .overlay(
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(priorityColor)
            )
    }

    private var initials: String {
        let name = patient.displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2, let f = parts.first?.first, let l = parts.last?.first {
            return "\(f)\(l)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
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

    private var cohortBadge: some View {
        Text(patient.cohortLabel)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.primary.opacity(0.10), in: Capsule())
    }

    private func signalChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.medium).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct PatientDetailView: View {
    let patient: PatientRosterEntry
    @State private var detail: PatientDetail?
    @State private var isLoading = true
    @State private var error: String?
    private let client = RosterClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                signalGrid
                if isLoading && detail == nil {
                    ProgressView("Loading patient data...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let detail {
                    cgmChartCard(detail.cgm)
                    medicationsCard(detail.medications)
                    suppliesCard(detail.supplies)
                    if let sleep = detail.sleep {
                        sleepCard(sleep)
                    }
                    if let nutrition = detail.nutrition {
                        nutritionCard(nutrition)
                    }
                } else if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.high)
                        .padding()
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationTitle(detail?.patient.displayName ?? patient.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: patient.id) { await loadDetail() }
        .refreshable { await loadDetail() }
    }

    private func loadDetail() async {
        isLoading = true
        error = nil
        let fetched = await client.fetchPatientDetail(patient.id)
        await MainActor.run {
            self.detail = fetched
            self.isLoading = false
            if fetched == nil {
                self.error = "Couldn't load this patient. They may not be linked to your account."
            }
        }
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
                Text(detail?.patient.displayName ?? patient.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail?.patient.email ?? patient.email)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if let cohort = detail?.patient.cohort {
                    Text(cohortLabel(cohort))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.primary.opacity(0.1), in: Capsule())
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    private func cohortLabel(_ raw: String) -> String {
        switch raw {
        case "t1d": return "T1D"
        case "t2d": return "T2D"
        case "glp1": return "GLP-1"
        default: return raw.uppercased()
        }
    }

    private var signalGrid: some View {
        let cgm = detail?.cgm
        let tir = cgm?.tir_pct ?? patient.tir_pct
        let hypo = cgm?.hypo_events_14d ?? patient.hypo_events_14d
        let adh = patient.adherence_pct_7d
        let lowCount = detail?.supplies.filter(\.is_low).count ?? patient.low_supplies
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                signalBox("Time in Range (14d)", value: tir.map { "\(Int($0))%" } ?? "—", color: Theme.primary)
                signalBox("Hypos (14d)", value: "\(hypo)", color: hypo > 3 ? Theme.high : Theme.normal)
            }
            HStack(spacing: 12) {
                signalBox("Adherence (7d)", value: adh.map { "\(Int($0))%" } ?? "—", color: Theme.accent)
                signalBox("Low Supplies", value: "\(lowCount)", color: lowCount > 0 ? Theme.elevated : Theme.normal)
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

    private func cgmChartCard(_ cgm: PatientCGM) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Glucose · last 14 days (hourly avg)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let avg = cgm.avg_mg_dl_14d {
                    Text("avg \(avg) mg/dL")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if cgm.series_14d.isEmpty {
                Text("No CGM readings in the last 14 days.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    RuleMark(y: .value("Low", 70))
                        .foregroundStyle(Theme.low.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                    RuleMark(y: .value("High", 180))
                        .foregroundStyle(Theme.high.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                    ForEach(cgm.series_14d) { p in
                        if let d = p.date {
                            LineMark(
                                x: .value("Time", d),
                                y: .value("mg/dL", p.mg_dl)
                            )
                            .foregroundStyle(Theme.primary)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartYScale(domain: 40...300)
                .frame(height: 180)
            }
        }
        .padding(16)
        .card()
    }

    private func medicationsCard(_ meds: [PatientMedication]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Medications · 7-day adherence")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if meds.isEmpty {
                Text("No active medications.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(meds) { med in
                    medicationRow(med)
                    if med.id != meds.last?.id { Divider() }
                }
            }
        }
        .padding(16)
        .card()
    }

    private func medicationRow(_ med: PatientMedication) -> some View {
        let pct = med.adherence_pct_7d
        let color: Color = {
            guard let p = pct else { return Theme.textTertiary }
            if p < 70 { return Theme.high }
            if p < 85 { return Theme.elevated }
            return Theme.normal
        }()
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(med.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(med.dosage.isEmpty ? med.frequency : "\(med.dosage) · \(med.frequency)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(pct.map { "\(Int($0))%" } ?? "—")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                Text("\(med.taken_7d) / \(med.expected_7d)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func suppliesCard(_ supplies: [PatientSupply]) -> some View {
        let lows = supplies.filter(\.is_low)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Supplies")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !lows.isEmpty {
                    Text("\(lows.count) running low")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.elevated)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.elevated.opacity(0.12), in: Capsule())
                }
            }
            if supplies.isEmpty {
                Text("No supplies tracked.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(supplies) { supply in
                    supplyRow(supply)
                    if supply.id != supplies.last?.id { Divider() }
                }
            }
        }
        .padding(16)
        .card()
    }

    private func supplyRow(_ supply: PatientSupply) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(supply.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(supply.quantity) on hand")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let days = supply.projected_days_remaining {
                Text("\(Int(days))d")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(supply.is_low ? Theme.high : Theme.textSecondary)
            } else {
                Text("—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func sleepCard(_ sleep: PatientSleep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sleep - last 7 nights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let avg = sleep.avg_hours_7d {
                    Text("avg \(String(format: "%.1f", avg))h")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if sleep.last_7d.isEmpty {
                Text("No sleep data recorded.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(sleep.last_7d) { night in
                    sleepRow(night)
                    if night.id != sleep.last_7d.last?.id { Divider() }
                }
            }
        }
        .padding(16)
        .card()
    }

    private func sleepRow(_ night: SleepNight) -> some View {
        let hoursColor: Color = {
            guard let h = night.total_hours else { return Theme.textTertiary }
            if h < 6 { return Theme.high }
            if h < 7 { return Theme.elevated }
            return Theme.normal
        }()
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortDate(night.date))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    if let deep = night.deep_minutes {
                        Text("Deep \(deep)m")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let rem = night.rem_minutes {
                        Text("REM \(rem)m")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer()
            if let h = night.total_hours {
                Text(String(format: "%.1fh", h))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(hoursColor)
            } else {
                Text("—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func nutritionCard(_ nutrition: PatientNutrition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nutrition - last 7 days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let carbs = nutrition.avg_carbs_per_day_7d {
                    Text("avg \(Int(carbs))g carbs/day")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if nutrition.meals_7d.isEmpty {
                Text("No meal data recorded.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                let byDate = Dictionary(grouping: nutrition.meals_7d, by: \.date)
                let sortedDates = byDate.keys.sorted(by: >)
                ForEach(sortedDates, id: \.self) { date in
                    if let meals = byDate[date] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shortDate(date))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                            ForEach(meals) { meal in
                                mealRow(meal)
                            }
                        }
                        if date != sortedDates.last { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .card()
    }

    private func mealRow(_ meal: MealRecord) -> some View {
        HStack {
            Text(meal.name)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(meal.carbs_g)g")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.primary)
            Text("\(meal.calories) cal")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 2)
    }

    private func shortDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    private var initials: String {
        let name = detail?.patient.displayName ?? patient.displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2, let f = parts.first?.first, let l = parts.last?.first {
            return "\(f)\(l)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
