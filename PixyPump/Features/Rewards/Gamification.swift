import Foundation

// Levels, badges, weekly quests and "weeks on plan" — all worked out from what you've
// logged, so nothing extra needs to be saved except which ones you've already seen.
// (The app's one real streak is the daily 🔥 streak in DailyStreak.swift.)

// MARK: - Weeks (Monday start)

@MainActor
enum Weeks {
    static var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    static func start(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }
}

// MARK: - Everything the game needs, computed once from your sets

@MainActor
struct GameStats {
    /// Working sets (no warm-ups), oldest first.
    let sets: [WorkoutSet]
    /// Training days, oldest first.
    let days: [Date]
    let totalKg: Double
    let bodyWeightKg: Double?
    let prCount: Int
    /// Weeks in a row on plan (shown as "weeks on plan", not as a streak).
    let streak: Streak
    /// XP for each training day: what the workout earned when you finished it,
    /// or (for workouts without Finish) 50 + 1 per 100 kg.
    let dayXP: [Date: Int]
    let xp: Int
    let journey: Journey.Progress

    init(allSets: [WorkoutSet]) {
        let working = allSets.filter { !$0.isWarmup }.sorted { $0.date < $1.date }
        sets = working
        let cal = Calendar.current
        let byDay = Dictionary(grouping: working) { cal.startOfDay(for: $0.date) }
        days = byDay.keys.sorted()
        totalKg = working.reduce(0) { $0 + $1.volume }
        bodyWeightKg = BodyWeightStore.shared.latest?.kg
            ?? (UserDefaults.standard.object(forKey: "profileWeight") as? Double)
        prCount = GameStats.countPRs(working)
        // Gym-bag freezes now belong to the daily streak, so none are passed here.
        streak = Streak.compute(days: days, goal: max(min(Routine.dayCount, 7), 1))

        let ledger = XPLedger.all
        var perDay: [Date: Int] = [:]
        for (day, list) in byDay {
            let volume = list.reduce(0) { $0 + $1.volume }
            perDay[day] = ledger[ActiveWorkout.key(for: day)]?.total ?? (50 + Int(volume / 100))
        }
        dayXP = perDay
        xp = perDay.values.reduce(0, +) + QuestLog.completedCount * 200 + BonusXP.total
        journey = Journey.progress(days: days)
    }

    /// What your buddy items are unlocked by.
    var unlocks: MascotUnlocks {
        if Unlocks.everything { return .everything }
        return MascotUnlocks(level: level.number, chaptersDone: journey.chaptersDone, items: Inventory.items)
    }

    var workouts: Int { days.count }

    /// Sets that beat the heaviest weight you'd done before on that exercise.
    private static func countPRs(_ sets: [WorkoutSet]) -> Int {
        var best: [String: Double] = [:]
        var count = 0
        for set in sets where set.weight > 0 {
            let name = set.exercise?.name.lowercased() ?? ""
            if let previous = best[name] {
                if set.weight > previous + 0.01 { count += 1; best[name] = set.weight }
            } else {
                best[name] = set.weight   // first time isn't a record
            }
        }
        return count
    }

    /// Heaviest working set for any exercise whose name contains `word`.
    func best(matching word: String) -> Double {
        sets.filter { ($0.exercise?.name.lowercased() ?? "").contains(word) }.map(\.weight).max() ?? 0
    }

    /// Biggest single-day volume.
    var biggestDay: Double {
        let cal = Calendar.current
        return Dictionary(grouping: sets) { cal.startOfDay(for: $0.date) }
            .values.map { $0.reduce(0) { $0 + $1.volume } }.max() ?? 0
    }

    /// Most workouts in one Monday–Sunday week.
    var bestWeekCount: Int {
        Dictionary(grouping: days) { Weeks.start(of: $0) }.values.map(\.count).max() ?? 0
    }

    // MARK: Level

    var level: Level { Level(xp: xp) }
}

// MARK: - Levels

struct Level: Equatable {
    let number: Int
    let xp: Int

