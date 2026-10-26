import Foundation

// Micro-competitions you can win every day. The opponent is always your own
// past self (a "ghost"), so they're fair at every level and need no internet.

// MARK: - Set duels: every set vs the same set last time

enum DuelResult {
    case win, tie, lose
}

@MainActor
enum SetDuel {
    static let xp = 5
    /// Set-duel XP is capped per day so extra junk sets don't farm points.
    static let dailyXPCap = 20

    /// Compares a set with last time's set at the same position (by estimated 1-rep max,
    /// so more weight or more reps both count).
    static func result(weightKg: Double, reps: Int, against ghost: WorkoutSet) -> DuelResult {
        let mine = reps <= 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
        let theirs = ghost.estimatedMax
        if mine > theirs + 0.01 { return .win }
        if abs(mine - theirs) <= 0.01 { return .tie }
        return .lose
    }

    private static func prefix(_ day: Date) -> String { "set:\(ActiveWorkout.key(for: day)):" }

    /// Set duels won today.
    static func winsToday() -> Int {
        let p = prefix(.now)
        return BonusXP.all.keys.filter { $0.hasPrefix(p) }.count
    }

    /// All set duels ever won.
    static var totalWins: Int { BonusXP.all.keys.filter { $0.hasPrefix("set:") }.count }

    /// Records a win (once per exercise and set number per day). Returns the XP paid (0 at the cap).
    @discardableResult
    static func recordWin(exercise: String, setIndex: Int) -> Int {
        let id = prefix(.now) + "\(exercise.lowercased()):\(setIndex)"
        let paidToday = BonusXP.all.filter { $0.key.hasPrefix(prefix(.now)) }.values.reduce(0, +)
        let pay = paidToday + xp <= dailyXPCap ? xp : 0
        return BonusXP.award(id, xp: pay) ? pay : 0
    }
}

// MARK: - Exercise duels: each exercise's total vs last time

struct ExerciseDuel: Identifiable {
    let name: String
    let todayKg: Double
    let lastKg: Double
    var id: String { name }

    var result: DuelResult {
        if todayKg > lastKg + 0.5 { return .win }
        if abs(todayKg - lastKg) <= 0.5 { return .tie }
        return .lose
    }
}

@MainActor
enum ExerciseDuels {
    static let xp = 15

    /// One duel per exercise trained on `day` that you'd also done before.
    static func list(on day: Date, allSets: [WorkoutSet]) -> [ExerciseDuel] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let working = allSets.filter { !$0.isWarmup && $0.exercise != nil }
        let today = working.filter { cal.isDate($0.date, inSameDayAs: day) }
        var order: [String] = []
        for set in today {
            let name = set.exercise?.name ?? ""
            if !order.contains(name) { order.append(name) }
        }
        return order.compactMap { name in
            let before = working.filter { $0.exercise?.name == name && $0.date < start }
            guard let lastDay = before.map({ cal.startOfDay(for: $0.date) }).max() else { return nil }
            let lastKg = before.filter { cal.isDate($0.date, inSameDayAs: lastDay) }.reduce(0) { $0 + $1.volume }
            let todayKg = today.filter { $0.exercise?.name == name }.reduce(0) { $0 + $1.volume }
            guard lastKg > 0 else { return nil }
            return ExerciseDuel(name: name, todayKg: todayKg, lastKg: lastKg)
        }
    }

    /// Pays out won duels once. Returns what was newly paid.
    @discardableResult
    static func bank(_ duels: [ExerciseDuel], on day: Date) -> [XPLine] {
        var paid: [XPLine] = []
        for duel in duels where duel.result == .win {
            if BonusXP.award("exduel:\(ActiveWorkout.key(for: day)):\(duel.name.lowercased())", xp: xp) {
                paid.append(XPLine(label: "Duel won: \(duel.name)", xp: xp))
            }
        }
        return paid
    }

    static var totalWins: Int { BonusXP.all.keys.filter { $0.hasPrefix("exduel:") }.count }
}

// MARK: - Daily challenges: three small ones every day

struct DailyChallenge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let progress: Double
    let xp: Int
    var isDone: Bool { progress >= 1 }
}

