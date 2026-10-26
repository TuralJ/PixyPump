import SwiftUI
import SwiftData

// MARK: - Training plan (list of days)

/// Edit your training plan: add, rename, reorder and remove days,
/// and choose the exercises (and target sets) for each day.
struct RoutineEditorView: View {
    /// Open straight into this 1-based day (e.g. from the Workout tab).
    var startDay: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @Bindable private var store = RoutineStore.shared
    @State private var path: [UUID] = []
    @State private var confirmReset = false
    @State private var pendingTemplate: RoutineTemplate?
    @State private var didOpenStartDay = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    if store.days.isEmpty {
                        Text("No days yet. Add your first training day below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(store.days.enumerated()), id: \.element.id) { index, day in
                        NavigationLink(value: day.id) {
                            DaySummaryRow(number: index + 1, day: day)
                        }
                    }
                    .onMove { from, to in
                        Haptics.select()
                        store.days.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        Haptics.warning()
                        store.days.remove(atOffsets: offsets)
                    }
                } header: {
                    PPHeader("Your days")
                } footer: {
                    Text("Days repeat in this order. Drag to reorder, swipe left to remove.")
                }
                .listRowBackground(Color.ppCard)

                Section {
                    Button {
                        addDay()
                    } label: {
                        Label { Text("Add a day") } icon: { Image.pixel(.plusBox) }
                    }
                    .disabled(store.days.count >= RoutineStore.maxDays)
                } footer: {
                    if store.days.count >= RoutineStore.maxDays {
                        Text("That's the maximum of \(RoutineStore.maxDays) days.")
                    }
                }
                .listRowBackground(Color.ppCard)

                Section {
                    Menu {
                        ForEach(RoutineTemplate.all) { template in
                            Button("\(template.name) · \(template.dayCount) days") {
                                pendingTemplate = template
                                confirmReset = true
                            }
                        }
                    } label: {
                        Label { Text("Replace with a ready-made plan…") } icon: { Image.pixel(.reload) }
                    }
                } footer: {
                    Text("Your logged sets are never touched when you change the plan.")
                }
                .listRowBackground(Color.ppCard)
            }
            .ppScreen()
            .navigationTitle("Training plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                DayEditorView(dayID: id)
            }
            .confirmationDialog("Replace your plan with \(pendingTemplate?.name ?? "this plan")?",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Replace plan", role: .destructive) {
                    Haptics.warning()
                    store.apply(pendingTemplate)
                }
            } message: {
                Text("Your current days are replaced. Logged sets are kept.")
            }
            .onAppear {
                guard !didOpenStartDay else { return }
                didOpenStartDay = true
                if let startDay, startDay >= 1, startDay <= store.days.count {
                    path = [store.days[startDay - 1].id]
                }
            }
        }
    }

    private func addDay() {
        Haptics.press()
        let day = RoutineDay(name: "Day \(store.days.count + 1)", items: [])
        store.days.append(day)
        path.append(day.id)
    }
}

private struct DaySummaryRow: View {
    let number: Int
    let day: RoutineDay

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.pixel(DS.TextSize.body))
                .foregroundStyle(Color.ppText)
                .frame(width: 32, height: 32)
                .background(Color.ppLine.opacity(0.16), in: RoundedRectangle(cornerRadius: DS.Radius.xs))
            VStack(alignment: .leading, spacing: 2) {
                Text(day.name.isEmpty ? "Day \(number)" : day.name)
                    .font(.callout.weight(.medium))
                Text(day.items.isEmpty
                     ? "No exercises yet"
                     : "\(day.items.count) exercises · \(day.items.reduce(0) { $0 + $1.sets }) sets")
                    .font(.footnote)
                    .foregroundStyle(day.items.isEmpty ? Color.ppCarbs : .secondary)
            }
        }
    }
}

// MARK: - One day

/// Rename a day, pick its exercises, set target sets and the order.
struct DayEditorView: View {
    let dayID: UUID

    @Bindable private var store = RoutineStore.shared
    @State private var picking = false

    private var index: Int? { store.days.firstIndex { $0.id == dayID } }

