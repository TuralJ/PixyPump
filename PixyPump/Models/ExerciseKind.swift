import Foundation

// What kind of exercise a name is, guessed from the name (works for the library and your own names).
// Used for sensible defaults: how much −/+ changes the weight, and how long to rest.

nonisolated enum ExerciseEquipment: Sendable {
    case barbell, dumbbell, machine, bodyweight

    /// −/+ step in kg.
    var stepKg: Double {
        switch self {
        case .barbell, .bodyweight: return 2.5
        case .dumbbell: return 2
        case .machine: return 5
        }
    }

    /// −/+ step in lb.
    var stepLb: Double {
        switch self {
        case .barbell, .dumbbell, .bodyweight: return 5
        case .machine: return 10
        }
    }
}

nonisolated enum ExerciseSize: Sendable {
    /// Heavy multi-joint lifts (squat, deadlift, bench…): longest rest.
    case big
    /// Other multi-joint moves.
    case medium
    /// One-joint moves (curls, raises, pushdowns…): shortest rest.
    case small
}

nonisolated enum ExerciseKind {
    static func equipment(_ name: String) -> ExerciseEquipment {
        let n = name.lowercased()
        if has(n, ["dumbbell", "goblet", "arnold", "hammer curl", "lateral raise", "rear delt", "kettlebell"]) {
            return .dumbbell
        }
        if has(n, ["machine", "cable", "pulldown", "leg press", "leg extension", "hamstring curl", "pushdown",
                   "face pull", "calf raise", "smith", "pec deck", "chest-supported"]) {
            return .machine
        }
        if has(n, ["push-up", "pushup", "pull-up", "pullup", "chin-up", "chinup", "dip", "plank", "bodyweight",
                   "inverted", "hanging", "ab wheel", "glute bridge", "lunge", "split squat", "crunch"]) {
            return .bodyweight
        }
        return .barbell
    }

    static func size(_ name: String) -> ExerciseSize {
        let n = name.lowercased()
        if has(n, ["curl", "raise", "fly", "extension", "pushdown", "triceps", "skull", "face pull", "calf",
                   "crunch", "plank", "rear delt", "ab wheel", "shrug", "kickback"]) {
            return .small
        }
        let lightVersion = has(n, ["goblet", "bodyweight", "split", "dumbbell", "push-up", "inverted"])
        if !lightVersion, has(n, ["squat", "deadlift", "bench press", "standing press", "overhead press",
                                  "barbell row", "pendlay", "leg press", "hip thrust", "weighted dip",
                                  "pull-up", "chin-up"]) {
            return .big
        }
        return .medium
    }

    private static func has(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }
}

// MARK: - Rest length per exercise

/// How long to rest after a set of an exercise.
/// Starts from your rest length in Settings (big lifts +60 s, small moves −30 s), and remembers
/// it per exercise when you change the timer with +30 / −30 during that exercise's rest.
@MainActor
enum RestPlan {
    /// Remembered lengths, by lower-cased exercise name.
    static let key = "restByExercise.v1"

    static var baseSeconds: Int {
        let saved = UserDefaults.standard.integer(forKey: Prefs.restSeconds)
        return saved > 0 ? saved : 90
    }

    static func defaultSeconds(for name: String) -> Int {
        let base = baseSeconds
        switch ExerciseKind.size(name) {
        case .big: return max(base + 60, 120)
        case .medium: return base
        case .small: return max(base - 30, 45)
        }
    }

    static func seconds(for name: String) -> Int {
        saved[name.lowercased()] ?? defaultSeconds(for: name)
    }

    /// Remembers a changed rest for this exercise (rounded to 15 s, 30 s to 5 min).
    static func remember(_ seconds: Int, for name: String) {
        var all = saved
        let rounded = min(max(Int((Double(seconds) / 15).rounded()) * 15, 30), 300)
        if rounded == defaultSeconds(for: name) {
            all[name.lowercased()] = nil
        } else {
            all[name.lowercased()] = rounded
        }
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Any exercise with its own remembered length.
    static var hasCustom: Bool { !saved.isEmpty }

    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static var saved: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }
}
