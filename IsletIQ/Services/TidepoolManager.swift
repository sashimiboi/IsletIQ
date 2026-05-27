import Foundation
import SwiftData

/// Sync manager for Tidepool.
///
/// Caveat: as of Dec 2022 Tidepool started migrating auth to Keycloak /
/// OpenID Connect, and in 2024 they paused issuing new client IDs. The
/// legacy `x-tidepool-session-token` path this manager uses still works for
/// existing individual-user accounts but is on a sunset track — if Tidepool
/// ever turns it off entirely, we need an OAuth2 flow here.
///
/// Keychain keys: tidepool_token, tidepool_email, tidepool_password.
@Observable
final class TidepoolManager {
    var isLoggedIn: Bool = false
    var isLoading: Bool = false
    var error: String?
    var lastSync: Date?

    private let client = TidepoolClient()

    init() {
        isLoggedIn = KeychainHelper.load(key: "tidepool_token") != nil
    }

    func logout() {
        for k in ["tidepool_token", "tidepool_email", "tidepool_password"] {
            KeychainHelper.delete(key: k)
        }
        isLoggedIn = false
        lastSync = nil
    }

    func fetchLatest(modelContext: ModelContext? = nil) async {
        guard isLoggedIn,
              let email = KeychainHelper.load(key: "tidepool_email"),
              let pass  = KeychainHelper.load(key: "tidepool_password") else { return }

        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        do {
            // Tidepool session tokens are short-lived; re-login every sync
            // is simpler than managing refresh, since the client is an actor
            // and we already have the credentials stashed.
            _ = try await client.login(email: email, password: pass)
            let start = Calendar.current.date(byAdding: .day, value: -1, to: .now)
            async let cbg  = client.fetchData(type: "cbg",   startDate: start)
            async let bolus = client.fetchData(type: "bolus", startDate: start)
            let (cgm, bol) = try await (cbg, bolus)

            if let ctx = modelContext {
                await MainActor.run {
                    Self.mergeCGM(cgm, into: ctx)
                    Self.mergeBoluses(bol, into: ctx)
                }
            }
            await MainActor.run {
                self.lastSync = Date()
                self.error = nil
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    // MARK: - SwiftData merge

    @MainActor
    private static func mergeCGM(_ data: [TidepoolClient.DeviceDatum], into ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<GlucoseReading>())) ?? []
        let seen = Set(existing.map { Int($0.timestamp.timeIntervalSince1970) })
        var inserted = 0
        // Tidepool returns cbg values in mmol/L by default; DeviceDatum.mgDl
        // handles the conversion.
        let sorted = data.compactMap { d -> (Date, Int)? in
            guard let ts = d.timestamp, d.mgDl >= 30, d.mgDl <= 600 else { return nil }
            return (ts, d.mgDl)
        }.sorted { $0.0 < $1.0 }

        var previous: Int? = existing.sorted(by: { $0.timestamp < $1.timestamp }).last?.value
        for (ts, mgdl) in sorted {
            let key = Int(ts.timeIntervalSince1970)
            if seen.contains(key) { continue }
            ctx.insert(GlucoseReading(
                value: mgdl,
                timestamp: ts,
                trendArrow: Self.inferTrend(current: mgdl, previous: previous),
                source: .cgm,
                importOrigin: "tidepool"
            ))
            previous = mgdl
            inserted += 1
        }
        if inserted > 0 { try? ctx.save() }
    }

    @MainActor
    private static func mergeBoluses(_ data: [TidepoolClient.DeviceDatum], into ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<InsulinEntry>(
            predicate: #Predicate { $0.kindRaw == "bolus" }
        ))) ?? []
        let seen = Set(existing.map { "\(Int($0.timestamp.timeIntervalSince1970))|\($0.units)" })
        var inserted = 0
        for d in data {
            guard let ts = d.timestamp else { continue }
            // Tidepool's "normal" field is the delivered amount (units) for
            // a standard bolus; "extended" is the tail of a dual-wave.
            let units = (d.normal ?? 0) + (d.extended ?? 0)
            guard units > 0 else { continue }
            let key = "\(Int(ts.timeIntervalSince1970))|\(units)"
            if seen.contains(key) { continue }
            ctx.insert(InsulinEntry(
                timestamp: ts,
                units: units,
                kind: .bolus,
                carbs: d.carbInput ?? 0,
                source: "tidepool"
            ))
            inserted += 1
        }
        if inserted > 0 { try? ctx.save() }
    }

    /// Cheap directional trend from two samples. Tidepool doesn't ship a
    /// trend arrow on cbg rows, so we synthesize one the same way the Glooko
    /// importer does.
    private static func inferTrend(current: Int, previous: Int?) -> TrendArrow {
        guard let prev = previous else { return .flat }
        let delta = current - prev
        switch delta {
        case 20...:     return .risingFast
        case 6..<20:    return .rising
        case -5...5:    return .flat
        case -19...(-6):return .falling
        default:        return .fallingFast
        }
    }
}
