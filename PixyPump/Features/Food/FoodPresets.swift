import Foundation
import SwiftData

/// Common basics, preloaded so you can start logging straight away.
/// Values are typical averages per 100 g; packaged products are best scanned.
enum FoodPresets {
    // name, kcal, protein, carbs, fat, usual portion (g)
    static let all: [(String, Double, Double, Double, Double, Double)] = [
        // Meat, fish, eggs
        ("Chicken breast (raw)", 120, 22.5, 0, 2.6, 150),
        ("Chicken breast (cooked)", 165, 31, 0, 3.6, 120),
        ("Turkey breast (raw)", 114, 23.7, 0, 1.5, 150),
        ("Beef mince 5% fat (raw)", 137, 21.4, 0, 5.5, 125),
        ("Beef mince 15% fat (raw)", 215, 18.6, 0, 15, 125),
        ("Ham (sliced)", 120, 19, 1.5, 4, 30),
        ("Salmon (raw)", 208, 20, 0, 13, 125),
        ("Cod (raw)", 82, 18, 0, 0.7, 150),
        ("Tuna in water (canned, drained)", 116, 26, 0, 1, 120),
        ("Egg (whole)", 143, 12.6, 0.7, 9.5, 50),
        ("Egg, boiled", 155, 12.6, 1.1, 10.6, 50),
        ("Egg whites", 52, 10.9, 0.7, 0.2, 100),
        ("Tofu (firm)", 144, 17.3, 2.8, 8.7, 100),

        // Dairy & protein
        ("Milk 2%", 50, 3.4, 4.8, 2, 250),
        ("Greek yogurt 0%", 59, 10.3, 3.6, 0.4, 150),
        ("Skyr (natural)", 63, 11, 4, 0.2, 150),
        ("Quark / twaróg (low-fat)", 99, 19.8, 3.5, 0.5, 100),
        ("Cottage cheese", 98, 11.1, 3.4, 4.3, 150),
        ("Mozzarella", 280, 28, 3, 17, 30),
        ("Cheddar / hard cheese", 403, 25, 1.3, 33, 30),
        ("Whey protein powder", 400, 78, 8, 6, 30),

        // Carbs
        ("Oats", 389, 16.9, 66, 6.9, 60),
        ("White rice (dry)", 365, 7.1, 80, 0.7, 75),
        ("White rice (cooked)", 130, 2.7, 28, 0.3, 200),
        ("Brown rice (cooked)", 123, 2.7, 25.6, 1, 200),
        ("Pasta (dry)", 371, 13, 75, 1.5, 80),
        ("Pasta (cooked)", 158, 5.8, 31, 0.9, 200),
        ("Buckwheat / kasza gryczana (dry)", 343, 13, 72, 3.4, 70),
        ("Couscous (dry)", 376, 12.8, 77, 0.6, 70),
        ("Potatoes (raw)", 77, 2, 17, 0.1, 250),
        ("Sweet potato (raw)", 86, 1.6, 20, 0.1, 200),
        ("Bread, white", 265, 9, 49, 3.2, 35),
        ("Bread, wholegrain", 247, 13, 41, 3.4, 35),
        ("Tortilla wrap", 312, 8, 52, 8, 60),
        ("Rice cakes", 387, 8, 81, 2.8, 10),
        ("Granola", 471, 10, 64, 20, 50),

        // Fruit & veg
        ("Banana", 89, 1.1, 23, 0.3, 120),
        ("Apple", 52, 0.3, 14, 0.2, 180),
        ("Orange", 47, 0.9, 12, 0.1, 150),
        ("Blueberries", 57, 0.7, 14.5, 0.3, 100),
        ("Strawberries", 32, 0.7, 7.7, 0.3, 150),
        ("Avocado", 160, 2, 8.5, 14.7, 100),
        ("Broccoli", 34, 2.8, 7, 0.4, 150),
        ("Spinach", 23, 2.9, 3.6, 0.4, 50),
        ("Tomato", 18, 0.9, 3.9, 0.2, 120),
        ("Cucumber", 15, 0.7, 3.6, 0.1, 150),
        ("Bell pepper", 31, 1, 6, 0.3, 150),
        ("Carrot", 41, 0.9, 10, 0.2, 80),
        ("Onion", 40, 1.1, 9.3, 0.1, 80),

        // Legumes
        ("Chickpeas (cooked)", 164, 8.9, 27.4, 2.6, 120),
        ("Red kidney beans (cooked)", 127, 8.7, 22.8, 0.5, 120),
        ("Lentils (cooked)", 116, 9, 20, 0.4, 150),
        ("Hummus", 166, 7.9, 14.3, 9.6, 50),

        // Fats & extras
        ("Olive oil", 884, 0, 0, 100, 10),
        ("Butter", 717, 0.9, 0.1, 81, 10),
        ("Peanut butter", 588, 25, 20, 50, 15),
        ("Almonds", 579, 21, 22, 50, 30),
        ("Walnuts", 654, 15, 14, 65, 30),
        ("Dark chocolate 70%", 598, 7.8, 46, 43, 20),
        ("Honey", 304, 0.3, 82, 0, 15),
        ("Sugar", 387, 0, 100, 0, 5),

        // Drinks
        ("Orange juice", 45, 0.7, 10.4, 0.2, 250),
        ("Coca-Cola", 42, 0, 10.6, 0, 330),
        ("Beer", 43, 0.5, 3.6, 0, 500),
    ]

    /// Foods you can count: name → (piece name, grams per piece).
    static let pieces: [String: (String, Double)] = [
        "Egg (whole)": ("egg", 50),
        "Egg, boiled": ("egg", 50),
        "Ham (sliced)": ("slice", 15),
        "Mozzarella": ("ball", 125),
        "Cheddar / hard cheese": ("slice", 20),
        "Whey protein powder": ("scoop", 30),
        "Bread, white": ("slice", 35),
        "Bread, wholegrain": ("slice", 35),
        "Tortilla wrap": ("wrap", 60),
        "Rice cakes": ("rice cake", 9),
        "Potatoes (raw)": ("potato", 150),
        "Banana": ("banana", 120),
        "Apple": ("apple", 180),
        "Orange": ("orange", 150),
        "Avocado": ("avocado", 150),
        "Tomato": ("tomato", 120),
        "Bell pepper": ("pepper", 150),
        "Carrot": ("carrot", 80),
        "Onion": ("onion", 110),
        "Coca-Cola": ("can", 330),
        "Beer": ("bottle", 500),
    ]

    /// Bump when the list above changes, so existing installs get the update.
    static let version = 2

    /// Adds presets and piece sizes. Safe to run every launch: it only fills
    /// in what's missing and never touches foods you created yourself.
    @MainActor
    static func install(into context: ModelContext, installedVersion: Int) {
        guard installedVersion < version else { return }
        let existing = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        let basicsByName = Dictionary(existing.filter(\.isBasic).map { ($0.name, $0) },
                                      uniquingKeysWith: { first, _ in first })

        for (name, kcal, p, c, f, serving) in all {
            let piece = pieces[name]
            if let food = basicsByName[name] {
                if food.pieceName == nil, let piece {
                    food.pieceName = piece.0
                    food.pieceGrams = piece.1
                }
            } else {
                context.insert(FoodItem(name: name, kcal: kcal, protein: p, carbs: c, fat: f,
                                        servingGrams: serving,
                                        pieceName: piece?.0, pieceGrams: piece?.1,
                                        isBasic: true))
            }
        }
    }
}
