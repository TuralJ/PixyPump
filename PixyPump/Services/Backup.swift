import Foundation
import SwiftData

/// Saves everything you've logged to a single .json file, and reads it back.
/// Restoring *merges*: anything already on the phone is kept, nothing is duplicated.
enum Backup {
    static let lastBackupKey = "lastBackupAt"

    /// Settings copied into the backup (goals, profile, rest timer…).
    static let settingKeys = [
        "goalKcal", "goalProtein", "goalCarbs", "goalFat",
        "profileSex", "profileAge", "profileHeight", "profileWeight",
        "profileActivity", "profileGoal",
        "lastTrainedDay", "lastTrainedAt",
        Prefs.autoRest, Prefs.restSeconds, Prefs.distanceUnit, Prefs.lengthUnit, "profileBirthDate",
        "planGoal", "planGoals", "planExperience", "planDays", "planMinutes", "planEquipment", "planFocus", "planAvoid",
        "plateExercises", "barWeight.kg", "barWeight.lb",
        "mascotLook.v1", "mascot", "xpLedger.v1", "bonusXP.v1", "inventory.v1", "rewardsStart",
        RestPlan.key,
    ]

    nonisolated enum BackupError: LocalizedError {
        case notABackup
        var errorDescription: String? { "This file isn't a \(AppInfo.name) backup." }
    }

    struct Summary {
        var sets = 0, foods = 0, entries = 0, meals = 0, weighIns = 0
        var text: String {
            if sets + foods + entries + meals + weighIns == 0 { return "Everything in the backup is already on this phone." }
            return "Added \(sets) sets, \(entries) food entries, \(foods) foods, \(meals) saved meals and \(weighIns) weigh-ins."
        }
    }

    // MARK: - Export

