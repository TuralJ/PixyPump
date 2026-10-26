import Foundation

/// Remembers which plan day you trained on each date, so the app can
/// suggest the next one — even if you picked a different day than suggested,
/// skipped a week, or deleted a workout.
@MainActor
enum TrainingLog {
    private static let key = "trainedDays.v1"   // "2026-10-13" → plan day (1-based)

    private static func dateKey(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    private static var all: [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    static func record(day: Int, on date: Date = .now) {
        guard day > 0 else { return }
        var log = all
        log[dateKey(date)] = day
        UserDefaults.standard.set(log, forKey: key)
    }

    static func remove(on date: Date) {
        var log = all
        log[dateKey(date)] = nil
        UserDefaults.standard.set(log, forKey: key)
    }

    static func day(on date: Date) -> Int? { all[dateKey(date)] }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// What to train next, and why.
struct DaySuggestion {
    /// The plan day to do next (1-based).
    let day: Int
    /// Your most recent workout before today, if any.
    let lastDay: Int?
    let lastDate: Date?

    /// "Last time: Day 3 · Pull-ups & Incline, yesterday" — shown under the day on the Start card.
    @MainActor var reason: String? {
        guard let lastDay, let lastDate else { return nil }
        let days = Calendar.current.dateComponents([.day],
                                                   from: Calendar.current.startOfDay(for: lastDate),
                                                   to: Calendar.current.startOfDay(for: .now)).day ?? 0
        let when: String
        switch days {
        case 1: when = "yesterday"
        case 2...6: when = lastDate.formatted(.dateTime.weekday(.wide))
        default: when = "\(days) days ago"
        }
        let name = lastDay <= Routine.dayCount ? " · \(Routine.dayName(lastDay))" : ""
        if days >= 7 { return "Welcome back! Your last workout was Day \(lastDay)\(name), \(when)." }
        return "Last time: Day \(lastDay)\(name), \(when)."
    }
}

extension Routine {
    /// Next day in the rotation after your most recent workout before today.
    /// Uses what you actually trained (not a fixed calendar), so picking another
    /// day, missing days or deleting a workout all keep the rotation right.
    static func suggestion(from sets: [WorkoutSet]) -> DaySuggestion {
        guard dayCount > 0 else { return DaySuggestion(day: 1, lastDay: nil, lastDate: nil) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Most recent training date before today (sets are only real workouts, not warm-ups alone).
        let past = sets.filter { !$0.isWarmup && $0.date < today }
        guard let lastDate = past.map(\.date).max() else {
            return DaySuggestion(day: 1, lastDay: nil, lastDate: nil)
        }
        let session = WorkoutSession(day: calendar.startOfDay(for: lastDate),
                                     sets: past.filter { calendar.isDate($0.date, inSameDayAs: lastDate) })
        guard let lastDay = TrainingLog.day(on: lastDate) ?? session.routineDay else {
            return DaySuggestion(day: 1, lastDay: nil, lastDate: lastDate)
        }
        let clamped = min(max(lastDay, 1), dayCount)
        return DaySuggestion(day: clamped % dayCount + 1, lastDay: clamped, lastDate: lastDate)
    }
}
