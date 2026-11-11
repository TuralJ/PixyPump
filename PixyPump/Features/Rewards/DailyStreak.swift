import Foundation
import UserNotifications

// The daily streak: "I can't miss today".
// A day counts when you train OR win any daily challenge, so rest days
// (log food, weigh in) keep it alive too — no need to lift every day.
// Every 7 days in a row earns a freeze (hold up to 2) that saves one missed day.
// Gym bags can also drop a "Streak freeze" (saved in the inventory, hold up to 3 more).
// Pro adds one free freeze each week (the "streak shield").
// This is the one and only streak in the app.

struct DailyStreakState {
    /// Days in a row, including today if it's secured.
    let current: Int
    let best: Int
    /// Today already counts.
    let securedToday: Bool
    /// Freezes ready to save a missed day (earned + from gym bags).
    let freezes: Int
    /// Days a freeze saved, so the calendar can show them.
    let frozenDays: Set<Date>
    /// Secured days (start of day), for the week view.
    let securedDays: Set<Date>
    /// The part of `freezes` that came from gym bags.
    var bagFreezes: Int = 0

    /// There's a streak to lose and today isn't done yet.
    var atRisk: Bool { current > 0 && !securedToday }

    static let milestones = [3, 7, 14, 30, 50, 100, 150, 200, 365, 500, 1000]

    /// XP for reaching a milestone.
    static func milestoneXP(_ days: Int) -> Int {
        switch days {
        case ..<7: return 25
        case ..<30: return 75
        case ..<100: return 200
        case ..<365: return 400
        default: return 1000
        }
    }

    var nextMilestone: Int? { Self.milestones.first { $0 > current } }
}

@MainActor
enum DailyStreak {
    /// Freezes you can hold from 7-day runs.
    static let maxFreezes = 2
    /// Freezes from gym bags you can hold on top (bags stop dropping them at this many).
    static let maxBagFreezes = 3

    /// Unused gym-bag freezes, as of the last time the streak was worked out.
    /// Gym bags use it to decide whether a freeze can still drop.
    private(set) static var bagFreezesLeft = 0

    /// Days with at least one daily challenge won (from the XP store keys "daily:2026-10-16:id").
    private static var challengeDays: Set<Date> {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        return Set(BonusXP.all.keys.compactMap { key -> Date? in
            let parts = key.split(separator: ":")
            guard parts.count >= 2, parts[0] == "daily", let date = parser.date(from: String(parts[1])) else { return nil }
            return cal.startOfDay(for: date)
        })
    }

    static func compute(sets: [WorkoutSet], now: Date = .now) -> DailyStreakState {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let secured = Set(sets.filter { !$0.isWarmup }.map { cal.startOfDay(for: $0.date) })
            .union(challengeDays)
            .filter { $0 <= today }
        // Freezes won from gym bags (the inventory still calls them "shields", so old saves load).
        var bagUnused = Inventory.shieldDates.filter { $0 <= now }.sorted()
        guard let start = secured.min() else {
            let left = min(bagUnused.count, maxBagFreezes)
            bagFreezesLeft = left
            return DailyStreakState(current: 0, best: 0, securedToday: false, freezes: left, frozenDays: [],
                                    securedDays: [], bagFreezes: left)
        }

        var run = 0, best = 0, freezes = 0
        var frozen = Set<Date>()
        // Pro's streak shield: one free freeze each week (renews on the first day of the week, doesn't stack).
        let pro = ProStatus.isActive
        var weekly = pro ? 1 : 0
        var d = start
        while d < today {
            if pro, d != start, cal.component(.weekday, from: d) == cal.firstWeekday { weekly = 1 }
            if secured.contains(d) {
                run += 1
                if run % 7 == 0 { freezes = min(freezes + 1, maxFreezes) }
            } else if run > 0 && weekly > 0 {
                weekly -= 1
                frozen.insert(d)
            } else if run > 0 && freezes > 0 {
                freezes -= 1
                frozen.insert(d)            // saved: the streak carries on (without counting the day)
            } else if run > 0, let end = cal.date(byAdding: .day, value: 1, to: d),
                      let index = bagUnused.firstIndex(where: { $0 < end }) {
                // No earned freeze left: use one from a gym bag (only one you'd already won that day).
                bagUnused.remove(at: index)
                frozen.insert(d)
            } else {
                run = 0
                freezes = 0
            }
            best = max(best, run)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        if pro, cal.component(.weekday, from: today) == cal.firstWeekday { weekly = 1 }
        let securedToday = secured.contains(today)
        if securedToday {
            run += 1
            best = max(best, run)
        }
        let bagLeft = min(bagUnused.count, maxBagFreezes)
        bagFreezesLeft = bagLeft
        return DailyStreakState(current: run, best: best, securedToday: securedToday, freezes: freezes + bagLeft + weekly,
                                frozenDays: frozen, securedDays: secured, bagFreezes: bagLeft)
    }

    /// Pays out milestones reached (once each). Returns the newest one reached now, if any.
    @discardableResult
    static func bankMilestones(_ state: DailyStreakState) -> Int? {
        var newest: Int?
        for m in DailyStreakState.milestones where state.current >= m {
            if BonusXP.award("streak:\(m)", xp: DailyStreakState.milestoneXP(m)) { newest = m }
        }
        return newest
    }

    // MARK: Evening reminder

    private static let reminderID = "streak.reminder"
    /// Hour of the "your streak ends tonight" reminder.
    static let reminderHour = 20

    /// Schedules tonight's reminder while the streak is at risk, and removes it once today is secured.
    static func updateReminder(_ state: DailyStreakState) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID, lastCallID])
        guard UserDefaults.standard.object(forKey: reminderKey) as? Bool ?? true else { return }
        let cal = Calendar.current

        // Last call at 22:00 for streaks worth protecting (7+ days) that aren't secured yet.
        if !state.securedToday, state.current >= 7,
           let late = cal.date(bySettingHour: 22, minute: 0, second: 0, of: .now), late > .now {
            let content = UNMutableNotificationContent()
            content.title = "⏰ 2 hours left: your \(state.current)-day streak"
            content.body = "Log a meal or weigh in — 10 seconds keeps it alive."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: late)
            center.add(UNNotificationRequest(identifier: lastCallID, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        // Tonight while today still needs securing; tomorrow evening once it's done.
        let base = state.securedToday ? (cal.date(byAdding: .day, value: 1, to: .now) ?? .now) : .now
        guard let when = cal.date(bySettingHour: reminderHour, minute: 0, second: 0, of: base), when > .now else { return }
        let streak = state.current

        let content = UNMutableNotificationContent()
        if streak > 0 {
            content.title = "🔥 Your \(streak)-day streak ends at midnight"
            content.body = "One quick win keeps it alive: log a meal, weigh in or do a workout."
        } else {
            content.title = "Start a streak today 🔥"
            content.body = "Win one daily challenge in \(AppInfo.name). It only takes a minute."
        }
        content.sound = .default
        let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        let request = UNNotificationRequest(identifier: reminderID, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        center.add(request)
    }

    /// Settings switch for the evening reminder (on by default).
    static let reminderKey = "streakReminderOn"

    private static let lastCallID = "streak.lastcall"

    static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID, lastCallID])
    }
}
