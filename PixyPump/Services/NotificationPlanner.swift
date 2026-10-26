import Foundation
import UserNotifications

/// Friendly nudges that bring you back: training reminders at your usual time,
/// waiting gym bags, milestone teasers, weekly missions, breakfast challenges and
/// gentle comeback messages. All scheduled on the phone (no server).
///
/// Rules: at most one nudge a day (the streak alert is separate), nothing during
/// quiet hours (22:30–8:00), and every type can be switched off in Settings.
@MainActor
enum NotificationPlanner {
    enum Kind: String, CaseIterable, Identifiable {
        case training, rewards, missions, food, comeback

        var id: String { rawValue }
        var key: String { "notif.\(rawValue)" }
        var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

        var title: String {
            switch self {
            case .training: return "Training reminders"
            case .rewards: return "Rewards and gym bags"
            case .missions: return "Weekly missions"
            case .food: return "Food challenges"
            case .comeback: return "Comeback messages"
            }
        }
    }

    private struct Nudge {
        let date: Date
        let kind: Kind
        let priority: Int
        let title: String
        let body: String
    }

    private static let idPrefix = "nudge."
    private static let daysAhead = 7

    /// Rebuilds the next 7 days of nudges from your current progress.
    /// Called when the app goes to the background (and on launch).
    static func reschedule(sets: [WorkoutSet], now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<daysAhead).map { idPrefix + "\($0)" })
        for (offset, nudge) in plan(sets: sets, now: now) {
            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nudge.date)
            center.add(UNNotificationRequest(identifier: idPrefix + "\(offset)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: (0..<daysAhead).map { idPrefix + "\($0)" })
    }

    // MARK: Planning

    private static func plan(sets: [WorkoutSet], now: Date) -> [Int: Nudge] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let working = sets.filter { !$0.isWarmup }
        let byDay = Dictionary(grouping: working) { cal.startOfDay(for: $0.date) }
        let trainingDays = Set(byDay.keys)
        let lastWorkout = trainingDays.max()
        let trainedToday = trainingDays.contains(today)
        let name = (UserDefaults.standard.string(forKey: Prefs.userName) ?? "").trimmingCharacters(in: .whitespaces)
        let buddy = name.isEmpty ? "Your buddy" : "\(name), your buddy"

        // When you usually train: median hour of your first set (last 60 days), default 18:00.
        let recent = byDay.filter { $0.key >= (cal.date(byAdding: .day, value: -60, to: today) ?? today) }
        let hours = recent.values.compactMap { $0.map(\.date).min() }.map { cal.component(.hour, from: $0) }.sorted()
        let usualHour = hours.isEmpty ? 18 : hours[hours.count / 2]
        // Remind 30 minutes before, kept inside waking hours.
        let reminderMinutes = min(max(usualHour * 60 - 30, 8 * 60), 21 * 60 + 30)

        // Which weekdays you train: at least twice in the last 4 weeks. Short history: every other day.
        let fourWeeksAgo = cal.date(byAdding: .day, value: -28, to: today) ?? today
        let weekdayCounts = Dictionary(grouping: trainingDays.filter { $0 >= fourWeeksAgo }) { cal.component(.weekday, from: $0) }
            .mapValues(\.count)
        let patternDays = Set(weekdayCounts.filter { $0.value >= 2 }.keys)
        let historySpan = (trainingDays.min()).map { cal.dateComponents([.day], from: $0, to: today).day ?? 0 } ?? 0
        let usePattern = historySpan >= 14 && !patternDays.isEmpty

        var nextPlanDay = Routine.dayCount > 0 ? Routine.suggestion(from: sets).day : 0
        let streak = DailyStreak.compute(sets: sets, now: now)
        let stats = GameStats(allSets: sets)
        let missionsLeft = WeeklyMissions.current(stats: stats).filter { !$0.isDone }.count

        func at(_ day: Date, _ minutes: Int) -> Date? {
            cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
        }
        func daysBetween(_ a: Date, _ b: Date) -> Int { cal.dateComponents([.day], from: a, to: b).day ?? 0 }

        var result: [Int: Nudge] = [:]
        for offset in 0..<daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            var options: [Nudge] = []
            let weekday = cal.component(.weekday, from: day)   // 1 = Sunday, 2 = Monday … 6 = Friday

            // A bag is waiting (next morning).
            if offset == 1, !GymBag.pending.isEmpty, let when = at(day, 9 * 60) {
                options.append(Nudge(date: when, kind: .rewards, priority: 100,
                                     title: "A gym bag is waiting 🎁",
                                     body: "Could be a Legendary gym bag 👀 Open it in \(AppInfo.name)."))
            }

            // Tomorrow is a streak milestone (only if today is already secured).
            if offset == 1, streak.securedToday,
               DailyStreakState.milestones.contains(streak.current + 1), let when = at(day, 9 * 60) {
                let m = streak.current + 1
                let bag = m >= 100 ? "a Legendary gym bag" : m >= 30 ? "an Epic gym bag" : m >= 7 ? "a Rare gym bag" : "a gym bag"
                options.append(Nudge(date: when, kind: .rewards, priority: 90,
                                     title: "Today = your \(m)-day streak 🔥",
                                     body: "Train or win one daily challenge to claim \(bag) 🎁"))
            }

            // Away for a while: gentle at 3 days, a real reason to return at 7.
            if let last = lastWorkout {
                let gap = daysBetween(last, day)
                if gap == 3, let when = at(day, reminderMinutes) {
                    options.append(Nudge(date: when, kind: .comeback, priority: 80,
                                         title: "\(buddy) misses you 🥺",
                                         body: "It's been 3 days. A short workout keeps your progress rolling."))
                } else if gap == 7, let when = at(day, reminderMinutes) {
                    options.append(Nudge(date: when, kind: .comeback, priority: 85,
                                         title: "Comeback bonus: 2× XP 💥",
                                         body: "Your next workout earns double XP. Your buddy's waiting!"))
                }
            }

            // Training reminder at your usual time on your usual days.
            let gapOK = lastWorkout.map { daysBetween($0, day) < 3 } ?? true
            let isTrainingDay = usePattern ? patternDays.contains(weekday)
                : lastWorkout.map { daysBetween($0, day) >= 2 && daysBetween($0, day) % 2 == 0 } ?? (offset >= 1)
            if nextPlanDay > 0, isTrainingDay, gapOK, !(offset == 0 && trainedToday),
               let when = at(day, reminderMinutes) {
                let planDay = nextPlanDay
                options.append(Nudge(date: when, kind: .training, priority: 60,
                                     title: "Day \(planDay) · \(Routine.dayName(planDay)) is up 💪",
                                     body: "\(buddy)'s warming up. Every set races your last workout."))
                nextPlanDay = planDay % max(Routine.dayCount, 1) + 1
            }

            // Breakfast challenge mornings.
            if DailyChallenges.isBreakfastDay(day), let when = at(day, 9 * 60 + 30) {
                options.append(Nudge(date: when, kind: .food, priority: 40,
                                     title: "Log breakfast to win a daily challenge 🍳",
                                     body: "+20 XP, and it keeps your 🔥 streak alive."))
            }

            // Weekly missions: new on Monday, last call on Friday.
            if weekday == 2, let when = at(day, 9 * 60) {
                options.append(Nudge(date: when, kind: .missions, priority: 30,
                                     title: "New weekly missions are in 🎯",
                                     body: "3 weekly missions, plus a gym bag if you finish them all."))
            }
            // (Only this week's Friday: missions reset on Monday.)
            if weekday == 6, (1...2).contains(missionsLeft),
               (2...6).contains(cal.component(.weekday, from: today)),
               let when = at(day, 18 * 60) {
                options.append(Nudge(date: when, kind: .missions, priority: 50,
                                     title: "\(missionsLeft) weekly \(missionsLeft == 1 ? "mission" : "missions") left",
                                     body: "2 days to finish. Clear them all for a gym bag 🎁"))
            }

            // Keep what's allowed, in the future and outside quiet hours; one per day.
            let allowed = options.filter { nudge in
                guard nudge.kind.isOn, nudge.date > now.addingTimeInterval(60) else { return false }
                let minutes = cal.component(.hour, from: nudge.date) * 60 + cal.component(.minute, from: nudge.date)
                return minutes >= 8 * 60 && minutes <= 22 * 60 + 30
            }
            if let best = allowed.max(by: { $0.priority < $1.priority }) { result[offset] = best }
        }
        return result
    }
}
