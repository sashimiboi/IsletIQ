import SwiftUI
import SwiftData

struct LogEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var glucoseValue: String = ""
    @State private var selectedMeal: MealTag = .none
    @State private var note: String = ""
    @State private var timestamp: Date = .now
    @State private var showConfirmation = false
    @State private var carbsValue: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Glucose display
                    VStack(spacing: 4) {
                        Text(glucoseValue.isEmpty ? "--" : glucoseValue)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(currentColor)
                            .animation(.easeInOut(duration: 0.15), value: glucoseValue)
                        Text("mg/dL")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .card()

                    // Number pad
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(1...9, id: \.self) { num in
                            PadButton(label: "\(num)") { appendDigit("\(num)") }
                        }
                        PadButton(label: "C", isSecondary: true) { glucoseValue = "" }
                        PadButton(label: "0") { appendDigit("0") }
                        PadButton(label: "delete.left", isSymbol: true, isSecondary: true) {
                            if !glucoseValue.isEmpty { glucoseValue.removeLast() }
                        }
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Details")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        // Meal tags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MealTag.allCases, id: \.self) { tag in
                                    Button {
                                        selectedMeal = tag
                                    } label: {
                                        Text(tag.rawValue)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(selectedMeal == tag ? .white : Theme.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(
                                                selectedMeal == tag ? Theme.primary : Theme.primary.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Divider()

                        // Carbs
                        HStack {
                            Image(systemName: "fork.knife")
                                .foregroundStyle(Theme.teal)
                                .font(.subheadline)
                            Text("Carbs")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            TextField("0", text: $carbsValue)
                                .font(.subheadline.weight(.medium).monospacedDigit())
                                .multilineTextAlignment(.trailing)
                                .frame(width: 50)
                            Text("g")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }

                        Divider()

                        // Time
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(Theme.textTertiary)
                                .font(.subheadline)
                            DatePicker("", selection: $timestamp)
                                .labelsHidden()
                                .tint(Theme.primary)
                        }

                        Divider()

                        TextField("Add a note...", text: $note, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(3)
                    }
                    .padding(20)
                    .card()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.bg)
            .navigationTitle("Log Reading")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveReading() }
                        .fontWeight(.semibold)
                        .foregroundStyle(glucoseValue.isEmpty ? Theme.textTertiary : Theme.primary)
                        .disabled(glucoseValue.isEmpty)
                }
            }
            .overlay {
                if showConfirmation {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.normal)
                        Text("Saved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(32)
                    .card()
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var currentColor: Color {
        guard let val = Int(glucoseValue) else { return Theme.primary }
        return Theme.statusColor(GlucoseReading(value: val).status)
    }

    private func appendDigit(_ digit: String) {
        guard glucoseValue.count < 3 else { return }
        glucoseValue += digit
    }

    private func saveReading() {
        guard let value = Int(glucoseValue) else { return }
        let reading = GlucoseReading(value: value, timestamp: timestamp, note: note, mealTag: selectedMeal, source: .manual)
        modelContext.insert(reading)
        withAnimation(.spring(duration: 0.4)) { showConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}

struct PadButton: View {
    let label: String
    var isSymbol: Bool = false
    var isSecondary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isSymbol {
                    Image(systemName: label).font(.title3)
                } else {
                    Text(label).font(.title3.weight(.medium))
                }
            }
            .foregroundStyle(isSecondary ? Theme.textSecondary : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSecondary ? Theme.muted : Theme.cardBg)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LogEntryView()
        .modelContainer(for: GlucoseReading.self, inMemory: true)
}
