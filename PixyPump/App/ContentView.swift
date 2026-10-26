import SwiftUI
import Combine
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .home
    @AppStorage(TabRequest.key) private var requestedTab = -1
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @State private var checkedFirstLaunch = false
    /// Changes after "Delete all data" so every tab starts over (no stale screens).
    @State private var resetID = UUID()
    /// The appearance the tabs were last drawn with (Settings → Appearance).
    @State private var appliedLook = AppTheme.signature

    private func consumeTabRequest(_ raw: Int) {
        guard raw >= 0, let target = AppTab(rawValue: raw) else { return }
        requestedTab = -1
        withAnimation { tab = target }
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tint(Color.brand)
                .restTimerSlot()
                .tabItem { Label { Text("Home") } icon: { Image.pixelTab(.home) } }
                .tag(AppTab.home)
            WorkoutView()
                .tint(Color.brand)
                .restTimerSlot()
                .tabItem { Label { Text("Workout") } icon: { Image.pixelTab(.dumbbell) } }
                .tag(AppTab.workout)
            ProgressTabView()
                .tint(Color.brand)
                .restTimerSlot()
                .tabItem { Label { Text("Progress") } icon: { Image.pixelTab(.chart) } }
                .tag(AppTab.progress)
            FoodView()
                .tint(Color.brand)
                .tabItem { Label { Text("Calories") } icon: { Image.pixelTab(.food) } }
                .tag(AppTab.food)
        }
        .id("\(resetID)-\(appliedLook)")
        .missionToasts()
        .undoToasts()
        .onReceive(NotificationCenter.default.publisher(for: .appearanceMayHaveChanged)) { _ in
            guard AppTheme.signature != appliedLook else { return }
            PixelFont.styleSystemBars()
            appliedLook = AppTheme.signature   // redraw every tab in the new look
        }
        .tint(Color.ppText)          // selected tab: white, like the design
        .hapticOnChange(of: tab)
        // Welcome flow on first launch. People who already have data skip it.
        .fullScreenCover(isPresented: Binding(
            get: { checkedFirstLaunch && !onboarded },
            set: { _ in })) {
            OnboardingView()
        }
        // After the cover, so onboarding can switch tabs too.
        .environment(\.selectTab, { target in withAnimation { tab = target } })
        // A screen asked to open a tab (e.g. onboarding's "Start Day 1" → Workout).
        .onChange(of: requestedTab) { _, raw in consumeTabRequest(raw) }
        .onAppear { consumeTabRequest(requestedTab) }
        .onChange(of: onboarded) { _, isDone in
            guard !isDone else { return }
            // "Delete all data" just ran: rebuild the tabs and show the welcome flow
            // once the Settings sheet has finished closing.
            tab = .home
            resetID = UUID()
            checkedFirstLaunch = false
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                checkedFirstLaunch = true
            }
        }
        .task {
            if !onboarded {
                let sets = (try? context.fetchCount(FetchDescriptor<WorkoutSet>())) ?? 0
                let food = (try? context.fetchCount(FetchDescriptor<FoodEntry>())) ?? 0
                if sets + food > 0 { onboarded = true }
            }
            checkedFirstLaunch = true
            SFX.preload()
            removeOldExercisePhotos()
        }
    }
}

extension ContentView {
    /// Exercise pictures were removed from the app: free the space of photos people had added (once).
    fileprivate func removeOldExercisePhotos() {
        let key = "exercisePhotosRemoved.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in all where exercise.imageData != nil { exercise.imageData = nil }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// Puts the rest timer in its own space *below* the screen's content, so it
/// never covers anything: the page simply ends above the timer while it runs.
private struct RestTimerSlot: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            RestTimerBar()   // takes no space at all when the timer is off
        }
        .background(AppBackground())
    }
}

private extension View {
    func restTimerSlot() -> some View { modifier(RestTimerSlot()) }
}

/// All exercises, including ones outside the routine (Progress → All exercises).
struct ExerciseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var showingAdd = false
    @State private var newName = ""
    @State private var editMode: EditMode = .inactive

    var body: some View {
            List {
                ForEach(exercises) { exercise in
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                    } label: {
                        ExerciseRow(exercise: exercise)
                    }
                }
                // Delete only via the Edit button: removing an exercise removes its history too.
                .onDelete(perform: deleteAction)
                .listRowBackground(Color.ppCard)
            }
            .ppScreen()
            .environment(\.editMode, $editMode)
            .overlay {
                if exercises.isEmpty {
                    ContentUnavailableView {
                        Label { Text("No exercises") } icon: { Image.pixel(.dumbbell, size: 48) }
                    } description: {
                        Text("Tap + to add one.")
                    }
                }
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image.pixel(.plus) }
                        .accessibilityLabel("Add exercise")
                }
            }
            .alert("New exercise", isPresented: $showingAdd) {
                TextField("Name", text: $newName)
                Button("Add", action: addExercise)
                Button("Cancel", role: .cancel) { newName = "" }
            }
    }

    /// Swipe-to-delete is off unless you're in Edit mode.
    private var deleteAction: ((IndexSet) -> Void)? {
        guard editMode.isEditing else { return nil }
        return { offsets in deleteExercises(offsets) }
    }

    private func deleteExercises(_ offsets: IndexSet) {
        for index in offsets { context.delete(exercises[index]) }
    }

    private func addExercise() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty else { return }
        context.insert(Exercise(name: name))
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name).font(.body.weight(.medium))
            Group {
                if let last = exercise.lastSet {
                    HStack(spacing: 4) {
                        Text("\(Units.weight(last.weight)) × \(last.reps)")
                        Text("·")
                        Text(last.date, format: .relative(presentation: .named))
                    }
                } else {
                    Text("Not logged yet")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Exercise.self, WorkoutSet.self, FoodItem.self, FoodEntry.self, SavedMeal.self, SavedMealItem.self], inMemory: true)
}
