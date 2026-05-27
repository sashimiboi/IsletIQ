# Libre / Nightscout / Tidepool wiring

Three new `@Observable` managers now exist:

- `IsletIQ/Services/LibreManager.swift`
- `IsletIQ/Services/NightscoutManager.swift`
- `IsletIQ/Services/TidepoolManager.swift`

Each does its own SwiftData merge (origin tags: `libre` / `nightscout` /
`tidepool`), so readings/boluses flow into the dashboard automatically via the
existing `@Query` on `GlucoseReading` and `InsulinEntry`.

The following edits are needed to actually call them. The sandbox blocked
writes to existing files during this session, so apply manually.

---

## 1. `IsletIQ/IsletIQApp.swift` — foreground refresh

Inside the `.onChange(of: scenePhase)` block, in the `.active` branch,
append after the Glooko sync task:

```swift
// Libre / Nightscout / Tidepool foreground pulls. Each no-ops if the
// user hasn't connected that integration.
Task {
    let ctx = sharedModelContainer.mainContext
    let libre = LibreManager()
    if libre.isLoggedIn { await libre.fetchLatest(modelContext: ctx) }
    let ns = NightscoutManager()
    if ns.isLoggedIn { await ns.fetchLatest(modelContext: ctx) }
    let tp = TidepoolManager()
    if tp.isLoggedIn { await tp.fetchLatest(modelContext: ctx) }
}
```

### Background refresh

In `handleBackgroundRefresh(_:)` (the top-level function at the bottom of
the file), inside the `workTask`, after the Dexcom block, append:

```swift
// Opportunistic pulls for the other CGM integrations. SwiftData writes
// from a background task need their own container context.
let bgContainer = try? ModelContainer(
    for: GlucoseReading.self, InsulinEntry.self
)
if let ctx = bgContainer?.mainContext {
    let libre = await MainActor.run { LibreManager() }
    if await MainActor.run(body: { libre.isLoggedIn }) {
        await libre.fetchLatest(modelContext: ctx)
    }
    let ns = await MainActor.run { NightscoutManager() }
    if await MainActor.run(body: { ns.isLoggedIn }) {
        await ns.fetchLatest(modelContext: ctx)
    }
    let tp = await MainActor.run { TidepoolManager() }
    if await MainActor.run(body: { tp.isLoggedIn }) {
        await tp.fetchLatest(modelContext: ctx)
    }
}
```

---

## 2. `IsletIQ/ContentView.swift` — instantiate managers

Next to the existing `@State private var healthKit = HealthKitManager()`,
add:

```swift
@State private var libre = LibreManager()
@State private var nightscout = NightscoutManager()
@State private var tidepool = TidepoolManager()
```

If you want the Settings sheet to show live sync state, pass them into
`SettingsView` like the existing managers (`healthKit`, `dexcomManager`).

---

## 3. `IsletIQ/Views/SettingsView.swift` — Last Sync + Sync Now + Disconnect

Each of the three cards today only has a "Connect" button. Mirror the
Dexcom pattern (lines ~323-429): when `KeychainHelper.load(key: ...) != nil`,
show Last Sync, a Sync Now button, and a Disconnect button.

Minimal change: accept the three managers as `@Bindable` inputs and, in the
three cards, replace the single `onConnect` closure with a richer body that
checks the manager's `isLoggedIn` and calls `fetchLatest(modelContext:)` /
`logout()`.

---

## 4. `IsletIQ/Views/NightscoutLoginView.swift` — token field

Add a second SecureField:

```swift
@State private var accessToken = ""
// ...
SecureField("Access Token (optional)", text: $accessToken)
    .textContentType(.password)
    .padding(14)
    .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
```

In `connect()`, after saving the URL:

```swift
if !accessToken.isEmpty {
    KeychainHelper.save(key: "nightscout_token", value: accessToken)
}
```

Leave the existing API_SECRET field — users can populate either.

---

## Notes

- **Nightscout API_SECRET hashing** is now handled inside `NightscoutManager`
  via `CryptoKit.Insecure.SHA1`. Users enter the plain secret; the manager
  hashes it before sending the `api-secret` header (per NS spec). If the
  user pastes a 40-char SHA1 digest directly, the manager won't re-hash.
- **Tidepool auth is legacy** (`x-tidepool-session-token`). Tidepool started
  migrating to Keycloak/OIDC in Dec 2022 and paused issuing new client IDs in
  2024. The legacy path still works for existing individual-user accounts but
  is on a sunset track — if Tidepool ever turns it off, this manager needs an
  OAuth2 flow.
- **Libre re-auth:** `LibreManager.fetchLatest` retries once on auth failure
  using the stored email/password, since LibreLink Up tokens expire quickly.
- All three managers write to SwiftData with `importOrigin` tagged so a
  future per-integration wipe (`Disconnect and clear imported data`) can
  target one source cleanly.
