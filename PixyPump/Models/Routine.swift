import Foundation
import Observation

// MARK: - Your training plan (editable in the app)

/// One exercise in a day of the plan.
nonisolated struct RoutineItem: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var sets: Int = 3
    /// Rep range you aim for, e.g. 8–10. When you hit the top on every set,
    /// the app suggests adding weight next time.
    var repsLow: Int = 8
    var repsHigh: Int = 10

    var repsText: String { repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)–\(repsHigh)" }

    init(name: String, sets: Int = 3, repsLow: Int = 8, repsHigh: Int = 10) {
        self.name = name
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = repsHigh
    }

    // Plans saved by older versions don't have the rep range yet — fill in defaults.
    private nonisolated enum CodingKeys: String, CodingKey { case id, name, sets, repsLow, repsHigh }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 3
        repsLow = try c.decodeIfPresent(Int.self, forKey: .repsLow) ?? 8
        repsHigh = try c.decodeIfPresent(Int.self, forKey: .repsHigh) ?? 10
    }
}

/// One training day: a name and its exercises in order.
nonisolated struct RoutineDay: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var items: [RoutineItem]
}

/// Holds the plan and saves every change on the phone.
/// Edit it from Workout → ✎ or Settings → Training plan.
@MainActor @Observable
final class RoutineStore {
    static let shared = RoutineStore()
    static let maxDays = 7
    private static let key = "routineDays.v1"

    var days: [RoutineDay] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([RoutineDay].self, from: data) {
            days = saved
        } else {
            days = Self.starterPlan
        }
        renameOldPixyPumpDays()
    }

    /// One-time update: the PixyPump split's "Upper A"/"Upper B" got clearer names.
    /// Only touches days that still have the old name and the original first exercise.
    private func renameOldPixyPumpDays() {
        let flag = "renamedUpperDays.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let renames = [("Upper A", "Bench Press", "Bench & Rows"),
                       ("Upper B", "Pull-up", "Pull-ups & Incline")]
        var updated = days
        for index in updated.indices {
            for (oldName, firstExercise, newName) in renames
            where updated[index].name == oldName && updated[index].items.first?.name == firstExercise {
                updated[index].name = newName
            }
        }
        if updated != days { days = updated }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func resetToStarterPlan() { days = Self.starterPlan }

    /// Swaps one exercise for another in the plan for good, keeping its sets and reps.
    func replace(_ name: String, with replacement: String, onDay day: Int) {
        guard day >= 1, day <= days.count,
              let index = days[day - 1].items.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return }
        days[day - 1].items[index].name = replacement
    }

    func apply(_ template: RoutineTemplate?) {
        days = template?.makeDays() ?? []
    }

    /// Picks up a plan written by "Restore from backup".
    func reloadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([RoutineDay].self, from: data) {
            days = saved
        }
    }

    /// The original 4-day split.
    static var starterPlan: [RoutineDay] {
        starterLists.map { RoutineDay(name: $0.name, items: $0.exercises.map { RoutineItem(name: $0) }) }
    }

    nonisolated static let starterLists: [(name: String, exercises: [String])] = {
        // Named after each day's main lifts, so the two upper days are easy to tell apart.
        let names = ["Bench & Rows", "Legs & Shoulders", "Pull-ups & Incline", "Shoulders & Legs"]
        let lists: [[String]] = [
        // Day 1
        ["Bench Press",
         "Pendlay Row",
         "Incline Dumbbell Press",
         "Lat Pulldown",
         "Cable Row",
         "Curl (Barbell/Dumbbell)",
         "Overhead Triceps"],

        // Day 2
        ["Squat",
         "Seated Dumbbell Press",
         "Romanian Deadlift",
         "Lateral Raise",
         "Split Squat",
         "Dumbbell Skull Crusher",
         "Overhead Triceps"],

        // Day 3
        ["Pull-up",
         "Incline Bench Press",
         "Chest-Supported Row",
         "Weighted Dip",
         "Machine Press",
         "Incline Dumbbell Curl",
         "Triceps"],

        // Day 4
        ["Standing Press",
         "Lateral Raise",
         "Leg Press",
         "Lying Hamstring Curl",
         "Triceps",
         "Overhead Triceps"],
    ]
        return zip(names, lists).map { (name: $0, exercises: $1) }
    }()
}

// MARK: - Ready-made plans (picked during onboarding or in the plan editor)

