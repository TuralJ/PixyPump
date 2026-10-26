import Foundation
import Observation

/// One-off changes for today only: skip an exercise, swap it for another
/// (machine taken, sore shoulder…) or change the order. Your plan itself stays the same, and
/// everything resets by itself tomorrow.
@MainActor @Observable
final class TodayChanges {
    static let shared = TodayChanges()
    private static let key = "todayChanges.v1"

    /// The date these changes belong to ("2026-10-08").
    private var dateKey: String
    /// "day|original name" → replacement name ("" = skipped).
    private var changes: [String: String]

    private init() {
        let saved = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        dateKey = saved["__date"] ?? ""
        var rest = saved
        rest["__date"] = nil
        changes = rest
    }

    private static var todayKey: String {
        Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    /// Today's changes (empty if they were made on another day).
    private var current: [String: String] {
        dateKey == Self.todayKey ? changes : [:]
    }

    private func id(_ day: Int, _ name: String) -> String { "\(day)|\(name.lowercased())" }

    private func update(_ body: (inout [String: String]) -> Void) {
        var copy = current
        body(&copy)
        changes = copy
        dateKey = Self.todayKey
        var saved = copy
        saved["__date"] = dateKey
        UserDefaults.standard.set(saved, forKey: Self.key)
    }

    // MARK: Changing today

    /// Skip for today. Skipping a swapped-in exercise skips the plan's original slot.
    func skip(_ name: String, day: Int) {
        let target = original(of: name, day: day) ?? name
        update { $0[id(day, target)] = "" }
    }
    func swap(_ name: String, for replacement: String, day: Int) { update { $0[id(day, name)] = replacement } }

    /// Undo a skip or swap. Accepts either the original or the replacement name.
    func undo(_ name: String, day: Int) {
        update { changes in
            changes[id(day, name)] = nil
            if let original = changes.first(where: { $0.key.hasPrefix("\(day)|") && $0.value.caseInsensitiveCompare(name) == .orderedSame })?.key {
                changes[original] = nil
            }
        }
    }

    // MARK: Finishing an exercise with fewer sets

    private func doneID(_ day: Int, _ name: String) -> String { "done|\(day)|\(name.lowercased())" }

    /// "That's enough for today": counts the exercise as done with the sets you've logged.
    func finishEarly(_ name: String, day: Int, sets: Int) {
        update { $0[doneID(day, name)] = String(max(sets, 1)) }
    }

    /// Undo an early finish (back to the planned number of sets).
    func reopen(_ name: String, day: Int) {
        update { $0[doneID(day, name)] = nil }
    }

    /// Sets you finished this exercise at today, if you ended it early.
    func finishedSets(_ name: String, day: Int) -> Int? {
        current[doneID(day, name)].flatMap { Int($0) }
    }

    // MARK: Changing the order for today

    private func orderID(_ day: Int) -> String { "order|\(day)" }

    /// Do today's exercises in a different order (machine busy, gym crowded…).
    /// Pass the plan's names (not swapped-in ones), so a swap keeps its new spot.
    func setOrder(_ names: [String], day: Int) {
        update { $0[orderID(day)] = names.map { $0.lowercased() }.joined(separator: "\n") }
    }

    /// Back to the plan's order for today.
    func resetOrder(day: Int) {
        update { $0[orderID(day)] = nil }
    }

    /// True if today's order on this day differs from the plan.
    func hasCustomOrder(day: Int) -> Bool {
        !(current[orderID(day)] ?? "").isEmpty
    }

    /// The plan's list in today's order. Names you moved come first, in your order;
    /// anything not in it (e.g. an exercise you brought back) follows in plan order.
    func ordered(_ list: [String], day: Int) -> [String] {
        guard let saved = current[orderID(day)], !saved.isEmpty else { return list }
        var remaining = list
        var result: [String] = []
        for key in saved.components(separatedBy: "\n") {
            if let i = remaining.firstIndex(where: { $0.lowercased() == key }) {
                result.append(remaining.remove(at: i))
            }
        }
        return result + remaining
    }

    // MARK: Reading

    /// The day's exercises with today's skips and swaps applied.
    func apply(_ list: [String], day: Int) -> [String] {
        let now = current
        guard !now.isEmpty else { return list }
        return list.compactMap { name in
            guard let replacement = now[id(day, name)] else { return name }
            return replacement.isEmpty ? nil : replacement
        }
    }

    /// Exercises skipped today on this day.
    func skipped(in list: [String], day: Int) -> [String] {
        list.filter { current[id(day, $0)] == "" }
    }

    /// If `name` is standing in for another exercise today, the original's name.
    func original(of name: String, day: Int) -> String? {
        let prefix = "\(day)|"
        guard let key = current.first(where: { $0.key.hasPrefix(prefix) && !$0.value.isEmpty
                                               && $0.value.caseInsensitiveCompare(name) == .orderedSame })?.key
        else { return nil }
        let lowered = String(key.dropFirst(prefix.count))
        return Routine.exercises(onDay: day).first { $0.lowercased() == lowered }
    }
}
