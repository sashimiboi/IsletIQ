import SwiftUI

/// Banner shown when CGM data is older than the freshness threshold.
/// Drop into any view that derives insights from glucose so users
/// understand the data underlying the insight may be out of date.
struct StaleDataBanner: View {
    let ageDescription: String
    var onTapRefresh: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("CGM data is stale")
                    .font(.subheadline.weight(.semibold))
                Text("Last reading \(ageDescription). Insights below may be out of date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onTapRefresh {
                Button("Refresh", action: onTapRefresh)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange.opacity(0.4), lineWidth: 1)
        )
    }
}

#Preview {
    VStack {
        StaleDataBanner(ageDescription: "32 min ago")
        StaleDataBanner(ageDescription: "1 hr ago", onTapRefresh: {})
    }
    .padding()
}
