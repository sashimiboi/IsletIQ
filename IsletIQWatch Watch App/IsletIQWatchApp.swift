import SwiftUI

@main
struct IsletIQWatchApp: App {
    @State private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(connectivity)
        }
    }
}
