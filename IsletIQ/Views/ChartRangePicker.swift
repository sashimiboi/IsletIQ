import SwiftUI

/// Reusable pill row for the 1d / 2d / 14d / 30d filter set so every
/// chart in the app picks ranges the same way. Bind `selection` and
/// the picker handles the rest.
struct ChartRangePicker: View {
    @Binding var selection: ChartRange
    var ranges: [ChartRange] = ChartRange.allCases

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ranges, id: \.self) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = range }
                } label: {
                    Text(range.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(selection == range ? .white : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selection == range ? Theme.primary.opacity(0.7) : Theme.muted,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