nonisolated struct RoutineTemplate: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let days: [(name: String, exercises: [String])]

    var dayCount: Int { days.count }

    func makeDays() -> [RoutineDay] {
        days.map { RoutineDay(name: $0.name, items: $0.exercises.map { RoutineItem(name: $0) }) }
    }

    static let all: [RoutineTemplate] = [
        RoutineTemplate(
            id: "fullbody", name: "Full body", summary: "3 days a week · great to start with",
            days: [
                ("Full Body A", ["Squat", "Bench Press", "Barbell Row", "Lateral Raise",
                                 "Curl (Barbell/Dumbbell)", "Triceps Pushdown"]),
                ("Full Body B", ["Romanian Deadlift", "Standing Press", "Lat Pulldown",
                                 "Incline Dumbbell Press", "Hanging Leg Raise"]),
                ("Full Body C", ["Leg Press", "Incline Bench Press", "Chest-Supported Row",
                                 "Lying Hamstring Curl", "Hammer Curl", "Overhead Triceps"]),
            ]),
        RoutineTemplate(
            id: "upperlower", name: "Upper / Lower", summary: "4 days a week · balanced strength and size",
            days: [
                ("Upper A", ["Bench Press", "Barbell Row", "Seated Dumbbell Press", "Lat Pulldown",
                             "Curl (Barbell/Dumbbell)", "Triceps Pushdown"]),
                ("Lower A", ["Squat", "Romanian Deadlift", "Leg Press", "Lying Hamstring Curl", "Calf Raise"]),
                ("Upper B", ["Incline Dumbbell Press", "Pull-up", "Standing Press", "Cable Row",
                             "Lateral Raise", "Hammer Curl"]),
                ("Lower B", ["Deadlift", "Split Squat", "Seated Hamstring Curl", "Leg Extension",
                             "Hanging Leg Raise"]),
            ]),
        RoutineTemplate(
            id: "ppl", name: "Push / Pull / Legs", summary: "3 or 6 days a week · classic bodybuilding split",
            days: [
                ("Push", ["Bench Press", "Standing Press", "Incline Dumbbell Press", "Lateral Raise",
                          "Triceps Pushdown", "Overhead Triceps"]),
                ("Pull", ["Pull-up", "Barbell Row", "Lat Pulldown", "Face Pull",
                          "Curl (Barbell/Dumbbell)", "Hammer Curl"]),
                ("Legs", ["Squat", "Romanian Deadlift", "Leg Press", "Lying Hamstring Curl", "Calf Raise"]),
            ]),
        RoutineTemplate(
            id: "powerpuff", name: "\(AppInfo.name) split", summary: "4 days a week · upper/legs & shoulders",
            days: RoutineStore.starterLists),
    ]
}

// MARK: - Shortcuts used around the app

/// Read-only helpers on top of `RoutineStore` (screens update automatically when the plan changes).
@MainActor
enum Routine {
    private static var store: RoutineStore { RoutineStore.shared }

    /// Exercise names for each day.
    static var days: [[String]] { store.days.map { $0.items.map(\.name) } }

    static var dayCount: Int { store.days.count }

    /// Exercises on a 1-based day (empty if that day doesn't exist).
    static func exercises(onDay day: Int) -> [String] {
        guard (1...max(dayCount, 1)).contains(day), day <= dayCount else { return [] }
        return store.days[day - 1].items.map(\.name)
    }

    /// Today's list for a day: the plan in today's order, with today's skips and swaps applied.
    static func todayExercises(onDay day: Int) -> [String] {
        let changes = TodayChanges.shared
        return changes.apply(changes.ordered(exercises(onDay: day), day: day), day: day)
    }

    static func dayName(_ day: Int) -> String {
        guard day >= 1, day <= dayCount else { return "Day \(day)" }
        let name = store.days[day - 1].name.trimmingCharacters(in: .whitespaces)
        guard let first = name.first else { return "Day \(day)" }
        // Show "arms" as "Arms" (only the first letter changes; "PPL" stays as typed).
        return first.uppercased() + name.dropFirst()
    }

    /// The plan entry for an exercise (from that day if given, otherwise the first day it's on).
    static func item(for name: String, onDay day: Int? = nil) -> RoutineItem? {
        let matches: (RoutineItem) -> Bool = { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if let day, day >= 1, day <= dayCount,
           let item = store.days[day - 1].items.first(where: matches) {
            return item
        }
        for routineDay in store.days {
            if let item = routineDay.items.first(where: matches) { return item }
        }
        // Swapped in for today? Use the targets of the exercise it replaces.
        if let day, let original = TodayChanges.shared.original(of: name, day: day),
           original.caseInsensitiveCompare(name) != .orderedSame {
            return item(for: original, onDay: day)
        }
        return nil
    }

    /// Target sets for an exercise — from that day if given, otherwise the first day it appears on (default 3).
    /// If you finished it early today ("Finish exercise"), today's target is what you logged.
    static func targetSets(for name: String, onDay day: Int? = nil) -> Int {
        if let day, let finished = TodayChanges.shared.finishedSets(name, day: day) { return finished }
        return plannedSets(for: name, onDay: day)
    }

    /// Sets in your plan, ignoring today's early finish.
    static func plannedSets(for name: String, onDay day: Int? = nil) -> Int {
        max(item(for: name, onDay: day)?.sets ?? 3, 1)
    }

    /// The exercise after `name` on the given day, if any.
    static func next(after name: String, onDay day: Int) -> String? {
        let list = todayExercises(onDay: day)
        guard let i = list.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
              i + 1 < list.count else { return nil }
        return list[i + 1]
    }

    /// Every exercise in the plan, without duplicates.
    static var allExerciseNames: [String] {
        var seen = Set<String>()
        return days.flatMap { $0 }.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Which day to train: today's day if you've already trained today,
    /// otherwise the next one in the rotation (Day 1 if you've never trained).
    static func dayToTrain(lastDay: Int, lastTrainedAt: Double) -> Int {
        guard dayCount > 0 else { return 1 }
        guard lastDay > 0 else { return 1 }
        let last = min(lastDay, dayCount)
        let trainedToday = Calendar.current.isDateInToday(Date(timeIntervalSince1970: lastTrainedAt))
        return trainedToday ? last : last % dayCount + 1
    }
}
