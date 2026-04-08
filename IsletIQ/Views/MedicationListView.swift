import SwiftUI

struct MedicationListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var medications: [Medication] = []
    @State private var showAddMed = false
    @State private var editingMed: Medication?

    private let medClient = MedicationClient()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if medications.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "pills.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.textTertiary)
                        Text("No medications yet")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Text("Tap + to add your first medication")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(medications) { med in
                        MedicationCard(medication: med, onEdit: {
                            editingMed = med
                        }, onDelete: {
                            Task { await deleteMed(med.id) }
                        }, onToggle: {
                            Task { await toggleActive(med) }
                        })
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Theme.bg)
        .navigationTitle("Medications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddMed = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .sheet(isPresented: $showAddMed) {
            AddMedicationView(onSave: { Task { await load() } })
        }
        .sheet(item: $editingMed) { med in
            AddMedicationView(editing: med, onSave: { Task { await load() } })
        }
        .task { await load() }
    }

    private func load() async {
        medications = await medClient.fetchMedications()
    }

    private func deleteMed(_ id: Int) async {
        _ = await medClient.deleteMedication(id: id)
        await load()
    }

    private func toggleActive(_ med: Medication) async {
        _ = await medClient.updateMedication(id: med.id, isActive: !med.isActive)
        await load()
    }
}

// MARK: - Medication Card

struct MedicationCard: View {
    let medication: Medication
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: medication.categoryIcon)
                    .font(.caption)
                    .foregroundStyle(medication.isActive ? Theme.primary : Theme.textTertiary)
                Text(medication.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(medication.isActive ? Theme.textPrimary : Theme.textTertiary)
                Spacer()
                Menu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button { onToggle() } label: {
                        Label(medication.isActive ? "Disable" : "Enable",
                              systemImage: medication.isActive ? "pause.circle" : "play.circle")
                    }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.textTertiary)
                        .padding(6)
                }
            }

            HStack(spacing: 12) {
                if !medication.dosage.isEmpty {
                    Label(medication.dosage, systemImage: "pills.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Label(medication.frequencyLabel, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if !medication.scheduleTimes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(medication.scheduleTimes, id: \.self) { time in
                        Text(time)
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.primary.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .opacity(medication.isActive ? 1 : 0.5)
        .card()
    }
}
