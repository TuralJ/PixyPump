import Foundation
import SwiftData

/// Spreadsheet export and "delete everything".
@MainActor
enum DataTools {

    // MARK: CSV export

    /// Two files you can open in Numbers, Excel or Google Sheets:
    /// every set you've logged, and everything you've eaten.
    static func exportCSV(context: ModelContext) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppInfo.name) export", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let dateFormat = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        let timeFormat = Date.ISO8601FormatStyle(timeZone: .current).time(includingFractionalSeconds: false)
        let unit = Units.symbol

        // Workouts
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>(sortBy: [SortDescriptor(\.date)]))
        var workouts = "date,time,exercise,weight,unit,reps\n"
        for set in sets {
            workouts += [
                set.date.formatted(dateFormat),
                set.date.formatted(timeFormat),
                csv(set.exercise?.name ?? ""),
                Units.number(set.weight),
                unit,
                "\(set.reps)",
            ].joined(separator: ",") + "\n"
        }

        // Food
        let entries = try context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
        var food = "date,meal,food,grams,kcal,protein_g,carbs_g,fat_g\n"
        for entry in entries {
            let n = entry.nutrition
            food += [
                entry.date.formatted(dateFormat),
                entry.meal.title,
                csv(entry.name),
                String(format: "%.0f", entry.grams),
                String(format: "%.0f", n.kcal),
                String(format: "%.1f", n.protein),
                String(format: "%.1f", n.carbs),
                String(format: "%.1f", n.fat),
            ].joined(separator: ",") + "\n"
        }

        // Body weight
        var weights = "date,weight,unit\n"
        for entry in BodyWeightStore.shared.entries {
            weights += [entry.date.formatted(dateFormat), Units.number(entry.kg), unit].joined(separator: ",") + "\n"
        }

        let stamp = Date.now.formatted(dateFormat)
        let workoutsURL = folder.appendingPathComponent("\(AppInfo.name) workouts \(stamp).csv")
        let foodURL = folder.appendingPathComponent("\(AppInfo.name) food \(stamp).csv")
        try Data(workouts.utf8).write(to: workoutsURL, options: [.atomic, .completeFileProtection])
        try Data(food.utf8).write(to: foodURL, options: [.atomic, .completeFileProtection])
        var urls = [workoutsURL, foodURL]
        if !BodyWeightStore.shared.entries.isEmpty {
            let weightURL = folder.appendingPathComponent("\(AppInfo.name) body weight \(stamp).csv")
            try Data(weights.utf8).write(to: weightURL, options: [.atomic, .completeFileProtection])
            urls.append(weightURL)
        }
        return urls
    }

    /// Quotes a text cell if it contains a comma or quote.
    private static func csv(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Removes backup / CSV files left in the temporary folder after sharing
    /// (they hold your health data). Called at launch and by "Delete all data".
    static func removeExportedFiles() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        try? fm.removeItem(at: tmp.appendingPathComponent("\(AppInfo.name) export", isDirectory: true))
        for name in (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? []
        where (name.hasPrefix("\(AppInfo.name) backup") || name.hasPrefix("Powerpuff backup")) && name.hasSuffix(".json") {
            try? fm.removeItem(at: tmp.appendingPathComponent(name))
        }
    }

    // MARK: Start fresh

    /// Removes every workout, food, saved meal and setting, then shows the welcome screens again.
    static func deleteEverything(context: ModelContext) {
        RestTimer.shared.stop()
        // Photos are stored as separate files: clear them one by one so they're really removed
        // (a bulk delete may leave the external files behind).
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] where exercise.imageData != nil {
            exercise.imageData = nil
        }
        try? context.save()
        try? context.delete(model: WorkoutSet.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: SavedMealItem.self)
        try? context.delete(model: SavedMeal.self)
        try? context.delete(model: FoodItem.self)
        try? context.save()

        let defaults = UserDefaults.standard
        let keys = Backup.settingKeys + [
            Prefs.userName, Prefs.unit, Prefs.haptics, Backup.lastBackupKey,
            "foodPresetVersion", "restTimerEnd", "restTimerDuration", "todayChanges.v1",
            "goalsSetUp", "workoutOpenNext", "restTimerAlarmID", HealthSync.enabledKey, "healthSavedDays",
            AppTheme.accentKey, AppTheme.surfaceKey, AppTheme.headingKey,
            DailyStreak.reminderKey, "rewardsVersion",
            GettingStarted.claimedKey, GettingStarted.buddyKey, GettingStarted.bagKey,
            "notif.training", "notif.rewards", "notif.missions", "notif.food", "notif.comeback",
            SFX.enabledKey, SFX.volumeKey, SFX.packKey,
            // Appearance and customisation.
            ConfettiStyle.key, CelebrationLevel.key, RestSkin.key, XPBarStyle.key, PlateColors.key,
            ProfileBanner.key, "homeOrder", "homeHidden", "plateStackBest",   // homeOrder/homeHidden: old Home layout
            "streakReminderOn", DevMode.unlockAllKey, TabRequest.key, AuthStore.nudgeDismissedKey,
            // Workout mode.
            "restExercise", WorkoutModeTips.seenKey,
        ]
        for key in keys { defaults.removeObject(forKey: key) }
        removeExportedFiles()
        URLCache.shared.removeAllCachedResponses()   // Open Food Facts lookups (what you scanned)

        BodyWeightStore.shared.removeAll()
        ActiveWorkout.shared.reset()
        TrainingLog.clear()
        BadgeLog.clear()
        QuestLog.clear()
        XPLedger.clear()
        BonusXP.clear()
        Inventory.clear()
        RewardsStart.clear()
        LevelLog.clear()
        DailyStreak.cancelReminder()
        NotificationPlanner.cancelAll()
        RoutineStore.shared.resetToStarterPlan()
        // Back to the main app icon.
        Task { _ = await AppIconChoice.pixel.apply() }
        defaults.set(false, forKey: Prefs.onboarded)   // welcome screens appear again
    }
}
