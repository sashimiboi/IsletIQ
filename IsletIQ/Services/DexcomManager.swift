import Foundation
import SwiftData

@Observable
final class DexcomManager {
    var isLoggedIn: Bool = false
    var isLoading: Bool = false
    var error: String?
    var lastSync: Date?
    var liveReadings: [DexcomShareClient.ShareGlucoseReading] = []

    private let client = DexcomShareClient()
    private var sessionId: String?
    private var timer: Timer?

    init() {
        // Check if we have stored credentials
        if let _ = KeychainHelper.load(key: "dexcom_session") {
            isLoggedIn = true
        }
    }

    func login(username: String, password: String) async {
        isLoading = true
        error = nil

        do {
            let session = try await client.login(username: username, password: password)
            sessionId = session
            KeychainHelper.save(key: "dexcom_session", value: session)
            KeychainHelper.save(key: "dexcom_username", value: username)
            KeychainHelper.save(key: "dexcom_password", value: password)

            await MainActor.run {
                isLoggedIn = true
                isLoading = false
            }

            // Fetch initial data
            await fetchLatest()
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func logout() {
        KeychainHelper.delete(key: "dexcom_session")
        KeychainHelper.delete(key: "dexcom_username")
        KeychainHelper.delete(key: "dexcom_password")
        sessionId = nil
        isLoggedIn = false
        liveReadings = []
        timer?.invalidate()
    }

    func fetchLatest() async {
        // Try stored session first, re-login if needed
        var session = sessionId ?? KeychainHelper.load(key: "dexcom_session")

        if session == nil {
            // Try re-login with stored credentials
            guard let user = KeychainHelper.load(key: "dexcom_username"),
                  let pass = KeychainHelper.load(key: "dexcom_password") else {
                await MainActor.run { error = "No stored credentials" }
                return
            }
            do {
                session = try await client.login(username: user, password: pass)
                sessionId = session
                KeychainHelper.save(key: "dexcom_session", value: session!)
            } catch {
                await MainActor.run {
                    self.error = "Re-login failed: \(error.localizedDescription)"
                    self.isLoggedIn = false
                }
                return
            }
        }

        guard let validSession = session else { return }

        do {
            let readings = try await client.fetchLatestReadings(sessionId: validSession)
            await MainActor.run {
                self.liveReadings = readings
                self.lastSync = Date()
                self.error = nil
            }
        } catch {
            // Session might be expired, try re-login
            if let user = KeychainHelper.load(key: "dexcom_username"),
               let pass = KeychainHelper.load(key: "dexcom_password") {
                do {
                    let newSession = try await client.login(username: user, password: pass)
                    self.sessionId = newSession
                    KeychainHelper.save(key: "dexcom_session", value: newSession)
                    let readings = try await client.fetchLatestReadings(sessionId: newSession)
                    await MainActor.run {
                        self.liveReadings = readings
                        self.lastSync = Date()
                        self.error = nil
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.fetchLatest() }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
    }

    // Convert live readings to GlucoseReading models
    func toGlucoseReadings() -> [GlucoseReading] {
        liveReadings.compactMap { reading in
            guard let ts = reading.timestamp else { return nil }
            return GlucoseReading(
                value: reading.safeValue,
                timestamp: ts,
                trendArrow: reading.trendArrow,
                source: .cgm
            )
        }
    }

    var latestValue: Int? {
        liveReadings.first?.Value
    }

    var latestTrend: TrendArrow {
        liveReadings.first?.trendArrow ?? .flat
    }
}
