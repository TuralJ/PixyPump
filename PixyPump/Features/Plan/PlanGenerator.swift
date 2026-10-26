import Foundation

// Builds a training plan from your answers: goal, experience, days, time,
// equipment, focus areas and anything to avoid.

// MARK: - Answers

enum TrainingGoal: String, CaseIterable, Identifiable {
    case muscle, strength, fatLoss, fitness
    var id: String { rawValue }
    var title: String {
        switch self {
        case .muscle: return "Build muscle"
        case .strength: return "Get stronger"
        case .fatLoss: return "Lose fat"
        case .fitness: return "Get fit and healthy"
        }
    }
    var detail: String {
        switch self {
        case .muscle: return "Grow bigger muscles"
        case .strength: return "Lift heavier weights"
        case .fatLoss: return "Burn fat, keep muscle"
        case .fitness: return "Feel good and move well"
        }
    }
}

enum LiftingExperience: String, CaseIterable, Identifiable {
    case new, beginner, intermediate, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .new: return "I'm new"
        case .beginner: return "Less than a year"
        case .intermediate: return "1–3 years"
        case .advanced: return "3+ years"
        }
    }
    var detail: String {
        switch self {
        case .new: return "Still learning the main exercises"
        case .beginner: return "I know the basics"
        case .intermediate: return "I train regularly"
        case .advanced: return "I know what I'm doing"
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable, Hashable {
    case barbell, dumbbells, bench, cables, machines, pullupBar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .barbell: return "Barbell & plates"
        case .dumbbells: return "Dumbbells"
        case .bench: return "Bench"
        case .cables: return "Cable machine"
        case .machines: return "Weight machines"
        case .pullupBar: return "Pull-up bar"
        }
    }
    var glyph: PixelGlyph {
        switch self {
        case .barbell, .dumbbells: return .dumbbell
        case .bench: return .list
        case .cables: return .reload
        case .machines: return .gear
        case .pullupBar: return .trendingUp
        }
    }
}

enum EquipmentPreset: String, CaseIterable, Identifiable {
    case fullGym, homeDumbbells, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullGym: return "Full gym"
        case .homeDumbbells: return "Home with dumbbells"
        case .none: return "No equipment"
        }
    }
    var equipment: Set<Equipment> {
        switch self {
        case .fullGym: return Set(Equipment.allCases)
        case .homeDumbbells: return [.dumbbells, .bench]
        case .none: return []
        }
    }
}

enum MuscleArea: String, CaseIterable, Identifiable, Hashable {
    case chest, back, shoulders, arms, legs, glutes, core
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AvoidOption: String, CaseIterable, Identifiable, Hashable {
    case barbellSquats, deadlifts, overhead, pullups, lunges
    var id: String { rawValue }
    var title: String {
        switch self {
        case .barbellSquats: return "Barbell squats"
        case .deadlifts: return "Deadlifts"
        case .overhead: return "Overhead pressing"
        case .pullups: return "Pull-ups & chin-ups"
        case .lunges: return "Lunges & split squats"
        }
    }
    var detail: String {
        switch self {
        case .barbellSquats: return "e.g. knee or back trouble"
        case .deadlifts: return "e.g. lower back"
        case .overhead: return "e.g. shoulder pain"
        case .pullups: return "Can't do them yet"
        case .lunges: return "e.g. balance or knees"
        }
    }
    /// Exercises this rules out.
    var excludes: Set<String> {
        switch self {
        case .barbellSquats: return ["Squat", "Front Squat"]
        case .deadlifts: return ["Deadlift", "Romanian Deadlift"]
        case .overhead: return ["Standing Press", "Seated Dumbbell Press", "Arnold Press", "Pike Push-up", "Overhead Triceps"]
        case .pullups: return ["Pull-up", "Chin-up"]
        case .lunges: return ["Lunge", "Split Squat"]
        }
    }
}

struct PlanInputs {
    /// One or more goals (e.g. build muscle *and* lose fat).
    var goals: Set<TrainingGoal> = [.muscle]
    var experience: LiftingExperience = .new
    var days: Int = 3
    var minutes: Int = 45
    var equipment: Set<Equipment> = Set(Equipment.allCases)
    var focus: Set<MuscleArea> = []
    var avoid: Set<AvoidOption> = []
}

// MARK: - Exercise catalog

private enum Slot: String {
    case squat, squat2, hinge, hPush, inclinePush, vPush, hPull, hPull2, vPull
    case lunge, quadIso, hamIso, glute, calves, chestIso, lateral, rearDelt, biceps, triceps, core