    var body: some View {
        if let index {
            List {
                Section {
                    TextField("Name, e.g. Push or Upper A", text: $store.days[index].name)
                        .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                        .foregroundStyle(Color.ppText)
                } header: {
                    PPHeader("Day \(index + 1) name")
                }
                .listRowBackground(Color.ppCard)

                Section {
                    ForEach($store.days[index].items) { $item in
                        NavigationLink {
                            ItemEditorView(item: $item)
                        } label: {
                            HStack {
                                Text(item.name)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(item.sets) × \(item.repsText)")
                                    .font(.pixel(DS.TextSize.subhead))
                                    .foregroundStyle(Color.ppText)
                            }
                        }
                    }
                    .onMove { from, to in
                        Haptics.select()
                        store.days[index].items.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        Haptics.warning()
                        store.days[index].items.remove(atOffsets: offsets)
                    }

                    Button {
                        picking = true
                    } label: {
                        Label { Text("Add exercises") } icon: { Image.pixel(.plusBox) }
                    }
                } header: {
                    PPHeader("Exercises")
                } footer: {
                    Text(store.days[index].items.isEmpty
                         ? "Pick exercises from the list, or create your own."
                         : "Tap an exercise to set its sets and rep range. Long-press and drag to reorder, swipe left to remove.")
                }
                .listRowBackground(Color.ppCard)
            }
            .ppScreen()
            .navigationTitle(store.days[index].name.isEmpty ? "Day \(index + 1)" : store.days[index].name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $picking) {
                ExercisePickerView(alreadyAdded: Set(store.days[index].items.map { $0.name.lowercased() })) { names in
                    store.days[index].items += names.map { RoutineItem(name: $0) }
                }
            }
        } else {
            ContentUnavailableView("This day was removed", systemImage: "calendar")
                .background(AppBackground())
        }
    }
}

// MARK: - Choosing exercises

/// Ready-made exercises, grouped by body part.
enum ExerciseLibrary {
    static let groups: [(title: String, names: [String])] = [
        ("Chest", ["Bench Press", "Incline Bench Press", "Incline Dumbbell Press", "Dumbbell Bench Press",
                   "Machine Press", "Cable Fly", "Weighted Dip", "Push-up", "Pike Push-up"]),
        ("Back", ["Pull-up", "Chin-up", "Lat Pulldown", "Pendlay Row", "Barbell Row", "Cable Row",
                  "Chest-Supported Row", "One-Arm Dumbbell Row", "Inverted Row", "Deadlift", "Face Pull"]),
        ("Legs", ["Squat", "Front Squat", "Goblet Squat", "Bodyweight Squat", "Leg Press", "Romanian Deadlift",
                  "Dumbbell Romanian Deadlift", "Split Squat", "Lunge", "Leg Extension", "Lying Hamstring Curl",
                  "Seated Hamstring Curl", "Hip Thrust", "Glute Bridge", "Calf Raise"]),
        ("Shoulders", ["Standing Press", "Seated Dumbbell Press", "Arnold Press", "Lateral Raise",
                       "Rear Delt Fly", "Upright Row"]),
        ("Arms", ["Curl (Barbell/Dumbbell)", "Incline Dumbbell Curl", "Hammer Curl", "Preacher Curl",
                  "Overhead Triceps", "Triceps", "Triceps Pushdown", "Dumbbell Skull Crusher",
                  "Close-Grip Bench Press"]),
        ("Core", ["Plank", "Hanging Leg Raise", "Cable Crunch", "Ab Wheel"]),
    ]

    static var allNames: Set<String> {
        Set(groups.flatMap { $0.names.map { $0.lowercased() } })
    }
}

/// Multi-select list of exercises (yours + the library), with search and "create new".
struct ExercisePickerView: View {
    /// Lower-cased names already on this day.
    let alreadyAdded: Set<String>
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var myExercises: [Exercise]

    @State private var search = ""
    @State private var picked: [String] = []

