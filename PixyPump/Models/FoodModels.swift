import Foundation
import SwiftData

// MARK: - Meals

enum Meal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snacks

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snacks: return "carrot"
        }
    }

    /// Picks a sensible meal from the time of day.
    static func forTime(_ date: Date = .now) -> Meal {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<21: return .dinner
        default: return .snacks
        }
    }
}

// MARK: - Nutrition values

struct Nutrition {
    var kcal = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0

    static func + (a: Nutrition, b: Nutrition) -> Nutrition {
        Nutrition(kcal: a.kcal + b.kcal, protein: a.protein + b.protein,
                  carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }

    /// Values for a portion, when `self` is per 100 g.
    func portion(grams: Double) -> Nutrition {
        let f = grams / 100
        return Nutrition(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f)
    }
}

// MARK: - Stored data

/// A food you can pick from. All values are per 100 g.
@Model
final class FoodItem {
    var name: String
    var brand: String = ""
    var barcode: String? = nil
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingGrams: Double = 100
    /// Optional "by the piece" unit, e.g. "egg" weighing 50 g.
    var pieceName: String? = nil
    var pieceGrams: Double? = nil
    var isBasic: Bool = false
    var useCount: Int = 0
    var lastUsed: Date? = nil

    @Relationship(deleteRule: .nullify, inverse: \FoodEntry.food)
    var entries: [FoodEntry] = []

    init(name: String, brand: String = "", barcode: String? = nil,
         kcal: Double, protein: Double, carbs: Double, fat: Double,
         servingGrams: Double = 100, pieceName: String? = nil, pieceGrams: Double? = nil,
         isBasic: Bool = false) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingGrams = servingGrams
        self.pieceName = pieceName
        self.pieceGrams = pieceGrams
        self.isBasic = isBasic
    }

    var per100: Nutrition { Nutrition(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    /// The piece unit, if this food can be counted (e.g. eggs, slices of bread).
    var piece: PieceUnit? {
        guard let name = pieceName, let grams = pieceGrams, grams > 0 else { return nil }
        return PieceUnit(name: name, grams: grams)
    }
}

/// A countable unit, e.g. "egg" = 50 g.
struct PieceUnit: Hashable {
    var name: String
    var grams: Double

    /// "egg" for 1, "eggs" otherwise.
    func unitName(_ count: Double) -> String {
        if count == 1 || name.hasSuffix("s") { return name }
        if name.hasSuffix("ch") || name.hasSuffix("sh") || name.hasSuffix("x") { return name + "es" }
        return name + "s"
    }

    /// "1 egg", "3 eggs", "2 slices", "1.5 bananas"
    func label(_ count: Double) -> String { "\(count.plain) \(unitName(count))" }
}

/// Something you ate. Keeps its own copy of the values, so editing or
/// deleting a food later never changes your history.
@Model
final class FoodEntry {
    var date: Date
    var mealRaw: String
    var grams: Double
    var name: String
    var kcalPer100: Double
    var proteinPer100: Double
    var carbsPer100: Double
    var fatPer100: Double
    /// Set when logged by the piece (e.g. 3 eggs).
    var pieces: Double? = nil
    var pieceName: String? = nil
    /// Logged with "Quick add" (just calories/macros, no food).
    /// Optional on purpose: a new non-optional field can stop existing data from opening.
    var quickAdd: Bool? = nil
    var food: FoodItem?

    var isQuickAdd: Bool { quickAdd ?? false }

    init(food: FoodItem, grams: Double, pieces: Double? = nil, meal: Meal, date: Date) {
        self.date = date
        self.mealRaw = meal.rawValue
        self.grams = grams
        self.pieces = pieces
        self.pieceName = pieces == nil ? nil : food.pieceName
        self.name = food.brand.isEmpty ? food.name : "\(food.name) (\(food.brand))"
        self.kcalPer100 = food.kcal
        self.proteinPer100 = food.protein
        self.carbsPer100 = food.carbs
        self.fatPer100 = food.fat
        self.food = food
    }

    /// Builds an entry from stored values (copying a meal, saved meals, quick add, restore).
    init(name: String, per100: Nutrition, grams: Double, pieces: Double? = nil,
         pieceName: String? = nil, meal: Meal, date: Date,
         food: FoodItem? = nil, isQuickAdd: Bool = false) {
        self.date = date
        self.mealRaw = meal.rawValue
        self.grams = grams
        self.name = name
        self.kcalPer100 = per100.kcal
        self.proteinPer100 = per100.protein
        self.carbsPer100 = per100.carbs
        self.fatPer100 = per100.fat
        self.pieces = pieces
        self.pieceName = pieceName
        self.quickAdd = isQuickAdd ? true : nil
        self.food = food
    }

    /// A fresh copy of this entry for another day / meal.
    func copy(meal: Meal, date: Date) -> FoodEntry {
        FoodEntry(name: name, per100: per100, grams: grams, pieces: pieces,
                  pieceName: pieceName, meal: meal, date: date,
                  food: food, isQuickAdd: isQuickAdd)
    }

    var meal: Meal { Meal(rawValue: mealRaw) ?? .snacks }

    var per100: Nutrition {
        Nutrition(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100)
    }

    var nutrition: Nutrition { per100.portion(grams: grams) }

    /// "3 eggs · 150 g" or "150 g"
    var amountText: String {
        if isQuickAdd { return "Quick add" }
        if let pieces, let pieceName {
            return "\(PieceUnit(name: pieceName, grams: 0).label(pieces)) · \(grams.plain) g"
        }
        return "\(grams.plain) g"
    }
}

// MARK: - Saved meals

/// A group of foods you log together, e.g. "Protein shake" = whey + milk + banana.
@Model
final class SavedMeal {
    var name: String
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \SavedMealItem.savedMeal)
    var items: [SavedMealItem] = []

    init(name: String) {
        self.name = name
    }

    var sortedItems: [SavedMealItem] { items.sorted { $0.order < $1.order } }

    var total: Nutrition {
        items.reduce(Nutrition()) { $0 + $1.per100.portion(grams: $1.grams) }
    }
}

@Model
final class SavedMealItem {
    var order: Int
    var name: String
    var grams: Double
    var pieces: Double? = nil
    var pieceName: String? = nil
    var kcalPer100: Double
    var proteinPer100: Double
    var carbsPer100: Double
    var fatPer100: Double
    var isQuickAdd: Bool = false
    var savedMeal: SavedMeal?

