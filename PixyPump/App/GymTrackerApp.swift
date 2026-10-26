import SwiftUI
import SwiftData
import UserNotifications

@main
struct GymTrackerApp: App {
    /// Opened once at launch. If it can't open, we show an error instead of a
    /// blank app, so nothing new gets logged into a temporary empty store.
    private let container: Result<ModelContainer, Error>
    @State private var showSplash = true

    init() {
        // Show the "Rest's over" pop-up even while the app is open.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Pixel font + matching navigation bar titles.
        PixelFont.register()
        PixelFont.styleSystemBars()
        // Backup / CSV files from an earlier share shouldn't linger on the phone.
        DataTools.removeExportedFiles()
        container = AppData.container
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    switch container {
                    case .success(let container):
                        ContentView()
                            .modelContainer(container)
                    case .failure(let error):
                        DataErrorView(error: error)
                    }
                }
                // Animated splash on every cold start (tap to skip).
                if showSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
                    .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Color.brand)              // ice blue for links, toggles and rings
        }
    }
}

/// The one database for the whole app (anything that saves outside a screen uses this too).
@MainActor
enum AppData {
    static let container: Result<ModelContainer, Error> = Result {
        try ModelContainer(for: Exercise.self, WorkoutSet.self, FoodItem.self, FoodEntry.self,
                           SavedMeal.self, SavedMealItem.self)
    }
}

/// Shown only if your saved data can't be opened (e.g. after a bad update).
/// Your data is left untouched on the phone.
private struct DataErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label { Text("Couldn't open your data") } icon: { Image.pixel(.warning) }
        } description: {
            Text("Your workouts and food are still saved on this phone — nothing was deleted. Don't delete the app. Send this message to whoever updates \(AppInfo.name):\n\n\(error.localizedDescription)")
        }
        .textSelection(.enabled)
    }
}
