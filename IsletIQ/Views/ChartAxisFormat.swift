import Foundation

/// Centralized date-axis formatter for IsletIQ charts.
/// The dashboard's 1d/2d/14d/30d filter and any future range picker
/// should run timestamps through `ChartAxisFormat.label(for:range:)` so
/// labels stay readable and consistent across views (glucose, sleep,
/// nutrition, etc.).
enum ChartAxisFormat {
    /// Format a single x-axis label for the given timestamp at the given range.
    static func label(for date: Date, range: ChartRange) -> String {
        let f = DateFormatter()
        f.locale = .current
        switch range {
        case .day:
            // 1d: "9 AM", "3 PM"
            f.dateFormat = "h a"
        case .threeDays:
            // 3d: "Mon 9 AM" so users can tell the days apart
            f.dateFormat = "EEE h a"
        case .fourteenDays, .thirtyDays:
            // Multi-week: "Apr 14"
            f.dateFormat = "MMM d"
        }
        return f.string(from: date)
    }

    /// Suggested number of axis labels for a given chart width and range.
    /// Bigger ranges get fewer labels to stop them overlapping.
    static func suggestedLabelCount(for range: ChartRange) -> Int {
        switch range {
        case .day: 5         // every ~5 hours
        case .threeDays: 4     // every ~18 hours
        case .fourteenDays: 7
        case .thirtyDays: 6
        }
    }
}
