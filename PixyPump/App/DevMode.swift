import Foundation

/// Owner mode: everything unlocked (buddy items, gear, colours) without earning it.
/// Only exists in Debug builds (running from Xcode), so it can never ship in the App Store version.
nonisolated enum DevMode {
    static let unlockAllKey = "dev.unlockAll"

    static var unlockAll: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: unlockAllKey)
        #else
        false
        #endif
    }
}
