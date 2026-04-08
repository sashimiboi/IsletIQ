import SwiftUI

struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    var editing: Medication?
    var onSave: () -> Void

    @State private var name = ""
    @State private var dosage = ""
    @State private var category = "other"
    @State private var frequency = "daily"
    @State private var scheduleTimes: [Date] = [Calendar.current.date(from: DateComponents(hour: 8, minute: 0))!]
    @State private var notes = ""
    @State private var saving = false

    private let medClient = MedicationClient()

    private let categories = [
        ("other", "Other"), ("adjunct", "Adjunct"), ("statin", "Statin"),
        ("thyroid", "Thyroid"), ("vitamin", "Vitamin"), ("supplement", "Supplement"),
    ]

    private let frequencies = [
        ("daily", "Daily"), ("twice_daily", "Twice daily"),
        ("three_times", "3x daily"), ("weekly", "Weekly"), ("as_needed", "As needed"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Name + Dosage
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Medication")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        TextField("Name (e.g. Metformin)", text: $name)
                            .font(.subheadline)
                            .padding(12)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
                        TextField("Dosage (e.g. 500mg)", text: $dosage)
                            .font(.subheadline)
                            .padding(12)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(20)
                    .card()

                    // Category + Frequency
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Schedule")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        HStack {
                            Text("Category")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Picker("", selection: $category) {
                                ForEach(categories, id: \.0) { cat in
                                    Text(cat.1).tag(cat.0)
                                }
                            }
                            .tint(Theme.primary)
                        }

                        Divider()

                        HStack {
                            Text("Frequency")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Picker("", selection: $frequency) {
                                ForEach(frequencies, id: \.0) { freq in
                                    Text(freq.1).tag(freq.0)
                                }
                            }
                            .tint(Theme.primary)
                        }

                        Divider()

                        // Schedule times
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Times")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Button {
                                    scheduleTimes.append(Date())
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                            ForEach(scheduleTimes.indices, id: \.self) { i in
                                HStack {
                                    DatePicker("", selection: $scheduleTimes[i], displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                    if scheduleTimes.count > 1 {
                                        Button {
                                            scheduleTimes.remove(at: i)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(.red.opacity(0.7))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .card()

                    // Notes
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        TextField("Optional notes", text: $notes)
                            .font(.subheadline)
                            .padding(12)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(20)
                    .card()

                    // Save button
                    Button {
                        Task { await save() }
                    } label: {
                        Text(editing != nil ? "Update Medication" : "Add Medication")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                name.isEmpty ? Theme.textTertiary : Theme.primary,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .disabled(name.isEmpty || saving)
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Theme.bg)
            .navigationTitle(editing != nil ? "Edit Medication" : "Add Medication")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let med = editing {
                    name = med.name
                    dosage = med.dosage
                    category = med.category
                    frequency = med.frequency
                    notes = med.notes
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    scheduleTimes = med.scheduleTimes.compactMap { formatter.date(from: $0) }
                    if scheduleTimes.isEmpty {
                        scheduleTimes = [Calendar.current.date(from: DateComponents(hour: 8))!]
                    }
                }
            }
        }
    }

    private func save() async {
        saving = true
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let times = scheduleTimes.map { formatter.string(from: $0) }

        if let med = editing {
            _ = await medClient.updateMedication(
                id: med.id, name: name, dosage: dosage,
                category: category, frequency: frequency,
                scheduleTimes: times, notes: notes
            )
        } else {
            _ = await medClient.createMedication(
                name: name, dosage: dosage, category: category,
                frequency: frequency, scheduleTimes: times, notes: notes
            )
        }
        await MainActor.run {
            saving = false
            onSave()
            dismiss()
        }
    }
}