    init(copying entry: FoodEntry, order: Int) {
        self.order = order
        self.name = entry.name
        self.grams = entry.grams
        self.pieces = entry.pieces
        self.pieceName = entry.pieceName
        self.kcalPer100 = entry.kcalPer100
        self.proteinPer100 = entry.proteinPer100
        self.carbsPer100 = entry.carbsPer100
        self.fatPer100 = entry.fatPer100
        self.isQuickAdd = entry.isQuickAdd
    }

    init(order: Int, name: String, grams: Double, pieces: Double?, pieceName: String?,
         per100: Nutrition, isQuickAdd: Bool) {
        self.order = order
        self.name = name
        self.grams = grams
        self.pieces = pieces
        self.pieceName = pieceName
        self.kcalPer100 = per100.kcal
        self.proteinPer100 = per100.protein
        self.carbsPer100 = per100.carbs
        self.fatPer100 = per100.fat
        self.isQuickAdd = isQuickAdd
    }

    var per100: Nutrition {
        Nutrition(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100)
    }

    func makeEntry(meal: Meal, date: Date) -> FoodEntry {
        FoodEntry(name: name, per100: per100, grams: grams, pieces: pieces,
                  pieceName: pieceName, meal: meal, date: date, isQuickAdd: isQuickAdd)
    }
}

/// Date to store for food logged on `day` (now if today, otherwise midday).
func logDate(for day: Date) -> Date {
    Calendar.current.isDateInToday(day) ? Date.now
        : Calendar.current.startOfDay(for: day).addingTimeInterval(12 * 3600)
}

// MARK: - Formatting helpers

extension Double {
    /// "8.5" under 10, "42" above — good for grams of macros.
    var nice: String {
        self < 10 ? String(format: "%.1f", self).replacingOccurrences(of: ".0", with: "")
                  : String(Int(self.rounded()))
    }

    /// Plain number for text fields: "150", "12.5" (no thousands separators).
    var plain: String {
        self == self.rounded() ? String(Int(self)) : String(format: "%.1f", self)
    }

    var kcalText: String { "\(self.spaced) kcal" }
}
