import Foundation
import SwiftData
import CryptoKit

/// Sync manager for Nightscout.
///
/// Does its own HTTP calls (rather than routing through NightscoutClient) so
/// we can add the two things Nightscout's spec requires that the existing
/// client is missing:
///
///   1. API_SECRET must be sent as SHA1-hashed `api-secret` header. Users
///      enter their plain secret; we hash it. If they pasted a 40-char hex
///      digest, we don't re-hash.
///   2. Token auth (`?token=…` query param) is supported in parallel. Modern
///      NS sites prefer access tokens over the legacy API_SECRET.
///
/// Keychain keys: nightscout_url, nightscout_secret, nightscout_token.
@Observable
final class NightscoutManager {
    var isLoggedIn: Bool = false
    var isLoading: Bool = false
    var error: String?
    var lastSync: Date?

    init() {
        isLoggedIn = KeychainHelper.load(key: "nightscout_url") != nil
    }

    func logout() {
        for k in ["nightscout_url", "nightscout_secret", "nightscout_token"] {
            KeychainHelper.delete(key: k)
        }
        isLoggedIn = false
        lastSync = nil
    }

    func fetchLatest(modelContext: ModelContext? = nil) async {
        guard isLoggedIn, let urlBase = KeychainHelper.load(key: "nightscout_url") else { return }
        let secret = KeychainHelper.load(key: "nightscout_secret")
        let token  = KeychainHelper.load(key: "nightscout_token")

        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        do {
            async let entries    = fetchEntries(base: urlBase, secret: secret, token: token, count: 288)
            async let treatments = fetchTreatments(base: urlBase, secret: secret, token: token, count: 100)
            let (es, ts) = try await (entries, treatments)

            if let ctx = modelContext {
                await MainActor.run {
                    Self.mergeEntries(es, into: ctx)
                    Self.mergeTreatments(ts, into: ctx)
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

    // MARK: - HTTP

    private func buildRequest(base: String, path: String, query: [String: String], secret: String?, token: String?) -> URLRequest? {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: "\(trimmed)/api/v1\(path)")
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let t = token, !t.isEmpty {
            items.append(URLQueryItem(name: "token", value: t))
        }
        if !items.isEmpty { components?.queryItems = items }
        guard let url = components?.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let s = secret, !s.isEmpty {
            req.setValue(Self.sha1Secret(s), forHTTPHeaderField: "api-secret")
        }
        return req
    }

    private static func sha1Secret(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // If the user already pasted a SHA1 digest, don't re-hash it.
        if trimmed.count == 40, trimmed.allSatisfy({ $0.isHexDigit }) {
            return trimmed.lowercased()
        }
        let digest = Insecure.SHA1.hash(data: Data(trimmed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct NSEntry: Decodable {
        let sgv: Int?
        let date: Double?
        let direction: String?
    }

    private struct NSTreatment: Decodable {
        let eventType: String?
        let created_at: String?
        let insulin: Double?
        let carbs: Double?
    }

    private func fetchEntries(base: String, secret: String?, token: String?, count: Int) async throws -> [NSEntry] {
        guard let req = buildRequest(base: base, path: "/entries/sgv.json", query: ["count": "\(count)"], secret: secret, token: token) else {
            throw URLError(.badURL)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
            throw URLError(.userAuthenticationRequired)
        }
        return try JSONDecoder().decode([NSEntry].self, from: data)
    }

    private func fetchTreatments(base: String, secret: String?, token: String?, count: Int) async throws -> [NSTreatment] {
        guard let req = buildRequest(base: base, path: "/treatments.json", query: ["count": "\(count)"], secret: secret, token: token) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode([NSTreatment].self, from: data)
    }

    // MARK: - SwiftData merge

    @MainActor
    private static func mergeEntries(_ entries: [NSEntry], into ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<GlucoseReading>())) ?? []
        let seen = Set(existing.map { Int($0.timestamp.timeIntervalSince1970) })
        var inserted = 0
        for e in entries {
            guard let sgv = e.sgv, sgv >= 30, sgv <= 600,
                  let epochMs = e.date else { continue }
            let ts = Date(timeIntervalSince1970: epochMs / 1000.0)
            let key = Int(ts.timeIntervalSince1970)
            if seen.contains(key) { continue }
            ctx.insert(GlucoseReading(
                value: sgv,
                timestamp: ts,
                trendArrow: Self.trend(from: e.direction),
                source: .cgm,
                importOrigin: "nightscout"
            ))
            inserted += 1
        }
        if inserted > 0 { try? ctx.save() }
    }

    @MainActor
    private static func mergeTreatments(_ treatments: [NSTreatment], into ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<InsulinEntry>(
            predicate: #Predicate { $0.kindRaw == "bolus" }
        ))) ?? []
        let seen = Set(existing.map { "\(Int($0.timestamp.timeIntervalSince1970))|\($0.units)" })
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        var inserted = 0
        for t in treatments {
            guard let units = t.insulin, units > 0,
                  let tsString = t.created_at,
                  let ts = iso.date(from: tsString) ?? isoPlain.date(from: tsString) else { continue }
            // Nightscout bolus event types
            let type = (t.eventType ?? "").lowercased()
            guard type.contains("bolus") || type.contains("correction") else { continue }
            let key = "\(Int(ts.timeIntervalSince1970))|\(units)"
            if seen.contains(key) { continue }
            ctx.insert(InsulinEntry(
                timestamp: ts,
                units: units,
                kind: .bolus,
                carbs: t.carbs ?? 0,
                source: "nightscout"
            ))
            inserted += 1
        }
        if inserted > 0 { try? ctx.save() }
    }

    private static func trend(from direction: String?) -> TrendArrow {
        switch (direction ?? "Flat") {
        case "DoubleUp": return .risingFast
        case "SingleUp", "FortyFiveUp": return .rising
        case "Flat": return .flat
        case "FortyFiveDown", "SingleDown": return .falling
        case "DoubleDown": return .fallingFast
        default: return .flat
        }
    }
}
