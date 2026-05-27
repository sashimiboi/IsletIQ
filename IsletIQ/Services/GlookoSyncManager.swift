import Foundation
import SwiftData
#if canImport(WebKit)
import WebKit
#endif

/// Headless Glooko auto-sync.
///
/// Once the user connects Glooko via `GlookoLoginView`, the session cookies
/// live in `WKWebsiteDataStore.default()`. This manager spins up an offscreen
/// `WKWebView` that loads `my.glooko.com`, rides those cookies back into the
/// authenticated dashboard, auto-clicks Export to CSV (same JS the login
/// sheet uses), captures the download, and imports CGM rows into SwiftData
/// — all without any UI surfacing.
///
/// Call `performSyncIfNeeded(modelContext:)` from app-foreground transitions.
/// It self-throttles to at most one sync per `minInterval`.
@MainActor
final class GlookoSyncManager: NSObject {
    static let shared = GlookoSyncManager()

    /// Don't auto-sync more than once per hour.
    static let minInterval: TimeInterval = 3600

    #if canImport(WebKit)
    private var activeWebView: WKWebView?
    private var modelContext: ModelContext?
    private var timeoutTask: Task<Void, Never>?
    private var pendingDownloadDestination: URL?
    private var didImport = false

    /// Entry point for opportunistic sync. No-ops when:
    /// - user hasn't done an initial sync via the login sheet yet,
    /// - session cookies have expired,
    /// - another sync is already running,
    /// - we synced within the cooldown window.
    func performSyncIfNeeded(modelContext: ModelContext) {
        guard GlookoClient.isAuthenticated else { return }
        // Don't run until the user has done a first export through the sheet —
        // otherwise we'd be silently importing data they haven't opted into.
        guard let last = GlookoClient.lastSync else { return }
        guard activeWebView == nil else { return }
        if Date().timeIntervalSince(last) < Self.minInterval { return }
        startSync(modelContext: modelContext)
    }

    /// Force a sync regardless of cooldown. Useful for a manual "Sync Now"
    /// button if we expose one later.
    func forceSync(modelContext: ModelContext) {
        guard GlookoClient.isAuthenticated, activeWebView == nil else { return }
        startSync(modelContext: modelContext)
    }

    private func startSync(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.didImport = false

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // Silent background sync only needs incremental data — grab the last
        // day's readings each time and let dedup handle overlap. Ready flag
        // is set immediately because there's no user to tap Sync Now.
        let bootstrap = """
        window.__glookoRange = '\(GlookoClient.SyncRange.d1.rawValue)';
        window.__glookoReady = true;
        """
        let rangeScript = WKUserScript(
            source: bootstrap,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(rangeScript)

        let blob = WKUserScript(
            source: GlookoClient.blobInterceptorJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(blob)
        let export = WKUserScript(
            source: GlookoClient.autoExportJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(export)

        config.userContentController.add(self, name: "glookoBlob")
        config.userContentController.add(self, name: "glookoDiag")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: GlookoClient.loginURL))
        self.activeWebView = webView

        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self, self.activeWebView != nil else { return }
            self.teardown()
        }
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        activeWebView?.stopLoading()
        let ucc = activeWebView?.configuration.userContentController
        ucc?.removeScriptMessageHandler(forName: "glookoBlob")
        ucc?.removeScriptMessageHandler(forName: "glookoDiag")
        activeWebView = nil
        modelContext = nil
        pendingDownloadDestination = nil
    }

    private func handleCSV(data: Data, filename: String) {
        guard !didImport, let ctx = modelContext else { return }
        didImport = true
        _ = try? GlookoClient.importArchive(
            data: data,
            suggestedFilename: filename,
            modelContext: ctx
        )
        teardown()
    }
    #else
    func performSyncIfNeeded(modelContext: ModelContext) {}
    func forceSync(modelContext: ModelContext) {}
    #endif
}

#if canImport(WebKit)
extension GlookoSyncManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        // Session expired — Glooko bounced us back to login. Clear the flag
        // so the Settings card flips back to "Connect" and bail.
        if url.path.hasPrefix("/users/sign_in") {
            UserDefaults.standard.removeObject(forKey: GlookoClient.sessionFlagKey)
            teardown()
            return
        }
        webView.evaluateJavaScript(GlookoClient.autoExportJS) { _, _ in }
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        teardown()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse {
            let disposition = (http.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
            let mime = (http.mimeType ?? "").lowercased()
            if disposition.contains("attachment") || mime.contains("csv") {
                decisionHandler(.download)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }
}

extension GlookoSyncManager: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + suggestedFilename)
        pendingDownloadDestination = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = pendingDownloadDestination else { return }
        defer { try? FileManager.default.removeItem(at: url); pendingDownloadDestination = nil }
        guard let data = try? Data(contentsOf: url) else { teardown(); return }
        let stripped = url.lastPathComponent
            .components(separatedBy: "_")
            .dropFirst()
            .joined(separator: "_")
        let name = stripped.isEmpty ? "glooko.csv" : stripped
        handleCSV(data: data, filename: name)
    }

    func download(_ download: WKDownload,
                  didFailWithError error: Error,
                  resumeData: Data?) {
        teardown()
    }
}

extension GlookoSyncManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "glookoBlob",
           let body = message.body as? [String: Any],
           let b64 = body["base64"] as? String,
           let data = Data(base64Encoded: b64) {
            let filename = (body["filename"] as? String) ?? "glooko.csv"
            handleCSV(data: data, filename: filename)
        }
        // glookoDiag messages are ignored in silent sync; they're only useful
        // in the login sheet where we can show the user what's happening.
    }
}
#endif
