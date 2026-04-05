import SwiftUI

struct LogMealView: View {
    @Environment(\.dismiss) private var dismiss
    var healthKit: HealthKitManager

    @State private var mealName = ""
    @State private var carbs = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Meal name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What did you eat?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        TextField("e.g. Chicken burrito", text: $mealName)
                            .font(.subheadline)
                            .padding(12)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(20)
                    .card()

                    // Macros
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Nutrition")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        MacroField(label: "Carbs", unit: "g", value: $carbs, color: Theme.primary, icon: "leaf.fill")
                        Divider()
                        MacroField(label: "Calories", unit: "kcal", value: $calories, color: Theme.elevated, icon: "flame.fill")
                        Divider()
                        MacroField(label: "Protein", unit: "g", value: $protein, color: Theme.teal, icon: "fish.fill")
                        Divider()
                        MacroField(label: "Fat", unit: "g", value: $fat, color: Theme.elevated, icon: "drop.fill")
                    }
                    .padding(20)
                    .card()

                    // Save
                    Button {
                        Task { await saveMeal() }
                    } label: {
                        Text("Log to HealthKit")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                canSave ? Theme.primary : Theme.textTertiary,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .disabled(!canSave)
                    .buttonStyle(.plain)

                    // HealthKit badge
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Saves to Apple Health")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.bg)
            .navigationTitle("Log Meal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .overlay {
                if saved {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.normal)
                        Text("Logged to HealthKit")
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

    private var canSave: Bool {
        !mealName.isEmpty && !carbs.isEmpty
    }

    private func saveMeal() async {
        await healthKit.logMeal(
            name: mealName,
            calories: Double(calories) ?? 0,
            carbs: Double(carbs) ?? 0,
            protein: Double(protein) ?? 0,
            fat: Double(fat) ?? 0
        )
        withAnimation(.spring(duration: 0.4)) { saved = true }
        try? await Task.sleep(for: .seconds(1.2))
        dismiss()
    }
}

struct MacroField: View {
    let label: String
    let unit: String
    @Binding var value: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            TextField("0", text: $value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 30, alignment: .leading)
        }
    }
}

#Preview {
    LogMealView(healthKit: HealthKitManager())
}