@MainActor
enum DailyChallenges {
    /// Everything needed to check today's challenges.
    struct Inputs {
        var sets: [WorkoutSet]
        var food: [FoodEntry]
        var goalKcal: Double
        var goalProtein: Double
    }

    /// Today's three: one food, one training, one wildcard. Same three all day.
    static func today(_ inputs: Inputs) -> [DailyChallenge] {
        let cal = Calendar.current
        let sets = inputs.sets.filter { !$0.isWarmup && cal.isDateInToday($0.date) }
        let food = inputs.food.filter { cal.isDateInToday($0.date) }
        let eaten = food.reduce(Nutrition()) { $0 + $1.nutrition }
        let weighed = BodyWeightStore.shared.entries.contains { cal.isDateInToday($0.date) }
        let duelWins = SetDuel.winsToday()
        let workout = ActiveWorkout.shared

        func c(_ id: String, _ title: String, _ detail: String, _ progress: Double, _ xp: Int) -> DailyChallenge {
            DailyChallenge(id: id, title: title, detail: detail, progress: min(max(progress, 0), 1), xp: xp)
        }

        let kcalShare = inputs.goalKcal > 0 ? eaten.kcal / inputs.goalKcal : 0
        let foodPool = [
            c("breakfast", "Log a meal before 11:00", "Breakfast counts.",
              food.contains { cal.component(.hour, from: $0.date) < 11 } ? 1 : 0, 20),
            c("protein", "Hit your protein goal", "\(Int(eaten.protein))/\(Int(inputs.goalProtein)) g",
              inputs.goalProtein > 0 ? eaten.protein / inputs.goalProtein : 0, 30),
            c("foods3", "Log 3 foods", "\(min(food.count, 3))/3 logged", Double(food.count) / 3, 20),
            c("kcal", "Land on your calories", "Between 85% and 105% of your goal",
              kcalShare >= 0.85 && kcalShare <= 1.05 ? 1 : min(kcalShare / 0.85, 0.99), 25),
        ]
        let fastDone = (workout.minutesToday ?? Int.max) <= 60
        let trainingPool = [
            c("sets10", "Log 10 sets", "\(min(sets.count, 10))/10 sets", Double(sets.count) / 10, 25),
            c("duels3", "Win 3 set duels", "\(min(duelWins, 3))/3 won · beat last time's sets",
              Double(duelWins) / 3, 30),
            c("early", "Train before noon", "Any set before 12:00",
              sets.contains { cal.component(.hour, from: $0.date) < 12 } ? 1 : 0, 25),
            c("fast", "Finish a workout in under an hour", workout.minutesToday.map { "Took \($0) min" } ?? "Start to Finish",
              fastDone ? 1 : 0, 25),
        ]
        let wildPool = [
            c("weigh", "Weigh in today", "On the Progress tab", weighed ? 1 : 0, 15),
            c("train", "Show up today", "Log any set", sets.isEmpty ? 0 : 1, 20),
        ]

        let seed = cal.ordinality(of: .day, in: .era, for: .now) ?? 0
        let first = foodPool[seed % foodPool.count]
        let second = trainingPool[(seed / 2) % trainingPool.count]
        // Wildcard: any challenge not already picked.
        let rest = (wildPool + foodPool + trainingPool).filter { $0.id != first.id && $0.id != second.id }
        let third = rest[(seed * 7) % rest.count]
        return [second, first, third]
    }

    static let sweepXP = 25

    /// True if the food challenge on `date` is "Log a meal before 11:00" (for the morning nudge).
    static func isBreakfastDay(_ date: Date) -> Bool {
        (Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0) % 4 == 0
    }

    /// All three won today: a small extra bonus, once. Returns true when it's just been paid.
    static func bankSweep(_ challenges: [DailyChallenge]) -> Bool {
        guard challenges.count == 3, challenges.allSatisfy(\.isDone) else { return false }
        return BonusXP.award("dailysweep:\(ActiveWorkout.key(for: .now))", xp: sweepXP)
    }

    /// Pays out finished challenges once. Returns the newly won ones.
    @discardableResult
    static func bank(_ challenges: [DailyChallenge]) -> [DailyChallenge] {
        let day = ActiveWorkout.key(for: .now)
        return challenges.filter { $0.isDone && BonusXP.award("daily:\(day):\($0.id)", xp: $0.xp) }
    }
}