    var area: MuscleArea {
        switch self {
        case .squat, .squat2, .lunge, .quadIso, .hamIso, .calves: return .legs
        case .hinge, .glute: return .glutes
        case .hPush, .inclinePush, .chestIso: return .chest
        case .vPush, .lateral, .rearDelt: return .shoulders
        case .hPull, .hPull2, .vPull: return .back
        case .biceps, .triceps: return .arms
        case .core: return .core
        }
    }

    /// Big multi-joint lifts (get the strength rep range).
    var isMain: Bool {
        switch self {
        case .squat, .hinge, .hPush, .vPush, .hPull, .vPull, .inclinePush: return true
        default: return false
        }
    }
}

private struct Candidate {
    let name: String
    let needs: Set<Equipment>
}

private enum Catalog {
    static func c(_ name: String, _ needs: Equipment...) -> Candidate { Candidate(name: name, needs: Set(needs)) }

    static let options: [Slot: [Candidate]] = [
        .squat: [c("Squat", .barbell), c("Leg Press", .machines), c("Goblet Squat", .dumbbells), c("Bodyweight Squat")],
        .squat2: [c("Front Squat", .barbell), c("Leg Press", .machines), c("Goblet Squat", .dumbbells), c("Split Squat")],
        .hinge: [c("Romanian Deadlift", .barbell), c("Deadlift", .barbell), c("Dumbbell Romanian Deadlift", .dumbbells), c("Glute Bridge")],
        .hPush: [c("Bench Press", .barbell, .bench), c("Dumbbell Bench Press", .dumbbells, .bench), c("Machine Press", .machines), c("Push-up")],
        .inclinePush: [c("Incline Dumbbell Press", .dumbbells, .bench), c("Incline Bench Press", .barbell, .bench), c("Machine Press", .machines), c("Push-up")],
        .vPush: [c("Standing Press", .barbell), c("Seated Dumbbell Press", .dumbbells), c("Arnold Press", .dumbbells), c("Pike Push-up")],
        .hPull: [c("Barbell Row", .barbell), c("Chest-Supported Row", .dumbbells, .bench), c("Cable Row", .cables), c("One-Arm Dumbbell Row", .dumbbells), c("Inverted Row", .pullupBar)],
        .hPull2: [c("Cable Row", .cables), c("One-Arm Dumbbell Row", .dumbbells), c("Chest-Supported Row", .dumbbells, .bench), c("Inverted Row", .pullupBar)],
        .vPull: [c("Lat Pulldown", .cables), c("Pull-up", .pullupBar), c("Chin-up", .pullupBar)],
        .lunge: [c("Split Squat"), c("Lunge")],
        .quadIso: [c("Leg Extension", .machines), c("Goblet Squat", .dumbbells), c("Bodyweight Squat")],
        .hamIso: [c("Lying Hamstring Curl", .machines), c("Seated Hamstring Curl", .machines), c("Dumbbell Romanian Deadlift", .dumbbells), c("Glute Bridge")],
        .glute: [c("Hip Thrust", .barbell, .bench), c("Glute Bridge")],
        .calves: [c("Calf Raise")],
        .chestIso: [c("Cable Fly", .cables), c("Push-up")],
        .lateral: [c("Lateral Raise", .dumbbells)],
        .rearDelt: [c("Face Pull", .cables), c("Rear Delt Fly", .dumbbells)],
        .biceps: [c("Curl (Barbell/Dumbbell)", .dumbbells), c("Curl (Barbell/Dumbbell)", .barbell), c("Hammer Curl", .dumbbells), c("Chin-up", .pullupBar)],
        .triceps: [c("Triceps Pushdown", .cables), c("Overhead Triceps", .dumbbells), c("Dumbbell Skull Crusher", .dumbbells, .bench), c("Push-up")],
        .core: [c("Plank"), c("Hanging Leg Raise", .pullupBar), c("Cable Crunch", .cables), c("Ab Wheel")],
    ]
}

// MARK: - Day layouts (slots in priority order)

private struct DayLayout {
    let name: String
    let slots: [Slot]
}

private enum Layouts {
    static let fullA = DayLayout(name: "Full Body A", slots: [.squat, .hPush, .hPull, .hinge, .lateral, .biceps, .triceps, .core])
    static let fullB = DayLayout(name: "Full Body B", slots: [.hinge, .vPush, .vPull, .lunge, .chestIso, .triceps, .biceps, .core])
    static let fullC = DayLayout(name: "Full Body C", slots: [.squat2, .inclinePush, .hPull2, .hamIso, .lateral, .biceps, .triceps, .calves])
    static let upperA = DayLayout(name: "Upper A", slots: [.hPush, .hPull, .vPush, .vPull, .chestIso, .biceps, .triceps, .lateral])
    static let upperB = DayLayout(name: "Upper B", slots: [.inclinePush, .vPull, .hPull2, .vPush, .lateral, .triceps, .biceps, .rearDelt])
    static let lowerA = DayLayout(name: "Lower A", slots: [.squat, .hinge, .lunge, .quadIso, .hamIso, .calves, .core, .glute])
    static let lowerB = DayLayout(name: "Lower B", slots: [.hinge, .squat2, .glute, .hamIso, .quadIso, .calves, .core, .lunge])
    static let push = DayLayout(name: "Push", slots: [.hPush, .vPush, .inclinePush, .lateral, .triceps, .chestIso, .core])
    static let pull = DayLayout(name: "Pull", slots: [.vPull, .hPull, .hPull2, .rearDelt, .biceps, .core, .hinge])
    static let legs = DayLayout(name: "Legs", slots: [.squat, .hinge, .lunge, .quadIso, .hamIso, .calves, .glute, .core])

