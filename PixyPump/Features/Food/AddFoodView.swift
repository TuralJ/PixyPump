import SwiftUI
import SwiftData

enum FoodRoute: Hashable {
    case scan
    case quickAdd
    case amount(FoodItem)
    case newFood(FoodDraft)
    case editFood(FoodItem)
}

/// Sheet for adding food to a meal: search your foods, scan a barcode, or create one.
struct AddFoodView: View {
    let meal: Meal
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]
    @Query(sort: \SavedMeal.name) private var savedMeals: [SavedMeal]

    @State private var search = ""
    @State private var path: [FoodRoute] = []
    @State private var isLookingUp = false

    private var recent: [FoodItem] {
        foods.filter { $0.lastUsed != nil }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
            .prefix(8)
            .map { $0 }
    }

    private var filtered: [FoodItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return foods }
        return foods.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.brand.localizedCaseInsensitiveContains(q)
        }
    }

    private var filteredMeals: [SavedMeal] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return savedMeals }
        return savedMeals.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: FoodRoute.scan) {
                        Label { Text("Scan barcode") } icon: { Image.pixel(.barcode) }
                    }
                    NavigationLink(value: FoodRoute.quickAdd) {
                        Label { Text("Quick add calories") } icon: { Image.pixel(.zap) }
                    }
                    NavigationLink(value: FoodRoute.newFood(FoodDraft(name: search))) {
                        Label { Text("Create new food") } icon: { Image.pixel(.edit) }
                    }
                }
                .listRowBackground(Color.ppCard)

                if !filteredMeals.isEmpty {
                    Section {
                        ForEach(filteredMeals) { saved in
                            Button { logSavedMeal(saved) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label {
                                        Text(saved.name)
                                    } icon: {
                                        Image.pixel(.star).foregroundStyle(Color.ppFat)
                                    }
                                    Text("\(saved.items.count) items · \(saved.total.kcal.kcalText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                        }
                        .onDelete { offsets in
                            deleteSavedMeals(offsets.map { filteredMeals[$0] })
                        }
                    } header: {
                        PPHeader("Saved meals")
                    }
                    .listRowBackground(Color.ppCard)
                }

                if search.isEmpty && !recent.isEmpty {
                    Section {
                        ForEach(recent) { FoodRow(food: $0, onEdit: edit) }
                    } header: {
                        PPHeader("Recent")
                    }
                    .listRowBackground(Color.ppCard)
                }

                Section {
                    ForEach(filtered) { FoodRow(food: $0, onEdit: edit) }
                        .onDelete { offsets in
                            deleteFoods(offsets.map { filtered[$0] })
                        }
                } header: {
                    PPHeader(search.isEmpty ? "All foods" : "Results")
                } footer: {
                    Text("Swipe right on a food to edit it, left to delete it.")
                }
                .listRowBackground(Color.ppCard)
            }
            .ppScreen()
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search your foods")
            .navigationTitle("Add to \(meal.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: FoodRoute.self) { route in
                switch route {
                case .scan:
                    BarcodeScannerScreen { code in handleBarcode(code) }
                case .quickAdd:
                    QuickAddView(meal: meal) { name, nutrition, chosenMeal in
                        context.insert(FoodEntry(name: name, per100: nutrition, grams: 100,
                                                 meal: chosenMeal, date: logDate(for: day),
                                                 isQuickAdd: true))
                        Haptics.success()
                        dismiss()
                    }
                case .editFood(let food):
                    FoodFormView(editing: food) { _ in path.removeLast() }
                case .amount(let food):
                    AmountView(title: food.name,
                               per100: food.per100,
                               initialGrams: food.servingGrams,
                               meal: meal,
                               serving: food.servingGrams,
                               piece: food.piece,
                               buttonTitle: "Add") { grams, pieces, chosenMeal in
                        log(food, grams: grams, pieces: pieces, meal: chosenMeal)
                    }
                case .newFood(let draft):
                    FoodFormView(draft: draft) { saved in
                        path.removeLast()
                        path.append(.amount(saved))
                    }
                }
            }
            .overlay {
                if isLookingUp {
                    ProgressView("Looking up product…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                }
            }
        }
        // This is a sheet, so it needs its own Undo toast (the app's one sits underneath).
        .undoToasts()
    }

    /// Deletes foods from your list, with Undo. Past logs keep their own copy either way.
    private func deleteFoods(_ doomed: [FoodItem]) {
        guard !doomed.isEmpty else { return }
        Haptics.warning()
        let snapshots = doomed.map(FoodItemSnapshot.init)
        for food in doomed { context.delete(food) }
        let store = context
        let message = doomed.count == 1 ? "\(doomed[0].name) deleted" : "\(doomed.count) foods deleted"
        UndoCenter.shared.show(message) {
            for snapshot in snapshots { snapshot.restore(into: store) }
        }
    }

    /// Deletes saved meals, with Undo.
    private func deleteSavedMeals(_ doomed: [SavedMeal]) {
        guard !doomed.isEmpty else { return }
        Haptics.warning()
        let snapshots = doomed.map(SavedMealSnapshot.init)
        for saved in doomed { context.delete(saved) }
        let store = context
        let message = doomed.count == 1 ? "\(doomed[0].name) deleted" : "\(doomed.count) saved meals deleted"
        UndoCenter.shared.show(message) {
            for snapshot in snapshots { snapshot.restore(into: store) }
        }
    }

    private func edit(_ food: FoodItem) {
        path.append(.editFood(food))
    }

    private func logSavedMeal(_ saved: SavedMeal) {
        for item in saved.sortedItems {
            context.insert(item.makeEntry(meal: meal, date: logDate(for: day)))
        }
        hapticSuccess()
        dismiss()
    }

    private func log(_ food: FoodItem, grams: Double, pieces: Double?, meal: Meal) {
        let date = logDate(for: day)
        context.insert(FoodEntry(food: food, grams: grams, pieces: pieces, meal: meal, date: date))
        food.useCount += 1
        food.lastUsed = .now
        Haptics.success()
        dismiss()
    }

    private func handleBarcode(_ code: String) {
        // Leave the scanner screen.
        if path.last == .scan { path.removeLast() }

        // Only product numbers (EAN/UPC) go to Open Food Facts — a QR code could hold any text.
        guard OpenFoodFacts.isProductCode(code) else {
            path.append(.newFood(FoodDraft(
                note: "That isn't a product barcode (those are 8–14 digits). Enter the food from its label instead.")))
            return
        }

        // Already scanned before? Go straight to the amount.
        if let known = foods.first(where: { $0.barcode == code }) {
            path.append(.amount(known))
            return
        }
        isLookingUp = true
        Task {
            let draft = await OpenFoodFacts.lookup(barcode: code)
            isLookingUp = false
            path.append(.newFood(draft ?? FoodDraft(
                barcode: code,
                note: "This product isn't in the database yet. Enter the values from the label once and it's saved for next time."
            )))
        }
    }
}

private struct FoodRow: View {
    let food: FoodItem
    let onEdit: (FoodItem) -> Void

    var body: some View {
        NavigationLink(value: FoodRoute.amount(food)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(food.brand.isEmpty ? food.name : "\(food.name) · \(food.brand)")
                    .lineLimit(1)
                Text("\(food.kcal.kcalText) · P \(food.protein.nice) · C \(food.carbs.nice) · F \(food.fat.nice) per 100 g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Swipe right (or long-press) to fix its values or add a piece size.
        .swipeActions(edge: .leading) {
            Button { onEdit(food) } label: { Label { Text("Edit") } icon: { Image.pixel(.pencil) } }
                .tint(Color.brand)
        }
        .contextMenu {
            Button { onEdit(food) } label: { Label { Text("Edit food") } icon: { Image.pixel(.pencil) } }
        }
        .accessibilityAction(named: "Edit food") { onEdit(food) }
    }
}

// MARK: - Undo support

/// A plain copy of a food from your list, so Undo can bring it back
/// and re-link the past logs that pointed at it.
private struct FoodItemSnapshot {
    let name: String
    let brand: String
    let barcode: String?
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let servingGrams: Double
    let pieceName: String?
    let pieceGrams: Double?
    let isBasic: Bool
    let useCount: Int
    let lastUsed: Date?
    let entries: [FoodEntry]

    init(_ food: FoodItem) {
        name = food.name
        brand = food.brand
        barcode = food.barcode
        kcal = food.kcal
        protein = food.protein
        carbs = food.carbs
        fat = food.fat
        servingGrams = food.servingGrams
        pieceName = food.pieceName
        pieceGrams = food.pieceGrams
        isBasic = food.isBasic
        useCount = food.useCount
        lastUsed = food.lastUsed
        entries = food.entries
    }

    func restore(into context: ModelContext) {
        let food = FoodItem(name: name, brand: brand, barcode: barcode,
                            kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                            servingGrams: servingGrams, pieceName: pieceName, pieceGrams: pieceGrams,
                            isBasic: isBasic)
        context.insert(food)
        food.useCount = useCount
        food.lastUsed = lastUsed
        for entry in entries where !entry.isDeleted && entry.modelContext != nil {
            entry.food = food
        }
    }
}

/// A plain copy of a saved meal and its foods, for Undo.
private struct SavedMealSnapshot {
    struct Item {
        let order: Int
        let name: String
        let grams: Double
        let pieces: Double?
        let pieceName: String?
        let per100: Nutrition
        let isQuickAdd: Bool
    }

    let name: String
    let createdAt: Date
    let items: [Item]

    init(_ saved: SavedMeal) {
        name = saved.name
        createdAt = saved.createdAt
        items = saved.sortedItems.map {
            Item(order: $0.order, name: $0.name, grams: $0.grams, pieces: $0.pieces,
                 pieceName: $0.pieceName, per100: $0.per100, isQuickAdd: $0.isQuickAdd)
        }
    }

    func restore(into context: ModelContext) {
        let saved = SavedMeal(name: name)
        context.insert(saved)
        saved.createdAt = createdAt
        for item in items {
            let copy = SavedMealItem(order: item.order, name: item.name, grams: item.grams,
                                     pieces: item.pieces, pieceName: item.pieceName,
                                     per100: item.per100, isQuickAdd: item.isQuickAdd)
            context.insert(copy)
            copy.savedMeal = saved
        }
    }
}

// MARK: - Amount

/// Enter an amount — by the piece (3 eggs) or in grams — and see the
/// calories and macros for that portion.
struct AmountView: View {
    let title: String
    let per100: Nutrition
    let serving: Double?
    let piece: PieceUnit?
    let buttonTitle: String
    /// grams, pieces (nil when logged in grams), meal
    let onSave: (Double, Double?, Meal) -> Void

    @State private var byPiece: Bool
    @State private var gramsText: String
    @State private var piecesText: String
    @State private var meal: Meal
    @FocusState private var focused: Bool

    init(title: String, per100: Nutrition, initialGrams: Double, initialPieces: Double? = nil,
         meal: Meal, serving: Double? = nil, piece: PieceUnit? = nil, buttonTitle: String,
         onSave: @escaping (Double, Double?, Meal) -> Void) {
        self.title = title
        self.per100 = per100
        self.serving = serving
        self.piece = piece
        self.buttonTitle = buttonTitle
        self.onSave = onSave
        // Countable foods start in pieces, unless this entry was logged in grams.
        let startByPiece = piece != nil && (initialPieces != nil || initialGrams == serving)
        _byPiece = State(initialValue: startByPiece)
        _gramsText = State(initialValue: initialGrams.plain)
        _piecesText = State(initialValue: (initialPieces ?? 1).plain)
        _meal = State(initialValue: meal)
    }

    private var pieces: Double { Double(userInput: piecesText) ?? 0 }

    private var grams: Double {
        if byPiece, let piece { return pieces * piece.grams }
        return Double(userInput: gramsText) ?? 0
    }

    private var quickGrams: [Double] {
        var list: [Double] = [50, 100, 150, 200]
        if let serving, !list.contains(serving) { list.insert(serving, at: 0) }
        return Array(list.prefix(4))
    }

    var body: some View {
        let portion = per100.portion(grams: grams)
        Form {
            Section {
                if let piece {
                    Picker("Unit", selection: $byPiece) {
                        Text("Pieces (\(piece.name))").tag(true)
                        Text("Grams").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .hapticOnChange(of: byPiece)
                    .onChange(of: byPiece) { _, nowByPiece in
                        // Carry the amount across when switching.
                        if nowByPiece {
                            piecesText = max(1, ((Double(userInput: gramsText) ?? 0) / piece.grams).rounded()).plain
                        } else {
                            gramsText = (pieces * piece.grams).plain
                        }
                    }
                }

                HStack {
                    Text(byPiece ? "How many" : "Amount")
                    TextField("0", text: byPiece ? $piecesText : $gramsText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.pixel(DS.TextSize.title, relativeTo: .title))
                        .foregroundStyle(Color.ppText)
                        .focused($focused)
                        .frame(maxWidth: .infinity)
                    Text(byPiece ? (piece?.unitName(pieces) ?? "") : "g")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }

                HStack {
                    if byPiece {
                        ForEach([1.0, 2, 3, 4], id: \.self) { n in
                            Button(n.plain) { Haptics.select(); piecesText = n.plain }
                                .buttonStyle(.bordered)
                                .tint(Color.ppText)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(quickGrams, id: \.self) { amount in
                            Button("\(amount.plain) g") { Haptics.select(); gramsText = amount.plain }
                                .buttonStyle(.bordered)
                                .tint(Color.ppText)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                // Large buttons keep each quick amount at least 44 pt tall.
                .controlSize(.large)
            } footer: {
                if byPiece, let piece {
                    Text("1 \(piece.name) ≈ \(piece.grams.plain) g, so this is \(grams.plain) g.")
                }
            }
            .listRowBackground(Color.ppCard)

            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                .hapticOnChange(of: meal)
            }
            .listRowBackground(Color.ppCard)

            Section("This portion") {
                LabeledContent("Calories") {
                    Text(portion.kcal.kcalText)
                        .font(.pixel(DS.TextSize.title3, relativeTo: .headline))
                        .foregroundStyle(Color.ppText)
                }
                LabeledContent("Protein", value: "\(portion.protein.nice) g")
                LabeledContent("Carbs", value: "\(portion.carbs.nice) g")
                LabeledContent("Fat", value: "\(portion.fat.nice) g")
            }
            .listRowBackground(Color.ppCard)
        }
        .ppScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(buttonTitle) { onSave(grams, byPiece ? pieces : nil, meal) }
                    .disabled(grams <= 0)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }
}

// MARK: - New / scanned food

struct FoodDraft: Hashable {
    var name = ""
    var brand = ""
    var barcode: String? = nil
    var kcal = ""
    var protein = ""
    var carbs = ""
    var fat = ""
    var serving = "100"
    var pieceName = ""
    var pieceGrams = ""
    var note: String? = nil
}

/// Create a food from its label (values per 100 g). Also used to confirm scanned products.
struct FoodFormView: View {
    @Environment(\.modelContext) private var context
    @State private var draft: FoodDraft
    /// Set when changing an existing food instead of creating a new one.
    private let editing: FoodItem?
    let onSave: (FoodItem) -> Void

    init(draft: FoodDraft, onSave: @escaping (FoodItem) -> Void) {
        _draft = State(initialValue: draft)
        self.editing = nil
        self.onSave = onSave
    }

    init(editing food: FoodItem, onSave: @escaping (FoodItem) -> Void) {
        _draft = State(initialValue: FoodDraft(
            name: food.name, brand: food.brand, barcode: food.barcode,
            kcal: food.kcal.plain, protein: food.protein.plain,
            carbs: food.carbs.plain, fat: food.fat.plain,
            serving: food.servingGrams.plain,
            pieceName: food.pieceName ?? "",
            pieceGrams: food.pieceGrams?.plain ?? ""))
        self.editing = food
        self.onSave = onSave
    }

    private var protein: Double { Double(userInput: draft.protein) ?? 0 }
    private var carbs: Double { Double(userInput: draft.carbs) ?? 0 }
    private var fat: Double { Double(userInput: draft.fat) ?? 0 }
    private var macroKcal: Double { protein * 4 + carbs * 4 + fat * 9 }
    private var kcal: Double { Double(userInput: draft.kcal) ?? macroKcal }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && kcal > 0
    }

    var body: some View {
        Form {
            if let note = draft.note {
                Section { Text(note).font(.callout) }
                .listRowBackground(Color.ppCard)
            }

            Section("Food") {
                TextField("Name (e.g. Skyr natural)", text: $draft.name)
                TextField("Brand (optional)", text: $draft.brand)
                if let barcode = draft.barcode {
                    LabeledContent("Barcode", value: barcode)
                }
            }
            .listRowBackground(Color.ppCard)

            Section {
                numberRow("Calories", text: $draft.kcal, unit: "kcal",
                          placeholder: macroKcal > 0 ? macroKcal.plain : "0")
                numberRow("Protein", text: $draft.protein, unit: "g")
                numberRow("Carbs", text: $draft.carbs, unit: "g")
                numberRow("Fat", text: $draft.fat, unit: "g")
            } header: {
                Text("Per 100 g")
            } footer: {
                Text("Copy these from the label's \"per 100 g\" column. Leave calories empty to calculate them from the macros.")
            }
            .listRowBackground(Color.ppCard)

            Section {
                numberRow("Usual portion", text: $draft.serving, unit: "g")
            }
            .listRowBackground(Color.ppCard)

            Section {
                TextField("Piece name (e.g. egg, slice, bar)", text: $draft.pieceName)
                numberRow("Weight of 1 piece", text: $draft.pieceGrams, unit: "g")
            } header: {
                Text("Count by the piece (optional)")
            } footer: {
                Text("Fill this in for things you count, like eggs or protein bars, so you can log \"3 eggs\" instead of grams.")
            }
            .listRowBackground(Color.ppCard)
        }
        .ppScreen()
        .navigationTitle(editing != nil ? "Edit food" : draft.barcode == nil ? "New food" : "Scanned product")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!canSave)
            }
        }
    }

    private func numberRow(_ label: String, text: Binding<String>, unit: String,
                           placeholder: String = "0") -> some View {
        HStack {
            Text(label)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let trimmedPiece = draft.pieceName.trimmingCharacters(in: .whitespaces)
        let pieceName: String? = trimmedPiece.isEmpty || (Double(userInput: draft.pieceGrams) ?? 0) <= 0
            ? nil : trimmedPiece
        if let food = editing {
            // Changes apply to future logs; past entries keep their own copy.
            food.name = draft.name.trimmingCharacters(in: .whitespaces)
            food.brand = draft.brand.trimmingCharacters(in: .whitespaces)
            food.kcal = kcal
            food.protein = protein
            food.carbs = carbs
            food.fat = fat
            food.servingGrams = Double(userInput: draft.serving) ?? 100
            food.pieceName = pieceName
            food.pieceGrams = pieceName == nil ? nil : Double(userInput: draft.pieceGrams)
            onSave(food)
            return
        }
        let food = FoodItem(
            name: draft.name.trimmingCharacters(in: .whitespaces),
            brand: draft.brand.trimmingCharacters(in: .whitespaces),
            barcode: draft.barcode,
            kcal: kcal, protein: protein, carbs: carbs, fat: fat,
            servingGrams: Double(userInput: draft.serving) ?? 100,
            pieceName: pieceName,
            pieceGrams: pieceName == nil ? nil : Double(userInput: draft.pieceGrams))
        context.insert(food)
        onSave(food)
    }
}

// MARK: - Open Food Facts lookup

/// Free, open food database with good coverage of European supermarket products.
enum OpenFoodFacts {
    /// EAN-8, UPC-A, EAN-13, ITF-14: digits only, so it's safe to put in the URL.
    static func isProductCode(_ code: String) -> Bool {
        (8...14).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func lookup(barcode: String) async -> FoodDraft? {
        guard isProductCode(barcode) else { return nil }
        let fields = "product_name,product_name_pl,product_name_en,brands,nutriments,serving_quantity"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("\(AppInfo.name)/1.0 (personal iOS gym app)", forHTTPHeaderField: "User-Agent")

        guard let result = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              (json["status"] as? Int) == 1,
              let product = json["product"] as? [String: Any]
        else { return nil }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        // Anyone can edit Open Food Facts: a huge value would crash `.plain` (Int conversion).
        func number(_ value: Any?) -> Double? {
            if let d = value as? Double { return d.isFinite && abs(d) < 100_000 ? d : nil }
            if let s = value as? String { return Double(userInput: s) }
            return nil
        }
        func n(_ key: String) -> Double? { number(nutriments[key]) }

        var kcal = n("energy-kcal_100g")
        if kcal == nil, let kj = n("energy-kj_100g") ?? n("energy_100g") { kcal = kj / 4.184 }

        func text(_ key: String) -> String? {
            guard let s = product[key] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return String(s.prefix(200))
        }
        let name = text("product_name_pl") ?? text("product_name") ?? text("product_name_en") ?? ""
        let brand = (text("brands") ?? "").components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let serving = number(product["serving_quantity"]).map { $0.plain } ?? "100"

        func field(_ value: Double?) -> String { value.map { $0.plain } ?? "" }

        return FoodDraft(
            name: name,
            brand: brand,
            barcode: barcode,
            kcal: field(kcal),
            protein: field(n("proteins_100g")),
            carbs: field(n("carbohydrates_100g")),
            fat: field(n("fat_100g")),
            serving: serving,
            note: "Found on Open Food Facts. Check the numbers match the label, then tap Save."
        )
    }
}

// MARK: - Quick add

/// Log just calories (and optional macros) — for eating out or when you only know the total.
struct QuickAddView: View {
    let onAdd: (String, Nutrition, Meal) -> Void

    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var meal: Meal
    @FocusState private var kcalFocused: Bool

    init(meal: Meal, onAdd: @escaping (String, Nutrition, Meal) -> Void) {
        _meal = State(initialValue: meal)
        self.onAdd = onAdd
    }

    private var calories: Double { Double(userInput: kcal) ?? 0 }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Calories")
                    TextField("0", text: $kcal)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.pixel(DS.TextSize.title, relativeTo: .title))
                        .foregroundStyle(Color.ppText)
                        .focused($kcalFocused)
                    Text("kcal").foregroundStyle(.secondary)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
                .onTapGesture { kcalFocused = true }
                TextField("What was it? (optional)", text: $name)
            }
            .listRowBackground(Color.ppCard)

            Section {
                macroRow("Protein", $protein)
                macroRow("Carbs", $carbs)
                macroRow("Fat", $fat)
            } header: {
                Text("Macros (optional)")
            }
            .listRowBackground(Color.ppCard)

            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                .hapticOnChange(of: meal)
            }
            .listRowBackground(Color.ppCard)
        }
        .ppScreen()
        .navigationTitle("Quick add")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let title = name.trimmingCharacters(in: .whitespaces)
                    onAdd(title.isEmpty ? "Quick add" : title,
                          Nutrition(kcal: calories,
                                    protein: Double(userInput: protein) ?? 0,
                                    carbs: Double(userInput: carbs) ?? 0,
                                    fat: Double(userInput: fat) ?? 0),
                          meal)
                }
                .disabled(calories <= 0)
            }
        }
        .onAppear { kcalFocused = true }
    }

    private func macroRow(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("g").foregroundStyle(.secondary)
        }
    }
}
