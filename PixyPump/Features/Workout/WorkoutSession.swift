import SwiftUI
import SwiftData

// Workout mode: one screen for the whole workout.
// A strip at the top shows where you are (day, time, one dot per exercise),
// the exercise fills the middle, and one button at the bottom always does the next thing
// (log the set → go to the next exercise → finish the workout). See docs/UX_FLOWS.md.

// MARK: - Rules shared by the Workout list and workout mode

@MainActor
enum WorkoutFlow {
    static func exercise(_ name: String, in all: [Exercise]) -> Exercise? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Enough working sets today for this exercise (counts an early "Finish exercise").
    static func isDone(_ name: String, day: Int, in all: [Exercise]) -> Bool {
        (exercise(name, in: all)?.workingSetsToday.count ?? 0) >= Routine.targetSets(for: name, onDay: day)
    }

    /// Today's exercises for `day` that still need sets, in today's order.
    static func remaining(day: Int, in all: [Exercise]) -> [String] {
        Routine.todayExercises(onDay: day).filter { !isDone($0, day: day, in: all) }
    }

    /// The next exercise still to do after `name`, wrapping round to ones skipped past at the start.
    /// Nil only when every other exercise is done, so starting from the bottom of the list
    /// never offers "Finish workout" too early.
    static func nextUnfinished(after name: String, day: Int, in all: [Exercise]) -> String? {
        let list = Routine.todayExercises(onDay: day)
        guard let i = list.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            return list.first { !isDone($0, day: day, in: all) }
        }
        let order = Array(list[(i + 1)...]) + Array(list[..<i])
        return order.first { !isDone($0, day: day, in: all) }
    }

    static func setsLoggedToday(_ all: [Exercise]) -> Int {
        all.reduce(0) { $0 + $1.workingSetsToday.count }
    }

    /// Can sets be logged for `day` right now?
    /// Before starting: any day (the first set starts it). While training: only today's day.
    /// After finishing: no, days are shown as a preview.
    static func canLog(day: Int) -> Bool {
        let workout = ActiveWorkout.shared
        switch workout.phase {
        case .notStarted: return true
        case .inProgress: return workout.day == nil || workout.day == day
        case .finished: return false
        }
    }

    /// Ends today's workout. Untouched exercises count as skipped; half-done ones stay as they are.
    static func finish(day: Int, in all: [Exercise]) {
        let left = remaining(day: day, in: all)
        for name in left where (exercise(name, in: all)?.workingSetsToday.isEmpty ?? true) {
            TodayChanges.shared.skip(name, day: day)
        }
        ActiveWorkout.shared.finish(early: !left.isEmpty)
    }
}

/// Where the Workout tab can go from its list.
nonisolated enum WorkoutRoute: Hashable {
    /// Workout mode for a day (the open exercise is held by the Workout tab).
    case session(day: Int)
    /// Look at an exercise without logging (another day, or after finishing).
    case preview(name: String, day: Int)
}

// MARK: - Workout mode

struct WorkoutSessionView: View {
    let day: Int
    /// The exercise on screen. Owned by the Workout tab so Home's "Continue" can change it.
    @Binding var current: String
    var onSetAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var exercises: [Exercise]

    /// Direction of the last move, for the slide.
    @State private var forward = true
    @State private var swapping = false
    @State private var confirmFinish = false
    @State private var confirmCancel = false
    @State private var showSummary = false
    /// The three tips, shown once (the first time workout mode opens).
    @AppStorage(WorkoutModeTips.seenKey) private var seenTips = false

    private let workout = ActiveWorkout.shared
    private let today = TodayChanges.shared

    private var names: [String] { Routine.todayExercises(onDay: day) }
    private var index: Int? { names.firstIndex { same($0, current) } }
    private var next: String? { WorkoutFlow.nextUnfinished(after: current, day: day, in: exercises) }
    private var remaining: [String] { WorkoutFlow.remaining(day: day, in: exercises) }
    private var setsToday: Int { WorkoutFlow.setsLoggedToday(exercises) }

    var body: some View {
        ZStack {
            ExerciseResolver(name: current, known: WorkoutFlow.exercise(current, in: exercises)) { exercise in
                detail(for: exercise)
            }
            .id(current.lowercased())
            .transition(slide)
        }
        // Swipes on the exercise only, so scrolling the dots in the strip doesn't change exercise.
        .horizontalSwipe(step)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                strip
                if !seenTips {
                    WorkoutModeTips {
                        Haptics.tap()
                        withAnimation(DS.Motion.spring) { seenTips = true }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { Haptics.tap(); dismiss() } label: {
                    HStack(spacing: DS.Space.xs) {
                        Image.pixel(.chevronLeft, size: 16)
                        Text("All exercises")
                            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                    }
                    .frame(minHeight: DS.Size.minTap)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("All exercises")
                .accessibilityHint("Shows today's whole list")
            }
        }
        .sheet(isPresented: $swapping) {
            SwapPickerView(replacing: current) { replacement, keep in
                swap(to: replacement, keep: keep)
            }
        }
        .sheet(isPresented: $showSummary, onDismiss: { dismiss() }) {
            WorkoutSummaryView()
        }
        .confirmationDialog(remaining.count == 1 ? "1 exercise left. Finish anyway?" : "\(remaining.count) exercises left. Finish anyway?",
                            isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish workout") { finishEarly() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("You'll miss the +\(WorkoutMissions.completeXP) XP finish bonus and today's gym bag. Exercises you haven't started are skipped for today.")
        }
        .confirmationDialog("Cancel this workout?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel workout", role: .destructive) {
                Haptics.warning()
                workout.cancel()
                dismiss()
            }
            Button("Keep workout", role: .cancel) {}
        } message: {
            Text("No sets logged yet, so nothing is lost.")
        }
    }