    static func split(days: Int) -> (name: String, days: [DayLayout]) {
        switch days {
        case ...2: return ("Full body", [fullA, fullB])
        case 3: return ("Full body", [fullA, fullB, fullC])
        case 4: return ("Upper / Lower", [upperA, lowerA, upperB, lowerB])
        case 5: return ("Upper / Lower + Push / Pull / Legs", [upperA, lowerA, push, pull, legs])
        default:
            return ("Push / Pull / Legs ×2", [
                push, pull, legs,
                DayLayout(name: "Push B", slots: [.inclinePush, .vPush, .hPush, .lateral, .triceps, .chestIso, .core]),
                DayLayout(name: "Pull B", slots: [.hPull, .vPull, .hPull2, .rearDelt, .biceps, .core, .hinge]),
                DayLayout(name: "Legs B", slots: [.squat2, .hinge, .glute, .hamIso, .quadIso, .calves, .core, .lunge]),
            ])
        }
    }
}

// MARK: - Generator

struct GeneratedPlan {
    let splitName: String
    let days: [RoutineDay]
    let reasons: [String]
    let minutes: Int
    let restSeconds: Int
}

enum PlanGenerator {
    static func exerciseCount(minutes: Int) -> Int {
        switch minutes {
        case ..<40: return 4
        case 40..<55: return 5
        case 55..<70: return 6
        case 70..<85: return 7
        default: return 8
        }
    }

