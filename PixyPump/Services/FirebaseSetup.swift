import Foundation
import FirebaseCore

// Firebase is only used for accounts. `GoogleService-Info.plist` isn't in git (each of us downloads
// our own from the Firebase console), so a build without it skips Firebase and accounts stay in demo mode.

enum FirebaseSetup {
    /// True once Firebase has been started with a config file.
    private(set) static var isConfigured = false

    /// Call once at launch, before anything uses Firebase.
    static func configure() {
        guard !isConfigured,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        isConfigured = true
    }
}