    private struct ExerciseGroup: Identifiable {
        let title: String
        let names: [String]
        var id: String { title }
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var groups: [ExerciseGroup] {
        let library = ExerciseLibrary.allNames
        let mine = myExercises.map(\.name).filter { !library.contains($0.lowercased()) }
        var all: [ExerciseGroup] = []
        if !mine.isEmpty { all.append(ExerciseGroup(title: "My exercises", names: mine)) }
        all += ExerciseLibrary.groups.map { ExerciseGroup(title: $0.title, names: $0.names) }
        guard !query.isEmpty else { return all }
        return all.compactMap { group in
            let hits = group.names.filter { $0.localizedCaseInsensitiveContains(query) }
            return hits.isEmpty ? nil : ExerciseGroup(title: group.title, names: hits)
        }
    }

    /// True if the typed name already exists somewhere in the list.
    private var queryExists: Bool {
        let q = query.lowercased()
        return ExerciseLibrary.allNames.contains(q)
            || myExercises.contains { $0.name.lowercased() == q }
            || picked.contains { $0.lowercased() == q }
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty && !queryExists {
                    Section {
                        Button {
                            Haptics.tap()
                            picked.append(query)
                            search = ""
                        } label: {
                            Label { Text("Create “\(query)”") } icon: { Image.pixel(.plusBox) }
                        }
                    }
                    .listRowBackground(Color.ppCard)
                }

                if !picked.isEmpty {
                    Section {
                        ForEach(picked, id: \.self) { name in
                            row(name)
                        }
                    } header: {
                        PPHeader("Selected (\(picked.count))")
                    }
                    .listRowBackground(Color.ppCard)
                }

                ForEach(groups) { group in
                    Section {
                        ForEach(group.names, id: \.self) { name in
                            row(name)
                        }
                    } header: {
                        PPHeader(group.title)
                    }
                    .listRowBackground(Color.ppCard)
                }
            }
            .ppScreen()
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search or type a new exercise")
            .navigationTitle("Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Add" : "Add (\(picked.count))") { addPicked() }
                        .disabled(picked.isEmpty)
                }
            }
        }
    }

    private func row(_ name: String) -> some View {
        let added = alreadyAdded.contains(name.lowercased())
        let isPicked = picked.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        return Button {
            Haptics.select()
            if isPicked {
                picked.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
            } else {
                picked.append(name)
            }
        } label: {
            HStack {
                Text(name)
                    .foregroundStyle(added ? Color.secondary : Color.ppText)
                Spacer()
                if added {
                    Text("On this day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isPicked {
                    Image.pixel(.check, size: 16)
                        .foregroundStyle(Color.brand)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    private func addPicked() {
        // Make sure each picked exercise exists, so it gets its own history.
        for name in picked where !myExercises.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            context.insert(Exercise(name: name))
        }
        Haptics.success()
        onAdd(picked)
        dismiss()
    }
}

/// Target sets and rep range for one exercise in the plan.
private struct ItemEditorView: View {
    @Binding var item: RoutineItem

    var body: some View {
        List {
            Section {
                Stepper(value: $item.sets, in: 1...10) {
                    row("Sets", "\(item.sets)")
                }
                .hapticOnChange(of: item.sets)
                Stepper(value: Binding(get: { item.repsLow },
                                       set: { item.repsLow = $0; if item.repsHigh < $0 { item.repsHigh = $0 } }),
                        in: 1...50) {
                    row("Reps from", "\(item.repsLow)")
                }
                .hapticOnChange(of: item.repsLow)
                Stepper(value: Binding(get: { item.repsHigh },
                                       set: { item.repsHigh = max($0, item.repsLow) }),
                        in: 1...50) {
                    row("Reps up to", "\(item.repsHigh)")
                }
                .hapticOnChange(of: item.repsHigh)
            } header: {
                PPHeader("\(item.sets) × \(item.repsText)")
            } footer: {
                Text("Hit \(item.repsHigh) reps on every set and \(AppInfo.name) suggests adding weight.")
            }
            .listRowBackground(Color.ppCard)
        }
        .ppScreen()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                .foregroundStyle(Color.ppText)
                .padding(.trailing, 8)
        }
    }
}
