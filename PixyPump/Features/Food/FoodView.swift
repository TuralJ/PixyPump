import SwiftUI
import SwiftData

/// The Food tab: today's calories and macros, split into meals.
struct FoodView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var allEntries: [FoodEntry]

    @AppStorage("foodPresetVersion") private var presetVersion = 0
    @AppStorage("goalKcal") private var goalKcal = 2500.0
    @AppStorage("goalProtein") private var goalProtein = 160.0
    @AppStorage("goalCarbs") private var goalCarbs = 280.0
    @AppStorage("goalFat") private var goalFat = 75.0

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var addingTo: Meal?
    @State private var editing: FoodEntry?
    @State private var showGoals = false
    @State private var mealToSave: Meal?
    @State private var savedMealName = ""
    /// Meal waiting for "Delete all" to be confirmed.
    @State private var mealToClear: Meal?

    private var entries: [FoodEntry] {
        allEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var total: Nutrition {
        entries.reduce(Nutrition()) { $0 + $1.nutrition }
    }

    private var previousDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
    }

    private func entries(for meal: Meal, on date: Date) -> [FoodEntry] {
        allEntries.filter { $0.meal == meal && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func copyFromPreviousDay(_ meal: Meal) {
        for entry in entries(for: meal, on: previousDay) {
            context.insert(entry.copy(meal: meal, date: logDate(for: day)))
        }
        hapticSuccess()
    }

    private func copyLabel(_ meal: Meal, _ previous: [FoodEntry]) -> String {
        let when = Calendar.current.isDateInToday(day) ? "yesterday's" : "previous day's"
        let kcal = previous.reduce(0.0) { $0 + $1.nutrition.kcal }
        return "Copy \(when) \(meal.title.lowercased()) · \(kcal.kcalText)"
    }

    private func saveMeal() {
        guard let meal = mealToSave else { return }
        let name = savedMealName.trimmingCharacters(in: .whitespaces)
        let saved = SavedMeal(name: name.isEmpty ? meal.title : name)
        context.insert(saved)
        for (i, entry) in entries(for: meal, on: day).enumerated() {
            let item = SavedMealItem(copying: entry, order: i)
            context.insert(item)
            item.savedMeal = saved
        }
        savedMealName = ""
        mealToSave = nil
        hapticSuccess()
    }

    /// Deletes one or more logged foods, with an Undo toast that puts them back.
    private func delete(_ doomed: [FoodEntry], message: String) {
        guard !doomed.isEmpty else { return }
        Haptics.warning()
        let snapshots = doomed.map(FoodEntrySnapshot.init)
        withAnimation {
            for entry in doomed { context.delete(entry) }
        }
        let store = context
        UndoCenter.shared.show(message) {
            withAnimation {
                for snapshot in snapshots { snapshot.restore(into: store) }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        DaySwitcher(day: $day)
                        // Tap the numbers to change your goals.
                        Button { Haptics.tap(); showGoals = true } label: {
                            SummaryCard(total: total, goalKcal: goalKcal, goalProtein: goalProtein,
                                        goalCarbs: goalCarbs, goalFat: goalFat)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens your calorie and macro goals")
                        // The ring is tappable too, but this says so out loud.
                        HStack {
                            Spacer()
                            Button { Haptics.tap(); showGoals = true } label: {
                                Label { Text("Edit goals") } icon: { Image.pixel(.target, size: 16) }
                                    .font(.subheadline)
                                    .frame(minHeight: 44)
                                    .padding(.horizontal, 12)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .tint(Color.brand)
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: DS.Radius.hero)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if entries.isEmpty && Calendar.current.isDateInToday(day) {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image.pixel(.food)
                                .foregroundStyle(Color.brand)
                            Text("Nothing logged today. Tap **+** at the top, or **Add food** under a meal.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.ppCard)
                }

                ForEach(Meal.allCases) { meal in
                    let items = entries.filter { $0.meal == meal }
                    let mealKcal = items.reduce(0) { $0 + $1.nutrition.kcal }
                    Section {
                        ForEach(items) { entry in
                            Button { editing = entry } label: { EntryRow(entry: entry) }
                                .tint(.primary)
                                .accessibilityHint("Opens to change the amount or meal")
                                // Tap or swipe right to edit, swipe left to delete (long-press works too).
                                .swipeActions(edge: .leading) {
                                    Button { editing = entry } label: {
                                        Label { Text("Edit") } icon: { Image.pixel(.pencil) }
                                    }
                                    .tint(Color.brand)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete([entry], message: "\(entry.name) deleted")
                                    } label: {
                                        Label { Text("Delete") } icon: { Image.pixel(.trash) }
                                    }
                                }
                                .contextMenu {
                                    Button { editing = entry } label: { Label { Text("Edit amount") } icon: { Image.pixel(.pencil) } }
                                    Button(role: .destructive) {
                                        delete([entry], message: "\(entry.name) deleted")
                                    } label: {
                                        Label { Text("Delete") } icon: { Image.pixel(.trash) }
                                    }
                                }
                        }
                        Button { addingTo = meal } label: {
                            Label { Text("Add food") } icon: { Image.pixel(.plusBox) }
                        }
                        // Two or more foods? Offer to keep them as one tap for next time.
                        if items.count >= 2 {
                            Button { mealToSave = meal } label: {
                                Label { Text("Save as a meal…") } icon: { Image.pixel(.star) }
                            }
                        }
                        // One tap to repeat what you ate in this meal the day before.
                        if items.isEmpty {
                            let previous = entries(for: meal, on: previousDay)
                            if !previous.isEmpty {
                                Button { copyFromPreviousDay(meal) } label: {
                                    Label { Text(copyLabel(meal, previous)) } icon: { Image.pixel(.copy) }
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image.pixel(meal.glyph, size: 16)
                                .foregroundStyle(Color.brand)
                            PPHeader(meal.title)
                            Spacer()
                            if mealKcal > 0 {
                                Text(mealKcal.kcalText)
                                    .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                                    .foregroundStyle(Color.ppText.opacity(0.8))
                            }
                            if !items.isEmpty {
                                Menu {
                                    Button { mealToSave = meal } label: { Label { Text("Save as a meal…") } icon: { Image.pixel(.star) } }
                                    Button(role: .destructive) {
                                        mealToClear = meal
                                    } label: {
                                        Label { Text("Delete all") } icon: { Image.pixel(.trash) }
                                    }
                                } label: {
                                    Image.pixel(.more)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("More for \(meal.title)")
                            }
                        }
                    }
                    .listRowBackground(Color.ppCard)
                }
            }
            .ppScreen()
            .navigationTitle("Calories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Quick log: opens Add food for the meal that fits the time of day.
                    Button {
                        Haptics.tap()
                        addingTo = Meal.forTime()
                    } label: {
                        Image.pixel(.plus)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Log food")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton()
                }
            }
            .confirmationDialog(
                "Delete everything in \(mealToClear?.title.lowercased() ?? "this meal")?",
                isPresented: Binding(get: { mealToClear != nil },
                                     set: { if !$0 { mealToClear = nil } }),
                titleVisibility: .visible,
                presenting: mealToClear) { meal in
                let doomed = entries.filter { $0.meal == meal }
                Button(doomed.count == 1 ? "Delete 1 food" : "Delete \(doomed.count) foods", role: .destructive) {
                    delete(doomed, message: "\(meal.title) cleared")
                    mealToClear = nil
                }
            } message: { _ in
                Text("You can undo this for a few seconds.")
            }
            .sheet(item: $addingTo) { meal in
                AddFoodView(meal: meal, day: day)
            }
            .sheet(item: $editing) { entry in
                EditEntrySheet(entry: entry)
            }
            .alert("Save as a meal", isPresented: Binding(
                get: { mealToSave != nil },
                set: { if !$0 { mealToSave = nil } })) {
                TextField("Name, e.g. Protein shake", text: $savedMealName)
                Button("Save", action: saveMeal)
                Button("Cancel", role: .cancel) { savedMealName = "" }
            } message: {
                Text("Log all of it again in one tap from Add food → Saved meals.")
            }
            .sheet(isPresented: $showGoals) {
                GoalsView()
            }
            .onAppear(perform: seedIfNeeded)
        }
    }

    private func seedIfNeeded() {
        FoodPresets.install(into: context, installedVersion: presetVersion)
        presetVersion = FoodPresets.version
    }
}

// MARK: - Pieces

private struct DaySwitcher: View {
    @Binding var day: Date

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var title: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    var body: some View {
        HStack {
            Button { move(-1) } label: { Image.pixel(.chevronLeft).frame(width: 44, height: 44) }
                .accessibilityLabel("Previous day")
            Spacer()
            Text(title).font(.pixel(DS.TextSize.headline, relativeTo: .headline)).foregroundStyle(Color.ppText)
            Spacer()
            Button { move(1) } label: { Image.pixel(.chevronRight).frame(width: 44, height: 44) }
                .disabled(isToday)
                .opacity(isToday ? 0.3 : 1)
                .accessibilityLabel("Next day")
        }
        .buttonStyle(.borderless)
        .tint(Color.ppText)
    }

    private func move(_ days: Int) {
        Haptics.select()
        day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
    }
}

struct SummaryCard: View {
    let total: Nutrition
    let goalKcal: Double
    let goalProtein: Double
    let goalCarbs: Double
    let goalFat: Double

    var body: some View {
        HStack(spacing: 20) {
            CalorieRing(eaten: total.kcal, goal: goalKcal)
                .frame(width: 120, height: 120)
            VStack(spacing: 12) {
                MacroBar(name: "Protein", value: total.protein, goal: goalProtein, color: .ppProtein)
                MacroBar(name: "Carbs", value: total.carbs, goal: goalCarbs, color: .ppCarbs)
                MacroBar(name: "Fat", value: total.fat, goal: goalFat, color: .ppFat)
            }
        }
    }
}

struct CalorieRing: View {
    let eaten: Double
    let goal: Double

    private var progress: Double { goal > 0 ? eaten / goal : 0 }
    private var left: Double { goal - eaten }
    /// Sweeps round from empty the first time it shows.
    @State private var filled = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.ppLine.opacity(0.12), lineWidth: 12)
            Circle()
                .trim(from: 0, to: filled ? min(progress, 1) : 0)
                .stroke(progress > 1 ? Color.ppCarbs : Color.brand,
                        style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(Int(abs(left).rounded()).spaced)
                    .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                    .foregroundStyle(Color.ppText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: left))
                Text(left >= 0 ? "kcal left" : "kcal over")
                    .font(.caption)
                    .foregroundStyle(left >= 0 ? Color.ppMint : Color.ppCarbs)
            }
            .padding(.horizontal, 14)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: eaten)
        .onAppear {
            guard !filled else { return }
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { filled = true }
        }
    }
}

struct MacroBar: View {
    let name: String
    let value: Double
    let goal: Double
    let color: Color
    @State private var filled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .tracking(-0.5)
                    .foregroundStyle(Color.ppText)
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(goal.rounded())) g")
                    .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                    .foregroundStyle(Color.ppText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ppLine.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * (filled ? min(max(value / max(goal, 1), 0), 1) : 0))
                }
            }
            .frame(height: 6)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
        }
        .onAppear {
            guard !filled else { return }
            withAnimation(.easeOut(duration: 0.8).delay(0.25)) { filled = true }
        }
    }
}

private struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        let n = entry.nutrition
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name).lineLimit(1)
                Spacer()
                Text(n.kcal.kcalText)
                    .font(.pixel(DS.TextSize.body))
                    .foregroundStyle(Color.ppText)
            }
            Text("\(entry.amountText) · P \(n.protein.nice) · C \(n.carbs.nice) · F \(n.fat.nice)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Tap a logged food to change the amount or move it to another meal.
private struct EditEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let entry: FoodEntry

    var body: some View {
        NavigationStack {
            AmountView(title: entry.name,
                       per100: entry.per100,
                       initialGrams: entry.grams,
                       initialPieces: entry.pieces,
                       meal: entry.meal,
                       serving: entry.food?.servingGrams,
                       piece: entry.food?.piece,
                       buttonTitle: "Save") { grams, pieces, meal in
                entry.grams = grams
                entry.pieces = pieces
                entry.pieceName = pieces == nil ? nil : entry.food?.pieceName
                entry.mealRaw = meal.rawValue
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Delete", role: .destructive) {
                        Haptics.warning()
                        let snapshot = FoodEntrySnapshot(entry)
                        let store = context
                        store.delete(entry)
                        dismiss()
                        UndoCenter.shared.show("\(snapshot.name) deleted") {
                            snapshot.restore(into: store)
                        }
                    }
                    .tint(.red)
                }
            }
        }
    }
}


// MARK: - Undo support

/// A plain copy of a logged food, taken just before it's deleted,
/// so Undo can put back an identical entry (same meal, amount and time).
struct FoodEntrySnapshot {
    let name: String
    let date: Date
    let meal: Meal
    let grams: Double
    let per100: Nutrition
    let pieces: Double?
    let pieceName: String?
    let isQuickAdd: Bool
    let food: FoodItem?

    init(_ entry: FoodEntry) {
        name = entry.name
        date = entry.date
        meal = entry.meal
        grams = entry.grams
        per100 = entry.per100
        pieces = entry.pieces
        pieceName = entry.pieceName
        isQuickAdd = entry.isQuickAdd
        food = entry.food
    }

    func restore(into context: ModelContext) {
        let entry = FoodEntry(name: name, per100: per100, grams: grams, pieces: pieces,
                              pieceName: pieceName, meal: meal, date: date,
                              isQuickAdd: isQuickAdd)
        context.insert(entry)
        // Re-link the food only if it hasn't been deleted in the meantime.
        if let food, !food.isDeleted, food.modelContext != nil {
            entry.food = food
        }
    }
}