    @MainActor
    static func export(context: ModelContext) throws -> URL {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let foods = try context.fetch(FetchDescriptor<FoodItem>())
        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
        let meals = try context.fetch(FetchDescriptor<SavedMeal>())

        var settings: [String: Any] = [:]
        for key in settingKeys {
            if let value = UserDefaults.standard.object(forKey: key) { settings[key] = value }
        }

        var root: [String: Any] = [
            "app": "PixyPump",   // backup file ID: keep fixed even if the app is renamed
            "version": 1,
            "exportedAt": Date.now.timeIntervalSince1970,
            "settings": settings,
            "exercises": exercises.map { ex in
                [
                    "name": ex.name,
                    "createdAt": ex.createdAt.timeIntervalSince1970,
                    "notes": ex.notes ?? "",
                    "sets": ex.sets.map { set in
                        ["date": set.date.timeIntervalSince1970, "weight": set.weight, "reps": set.reps,
                         "kind": set.kindRaw ?? ""] as [String: Any]
                    },
                ] as [String: Any]
            },
            "foods": foods.map { f in
                var d: [String: Any] = [
                    "name": f.name, "brand": f.brand,
                    "kcal": f.kcal, "protein": f.protein, "carbs": f.carbs, "fat": f.fat,
                    "servingGrams": f.servingGrams, "isBasic": f.isBasic, "useCount": f.useCount,
                ]
                if let v = f.barcode { d["barcode"] = v }
                if let v = f.pieceName { d["pieceName"] = v }
                if let v = f.pieceGrams { d["pieceGrams"] = v }
                if let v = f.lastUsed { d["lastUsed"] = v.timeIntervalSince1970 }
                return d
            },
            "foodEntries": entries.map { e in
                var d: [String: Any] = [
                    "date": e.date.timeIntervalSince1970, "meal": e.mealRaw, "grams": e.grams,
                    "name": e.name, "kcal": e.kcalPer100, "protein": e.proteinPer100,
                    "carbs": e.carbsPer100, "fat": e.fatPer100, "isQuickAdd": e.isQuickAdd,
                ]
                if let v = e.pieces { d["pieces"] = v }
                if let v = e.pieceName { d["pieceName"] = v }
                return d
            },
            "savedMeals": meals.map { m in
                [
                    "name": m.name,
                    "items": m.sortedItems.map { i in
                        var d: [String: Any] = [
                            "order": i.order, "name": i.name, "grams": i.grams,
                            "kcal": i.kcalPer100, "protein": i.proteinPer100,
                            "carbs": i.carbsPer100, "fat": i.fatPer100, "isQuickAdd": i.isQuickAdd,
                        ]
                        if let v = i.pieces { d["pieces"] = v }
                        if let v = i.pieceName { d["pieceName"] = v }
                        return d
                    },
                ] as [String: Any]
            },
        ]

        // Body weight log.
        root["bodyWeight"] = BodyWeightStore.shared.backupJSON

        // Your training plan (days, exercises, target sets).
        if let plan = UserDefaults.standard.data(forKey: "routineDays.v1"),
           let planJSON = try? JSONSerialization.jsonObject(with: plan) {
            root["routine"] = planJSON
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppInfo.name) backup \(stamp).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastBackupKey)
        return url
    }

    // MARK: - Restore (merge)

    @MainActor
    static func restore(from url: URL, context: ModelContext) throws -> Summary {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        // A real backup is a few MB at most; don't load a huge file into memory.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 50_000_000 else { throw BackupError.notABackup }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              ["PixyPump", "Powerpuff"].contains(root["app"] as? String ?? "")
        else { throw BackupError.notABackup }

        var summary = Summary()

        // The file may have been edited by hand: only accept values the app could have written.
        // (Huge or infinite numbers would crash Int(...) and the number formatting later.)
        func raw(_ d: [String: Any], _ key: String) -> Double? {
            if let v = d[key] as? Double { return v }
            if let v = d[key] as? Int { return Double(v) }
            return nil
        }
        func num(_ d: [String: Any], _ key: String) -> Double? {
            raw(d, key).flatMap { $0.isFinite && abs($0) < 100_000 ? $0 : nil }
        }
        /// Grams, kcal, reps, counts: never negative.
        func amount(_ d: [String: Any], _ key: String) -> Double? {
            num(d, key).flatMap { $0 >= 0 ? $0 : nil }
        }
        func date(_ d: [String: Any], _ key: String) -> Date? {
            guard let v = raw(d, key), v.isFinite, v >= 0, v < 4_102_444_800 else { return nil }   // 1970 – 2100
            return Date(timeIntervalSince1970: v)
        }
        func text(_ d: [String: Any], _ key: String, max: Int = 1_000) -> String? {
            guard let s = d[key] as? String, s.count <= max else { return nil }
            return s
        }

        // Exercises & sets
        let existingExercises = try context.fetch(FetchDescriptor<Exercise>())
        for item in root["exercises"] as? [[String: Any]] ?? [] {
            guard let name = text(item, "name") else { continue }
            let exercise: Exercise
            if let found = existingExercises.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                exercise = found
            } else {
                exercise = Exercise(name: name)
                context.insert(exercise)
            }
            if let notes = text(item, "notes", max: 10_000), !notes.isEmpty, (exercise.notes ?? "").isEmpty {
                exercise.notes = notes
            }
            var known = Set(exercise.sets.map { "\(Int($0.date.timeIntervalSince1970))|\($0.weight)|\($0.reps)" })
            for s in item["sets"] as? [[String: Any]] ?? [] {
                guard let when = date(s, "date"), let weight = num(s, "weight"),
                      let reps = amount(s, "reps") else { continue }
                let key = "\(Int(when.timeIntervalSince1970))|\(weight)|\(Int(reps))"
                guard !known.contains(key) else { continue }
                known.insert(key)
                let kind = SetKind(rawValue: s["kind"] as? String ?? "") ?? .working
                exercise.sets.append(WorkoutSet(reps: Int(reps), weight: weight, date: when, kind: kind))
                summary.sets += 1
            }
        }

        // Foods
        let existingFoods = try context.fetch(FetchDescriptor<FoodItem>())
        var foodKeys = Set(existingFoods.map { "\($0.name.lowercased())|\($0.brand.lowercased())" })
        for f in root["foods"] as? [[String: Any]] ?? [] {
            guard let name = text(f, "name"), let kcal = amount(f, "kcal") else { continue }
            let brand = text(f, "brand") ?? ""
            let key = "\(name.lowercased())|\(brand.lowercased())"
            guard !foodKeys.contains(key) else { continue }
            foodKeys.insert(key)
            let food = FoodItem(name: name, brand: brand, barcode: text(f, "barcode", max: 32),
                                kcal: kcal, protein: amount(f, "protein") ?? 0,
                                carbs: amount(f, "carbs") ?? 0, fat: amount(f, "fat") ?? 0,
                                servingGrams: amount(f, "servingGrams") ?? 100,
                                pieceName: text(f, "pieceName"),
                                pieceGrams: amount(f, "pieceGrams"),
                                isBasic: f["isBasic"] as? Bool ?? false)
            food.useCount = Int(amount(f, "useCount") ?? 0)
            food.lastUsed = date(f, "lastUsed")
            context.insert(food)
            summary.foods += 1
        }

        // Food entries
        let existingEntries = try context.fetch(FetchDescriptor<FoodEntry>())
        var entryKeys = Set(existingEntries.map { "\(Int($0.date.timeIntervalSince1970))|\($0.name)|\($0.grams)" })
        for e in root["foodEntries"] as? [[String: Any]] ?? [] {
            guard let when = date(e, "date"), let name = text(e, "name"),
                  let grams = amount(e, "grams") else { continue }
            let key = "\(Int(when.timeIntervalSince1970))|\(name)|\(grams)"
            guard !entryKeys.contains(key) else { continue }
            entryKeys.insert(key)
            let per100 = Nutrition(kcal: amount(e, "kcal") ?? 0, protein: amount(e, "protein") ?? 0,
                                   carbs: amount(e, "carbs") ?? 0, fat: amount(e, "fat") ?? 0)
            context.insert(FoodEntry(name: name, per100: per100, grams: grams,
                                     pieces: amount(e, "pieces"), pieceName: text(e, "pieceName"),
                                     meal: Meal(rawValue: e["meal"] as? String ?? "") ?? .snacks,
                                     date: when, isQuickAdd: e["isQuickAdd"] as? Bool ?? false))
            summary.entries += 1
        }

        // Saved meals
        let existingMeals = try context.fetch(FetchDescriptor<SavedMeal>())
        var mealNames = Set(existingMeals.map { $0.name.lowercased() })
        for m in root["savedMeals"] as? [[String: Any]] ?? [] {
            guard let name = text(m, "name"), !mealNames.contains(name.lowercased()) else { continue }
            mealNames.insert(name.lowercased())
            let meal = SavedMeal(name: name)
            context.insert(meal)
            for i in m["items"] as? [[String: Any]] ?? [] {
                let per100 = Nutrition(kcal: amount(i, "kcal") ?? 0, protein: amount(i, "protein") ?? 0,
                                       carbs: amount(i, "carbs") ?? 0, fat: amount(i, "fat") ?? 0)
                let item = SavedMealItem(order: Int(amount(i, "order") ?? 0),
                                         name: text(i, "name") ?? "Food",
                                         grams: amount(i, "grams") ?? 100,
                                         pieces: amount(i, "pieces"),
                                         pieceName: text(i, "pieceName"),
                                         per100: per100,
                                         isQuickAdd: i["isQuickAdd"] as? Bool ?? false)
                context.insert(item)
                item.savedMeal = meal
            }
            summary.meals += 1
        }

        // Body weight log (merged by day).
        if let weighIns = root["bodyWeight"] as? [[String: Any]] {
            summary.weighIns = BodyWeightStore.shared.merge(backup: weighIns)
        }

        // Training plan — replaced by the one in the backup (the app reloads it).
        if let plan = root["routine"], JSONSerialization.isValidJSONObject(plan),
           let planData = try? JSONSerialization.data(withJSONObject: plan),
           let days = try? JSONDecoder().decode([RoutineDay].self, from: planData),
           days.count <= RoutineStore.maxDays,
           days.allSatisfy({ day in
               day.name.count <= 1_000 && day.items.count <= 100 && day.items.allSatisfy {
                   (1...20).contains($0.sets) && (1...100).contains($0.repsLow) && (1...100).contains($0.repsHigh)
                       && $0.name.count <= 1_000
               }
           }) {
            UserDefaults.standard.set(planData, forKey: "routineDays.v1")
        }

        // Settings (goals, profile, timer)
        if let settings = root["settings"] as? [String: Any] {
            for key in settingKeys {
                if let value = settings[key].flatMap(settingValue), rewardsAreSane(key, value) {
                    UserDefaults.standard.set(value, forKey: key)
                }
            }
        }

        try context.save()
        return summary
    }

    /// Only the plain kinds of value the app saves. Anything else (null, nested objects,
    /// huge numbers) is skipped — UserDefaults crashes on null, and Int(...) on huge numbers.
    private static func settingValue(_ value: Any) -> Any? {
        switch value {
        case let text as String:
            return text.count <= 1_000_000 ? text : nil
        case let number as NSNumber:
            return number.doubleValue.isFinite && abs(number.doubleValue) <= 1e10 ? number : nil
        case let list as [String]:
            return list.count <= 1_000 && list.allSatisfy({ $0.count <= 1_000 }) ? list : nil
        case let numbers as [String: NSNumber]:
            // Rest length per exercise (RestPlan): names → seconds.
            let sane = numbers.count <= 1_000 && numbers.allSatisfy {
                $0.key.count <= 1_000 && $0.value.doubleValue.isFinite && abs($0.value.doubleValue) <= 1e10
            }
            return sane ? numbers.mapValues { $0.intValue } : nil
        default:
            return nil
        }
    }

    /// XP is added up on every launch; out-of-range numbers would overflow and crash the app each time.
    private static func rewardsAreSane(_ key: String, _ value: Any) -> Bool {
        guard key == XPLedger.key || key == BonusXP.key else { return true }
        guard let text = value as? String, let data = text.data(using: .utf8) else { return false }
        let range = 0...100_000
        if key == BonusXP.key {
            guard let list = try? JSONDecoder().decode([String: Int].self, from: data) else { return false }
            return list.count <= 10_000 && list.values.allSatisfy { range.contains($0) }
        }
        guard let list = try? JSONDecoder().decode([String: XPEntry].self, from: data) else { return false }
        return list.count <= 10_000 && list.values.allSatisfy { entry in
            range.contains(entry.total) && entry.multiplier.isFinite && entry.lines.allSatisfy { range.contains($0.xp) }
        }
    }
}
