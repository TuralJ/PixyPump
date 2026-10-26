import Foundation

// The reward loop: every workout earns XP (finishing earns the most), missions give
// you something to aim for during the workout and the week, a gym bag rewards
// finished workouts, and the journey map gives the long road ahead.

// MARK: - Small JSON store in UserDefaults (strings, so backups can carry them)

@MainActor
enum JSONDefaults {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let text = UserDefaults.standard.string(forKey: key), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: key)
    }
}

// MARK: - XP ledger (what each finished workout earned)

nonisolated struct XPLine: Codable, Hashable, Sendable {
    var label: String
    var xp: Int
}

nonisolated struct XPEntry: Codable, Sendable {
    var total: Int
    /// Every planned set was done (unlocks the gym bag and boss nodes).
    var completed: Bool
    var lines: [XPLine]
    var multiplier: Double
    /// What the gym bag gave, once opened.
    var bag: String?
}

@MainActor
enum XPLedger {
    static let key = "xpLedger.v1"

    static var all: [String: XPEntry] { JSONDefaults.load([String: XPEntry].self, key: key) ?? [:] }

    static func entry(on day: Date) -> XPEntry? { all[ActiveWorkout.key(for: day)] }

    static func set(_ entry: XPEntry?, on day: Date) {
        var list = all
        list[ActiveWorkout.key(for: day)] = entry
        JSONDefaults.save(list, key: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// One-off XP (weekly missions, chapters, gym bags). Each id pays out once.
@MainActor
enum BonusXP {
    static let key = "bonusXP.v1"

    static var all: [String: Int] { JSONDefaults.load([String: Int].self, key: key) ?? [:] }
    static var total: Int { all.values.reduce(0, +) }
    static func has(_ id: String) -> Bool { all[id] != nil }

    /// Returns true the first time.
    @discardableResult
    static func award(_ id: String, xp: Int) -> Bool {
        var list = all
        guard list[id] == nil else { return false }
        list[id] = xp
        JSONDefaults.save(list, key: key)
        return true
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Things won from gym bags: buddy items and streak freezes.
/// (Freezes are saved as `shields`, their old name, so older saves still load.)
@MainActor
enum Inventory {
    private static let key = "inventory.v1"

    nonisolated struct Contents: Codable, Sendable {
        var items: [String] = []
        /// When each streak freeze was won (old name kept for saved data).
        var shields: [Double] = []
        /// Gym bags earned but not opened yet (optional so older saves still load).
        var pending: [String]? = nil
    }

    private static var contents: Contents { JSONDefaults.load(Contents.self, key: key) ?? Contents() }

    /// "category:id", e.g. "top:hotpink".
    static var items: Set<String> { Set(contents.items) }
    static var shieldDates: [Date] { contents.shields.map { Date(timeIntervalSince1970: $0) } }

    static func add(item: String) {
        var c = contents
        guard !c.items.contains(item) else { return }
        c.items.append(item)
        JSONDefaults.save(c, key: key)
    }

    static var pendingBags: [String] { contents.pending ?? [] }

    static func addPendingBag(_ id: String) {
        var c = contents
        var list = c.pending ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        c.pending = list
        JSONDefaults.save(c, key: key)
    }

    static func removePendingBag(_ id: String) {
        var c = contents
        c.pending = (c.pending ?? []).filter { $0 != id }
        JSONDefaults.save(c, key: key)
    }

    /// Adds one streak freeze for the daily streak.
    static func addShield() {
        var c = contents
        c.shields.append(Date.now.timeIntervalSince1970)
        JSONDefaults.save(c, key: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// When the reward system was first used. Older workouts count as "finished"
/// for the journey, so nobody loses progress.
@MainActor
enum RewardsStart {
    private static let key = "rewardsStart"
    static var date: Date {
        let saved = UserDefaults.standard.double(forKey: key)
        if saved > 0 { return Date(timeIntervalSince1970: saved) }
        let now = Calendar.current.startOfDay(for: .now)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
        return now
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - Workout missions (live while you train)

struct WorkoutMission: Identifiable {
    let id: String
    let title: String
    let detail: String
    let xp: Int
    let done: Bool
}

@MainActor
enum WorkoutMissions {
    static let completeXP = 100

    /// Three missions for a workout on `planDay`, checked against today's sets.
    static func list(planDay: Int, on date: Date = .now, allSets: [WorkoutSet],
                     finishedEarly: Bool, minutes: Int?) -> [WorkoutMission] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let working = allSets.filter { !$0.isWarmup }
        let todaySets = working.filter { cal.isDate($0.date, inSameDayAs: date) }
        let names = Routine.todayExercises(onDay: planDay)
        guard !names.isEmpty else { return [] }

        func same(_ set: WorkoutSet, _ name: String) -> Bool {
            (set.exercise?.name ?? "").caseInsensitiveCompare(name) == .orderedSame
        }

        // 1. Finish every set.
        var target = 0, done = 0, touched = 0
        for name in names {
            let t = Routine.targetSets(for: name, onDay: planDay)
            let n = todaySets.filter { same($0, name) }.count
            target += t
            done += min(n, t)
            if n > 0 { touched += 1 }
        }
        let complete = WorkoutMission(id: "complete", title: "Finish every set",
                                      detail: finishedEarly ? "Finished early today" : "\(done)/\(target) sets",
                                      xp: completeXP, done: done >= target && !finishedEarly)

        // 2. Beat a lift from last time (or, for brand-new exercises, touch them all).
        var hasHistory = false
        var beaten: String?
        for name in names {
            let before = working.filter { same($0, name) && $0.date < dayStart }
            guard let lastDay = before.map({ cal.startOfDay(for: $0.date) }).max() else { continue }
            hasHistory = true
            let lastBest = before.filter { cal.isDate($0.date, inSameDayAs: lastDay) }.map(\.estimatedMax).max() ?? 0
            let todayBest = todaySets.filter { same($0, name) }.map(\.estimatedMax).max() ?? 0
            if lastBest > 0, todayBest > lastBest + 0.01 { beaten = name; break }
        }
        let every = WorkoutMission(id: "every", title: "Log a set on every exercise",
                                   detail: "\(touched)/\(names.count) exercises", xp: 40, done: touched >= names.count)
        let second = hasHistory
            ? WorkoutMission(id: "beat", title: "Beat a lift from last time",
                             detail: beaten.map { "Beaten: \($0)" } ?? "One more rep or a little more weight",
                             xp: 40, done: beaten != nil)
            : every

        // 3. A rotating one.
        let planned = max(5, Int((Double(target) * 2.5 / 5).rounded()) * 5)
        let paceLimit = planned + 10
        let pace = WorkoutMission(id: "pace", title: "Finish within \(paceLimit) min",
                                  detail: minutes.map { "Took \($0) min" } ?? "Start to Finish",
                                  xp: 30, done: (minutes ?? Int.max) <= paceLimit)
        var third = pace
        switch (cal.ordinality(of: .day, in: .era, for: date) ?? 0) % 3 {
        case 0:
            let earlier = WorkoutSession.all(from: allSets).first { $0.day < dayStart && $0.routineDay == planDay }
            if let earlier, earlier.volume > 0 {
                let goal = earlier.volume
                let now = todaySets.reduce(0) { $0 + $1.volume }
                third = WorkoutMission(id: "volume", title: "Match last time's total",
                                       detail: "\(Units.volume(min(now, goal)))/\(Units.volume(goal)) \(Units.symbol)",
                                       xp: 30, done: now >= goal)
            }
        case 1:
            if second.id != "every" { third = every.with(xp: 30) }
        default:
            break
        }
        return [complete, second, third]
    }
}

private extension WorkoutMission {
    func with(xp: Int) -> WorkoutMission {
        WorkoutMission(id: id, title: title, detail: detail, xp: xp, done: done)
    }
}

// MARK: - The XP a workout earns

struct WorkoutReward {
    let lines: [XPLine]
    let multiplier: Double
    let total: Int
    let completed: Bool

    static let showUpXP = 50
    static let recordXP = 30
    static let dailyCap = 500

    /// On-plan bonus: ×1.1 from the 2nd week in a row on plan, up to ×1.5.
    static func multiplier(streakWeeks: Int) -> Double {
        streakWeeks >= 2 ? 1 + min(0.5, Double(streakWeeks - 1) * 0.1) : 1
    }

    @MainActor
    static func make(missions: [WorkoutMission], recordCount: Int, volumeKg: Double, streakWeeks: Int,
                     comeback: Bool = false) -> WorkoutReward {
        var lines = [XPLine(label: "Showed up", xp: showUpXP)]
        for mission in missions where mission.done {
            lines.append(XPLine(label: mission.title, xp: mission.xp))
        }
        if recordCount > 0 {
            let n = min(recordCount, 3)
            lines.append(XPLine(label: n == 1 ? "New PR" : "New PRs ×\(n)", xp: recordXP * n))
        }
        let volumeXP = min(75, Int(volumeKg / 100))
        if volumeXP > 0 { lines.append(XPLine(label: "Weight lifted", xp: volumeXP)) }
        // Back after a week or more away: everything counts double.
        if comeback {
            lines.append(XPLine(label: "Comeback bonus ×2", xp: lines.reduce(0) { $0 + $1.xp }))
        }
        let subtotal = lines.reduce(0) { $0 + $1.xp }
        let mult = multiplier(streakWeeks: streakWeeks)
        let total = min(dailyCap, Int((Double(subtotal) * mult).rounded()))
        let completed = missions.first { $0.id == "complete" }?.done ?? false
        return WorkoutReward(lines: lines, multiplier: mult, total: total, completed: completed)
    }
}

// MARK: - Gym bag

@MainActor
enum GymBag {
    enum Rarity: Int, Comparable {
        case common, rare, epic, legendary

        static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }

        var name: String {
            switch self {
            case .common: return "Common"
            case .rare: return "Rare"
            case .epic: return "Epic"
            case .legendary: return "Legendary"
            }
        }

        /// "Epic gym bag": how a bag's rarity is shown everywhere.
        var bagName: String { "\(name) gym bag" }

        var hex: UInt32 {
            switch self {
            case .common: return 0x9AA6B8
            case .rare: return 0x6FB4F0
            case .epic: return 0xB06CFF
            case .legendary: return 0xFFC94A
            }
        }
    }

    enum Prize {
        case xp(Int)
        case shield
        case item(category: MascotCategory, option: MascotOption)

        var title: String {
            switch self {
            case .xp(let xp): return "+\(xp) bonus XP"
            case .shield: return "Streak freeze ❄️"
            case .item(let category, let option): return category.label(for: option)
            }
        }

        var detail: String {
            switch self {
            case .xp: return "Straight onto your level bar."
            case .shield: return "Saves your daily 🔥 streak if you miss a day."
            case .item: return "A rare item for your buddy. You can only get it from bags."
            }
        }
    }

    struct Result {
        let rarity: Rarity
        let prize: Prize
        /// Extra XP that comes with legendary items.
        let bonusXP: Int

        var summary: String {
            "\(rarity.bagName) · \(prize.title)" + (bonusXP > 0 ? " + \(bonusXP) XP" : "")
        }
    }

    /// Rolls a rarity (never below `minimum`) and a prize to match, and pays it out.
    /// `id` makes the XP payout unique, so the same bag can't pay twice.
    /// `shieldsLeft` is kept for older callers; whether a streak freeze can drop is decided
    /// by the freezes from bags you still have on your daily streak.
    static func roll(id: String, minimum: Rarity = .common, shieldsLeft: Int) -> Result {
        let r = Int.random(in: 0..<100)
        var rarity: Rarity = r < 3 ? .legendary : r < 15 ? .epic : r < 40 ? .rare : .common
        rarity = max(rarity, minimum)
        let missing = MascotOptions.bagItems.filter { !Inventory.items.contains($0.0.key($0.1.id)) }

        func xp(_ amount: Int) -> Prize {
            BonusXP.award("bag:\(id)", xp: amount)
            return .xp(amount)
        }
        func item(_ pick: (MascotCategory, MascotOption)) -> Prize {
            Inventory.add(item: pick.0.key(pick.1.id))
            return .item(category: pick.0, option: pick.1)
        }

        var bonus = 0
        let prize: Prize
        switch rarity {
        case .common:
            prize = xp([25, 40, 50].randomElement() ?? 40)
        case .rare:
            if DailyStreak.bagFreezesLeft < DailyStreak.maxBagFreezes && Bool.random() {
                Inventory.addShield()
                prize = .shield
            } else {
                prize = xp([75, 100].randomElement() ?? 75)
            }
        case .epic:
            prize = missing.randomElement().map(item) ?? xp(150)
        case .legendary:
            if let pick = missing.randomElement() {
                prize = item(pick)
                bonus = 150
                BonusXP.award("bagbonus:\(id)", xp: bonus)
            } else {
                prize = xp(300)
            }
        }
        return Result(rarity: rarity, prize: prize, bonusXP: bonus)
    }

    /// Opens a workout's bag (once) and notes what it gave.
    static func open(on day: Date, shieldsLeft: Int) -> Result {
        let result = roll(id: ActiveWorkout.key(for: day), shieldsLeft: shieldsLeft)
        if var entry = XPLedger.entry(on: day) {
            entry.bag = result.summary
            XPLedger.set(entry, on: day)
        }
        return result
    }

    // MARK: Bags waiting to be opened (streak milestones)

    /// Bags you've earned but not opened yet ("streak:7").
    static var pending: [String] { Inventory.pendingBags }

    static func addPending(_ id: String) { Inventory.addPendingBag(id) }

    /// Where a waiting bag came from, for the reveal screen.
    static func subtitle(for id: String) -> String {
        if id.hasPrefix("streak:"), let days = Int(id.dropFirst(7)) { return "\(days)-day streak reward" }
        if id.hasPrefix("sweep:") { return "Weekly missions clean sweep reward" }
        if id == "starter" { return "First week checklist reward" }
        return "Reward"
    }

    /// Opens a waiting bag. Longer streaks guarantee better bags.
    static func openPending(_ id: String, shieldsLeft: Int) -> Result {
        Inventory.removePendingBag(id)
        var minimum: Rarity = .common
        if id.hasPrefix("streak:"), let days = Int(id.dropFirst(7)) {
            minimum = days >= 100 ? .legendary : days >= 30 ? .epic : days >= 7 ? .rare : .common
        } else if id.hasPrefix("sweep:") {
            minimum = .rare
        } else if id == "starter" {
            minimum = .epic
        }
        return roll(id: id, minimum: minimum, shieldsLeft: shieldsLeft)
    }
}

// MARK: - Weekly missions

struct WeeklyMission: Identifiable {
    let id: String
    let title: String
    let detail: String
    let progress: Double
    let progressText: String
    let xp: Int
    var isDone: Bool { progress >= 1 }
}

@MainActor
enum WeeklyMissions {
    static let sweepXP = 100

    static func current(stats: GameStats) -> [WeeklyMission] {
        let cal = Weeks.calendar
        let weekStart = Weeks.start(of: .now)
        let thisWeek = stats.sets.filter { $0.date >= weekStart }
        let workouts = Set(thisWeek.map { Calendar.current.startOfDay(for: $0.date) }).count
        let week = cal.component(.weekOfYear, from: .now)

        // 1. Show up.
        let goal = max(min(Routine.dayCount, 5), 2)
        let train = WeeklyMission(id: "train", title: "Train \(goal) times",
                                  detail: "Any workout counts.",
                                  progress: Double(workouts) / Double(goal),
                                  progressText: "\(min(workouts, goal))/\(goal)", xp: 150)

        // 2. Push: more volume, or beat your most-trained lift.
        let volumeMission: WeeklyMission = {
            let lastStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
            let lastWeek = stats.sets.filter { $0.date >= lastStart && $0.date < weekStart }.reduce(0) { $0 + $1.volume }
            let target = lastWeek > 0 ? (lastWeek * 1.05 / 100).rounded(.up) * 100 : 5_000
            let now = thisWeek.reduce(0) { $0 + $1.volume }
            return WeeklyMission(id: "volume", title: "Lift \(Units.volume(target)) \(Units.symbol)",
                                 detail: lastWeek > 0 ? "5% more than last week." : "Every set adds up.",
                                 progress: now / target,
                                 progressText: "\(Units.volume(min(now, target)))/\(Units.volume(target))", xp: 150)
        }()
        var push = volumeMission
        if week % 2 == 1 {
            let before = stats.sets.filter { $0.date < weekStart }
            let byName = Dictionary(grouping: before) { $0.exercise?.name ?? "" }
            if let top = byName.filter({ !$0.key.isEmpty }).max(by: { $0.value.count < $1.value.count }),
               let best = top.value.map(\.estimatedMax).max(), best > 0 {
                let beaten = thisWeek.contains { $0.exercise?.name == top.key && $0.estimatedMax > best + 0.01 }
                push = WeeklyMission(id: "beat", title: "Beat your best \(top.key)",
                                     detail: "One more rep or a little more weight.",
                                     progress: beaten ? 1 : 0, progressText: beaten ? "Done" : "Not yet", xp: 150)
            }
        }

        // 3. Habit: finish workouts fully, try something new, or weigh in.
        let habit: WeeklyMission
        switch week % 3 {
        case 0:
            let ledger = XPLedger.all
            var finished = 0
            var day = weekStart
            while day <= .now {
                if ledger[ActiveWorkout.key(for: day)]?.completed == true { finished += 1 }
                day = cal.date(byAdding: .day, value: 1, to: day) ?? .distantFuture
            }
            habit = WeeklyMission(id: "finish2", title: "Finish every set twice",
                                  detail: "In 2 workouts this week.",
                                  progress: Double(finished) / 2, progressText: "\(min(finished, 2))/2", xp: 150)
        case 1:
            let firstSeen = Dictionary(grouping: stats.sets) { $0.exercise?.name ?? "" }
                .compactMapValues { $0.map(\.date).min() }
            let tried = firstSeen.contains { !$0.key.isEmpty && $0.value >= weekStart }
            habit = WeeklyMission(id: "new", title: "Try a new exercise",
                                  detail: "Swap one in for a day, or add one to your plan.",
                                  progress: tried ? 1 : 0, progressText: tried ? "Done" : "Not yet", xp: 100)
        default:
            let weighIns = BodyWeightStore.shared.entries.filter { $0.date >= weekStart }.count
            habit = WeeklyMission(id: "weigh", title: "Weigh in twice",
                                  detail: "On the Progress tab.",
                                  progress: Double(weighIns) / 2, progressText: "\(min(weighIns, 2))/2", xp: 75)
        }
        return [train, push, habit]
    }

    /// Pays out finished missions once. Returns what was newly paid.
    @discardableResult
    static func bank(_ missions: [WeeklyMission]) -> [XPLine] {
        let week = Weeks.key(.now)
        var paid: [XPLine] = []
        for mission in missions where mission.isDone {
            if BonusXP.award("weekly:\(week):\(mission.id)", xp: mission.xp) {
                paid.append(XPLine(label: "Weekly mission: \(mission.title)", xp: mission.xp))
            }
        }
        // Clean sweep: all three done this week → bonus XP and a gym bag.
        if !missions.isEmpty, missions.allSatisfy(\.isDone),
           BonusXP.award("weeklysweep:\(week)", xp: sweepXP) {
            paid.append(XPLine(label: "Weekly clean sweep!", xp: sweepXP))
            GymBag.addPending("sweep:\(week)")
        }
        return paid
    }
}

// MARK: - Journey map

struct JourneyChapter {
    let number: Int
    let name: String
    let nodes: Int
    let rewardXP: Int
    /// Backdrop unlocked for your buddy.
    let backdrop: String?
}

@MainActor
enum Journey {
    private static let story: [(String, Int, String)] = [
        ("Rookie Gym", 6, "gym"),
        ("Sunset Track", 8, "sunset"),
        ("Muscle Beach", 10, "ocean"),
        ("Forest Camp", 12, "forest"),
        ("Champion Arena", 14, "arena"),
    ]

    static func chapter(_ number: Int) -> JourneyChapter {
        if number >= 1 && number <= story.count {
            let s = story[number - 1]
            return JourneyChapter(number: number, name: s.0, nodes: s.1, rewardXP: 200 + number * 100, backdrop: s.2)
        }
        return JourneyChapter(number: number, name: "Legend Road \(number - story.count)", nodes: 15,
                              rewardXP: 800, backdrop: nil)
    }

    struct Progress {
        /// Chapter you're on (1-based).
        let chapter: Int
        /// Steps done in this chapter.
        let step: Int
        let chaptersDone: Int
        var current: JourneyChapter { Journey.chapter(chapter) }
        /// The next step is the boss (finish every set to beat it).
        var atBoss: Bool { step == current.nodes - 1 }
        var stepsToBoss: Int { max(current.nodes - 1 - step, 0) }
    }

    /// Each workout day moves you one step. The last step of a chapter is a boss:
    /// only a workout where you finish every set beats it.
    static func progress(days: [Date]) -> Progress {
        let ledger = XPLedger.all
        let start = RewardsStart.date
        var chapter = 1, step = 0, done = 0
        for day in days {
            let c = Journey.chapter(chapter)
            if step == c.nodes - 1 {
                let beaten = day < start || ledger[ActiveWorkout.key(for: day)]?.completed == true
                if !beaten { continue }
            }
            step += 1
            if step >= c.nodes {
                done += 1
                chapter += 1
                step = 0
            }
        }
        return Progress(chapter: chapter, step: step, chaptersDone: done)
    }

    /// Pays out finished chapters once. Returns what was newly paid.
    @discardableResult
    static func bank(_ progress: Progress) -> [XPLine] {
        guard progress.chaptersDone > 0 else { return [] }
        var paid: [XPLine] = []
        for n in 1...progress.chaptersDone {
            let c = chapter(n)
            if BonusXP.award("chapter:\(n)", xp: c.rewardXP) {
                paid.append(XPLine(label: "Chapter \(n) complete: \(c.name)", xp: c.rewardXP))
            }
        }
        return paid
    }
}
