import Foundation
import SwiftData

/// Real-time sync manager for FreeStyle Libre (via LibreLink Up).
///
/// Design mirrors DexcomManager: in-memory `liveReadings` for immediate UI,
/// plus SwiftData persistence (origin="libre") so the dashboard picks up
/// Libre points through its existing `storedReadings` query.
///
/// Credentials (email/password/region) are saved in the Keychain by
/// LibreLinkLoginView; this manager auto-reauths on token expiry.
@Observable
final class LibreManager {
    var isLoggedIn: Bool = false
    var isLoading: Bool = false
    var error: String?
    var lastSync: Date?
    var liveReadings: [LibreLinkClient.GlucoseReading] = []

    private var client: LibreLinkClient
    private var timer: Timer?

    init() {
        let regionRaw = KeychainHelper.load(key: "libre_region") ?? "us"
        let region = LibreLinkClient.Region(rawValue: regionRaw) ?? .us
        self.client = LibreLinkClient(region: region)
        if KeychainHelper.load(key: "libre_token") != nil {
            isLoggedIn = true
        }
    }

    func logout() {
        for k in ["libre_token", "libre_email", "libre_password", "libre_region"] {
            KeychainHelper.delete(key: k)
        }
        isLoggedIn = false
        liveReadings = []
        lastSync = nil
        timer?.invalidate()
    }

    /// Fetch latest readings and persist to SwiftData. Auto-reauths on token
    /// expiry using the stored email/password.
    func fetchLatest(modelContext: ModelContext? = nil) async {
        guard isLoggedIn else { return }
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        do {
            let readings = try await tryFetch()
            await MainActor.run {
                self.liveReadings = readings
                self.lastSync = Date()
                self.error = nil
            }
            if let ctx = modelContext {
                await MainActor.run { Self.merge(readings, into: ctx) }
            }
        } catch {
            // One re-auth retry: token lifetimes on LibreLink Up are short.
            if (try? await relogin()) != nil,
               let readings = try? await tryFetch() {
                await MainActor.run {
                    self.liveReadings = readings
                    self.lastSync = Date()
                    self.error = nil
                }
                if let ctx = modelContext {
                    await MainActor.run { Self.merge(readings, into: ctx) }
                }
                return
            }
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func tryFetch() async throws -> [LibreLinkClient.GlucoseReading] {
        let connections = try await client.getConnections()
        guard let first = connections.first, let pid = first.patientId else {
            throw LibreLinkClient.LibreError.noConnections
        }
        return try await client.fetchReadings(patientId: pid)
    }

    private func relogin() async throws -> String {
        guard let email = KeychainHelper.load(key: "libre_email"),
              let pass  = KeychainHelper.load(key: "libre_password") else {
            throw LibreLinkClient.LibreError.invalidCredentials
        }
        let token = try await client.login(email: email, password: pass)
        KeychainHelper.save(key: "libre_token", value: token)
        return token
    }

    func startAutoRefresh() {
        timer?.invalidate()
        // Libre sensor samples at ~1/min, the LLU API exposes ~1/5min. 5-min
        // poll keeps us fresh without hammering the endpoint.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.fetchLatest() }
        }
    }

    func stopAutoRefresh() { timer?.invalidate() }

    // MARK: - SwiftData merge

    @MainActor
    private static func merge(_ readings: [LibreLinkClient.GlucoseReading], into ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<GlucoseReading>())) ?? []
        // Match Glooko's dedup approach: integer-second precision so re-parses
        // of the same timestamp don't double-insert.
        let seen = Set(existing.map { Int($0.timestamp.timeIntervalSince1970) })

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        let isoFallback = ISO8601DateFormatter()

        var inserted = 0
        for r in readings {
            guard let tsString = r.Timestamp,
                  let ts = formatter.date(from: tsString) ?? isoFallback.date(from: tsString) else { continue }
            let key = Int(ts.timeIntervalSince1970)
            guard !seen.contains(key), r.mgDl > 0 else { continue }
            ctx.insert(GlucoseReading(
                value: r.mgDl,
                timestamp: ts,
                trendArrow: Self.trendArrow(from: r.TrendArrow ?? 0),
                source: .cgm,
                importOrigin: "libre"
            ))
            inserted += 1
        }
        if inserted > 0 { try? ctx.save() }
    }

    private static func trendArrow(from code: Int) -> TrendArrow {
        switch code {
        case 1: return .fallingFast
        case 2: return .falling
        case 3: return .flat
        case 4: return .rising
        case 5: return .risingFast
        default: return .flat
        }
    }
}
