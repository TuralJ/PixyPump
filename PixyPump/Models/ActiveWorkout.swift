import Foundation
import Observation

/// Today's workout: not started → in progress → finished.
/// Logging a set starts it automatically; logging after finishing reopens it.
/// Everything resets by itself the next day.
@MainActor @Observable
final class ActiveWorkout {
    static let shared = ActiveWorkout()
    private static let key = "activeWorkout.v1"

    /// The date this state belongs to ("2026-10-12").
    private var dateKey: String
    /// Plan day being trained (1-based).
    private(set) var storedDay: Int
    private var startedAt: Double
    private var finishedAt: Double
    /// Finished with exercises still left (no "finish every set" bonus today).
    private var early: Bool

    enum Phase {
        case notStarted
        case inProgress(since: Date)
        case finished(start: Date, end: Date)
    }

    private init() {
        let saved = UserDefaults.standard.dictionary(forKey: Self.key) ?? [:]
        dateKey = saved["date"] as? String ?? ""
        storedDay = saved["day"] as? Int ?? 0
        startedAt = saved["start"] as? Double ?? 0
        finishedAt = saved["end"] as? Double ?? 0
        early = saved["early"] as? Bool ?? false
    }

    /// True if today's workout was finished while exercises were still left.
    var finishedEarlyToday: Bool { isToday && early }

    /// "2026-10-16" for a date (used to key per-day rewards).
    static func key(for date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    private static var todayKey: String {
        Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    private var isToday: Bool { dateKey == Self.todayKey }

    var phase: Phase {
        guard isToday, startedAt > 0 else { return .notStarted }
        let start = Date(timeIntervalSince1970: startedAt)
        if finishedAt > 0 { return .finished(start: start, end: Date(timeIntervalSince1970: finishedAt)) }
        return .inProgress(since: start)
    }

    var isInProgress: Bool { if case .inProgress = phase { return true } else { return false } }
    var isFinished: Bool { if case .finished = phase { return true } else { return false } }

    /// The plan day of today's workout (nil if you haven't started).
    var day: Int? { isToday && startedAt > 0 && storedDay > 0 ? storedDay : nil }

    /// Minutes from Start to Finish (for the summary), if known.
    var minutesToday: Int? {
        guard case let .finished(start, end) = phase else { return nil }
        return max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    // MARK: Changes

    func start(day: Int) {
        // Check before moving dateKey to today, or yesterday's unfinished workout would look "in progress".
        let carryOn = isInProgress
        dateKey = Self.todayKey
        storedDay = day
        if !carryOn {
            startedAt = Date.now.timeIntervalSince1970
            early = false
        }
        finishedAt = 0
        save()
        TrainingLog.record(day: day)
    }

    /// Called whenever a set is logged.
    func noteSetLogged(day: Int?) {
        switch phase {
        case .notStarted:
            start(day: day ?? storedDay)
        case .finished:
            // Logged one more after finishing: carry on with the same workout.
            finishedAt = 0
            if let day { storedDay = day; TrainingLog.record(day: day) }
            save()
        case .inProgress:
            break
        }
    }

    /// `early`: finished with exercises still to do.
    func finish(early: Bool = false) {
        guard isInProgress else { return }
        finishedAt = Date.now.timeIntervalSince1970
        if early { self.early = true }
        save()
        // No rest timer after the workout.
        RestTimer.shared.stop()
    }

    /// Started by mistake (nothing logged yet): back to "not started".
    func cancel() {
        RestTimer.shared.stop()
        startedAt = 0
        finishedAt = 0
        early = false
        save()
        TrainingLog.remove(on: .now)
    }

    func reset() {
        dateKey = ""
        storedDay = 0
        startedAt = 0
        finishedAt = 0
        early = false
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func save() {
        let values: [String: Any] = ["date": dateKey, "day": storedDay, "start": startedAt, "end": finishedAt,
                                     "early": early]
        UserDefaults.standard.set(values, forKey: Self.key)
    }
}
