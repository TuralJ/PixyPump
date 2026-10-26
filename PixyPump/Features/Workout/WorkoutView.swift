import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]
    @Query(sort: \WorkoutSet.date) private var allSets: [WorkoutSet]

    /// 1-based day you last logged a set on (0 = never trained yet).
    @AppStorage("lastTrainedDay") private var lastDay = 0
    @AppStorage("lastTrainedAt") private var lastTrainedAt = 0.0

    @State private var selectedDay = 1
    /// Workout mode or a preview, pushed from the list.
    @State private var route: WorkoutRoute?
    /// The exercise on screen in workout mode.
    @State private var current = ""
    @State private var didPickDay = false
    @AppStorage(Prefs.unit) private var unitRaw = "kg"
    @State private var editingPlan = false
    @State private var planStartDay: Int?
    @State private var swapping: String?
    @State private var showSummary = false
    @State private var confirmFinish = false
    @State private var confirmCancel = false
    /// Dragging today's exercises into a new order (today only, the plan stays the same).
    @State private var reorderingToday = false
    /// Set by Home's Start button: open the next exercise when this tab appears.
    @AppStorage("workoutOpenNext") private var openNextRequested = false
    private let today = TodayChanges.shared
    private let workout = ActiveWorkout.shared

    /// The day's exercises with today's skips and swaps applied.
    private var dayExercises: [String] { Routine.todayExercises(onDay: selectedDay) }
    private var skippedToday: [String] { today.skipped(in: Routine.exercises(onDay: selectedDay), day: selectedDay) }

    private var doneCount: Int {
        dayExercises.filter { name in
            guard let ex = exercise(named: name) else { return false }
            return ex.workingSetsToday.count >= Routine.targetSets(for: name, onDay: selectedDay)
        }.count
    }

    /// Any working set logged today.
    private var trainedToday: Bool {
        exercises.contains { !$0.workingSetsToday.isEmpty }
    }

    // MARK: Today's workout (start → continue → finish)

    /// The day being trained today, or the one you're looking at if you haven't started.
    private var activeDay: Int { workout.day ?? selectedDay }
    private var activeExercises: [String] { Routine.todayExercises(onDay: activeDay) }

    private var remaining: [String] { WorkoutFlow.remaining(day: activeDay, in: exercises) }
    private var nextUp: String? { remaining.first }

    private var workingSetsToday: Int { WorkoutFlow.setsLoggedToday(exercises) }

    /// Sets can be logged for the day on screen (otherwise it's a preview).
    private var isLiveDay: Bool { WorkoutFlow.canLog(day: selectedDay) }

    var body: some View {
        NavigationStack {
            List {
                if Routine.dayCount == 0 {
                    // Empty state: no plan at all.
                    Section {
                        EmptyStateCard(
                            icon: .dumbbell,
                            title: "No training plan yet",
                            message: "Add your training days and pick the exercises for each one. \(AppInfo.name) then walks you through them in order.",
                            buttonTitle: "Create your plan"
                        ) { openPlan(day: nil) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                } else {
                    if workout.isFinished, let doneDay = workout.day {
                        Section {
                            DoneTodayBanner(doneDay: doneDay, nextDay: upNextDay,
                                            viewingDone: selectedDay == doneDay) { day in
                                Haptics.tap()
                                withAnimation { selectedDay = day }
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    if workout.isInProgress, !isLiveDay, let trainingDay = workout.day {
                        Section {
                            PreviewDayBanner(trainingDay: trainingDay) {
                                Haptics.tap()
                                withAnimation { selectedDay = trainingDay }
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    Section {
                        DaySwitcher(day: $selectedDay,
                                    count: Routine.dayCount,
                                    dueDay: upNextDay,
                                    dueLabel: workout.isFinished ? "TOMORROW" : "TODAY")
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    if let missions = missionsToShow {
                        Section {
                            WorkoutMissionsCard(missions: missions)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
                    }

                    if dayExercises.isEmpty {
                        // Empty state: this day has no exercises.
                        Section {
                            EmptyStateCard(
                                icon: .plusBox,
                                title: "Nothing on \(Routine.dayName(selectedDay)) yet",
                                message: "Pick the exercises for this day and how many sets you aim for.",
                                buttonTitle: "Add exercises"
                            ) { openPlan(day: selectedDay) }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    } else {
                        Section {
                            if reorderingToday {
                                // Drag the handles to change today's order.
                                ForEach(Array(dayExercises.enumerated()), id: \.offset) { index, name in
                                    HStack(spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.pixel(DS.TextSize.body, relativeTo: .body))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32)
                                        Text(name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(Color.ppText)
                                    }
                                    .frame(minHeight: 44)
                                }
                                .onMove(perform: moveToday)
                            } else {
                                ForEach(Array(dayExercises.enumerated()), id: \.offset) { index, name in
                                    if let exercise = exercise(named: name) {
                                        HStack(spacing: 4) {
                                            Button { open(name) } label: {
                                                HStack(spacing: 8) {
                                                    WorkoutRow(number: index + 1, exercise: exercise, day: selectedDay,
                                                               swappedFrom: today.original(of: name, day: selectedDay))
                                                    Spacer(minLength: 0)
                                                }
                                                .foregroundStyle(Color.ppText)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.borderless)

                                            // Visible "···": skip or swap just for today (also on long-press).
                                            // Only on the day you're training; other days are a preview.
                                            if isLiveDay {
                                                Menu { rowActions(for: name) } label: {
                                                    Image.pixel(.more, size: 16)
                                                        .foregroundStyle(.secondary)
                                                        .frame(width: DS.Size.minTap, height: DS.Size.minTap)
                                                        .contentShape(Rectangle())
                                                }
                                                .accessibilityLabel("More for \(name)")
                                            }
                                        }
                                        .contextMenu { if isLiveDay { rowActions(for: name) } }
                                    }
                                }
                            }
                            if reorderingToday, today.hasCustomOrder(day: selectedDay) {
                                Button {
                                    Haptics.tap()
                                    withAnimation { today.resetOrder(day: selectedDay) }
                                } label: {
                                    Label { Text("Back to plan order") } icon: { Image.pixel(.reload, size: 16) }
                                        .frame(minHeight: 44)
                                }
                                .moveDisabled(true)
                            }
                        } header: {
                            HStack {
                                PPHeader("Exercises")
                                Spacer()
                                if dayExercises.count > 1, isLiveDay {
                                    Button {
                                        Haptics.tap()
                                        withAnimation { reorderingToday.toggle() }
                                    } label: {
                                        Text(reorderingToday ? "Done" : "Reorder today")
                                            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                                            .foregroundStyle(Color.brand)
                                            .frame(minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityHint(reorderingToday ? "Stops reordering" : "Change the order of today's exercises. Your plan stays the same.")
                                }
                            }
                        } footer: {
                            Text(reorderingToday
                                 ? "Drag to change today's order. Your plan stays the same, and tomorrow it's back to normal."
                                 : (isLiveDay
                                    ? "\(doneCount) of \(dayExercises.count) done · ··· to skip or swap for today"
                                    : "Preview · tap an exercise to see its plan and history"))
                        }
                        .listRowBackground(Color.ppCard)
                    }

                    if !skippedToday.isEmpty {
                        Section {
                            ForEach(skippedToday, id: \.self) { name in
                                HStack {
                                    Text(name).foregroundStyle(.secondary).strikethrough()
                                    Spacer()
                                    if isLiveDay {
                                        Button("Undo") {
                                            Haptics.tap()
                                            today.undo(name, day: selectedDay)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        } header: {
                            PPHeader("Skipped today")
                        }
                        .listRowBackground(Color.ppCard)
                    }

                }
            }
            .environment(\.editMode, .constant(reorderingToday ? .active : .inactive))
            .ppScreen()
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            .horizontalSwipe(changeDay)
            .navigationDestination(item: $route) { route in
                switch route {
                case .session(let day):
                    WorkoutSessionView(day: day, current: $current) { markTrained(day: day) }
                case .preview(let name, let day):
                    // Finds the exercise, or creates it if it's missing (e.g. right after "Delete my data"),
                    // so this screen is never blank.
                    ExerciseResolver(name: name, known: exercise(named: name)) { exercise in
                        let note = previewNote(day: day)
                        ExerciseDetailView(exercise: exercise, day: day,
                                           previewNote: note.text,
                                           previewActionTitle: note.canAddMore ? "Add more sets" : nil,
                                           onPreviewAction: note.canAddMore ? { addMoreSets(name, day: day) } : nil)
                    }
                }
            }
            .navigationTitle("Workout")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { openPlan(day: Routine.dayCount == 0 ? nil : selectedDay) } label: {
                        Image.pixel(.pencil)
                    }
                    .accessibilityLabel("Edit training plan")
                }
                // Finishing normally is the bottom button; ending early lives in "···".
                if workout.isInProgress, nextUp != nil || workingSetsToday == 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: workingSetsToday == 0 ? .destructive : nil, action: finishTapped) {
                                Label { Text(workingSetsToday == 0 ? "Cancel workout" : "Finish workout early") } icon: {
                                    Image.pixel(workingSetsToday == 0 ? .close : .flag)
                                }
                            }
                        } label: {
                            Image.pixel(.more)
                        }
                        .accessibilityLabel("End workout")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    RestTimerMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton()
                }
            }
            .onAppear {
                ensureRoutineExercises()
                pickDayIfNeeded()
                handleOpenNextRequest()
            }
            .onChange(of: openNextRequested) { _, _ in handleOpenNextRequest() }
            // Reordering is for the day on screen: stop when you switch day or open an exercise.
            .onChange(of: selectedDay) { _, _ in reorderingToday = false }
            .onChange(of: route) { _, _ in reorderingToday = false }
            .confirmationDialog("Cancel this workout?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Cancel workout", role: .destructive) {
                    Haptics.warning()
                    withAnimation { workout.cancel() }
                }
                Button("Keep workout", role: .cancel) {}
            } message: {
                Text("No sets logged yet, so nothing is lost.")
            }
            // Finished: move on to the next day so the screen looks ahead.
            .onChange(of: workout.isFinished) { _, finished in
                if finished { withAnimation { selectedDay = upNextDay } }
            }
            .confirmationDialog(remaining.count == 1 ? "1 exercise left. Finish anyway?" : "\(remaining.count) exercises left. Finish anyway?",
                                isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish workout") { finishNow() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("You'll miss the +\(WorkoutMissions.completeXP) XP finish bonus and today's gym bag. Exercises you haven't started are skipped for today.")
            }
            .onChange(of: Routine.allExerciseNames) { _, _ in ensureRoutineExercises() }
            // All exercises were deleted (Settings → Delete my data): recreate the plan's ones.
            .onChange(of: exercises.count) { _, _ in ensureRoutineExercises() }
            .onChange(of: Routine.dayCount) { _, count in
                // A day was removed: stay on a day that still exists.
                if selectedDay > count { selectedDay = max(count, 1) }
            }
            .sheet(isPresented: $showSummary) { WorkoutSummaryView() }
            .sheet(isPresented: Binding(get: { swapping != nil }, set: { if !$0 { swapping = nil } })) {
                if let name = swapping {
                    SwapPickerView(replacing: name) { replacement, keep in
                        if exercise(named: replacement) == nil { context.insert(Exercise(name: replacement)) }
                        if keep {
                            RoutineStore.shared.replace(name, with: replacement, onDay: selectedDay)
                        } else {
                            today.swap(name, for: replacement, day: selectedDay)
                        }
                    }
                }
            }
            .sheet(isPresented: $editingPlan) {
                RoutineEditorView(startDay: planStartDay)
            }
        }
    }

    /// Skip / swap / keep-swap actions for one exercise (··· menu and long-press).
    @ViewBuilder
    private func rowActions(for name: String) -> some View {
        if let original = today.original(of: name, day: selectedDay) {
            Button { keepSwap(original: original, replacement: name) } label: {
                Label { Text("Keep in my plan") } icon: { Image.pixel(.save) }
            }
            Button { Haptics.tap(); today.undo(name, day: selectedDay) } label: {
                Label { Text("Undo swap") } icon: { Image.pixel(.reload) }
            }
            Button(role: .destructive) {
                Haptics.warning()
                today.skip(name, day: selectedDay)
            } label: {
                Label { Text("Skip today") } icon: { Image.pixel(.close) }
            }
        } else {
            Button { swapping = name } label: {
                Label { Text("Swap for today…") } icon: { Image.pixel(.reload) }
            }
            Button(role: .destructive) {
                Haptics.warning()
                today.skip(name, day: selectedDay)
            } label: {
                Label { Text("Skip today") } icon: { Image.pixel(.close) }
            }
        }
    }

    /// Drag-to-reorder for today. Saved as plan names, so a swapped-in exercise keeps its place.
    private func moveToday(from source: IndexSet, to destination: Int) {
        var names = dayExercises
        names.move(fromOffsets: source, toOffset: destination)
        Haptics.select()
        today.setOrder(names.map { today.original(of: $0, day: selectedDay) ?? $0 }, day: selectedDay)
    }

    /// Swipe left/right on the list: next/previous day.
    private func changeDay(_ step: Int) {
        let day = selectedDay + step
        if day >= 1 && day <= Routine.dayCount {
            withAnimation { selectedDay = day }
        }
    }

    private func exercise(named name: String) -> Exercise? {
        exercises.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Creates any routine exercise that doesn't exist yet.
    private func ensureRoutineExercises() {
        // Ask the database directly, so exercises added a moment ago aren't created twice.
        let existing = Set(((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map { $0.name.lowercased() })
        for name in Routine.allExerciseNames where !existing.contains(name.lowercased()) {
            context.insert(Exercise(name: name))
        }
    }

    /// Today's day while training; once today's workout is finished, the next day in the rotation.
    private var upNextDay: Int {
        if workout.isFinished, Routine.dayCount > 0 {
            return (workout.day ?? lastDay) % Routine.dayCount + 1
        }
        return workout.day ?? TrainingLog.day(on: .now) ?? Routine.suggestion(from: allSets).day
    }

    /// Opens on today's day if you're training, or on the next day once you've finished.
    private func pickDayIfNeeded() {
        guard !didPickDay else { return }
        didPickDay = true
        selectedDay = upNextDay
    }

    /// Tap on an exercise: workout mode on the day you can train, a preview on other days.
    private func open(_ name: String) {
        Haptics.tap()
        if isLiveDay {
            openSession(at: name, day: selectedDay)
        } else {
            route = .preview(name: name, day: selectedDay)
        }
    }

    private func openSession(at name: String, day: Int) {
        current = name
        if route != .session(day: day) { route = .session(day: day) }
    }

    /// Text at the top of a preview, and whether "Add more sets" makes sense (today's finished day).
    private func previewNote(day: Int) -> (text: String, canAddMore: Bool) {
        if workout.isFinished {
            if day == workout.day {
                return ("Today's workout is finished. Forgot a set? You can still add it.", true)
            }
            return ("Preview of Day \(day) · \(Routine.dayName(day)). Today's workout is done.", false)
        }
        if let training = workout.day {
            return ("Preview. You're training Day \(training) · \(Routine.dayName(training)) today, so sets go there.", false)
        }
        return ("Preview of Day \(day) · \(Routine.dayName(day)).", false)
    }

    /// After finishing: back into workout mode on today's day to log a forgotten set.
    private func addMoreSets(_ name: String, day: Int) {
        openSession(at: name, day: day)
    }

    /// Makes today's swap permanent: the plan now has the new exercise (same sets and reps).
    private func keepSwap(original: String, replacement: String) {
        Haptics.success()
        today.undo(replacement, day: selectedDay)
        RoutineStore.shared.replace(original, with: replacement, onDay: selectedDay)
    }

    private func openPlan(day: Int?) {
        Haptics.tap()
        planStartDay = day
        editingPlan = true
    }

    private func markTrained(day: Int) {
        lastDay = day
        lastTrainedAt = Date.now.timeIntervalSince1970
    }

    // MARK: Workout actions

    private func startWorkout() {
        Haptics.press()
        workout.start(day: selectedDay)
        markTrained(day: selectedDay)
        if let first = remaining.first { openSession(at: first, day: selectedDay) }
    }

    private func continueWorkout() {
        Haptics.press()
        if selectedDay != activeDay { selectedDay = activeDay }
        if let next = nextUp { openSession(at: next, day: activeDay) }
    }

    private func finishTapped() {
        if workingSetsToday == 0 {
            // Started by mistake, nothing logged: ask before cancelling.
            Haptics.tap()
            confirmCancel = true
        } else if !remaining.isEmpty {
            confirmFinish = true
        } else {
            finishNow()
        }
    }

    private func finishNow() {
        Haptics.success()
        WorkoutFlow.finish(day: activeDay, in: exercises)
        // Let the confirmation close before the summary slides up.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            showSummary = true
        }
    }

    /// Home's Start button: start (if needed) and jump straight into the next exercise.
    private func handleOpenNextRequest() {
        guard openNextRequested else { return }
        openNextRequested = false
        if let day = workout.day { selectedDay = day }
        if let next = nextUp { openSession(at: next, day: activeDay) }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var actionBar: some View {
        if Routine.dayCount > 0, route == nil {
            switch workout.phase {
            case .notStarted:
                if !dayExercises.isEmpty {
                    MiniBar(action: startWorkout) {
                        Text("Day \(selectedDay) · \(Routine.dayName(selectedDay))")
                            .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                            .foregroundStyle(Color.ppText)
                        Text(plannedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } trailing: {
                        PillLabel(title: "Start", style: .primary)
                    }
                }

            case .inProgress(let since):
                MiniBar(action: { if nextUp != nil { continueWorkout() } else { finishTapped() } }) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.ppDone).frame(width: 7, height: 7)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Self.clock(context.date.timeIntervalSince(since)))
                                .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                                .foregroundStyle(Color.ppText)
                                .monospacedDigit()
                        }
                        Text("\(activeExercises.count - remaining.count)/\(activeExercises.count)")
                            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                    Text(progressLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } trailing: {
                    if nextUp != nil {
                        RoundArrow()
                    } else {
                        PillLabel(title: "Finish workout", style: .primary)
                    }
                }

            case .finished(let start, let end):
                // Quiet status. Training twice today is possible but low-key.
                let other = selectedDay != workout.day && !dayExercises.isEmpty
                let startOther: (() -> Void)? = other ? { startWorkout() } : nil
                MiniBar(action: startOther) {
                    HStack(spacing: 8) {
                        Image.pixel(.check, size: 16)
                            .foregroundStyle(Color.ppDone)
                        Text("Workout done")
                            .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                            .foregroundStyle(Color.ppText)
                    }
                    Text(other
                         ? "Want to train \(Routine.dayName(selectedDay)) too?"
                         : "\(max(1, Int((end.timeIntervalSince(start) / 60).rounded()))) min · \(workingSetsToday) sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } trailing: {
                    if other { PillLabel(title: "Start", style: .outlined) }
                }
            }
        }
    }

    /// Missions for the day on screen: before you start (a preview) and while training.
    private var missionsToShow: [WorkoutMission]? {
        guard !dayExercises.isEmpty else { return nil }
        switch workout.phase {
        case .notStarted:
            return WorkoutMissions.list(planDay: selectedDay, allSets: allSets, finishedEarly: false, minutes: nil)
        case .inProgress:
            guard selectedDay == activeDay else { return nil }
            return WorkoutMissions.list(planDay: activeDay, allSets: allSets, finishedEarly: false, minutes: nil)
        case .finished:
            return nil
        }
    }

    /// Sets still to log for the "finish every set" bonus.
    private var setsToBonus: Int {
        activeExercises.reduce(0) { total, name in
            let target = Routine.targetSets(for: name, onDay: activeDay)
            let done = exercise(named: name)?.workingSetsToday.count ?? 0
            return total + max(target - done, 0)
        }
    }

    /// "Next: Squat · 6 sets to +100 XP" for the bar while training.
    private var progressLine: String {
        let next: String = nextUp.map { "Next: \($0)" } ?? "All exercises done"
        let toBonus = setsToBonus
        return toBonus > 0 ? next + " · \(toBonus) sets to +\(WorkoutMissions.completeXP) XP" : next
    }

    private var plannedText: String {
        let sets = dayExercises.reduce(0) { $0 + Routine.targetSets(for: $1, onDay: selectedDay) }
        let count = dayExercises.count
        return "\(count) \(count == 1 ? "exercise" : "exercises") · \(sets) sets"
    }

    /// 23:14 or 1:02:09.
    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct WorkoutRow: View {
    let number: Int
    let exercise: Exercise
    let day: Int
    var swappedFrom: String? = nil

    var body: some View {
        let today = exercise.workingSetsToday
        let target = Routine.targetSets(for: exercise.name, onDay: day)
        let done = today.count >= target
        HStack(spacing: 12) {
            Group {
                if done {
                    Image.pixel(.check, size: 16)
                        .foregroundStyle(Color.ppBackground)
                        .frame(width: 26, height: 26)
                        .background(Color.ppText, in: Circle())
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                } else {
                    Text("\(number)")
                        .font(.pixel(DS.TextSize.body))
                        .foregroundStyle(today.isEmpty ? Color.ppText : Color.ppBackground)
                        .frame(width: 32, height: 32)
                        .background(today.isEmpty ? Color.ppLine.opacity(0.16) : Color.brand,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.xs))
                }
            }
            .frame(width: 32)
            .animation(.spring(response: 0.35, dampingFraction: 0.55), value: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.body.weight(.medium))
                if let swappedFrom {
                    Text("Instead of \(swappedFrom) today")
                        .font(.subheadline)
                        .foregroundStyle(Color.ppCarbs)
                } else {
                    // Same pattern as Home: bars · 2/3 · last weight.
                    ExerciseStatusLine(done: today.count, target: target,
                                       last: today.isEmpty ? exercise.lastSet : nil)
                }
            }
        }
    }
}

/// Friendly placeholder card: icon, short explanation and one clear action.
struct EmptyStateCard: View {
    let icon: PixelGlyph
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image.pixel(icon, size: 48)
                .foregroundStyle(Color.brand)
                .breathe(true, amount: 0.08)
                .padding(.top, 6)
            Text(title)
                .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                .foregroundStyle(Color.ppText)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle, let action {
                Button(action: action) { Text(buttonTitle) }
                    .buttonStyle(.primary)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: DS.Radius.hero)
    }
}

/// Picks the training day without tabs, so it works for 1 day or 7:
/// ‹ › arrows (or swipe), a tappable day name that opens the full list,
/// and small dots showing where you are in the week.
private struct DaySwitcher: View {
    @Binding var day: Int
    /// Which way the day changed, so the name slides in from that side.
    @State private var forward = true
    let count: Int
    /// The day that's up next / being trained today.
    let dueDay: Int
    /// "TODAY" while training, "UP NEXT" once today's workout is done.
    var dueLabel = "TODAY"

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                arrow(-1)

                VStack(spacing: 6) {
                    Text(day == dueDay ? "DAY \(day) OF \(count) · \(dueLabel)" : "DAY \(day) OF \(count)")
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                        .foregroundStyle(Color.secondary)

                    Menu {
                        Picker("Day", selection: $day) {
                            ForEach(1...count, id: \.self) { d in
                                Text(d == dueDay
                                     ? "Day \(d) · \(Routine.dayName(d)) · \(dueLabel.lowercased())"
                                     : "Day \(d) · \(Routine.dayName(d))")
                                    .tag(d)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(Routine.dayName(day))
                                .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                                .foregroundStyle(Color.ppText)
                                .id(day)
                                .transition(.push(from: forward ? .trailing : .leading))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Image.pixel(.chevronDown, size: 16)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Choose day, currently \(Routine.dayName(day))")
                }
                .frame(maxWidth: .infinity)

                arrow(1)
            }

            // Where you are in the plan.
            HStack(spacing: 6) {
                ForEach(1...count, id: \.self) { d in
                    Capsule()
                        .fill(d == day ? Color.ppText : (d == dueDay ? Color.brand.opacity(0.6) : Color.ppLine.opacity(0.2)))
                        .frame(width: d == day ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy, value: day)
            // The dots only use colour and width, so say it in words for VoiceOver.
            .accessibilityElement()
            .accessibilityLabel(dotsLabel)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .hapticOnChange(of: day)
        .animation(.snappy(duration: 0.3), value: day)
        .onChange(of: day) { old, new in forward = new > old }
    }

    /// "Day 2 of 3, today" / "Day 1 of 3. Day 2 is today".
    private var dotsLabel: String {
        let base = "Day \(day) of \(count)"
        let due = dueLabel.lowercased()
        return day == dueDay ? "\(base), \(due)" : "\(base). Day \(dueDay) is \(due)"
    }

    private func arrow(_ step: Int) -> some View {
        let target = day + step
        let enabled = target >= 1 && target <= count
        return Button {
            forward = step > 0
            withAnimation(.snappy) { day = target }
        } label: {
            Image.pixel(step < 0 ? .chevronLeft : .chevronRight)
                .foregroundStyle(Color.ppText)
                .frame(width: 44, height: 44)
                .background(Color.ppLine.opacity(0.08), in: Circle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(step < 0 ? "Previous day" : "Next day")
    }
}

/// Pick one exercise to do instead of another, just for today.
struct SwapPickerView: View {
    let replacing: String
    /// The chosen exercise, and whether to change the plan for good.
    let onPick: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var myExercises: [Exercise]
    @State private var search = ""
    @State private var keepInPlan = false

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var groups: [(title: String, names: [String])] {
        let library = ExerciseLibrary.allNames
        let mine = myExercises.map(\.name).filter { !library.contains($0.lowercased()) }
        var all: [(title: String, names: [String])] = []
        if !mine.isEmpty { all.append((title: "My exercises", names: mine)) }
        all += ExerciseLibrary.groups
        let filtered = all.map { group in
            (title: group.title,
             names: group.names.filter { $0.caseInsensitiveCompare(replacing) != .orderedSame
                                         && (query.isEmpty || $0.localizedCaseInsensitiveContains(query)) })
        }
        return filtered.filter { !$0.names.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $keepInPlan) {
                        Label { Text("Change my plan too") } icon: { Image.pixel(.save) }
                    }
                    .hapticOnChange(of: keepInPlan)
                } footer: {
                    Text(keepInPlan
                         ? "The new exercise replaces \(replacing) in your plan from now on, with the same sets and reps."
                         : "Just for today. Tomorrow your plan is back to normal.")
                }
                .listRowBackground(Color.ppCard)

                if !query.isEmpty {
                    Section {
                        Button { pick(query) } label: {
                            Label { Text("Use “\(query)”") } icon: { Image.pixel(.plusBox) }
                        }
                    }
                    .listRowBackground(Color.ppCard)
                }
                ForEach(groups, id: \.title) { group in
                    Section {
                        ForEach(group.names, id: \.self) { name in
                            Button { pick(name) } label: {
                                Text(name).foregroundStyle(Color.ppText)
                            }
                        }
                    } header: {
                        PPHeader(group.title)
                    }
                    .listRowBackground(Color.ppCard)
                }
            }
            .ppScreen()
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search exercises")
            .navigationTitle("Instead of \(replacing)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func pick(_ name: String) {
        Haptics.success()
        onPick(name, keepInPlan)
        dismiss()
    }
}

/// Slim "now playing"-style bar above the tabs: two short lines and one small action.
/// The whole bar is tappable.
private struct MiniBar<Info: View, Trailing: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var info: Info
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Button {
            Haptics.press()
            action?()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) { info }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(minHeight: 64)
            .glassCard(cornerRadius: DS.Radius.hero)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.hero))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(alignment: .bottom) {
            // Soft fade so the list doesn't show through behind the bar.
            LinearGradient(colors: [Color.ppBackground.opacity(0), Color.ppBackground],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Short capsule label used inside the mini bar ("Start", "Finish").
private struct PillLabel: View {
    enum Style { case primary, outlined }
    let title: String
    let style: Style

    var body: some View {
        Text(title)
            .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
            .foregroundStyle(style == .primary ? Color.ppOnAccent : Color.ppText)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(style == .primary ? Color.ppText : Color.ppLine.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.ppLine.opacity(style == .primary ? 0 : 0.15), lineWidth: 1))
    }
}

/// Round white "›" button: open the next exercise.
private struct RoundArrow: View {
    var body: some View {
        Image.pixel(.chevronRight)
            .foregroundStyle(Color.ppOnAccent)
            .frame(width: 48, height: 48)
            .background(Color.ppText, in: Circle())
            .accessibilityLabel("Continue")
    }
}

/// "▬▬▬ 2/3 · last 40 kg × 8" — the same compact status on Home and Workout.
struct ExerciseStatusLine: View {
    let done: Int
    let target: Int
    var last: WorkoutSet? = nil

    var body: some View {
        HStack(spacing: 6) {
            SetBars(done: done, target: target)
            Text("\(done)/\(target)")
                .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                .foregroundStyle(done >= target ? Color.ppDone : Color.ppText.opacity(0.7))
                .contentTransition(.numericText(value: Double(done)))
                .animation(.snappy, value: done)
            if let last {
                Text("· last \(Units.weight(last.weight)) × \(last.reps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Workout tab, once today's done: which day you finished, and that the next one is tomorrow.
/// The button flips between viewing today's finished day and tomorrow's.
private struct DoneTodayBanner: View {
    let doneDay: Int
    let nextDay: Int
    let viewingDone: Bool
    let show: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Today: done.
            HStack(spacing: 12) {
                Image.pixel(.check, size: 14)
                    .foregroundStyle(Color.ppBackground)
                    .frame(width: 30, height: 30)
                    .background(Color.ppDone, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("DONE TODAY")
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                        .foregroundStyle(Color.ppDone)
                    Text("Day \(doneDay) · \(Routine.dayName(doneDay))")
                        .font(.pixel(DS.TextSize.callout, relativeTo: .headline))
                        .foregroundStyle(Color.ppText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(Color.ppLine.opacity(0.08))
                .frame(height: 1)

            // Tomorrow: what's next, and a switch between the two days.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOMORROW")
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                    Text("Day \(nextDay) · \(Routine.dayName(nextDay))")
                        .font(.subheadline)
                        .foregroundStyle(Color.ppText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                if doneDay != nextDay {
                    Button { show(viewingDone ? nextDay : doneDay) } label: {
                        HStack(spacing: 4) {
                            Text(viewingDone ? "See next" : "See today")
                                .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                            Image.pixel(viewingDone ? .chevronRight : .check, size: 12)
                        }
                        .foregroundStyle(Color.ppText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Color.ppLine.opacity(0.1), in: Capsule())
                        .fixedSize()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.ppDone.opacity(0.06))
        )
        .glassCard(cornerRadius: DS.Radius.card)
        // Room around the card so the list row never clips its edge.
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Shown above the day switcher while you train one day and look at another.
private struct PreviewDayBanner: View {
    let trainingDay: Int
    let back: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Image.pixel(.eye, size: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("PREVIEW")
                    .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                Text("You're training Day \(trainingDay) · \(Routine.dayName(trainingDay))")
                    .font(.subheadline)
                    .foregroundStyle(Color.ppText)
                    .lineLimit(2)
            }
            Spacer(minLength: DS.Space.s)
            Button(action: back) {
                Text("Back to today")
                    .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                    .foregroundStyle(Color.ppOnAccent)
                    .padding(.horizontal, DS.Space.m)
                    .frame(minHeight: DS.Size.minTap)
                    .background(Color.ppText, in: Capsule())
                    .fixedSize()
            }
            .buttonStyle(.borderless)
        }
        .padding(DS.Space.l)
        .glassCard(cornerRadius: DS.Radius.card)
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Back to today", back)
    }
}

/// Shows an exercise screen for `name`, creating the exercise first if it doesn't exist yet.
struct ExerciseResolver<Content: View>: View {
    let name: String
    let known: Exercise?
    @ViewBuilder let content: (Exercise) -> Content

    @Environment(\.modelContext) private var context
    @State private var resolved: Exercise?

    var body: some View {
        if let exercise = known ?? resolved {
            content(exercise)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppBackground())
                .task { resolve() }
        }
    }

    private func resolve() {
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        if let found = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            resolved = found
        } else {
            let created = Exercise(name: name)
            context.insert(created)
            try? context.save()
            resolved = created
        }
    }
}