    init(xp: Int) {
        self.xp = xp
        var n = 1
        while Level.xpNeeded(for: n + 1) <= xp { n += 1 }
        number = n
    }

    /// XP needed to reach a level: 0, 200, 600, 1 200, 2 000, …
    /// (A finished workout earns roughly 250–400 XP.)
    static func xpNeeded(for level: Int) -> Int { 100 * (level - 1) * level }

    var title: String {
        switch number {
        case ..<3: return "Rookie"
        case 3..<6: return "Regular"
        case 6..<10: return "Iron"
        case 10..<15: return "Steel"
        case 15..<20: return "Titan"
        default: return "Legend"
        }
    }

    /// 0 = rookie look, 1 = getting fit, 2 = buff (for the pixel buddy).
    var tier: Int { number >= 10 ? 2 : number >= 5 ? 1 : 0 }

    var progress: Double {
        let start = Level.xpNeeded(for: number)
        let end = Level.xpNeeded(for: number + 1)
        return Double(xp - start) / Double(max(end - start, 1))
    }

    var xpToNext: Int { Level.xpNeeded(for: number + 1) - xp }
}

// MARK: - Weeks on plan

/// Weeks in a row where you did your planned number of workouts ("weeks on plan").
/// One missed week is forgiven at most once every 4 weeks.
/// The names (`Streak`, `shieldUsed`, `shieldsLeft`) stay so other screens keep compiling,
/// but this is never shown as a streak: the daily 🔥 streak is the only one.
struct Streak {
    let current: Int
    let best: Int
    /// A shield saved the current streak recently.
    let shieldUsed: Bool
    /// Old: bag shields left. Bag prizes are daily streak freezes now, so this is 0
    /// unless an older caller passes `bonusShields`.
    var shieldsLeft: Int = 0

    /// `bonusShields`: when each gym-bag shield was won. One covers a missed week
    /// that ends after it was won, when the free shield isn't available.
    @MainActor
    static func compute(days: [Date], goal: Int, bonusShields: [Date] = []) -> Streak {
        guard let first = days.first else {
            return Streak(current: 0, best: 0, shieldUsed: false, shieldsLeft: bonusShields.count)
        }
        var unused = bonusShields.sorted()
        let counts = Dictionary(grouping: days) { Weeks.start(of: $0) }.mapValues(\.count)
        let cal = Weeks.calendar
        var weeks: [Date] = []
        var w = Weeks.start(of: first)
        let thisWeek = Weeks.start(of: .now)
        while w <= thisWeek {
            weeks.append(w)
            guard let next = cal.date(byAdding: .day, value: 7, to: w) else { break }
            w = next
        }

        var run = 0, best = 0, lastShield = -100, shieldInRun = false
        for (i, week) in weeks.enumerated() {
            let hit = (counts[week] ?? 0) >= goal
            let isCurrent = week == thisWeek
            if hit {
                run += 1
            } else if isCurrent {
                // This week isn't over yet: don't break the streak for it.
            } else if run > 0 && i - lastShield >= 4 {
                lastShield = i
                shieldInRun = true
            } else if run > 0, let end = cal.date(byAdding: .day, value: 7, to: week),
                      let index = unused.firstIndex(where: { $0 < end }) {
                unused.remove(at: index)
                lastShield = i
                shieldInRun = true
            } else {
                run = 0
                shieldInRun = false
            }
            best = max(best, run)
        }
        return Streak(current: run, best: best, shieldUsed: shieldInRun && weeks.count - lastShield <= 4,
                      shieldsLeft: unused.count)
    }
}

// MARK: - Badges

struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let glyph: PixelGlyph
    let earned: @MainActor (GameStats) -> Bool

    @MainActor
    static let all: [Badge] = [
        Badge(id: "first", title: "First steps", detail: "Log your first workout", glyph: .flag) { $0.workouts >= 1 },
        Badge(id: "firstpr", title: "Record breaker", detail: "Beat your heaviest weight on any exercise", glyph: .trophy) { $0.prCount >= 1 },
        Badge(id: "fullweek", title: "Full week", detail: "Do every workout in your plan in one week", glyph: .calendar) {
            $0.bestWeekCount >= max(min(Routine.dayCount, 7), 1)
        },
        Badge(id: "ten", title: "Ten down", detail: "10 workouts", glyph: .dumbbell) { $0.workouts >= 10 },
        Badge(id: "fifty", title: "Half century", detail: "50 workouts", glyph: .star) { $0.workouts >= 50 },
        Badge(id: "hundred", title: "Centurion", detail: "100 workouts", glyph: .trophy) { $0.workouts >= 100 },
        Badge(id: "streak4", title: "On a roll", detail: "4 weeks in a row on plan", glyph: .calendar) { $0.streak.best >= 4 },
        Badge(id: "streak12", title: "Unstoppable", detail: "12 weeks in a row on plan", glyph: .zap) { $0.streak.best >= 12 },
        Badge(id: "bwbench", title: "Bodyweight bench", detail: "Bench press your own body weight", glyph: .scale) { s in
            guard let bw = s.bodyWeightKg, bw > 0 else { return false }
            return s.best(matching: "bench") >= bw
        },
        Badge(id: "club100", title: "100 kg club", detail: "Lift 100 kg (220 lb) in any exercise", glyph: .target) { s in
            (s.sets.map(\.weight).max() ?? 0) >= 100
        },
        Badge(id: "dl2x", title: "Double up", detail: "Deadlift twice your body weight", glyph: .trendingUp) { s in
            guard let bw = s.bodyWeightKg, bw > 0 else { return false }
            return s.best(matching: "deadlift") >= bw * 2
        },
        Badge(id: "bigday", title: "Big day", detail: "Lift 10 000 kg in one workout", glyph: .chart) { $0.biggestDay >= 10_000 },
        Badge(id: "tonnes", title: "100 tonnes", detail: "Lift 100 000 kg in total", glyph: .heart) { $0.totalKg >= 100_000 },
        Badge(id: "daily7", title: "Can't miss", detail: "A 7-day daily streak", glyph: .fire) {
            DailyStreak.compute(sets: $0.sets).best >= 7
        },
        Badge(id: "daily30", title: "Habit locked", detail: "A 30-day daily streak", glyph: .fire) {
            DailyStreak.compute(sets: $0.sets).best >= 30
        },
        Badge(id: "early", title: "Early bird", detail: "Log a set before 7:00", glyph: .sun) { s in
            s.sets.contains { Calendar.current.component(.hour, from: $0.date) < 7 }
        },
        Badge(id: "night", title: "Night owl", detail: "Log a set after 21:00", glyph: .moon) { s in
            s.sets.contains { Calendar.current.component(.hour, from: $0.date) >= 21 }
        },
    ]
}

/// Which badges you've already been shown (so new ones can be celebrated once).
@MainActor
enum BadgeLog {
    private static let key = "seenBadges"

    static var seen: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    static func markSeen(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        UserDefaults.standard.set(Array(seen.union(ids)).sorted(), forKey: key)
    }

    static func newlyEarned(_ stats: GameStats) -> [Badge] {
        let seen = BadgeLog.seen
        return Badge.all.filter { !seen.contains($0.id) && $0.earned(stats) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - Old weekly quest log

/// Weeks whose (old, single) quest you completed. Still counts 200 XP each.
/// New weekly missions pay out through BonusXP.
@MainActor
enum QuestLog {
    private static let key = "questsDone"

    static var completedCount: Int { (UserDefaults.standard.stringArray(forKey: key) ?? []).count }

    static var doneThisWeek: Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(Weeks.key(.now))
    }

    /// Records this week's quest as done. Returns true the first time.
    @discardableResult
    static func markDoneThisWeek() -> Bool {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        let week = Weeks.key(.now)
        guard !list.contains(week) else { return false }
        list.append(week)
        UserDefaults.standard.set(list, forKey: key)
        return true
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Last level you were shown, so a level-up is celebrated once.
@MainActor
enum LevelLog {
    private static let key = "seenLevel"
    static var seen: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
