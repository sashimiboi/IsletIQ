import SwiftUI

struct LogInsulinView: View {
    @Environment(\.dismiss) private var dismiss
    var healthKit: HealthKitManager?

    @State private var units = ""
    @State private var insulinType: InsulinLogType = .bolus
    @State private var timestamp: Date = .now
    @State private var note = ""
    @State private var saved = false

    enum InsulinLogType: String, CaseIterable {
        case bolus = "Bolus"
        case correction = "Correction"
        case basal = "Basal"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Units input
                    VStack(spacing: 6) {
                        Text(units.isEmpty ? "--" : units)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primary)
                        Text("units")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .card()

                    // Number pad
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(1...9, id: \.self) { num in
                            InsulinPadButton(label: "\(num)") { appendDigit("\(num)") }
                        }
                        InsulinPadButton(label: ".", isSecondary: false) { appendDigit(".") }
                        InsulinPadButton(label: "0") { appendDigit("0") }
                        InsulinPadButton(label: "delete.left", isSymbol: true, isSecondary: true) {
                            if !units.isEmpty { units.removeLast() }
                        }
                    }

                    // Type & details
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Details")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        // Type picker
                        HStack(spacing: 6) {
                            ForEach(InsulinLogType.allCases, id: \.self) { type in
                                Button {
                                    insulinType = type
                                } label: {
                                    Text(type.rawValue)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(insulinType == type ? .white : Theme.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            insulinType == type ? Theme.primary : Theme.primary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(Theme.textTertiary)
                            DatePicker("", selection: $timestamp)
                                .labelsHidden()
                                .tint(Theme.primary)
                        }

                        Divider()

                        TextField("Note (optional)", text: $note)
                            .font(.subheadline)
                    }
                    .padding(20)
                    .card()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.bg)
            .navigationTitle("Log Insulin")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveInsulin() }
                        .fontWeight(.semibold)
                        .foregroundStyle(units.isEmpty ? Theme.textTertiary : Theme.primary)
                        .disabled(units.isEmpty)
                }
            }
            .overlay {
                if saved {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.normal)
                        Text("Logged")
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

    private func appendDigit(_ digit: String) {
        if digit == "." && units.contains(".") { return }
        if units.count >= 5 { return }
        units += digit
    }

    private func saveInsulin() {
        guard let value = Double(units), let hk = healthKit else { return }
        Task {
            await hk.logInsulin(units: value, date: timestamp, isBasal: insulinType == .basal)
            withAnimation(.spring(duration: 0.4)) { saved = true }
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        }
    }
}

struct InsulinPadButton: View {
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSecondary ? Theme.muted : Theme.cardBg)
                    .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LogInsulinView()
}