    private func detail(for exercise: Exercise) -> some View {
        let upNext = next
        let onNext: (() -> Void)? = upNext.map { name in { go(to: name) } }
        return ExerciseDetailView(exercise: exercise, day: day, onSetAdded: onSetAdded,
                                  nextName: upNext, onNext: onNext, onSkipped: skipToday)
    }

    private var slide: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                           removal: .move(edge: forward ? .leading : .trailing))
    }

    // MARK: Strip

    private var strip: some View {
        WorkoutStrip(day: day,
                     names: names,
                     current: current,
                     startedAt: workout.isInProgress && workout.day == day ? startDate : nil,
                     idleLabel: workout.isFinished ? "WORKOUT DONE" : "NOT STARTED",
                     isDone: { WorkoutFlow.isDone($0, day: day, in: exercises) },
                     onSelect: { go(to: $0) }) {
            menuItems
        }
    }

    private var startDate: Date? {
        if case let .inProgress(since) = workout.phase { return since }
        return nil
    }

    /// Skip / swap this exercise, or end the workout early. (Finishing normally is the bottom button.)
    @ViewBuilder
    private var menuItems: some View {
        Section(current) {
            if let original = today.original(of: current, day: day) {
                Button {
                    Haptics.tap()
                    today.undo(current, day: day)
                    withAnimation(DS.Motion.spring) { current = original }
                } label: {
                    Label { Text("Undo swap") } icon: { Image.pixel(.reload) }
                }
            } else {
                Button { swapping = true } label: {
                    Label { Text("Swap for today…") } icon: { Image.pixel(.reload) }
                }
            }
            Button(role: .destructive) { skipCurrent() } label: {
                Label { Text("Skip today") } icon: { Image.pixel(.close) }
            }
        }
        if workout.isInProgress {
            Section {
                if setsToday == 0 {
                    Button(role: .destructive) { Haptics.tap(); confirmCancel = true } label: {
                        Label { Text("Cancel workout") } icon: { Image.pixel(.close) }
                    }
                } else if !remaining.isEmpty {
                    Button { Haptics.tap(); confirmFinish = true } label: {
                        Label { Text("Finish workout early") } icon: { Image.pixel(.flag) }
                    }
                }
            }
        }
    }

    // MARK: Moving between exercises

    private func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// Swipe left/right: next/previous exercise in today's order.
    private func step(_ direction: Int) {
        guard let i = index else { return }
        let j = i + direction
        guard names.indices.contains(j) else {
            Haptics.warning()
            return
        }
        go(to: names[j])
    }

    private func go(to name: String) {
        guard !same(name, current) else { return }
        let from = index ?? -1
        let to = names.firstIndex { same($0, name) } ?? from + 1
        Haptics.select()
        // Set the direction first and move on the next tick, so the old screen slides out the right way.
        forward = to >= from
        Task { @MainActor in
            withAnimation(DS.Motion.spring) { current = name }
        }
    }

    // MARK: Actions

    /// Skips an exercise for today, then on to the next one, or back to the list if it was the last.
    /// Undo puts back exactly what was there, including today's swap.
    private func skipToday(_ skipped: String, next upNext: String?) {
        let swappedFrom = today.original(of: skipped, day: day)
        today.skip(skipped, day: day)
        UndoCenter.shared.show("\(skipped) skipped today") {
            // A skipped swap is stored on the plan's exercise, so undo that and swap again.
            today.undo(swappedFrom ?? skipped, day: day)
            if let swappedFrom { today.swap(swappedFrom, for: skipped, day: day) }
        }
        if let upNext {
            go(to: upNext)
        } else {
            dismiss()
        }
    }

    private func skipCurrent() {
        Haptics.warning()
        skipToday(current, next: next)
    }

    private func swap(to replacement: String, keep: Bool) {
        if WorkoutFlow.exercise(replacement, in: exercises) == nil {
            context.insert(Exercise(name: replacement))
        }
        if keep {
            RoutineStore.shared.replace(current, with: replacement, onDay: day)
        } else {
            today.swap(current, for: replacement, day: day)
        }
        withAnimation(DS.Motion.spring) { current = replacement }
    }

    private func finishEarly() {
        Haptics.success()
        WorkoutFlow.finish(day: day, in: exercises)
        // Let the confirmation close before the summary slides up.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            showSummary = true
        }
    }
}