    static func make(_ input: PlanInputs) -> GeneratedPlan {
        let split = Layouts.split(days: input.days)
        let count = exerciseCount(minutes: input.minutes)
        let excluded = input.avoid.reduce(into: Set<String>()) { $0.formUnion($1.excludes) }
        var usage: [Slot: Int] = [:]
        var focusAdded: [String] = []

        let days: [RoutineDay] = split.days.map { layout in
            // Take the first `count` slots, then make room for focus areas.
            var slots = Array(layout.slots.prefix(count))
            for area in input.focus.sorted(by: { $0.rawValue < $1.rawValue }) {
                let inDay = slots.filter { $0.area == area }.count
                guard inDay < 2, let extra = layout.slots.dropFirst(count).first(where: { $0.area == area })
                        ?? layout.slots.first(where: { $0.area == area && !slots.contains($0) })
                else { continue }
                if slots.count < 8 && count < 6 {
                    slots.append(extra)
                } else if let replace = slots.lastIndex(where: { !input.focus.contains($0.area) && !$0.isMain }) {
                    slots[replace] = extra
                } else {
                    continue
                }
                focusAdded.append(area.title)
            }

            var used = Set<String>()
            var items: [RoutineItem] = []
            for slot in slots {
                let options = (Catalog.options[slot] ?? []).filter {
                    $0.needs.isSubset(of: input.equipment) && !excluded.contains($0.name) && !used.contains($0.name)
                }
                guard !options.isEmpty else { continue }
                // Rotate choices across days so the same movement gets some variety.
                let n = usage[slot, default: 0]
                usage[slot] = n + 1
                let pick = slot.isMain ? options[0] : options[n % options.count]
                used.insert(pick.name)
                let scheme = setsAndReps(goals: input.goals, experience: input.experience, main: slot.isMain)
                items.append(RoutineItem(name: pick.name, sets: scheme.sets, repsLow: scheme.low, repsHigh: scheme.high))
            }
            return RoutineDay(name: layout.name, items: items)
        }

        let goals: Set<TrainingGoal> = input.goals.isEmpty ? [.fitness] : input.goals
        let rest: Int
        if goals.contains(.strength) {
            rest = goals.contains(.muscle) || goals.contains(.fatLoss) ? 120 : 180
        } else if goals.contains(.muscle) {
            rest = goals.contains(.fatLoss) ? 60 : 90
        } else {
            rest = 60
        }

        // Why the plan looks the way it does.
        var reasons = ["\(input.days) days a week → \(split.name)"]
        reasons.append("\(input.minutes) min per workout → \(count) exercises a day")
        let goalNames = TrainingGoal.allCases.filter { goals.contains($0) }.map { $0.title.lowercased() }
        let restText = rest >= 120 ? "\(rest / 60) min rest" : "\(rest) s rest"
        let scheme = setsAndReps(goals: goals, experience: input.experience, main: true)
        let extra = setsAndReps(goals: goals, experience: input.experience, main: false)
        let joined = goalNames.joined(separator: " + ")
        let goalLabel = joined.prefix(1).uppercased() + joined.dropFirst()
        reasons.append("\(goalLabel) → main lifts \(scheme.low)–\(scheme.high) reps, others \(extra.low)–\(extra.high), \(restText)")
        if goals.contains(.fatLoss) {
            reasons.append("Lose fat → shorter rests to keep you moving; the calorie goal does most of the work")
        }
        if input.experience == .new || input.experience == .beginner {
            reasons.append("New to lifting → 3 sets per exercise to start, with simple exercises first")
        }
        if input.equipment.isEmpty {
            reasons.append("No equipment → bodyweight exercises you can do anywhere")
        } else if !input.equipment.contains(.barbell) {
            reasons.append("No barbell → dumbbell and machine versions of the big lifts")
        }
        let focus = Array(Set(focusAdded)).sorted()
        if !focus.isEmpty { reasons.append("Focus on \(focus.joined(separator: ", ").lowercased()) → extra work for those") }
        if !input.avoid.isEmpty {
            reasons.append("Avoiding \(input.avoid.map { $0.title.lowercased() }.sorted().joined(separator: ", ")) → swapped for safer options")
        }

        return GeneratedPlan(splitName: split.name, days: days, reasons: reasons,
                             minutes: input.minutes, restSeconds: rest)
    }

    /// Blends several goals: strength sets the heavy main lifts, muscle the
    /// hypertrophy range, fat loss / fitness the lighter, quicker work.
    private static func setsAndReps(goals: Set<TrainingGoal>, experience: LiftingExperience,
                                    main: Bool) -> (sets: Int, low: Int, high: Int) {
        let seasoned = experience == .intermediate || experience == .advanced
        let strength = goals.contains(.strength)
        let muscle = goals.contains(.muscle)
        if strength && muscle {
            return main ? (seasoned ? 4 : 3, 4, 6) : (3, 8, 12)        // "power-building"
        }
        if strength {
            return main ? (seasoned ? 5 : 3, 3, 5) : (3, 8, 10)
        }
        if muscle {
            return main ? (seasoned ? 4 : 3, 6, 10) : (3, 10, 12)
        }
        return (3, 10, 15)
    }
}