// MARK: - Strip

/// "DAY 1 · PUSH   12:34  2/5  ···" with one dot per exercise underneath. Tap a dot to jump there.
struct WorkoutStrip<MenuItems: View>: View {
    let day: Int
    let names: [String]
    let current: String
    /// When today's workout started (nil when it isn't running).
    let startedAt: Date?
    /// Shown instead of the timer when it isn't running.
    var idleLabel = "NOT STARTED"
    let isDone: (String) -> Bool
    let onSelect: (String) -> Void
    @ViewBuilder let menu: MenuItems

    private var doneCount: Int { names.filter(isDone).count }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text("DAY \(day) · \(Routine.dayName(day).uppercased())")
                    .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: DS.Space.s)
                if let startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(WorkoutView.clock(context.date.timeIntervalSince(startedAt)))
                            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                            .foregroundStyle(Color.ppText)
                            .monospacedDigit()
                    }
                } else {
                    Text(idleLabel)
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                Text("\(doneCount)/\(names.count)")
                    .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                    .foregroundStyle(doneCount == names.count ? Color.ppDone : .secondary)
                    .contentTransition(.numericText(value: Double(doneCount)))
                    .animation(.snappy, value: doneCount)
                Menu { menu } label: {
                    Image.pixel(.more, size: 16)
                        .foregroundStyle(Color.ppText)
                        .frame(width: DS.Size.minTap, height: DS.Size.minTap)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More: skip, swap or end workout")
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.xs) {
                        ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                            StripDot(number: index + 1,
                                     name: name,
                                     isCurrent: name.caseInsensitiveCompare(current) == .orderedSame,
                                     isDone: isDone(name)) {
                                onSelect(name)
                            }
                            .id(index)
                        }
                    }
                }
                .onChange(of: current) { _, _ in scroll(proxy) }
                .onAppear { scroll(proxy) }
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, DS.Space.xs)
        .padding(.bottom, DS.Space.s)
        .background {
            Color.ppBackground
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.ppLine.opacity(DS.Opacity.fill)).frame(height: DS.Size.hairline)
                }
                .ignoresSafeArea(edges: .top)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let i = names.firstIndex(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) else { return }
        withAnimation(DS.Motion.spring) { proxy.scrollTo(i, anchor: .center) }
    }
}

/// One exercise in the strip: number (or ✓ when done); the current one is wider and filled.
private struct StripDot: View {
    let number: Int
    let name: String
    let isCurrent: Bool
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(isCurrent ? Color.brand : (isDone ? Color.ppDone.opacity(DS.Opacity.track) : Color.ppLine.opacity(DS.Opacity.fill)))
                Capsule()
                    .strokeBorder(Color.ppLine.opacity(isCurrent || isDone ? 0 : DS.Opacity.border), lineWidth: DS.Size.hairline)
                if isDone && !isCurrent {
                    Image.pixel(.check, size: 12)
                        .foregroundStyle(Color.ppDone)
                } else {
                    Text("\(number)")
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                        .foregroundStyle(isCurrent ? Color.ppOnAccent : Color.ppText)
                }
            }
            .frame(width: isCurrent ? DS.Space.xxl + DS.Space.l : DS.Space.xxl, height: DS.Space.xl + DS.Space.xs)
            .frame(minHeight: DS.Size.minTap)
            .contentShape(Rectangle())
            .animation(DS.Motion.spring, value: isCurrent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exercise \(number), \(name)\(isDone ? ", done" : "")\(isCurrent ? ", on screen" : "")")
    }
}

// MARK: - First-time tips

/// Shown once, the first time workout mode opens: how to move around.
struct WorkoutModeTips: View {
    static let seenKey = "tips.workoutMode"
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("HOW WORKOUT MODE WORKS")
                    .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                    .foregroundStyle(Color.brand)
                Spacer()
            }
            tip(.target, "Tap a dot above to jump to that exercise.")
            tip(.arrowRight, "Swipe left or right to change exercise.")
            tip(.check, "The button at the bottom always does the next thing: log, next, finish.")
            Button(action: dismiss) {
                Text("Got it")
                    .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                    .foregroundStyle(Color.ppOnAccent)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.minTap)
                    .background(Color.ppText, in: Capsule())
            }
            .buttonStyle(.squish)
        }
        .padding(DS.Space.l)
        .glassCard(cornerRadius: DS.Radius.card)
        .padding(.horizontal, DS.Space.screen)
        .padding(.vertical, DS.Space.s)
        .background(Color.ppBackground)
        .accessibilityElement(children: .contain)
    }

    private func tip(_ glyph: PixelGlyph, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image.pixel(glyph, size: 16)
                .foregroundStyle(Color.ppText)
                .frame(width: DS.Space.xl)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.ppText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
