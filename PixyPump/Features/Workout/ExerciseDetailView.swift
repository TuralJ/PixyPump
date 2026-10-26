import SwiftUI
import SwiftData
import Charts

/// One exercise: today's sets as a table (with last time's numbers next to each),
/// a suggestion for today, notes, progress chart and full history.
struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    var onSetAdded: (() -> Void)?
    /// Name of the next exercise in today's workout (shows a "Next" button).
    var nextName: String?
    var onNext: (() -> Void)?
    /// Which plan day this was opened from (for the right targets).
    var day: Int?
    /// Workout mode: skip this exercise (name, and the next one to go to, if any).
    /// Workout mode does the skip, moves on and shows Undo; without it the screen skips and closes.
    var onSkipped: ((String, String?) -> Void)?
    /// Shown at the top when sets can't be logged here (another day, or after finishing).
    var previewNote: String?
    /// Optional button under the preview note ("Add more sets").
    var previewActionTitle: String?
    var onPreviewAction: (() -> Void)?

    init(exercise: Exercise,
         day: Int? = nil,
         onSetAdded: (() -> Void)? = nil,
         nextName: String? = nil,
         onNext: (() -> Void)? = nil,
         onSkipped: ((String, String?) -> Void)? = nil,
         previewNote: String? = nil,
         previewActionTitle: String? = nil,
         onPreviewAction: (() -> Void)? = nil) {
        self.exercise = exercise
        self.day = day
        self.onSetAdded = onSetAdded
        self.nextName = nextName
        self.onNext = onNext
        self.onSkipped = onSkipped
        self.previewNote = previewNote
        self.previewActionTitle = previewActionTitle
        self.onPreviewAction = onPreviewAction
    }

    /// −/+ step for this exercise (barbell, dumbbell or machine).
    private var weightStep: Double { Units.step(for: exercise.name) }

    /// Sets are logged only inside today's workout (workout mode). Everywhere else this screen is for looking.
    private var canLog: Bool { onSetAdded != nil }

    @State private var weightText = ""
    @State private var reps = 8
    @State private var prMessage: String?
    /// Bumped on every logged set: drives the "+XP" pop and the new row's stamp.
    @State private var logCount = 0
    @State private var popText = ""
    @State private var justLogged = false
    /// Bumped when −/+ changes the weight, so the number gives a little bounce.
    @State private var nudges = 0
    @State private var editingSet: WorkoutSet?
    @State private var editingNotes = false
    @State private var showSummary = false
    /// Target done and "Add an extra set" tapped: the set card opens again and the bottom button logs it.
    @State private var addingExtra = false
    @State private var showPlates = false
    @State private var showGuide = false
    /// Show "what to load" under the weight (turned on from the plate calculator).
    @State private var platesOn = false
    @AppStorage(Prefs.unit) private var unitRaw = "kg"
    @AppStorage(Prefs.autoRest) private var autoRest = true
    /// New sets are always working sets (a set can be marked as a warm-up later: tap it → Type).
    private let logAsWarmup = false
    @FocusState private var weightFocused: Bool

    private let calendar = Calendar.current

    // MARK: - Data

    private struct DayGroup: Identifiable {
        let day: Date
        let sets: [WorkoutSet]
        var id: Date { day }
        var best: Double { sets.filter { !$0.isWarmup }.map(\.weight).max() ?? 0 }
    }

    /// Every day you did this exercise, newest first (sets newest first).
    private var days: [DayGroup] {
        let grouped = Dictionary(grouping: exercise.sets) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { DayGroup(day: $0.key, sets: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    /// Today's sets in the order you did them (warm-ups included).
    private var todayAll: [WorkoutSet] {
        exercise.sets.filter { calendar.isDateInToday($0.date) }.sorted { $0.date < $1.date }
    }

    private var todayWorking: [WorkoutSet] { todayAll.filter { !$0.isWarmup } }

    /// Working sets from the last session before today, in order.
    private var lastTime: [WorkoutSet] {
        guard let session = days.first(where: { !calendar.isDateInToday($0.day) }) else { return [] }
        return session.sets.filter { !$0.isWarmup }.sorted { $0.date < $1.date }
    }

    private var lastTimeDay: Date? { lastTime.first.map { calendar.startOfDay(for: $0.date) } }

    private var planItem: RoutineItem? { Routine.item(for: exercise.name, onDay: day) }
    private var plannedTarget: Int { max(planItem?.sets ?? 3, 1) }
    /// Sets you ended this exercise at today ("Finish exercise"), if you did.
    private var finishedEarlyAt: Int? { day.flatMap { TodayChanges.shared.finishedSets(exercise.name, day: $0) } }
    private var target: Int { finishedEarlyAt ?? plannedTarget }
    private var repsLow: Int { planItem?.repsLow ?? 8 }
    private var repsHigh: Int { planItem?.repsHigh ?? 10 }
    private var repsText: String { planItem?.repsText ?? "8–10" }
    private var targetReached: Bool { todayWorking.count >= target }

    /// What to aim for today, based on last time (simple double progression).
    private var suggestion: (weight: Double, reps: Int, reason: String)? {
        guard let top = lastTime.map(\.weight).max(), top > 0 else { return nil }
        let atTop = lastTime.filter { $0.weight == top }
        let hitTopOfRange = lastTime.count >= target && lastTime.prefix(target).allSatisfy { $0.reps >= repsHigh }
        if hitTopOfRange {
            let next = top + Units.toKg(weightStep)
            return (next, repsLow,
                    "You hit \(repsHigh) reps on every set last time, so add \(weightStep.plain) \(Units.symbol).")
        }
        let bestReps = atTop.map(\.reps).max() ?? repsLow
        let aim = min(max(bestReps + 1, repsLow), repsHigh)
        return (top, aim, "Same weight as last time. Aim for \(aim) reps, then add weight once you hit \(repsHigh) on every set.")
    }

    /// The suggestion only gets its own row when it asks for more than last time's first set.
    /// (Copying last time is already one tap on the "Last" chip.)
    private var suggestionIsNew: Bool {
        guard let suggestion else { return false }
        guard let first = lastTime.first else { return true }
        return abs(suggestion.weight - first.weight) > 0.01 || suggestion.reps != first.reps
    }

    // MARK: - Body

    var body: some View {
        // What you need mid-set comes first: goal, sets, next. Extras below.
        List {
            previewSection
            goalSection
            setsSection
            nextSection
            toolsSection
            chartSection
            historySections
        }
        .ppScreen()
        // One button, always in the same place: log the set → next exercise → finish workout.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canLog { actionDock }
        }
        .overlay(alignment: .top) {
            if let prMessage {
                PRBanner(message: prMessage)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RestTimerMenu()
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
        .sheet(item: $editingSet) { set in
            EditSetSheet(set: set)
        }
        .sheet(isPresented: $showGuide) {
            ExerciseGuideSheet(name: exercise.name)
        }
        .sheet(isPresented: $editingNotes) {
            NotesSheet(exercise: exercise)
        }
        .sheet(isPresented: $showSummary, onDismiss: {
            // Finished from the last exercise: go back to the Workout screen.
            if onSetAdded != nil, ActiveWorkout.shared.isFinished { dismiss() }
        }) {
            WorkoutSummaryView()
        }
        .sheet(isPresented: $showPlates, onDismiss: { platesOn = Plates.usesPlates(exercise.name) }) {
            PlateCalculatorSheet(exerciseName: exercise.name, weightText: $weightText)
        }
        .onAppear {
            platesOn = Plates.usesPlates(exercise.name)
            prefill()
        }
        // Hit the target for this exercise: a satisfying double-tap buzz.
        .onChange(of: targetReached) { was, now in
            if !was && now { Haptics.success() }
        }
    }

    // MARK: How to · Note

    private var toolsSection: some View {
        Section {
            HStack(spacing: 8) {
                Button { Haptics.tap(); showGuide = true } label: {
                    ToolChip(icon: .eye, title: "How to")
                }
                .buttonStyle(.borderless)
                Button { Haptics.tap(); editingNotes = true } label: {
                    ToolChip(icon: .pencil, title: "Note")
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)

            if let notes = exercise.notes, !notes.isEmpty {
                Button { editingNotes = true } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image.pixel(.pencil, size: 16).foregroundStyle(.secondary)
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(Color.ppText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(Color.ppCard)
    }

    // MARK: Goal + notes

    private var goalSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("\(target) × \(repsText)")
                    .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                    .foregroundStyle(Color.ppText)
                Text("sets × reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SetDots(done: todayWorking.count, target: target)
            }

            if canLog, let suggestion, todayWorking.isEmpty, suggestionIsNew {
                Button {
                    Haptics.select()
                    weightText = Units.number(suggestion.weight)
                    reps = suggestion.reps
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image.pixel(.zap)
                            .foregroundStyle(Color.ppFat)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aim today: \(Units.weight(suggestion.weight)) × \(suggestion.reps)")
                                .font(.pixel(DS.TextSize.callout, relativeTo: .body))
                                .foregroundStyle(Color.ppText)
                            Text(suggestion.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Text("Use")
                            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                            .foregroundStyle(Color.brand)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Fills in these numbers")
            }

        } header: {
            PPHeader("Today's goal")
        }
        .listRowBackground(Color.ppCard)
    }

    // MARK: Set table

    private var setsSection: some View {
        Section {
            // Column titles
            HStack(spacing: 10) {
                Text("SET").frame(width: 34, alignment: .leading)
                Text("LAST TIME").frame(maxWidth: .infinity, alignment: .leading)
                Text("TODAY").frame(width: 110, alignment: .trailing)
            }
            .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
            .foregroundStyle(.secondary)

            // Logged sets — tap to edit
            ForEach(Array(todayAll.enumerated()), id: \.element.persistentModelID) { index, set in
                Button { editingSet = set } label: {
                    SetTableRow(label: label(for: set),
                                previous: previous(for: set),
                                today: "\(Units.number(set.weight)) × \(set.reps)",
                                done: true,
                                warmup: set.isWarmup,
                                stampIn: justLogged && index == todayAll.count - 1)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit or delete this set")
            }

            // The set you're about to do
            if showsEntry {
                entryRow
            } else if canLog && targetReached {
                extraSetLink
            }

            // The rest of today's sets, so you can see what's left
            if firstPendingSet <= target {
                ForEach(firstPendingSet...target, id: \.self) { number in
                    SetTableRow(label: "\(number)",
                                previous: previousText(index: number - 1),
                                today: "–",
                                done: false,
                                warmup: false)
                        .opacity(0.5)
                }
            }
        } header: {
            PPHeader(targetReached ? "Sets · target done" : "Sets")
        } footer: {
            if let lastTimeDay {
                Text("Last time: \(lastTimeDay.formatted(.relative(presentation: .named))). Tap a set to edit it.")
            } else {
                Text("Tap a set to edit it.")
            }
        }
        .listRowBackground(Color.ppCard)
    }

    /// First set number shown greyed out (after the entry row, when there is one).
    private var firstPendingSet: Int { todayWorking.count + (showsEntry ? 2 : 1) }

    /// The weight/reps card is open: while sets are left, or while adding an extra set.
    /// Once the target is done it closes, so there's only ever one thing to tap (the bottom button).
    private var showsEntry: Bool { canLog && (!targetReached || addingExtra) }

    /// Target done: a quiet link to do one more, instead of a second big button.
    private var extraSetLink: some View {
        Button {
            Haptics.tap()
            withAnimation(DS.Motion.spring) { addingExtra = true }
        } label: {
            HStack(spacing: DS.Space.s) {
                Image.pixel(.plus, size: 16)
                Text("Add an extra set")
                    .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.brand)
            .frame(minHeight: DS.Size.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Opens the set card again for one more set")
    }

    private var entryRow: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(logAsWarmup ? "Warm-up" : (targetReached ? "Extra set" : "Set \(todayWorking.count + 1)"))
                    .font(.pixel(DS.TextSize.callout, relativeTo: .body))
                    .foregroundStyle(Color.ppText)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                // Last time's set at this position + the live set duel against it, in one chip.
                if let ghost = ghostSet {
                    lastChip(ghost)
                }
                if addingExtra {
                    Button("Cancel") {
                        Haptics.tap()
                        withAnimation(DS.Motion.spring) { addingExtra = false }
                    }
                    .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: DS.Size.minTap)
                    .buttonStyle(.borderless)
                }
            }

            // Weight: −  [ 42.5 kg ]  +
            HStack(spacing: 10) {
                stepButton(-1)
                HStack(spacing: 6) {
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.pixel(DS.TextSize.title, relativeTo: .title))
                        .foregroundStyle(Color.ppText)
                        .focused($weightFocused)
                        .popOnChange(of: nudges, scale: 1.08)
                        .accessibilityLabel("Weight in \(Units.symbol)")
                    Text(Units.symbol).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
                .onTapGesture { weightFocused = true }
                stepButton(1)
            }

            // Barbell: what to put on each side.
            Button { Haptics.tap(); showPlates = true } label: {
                HStack(spacing: 8) {
                    Image.pixel(.dumbbell, size: 16)
                    if platesOn, let typed = Double(userInput: weightText) {
                        Text("Each side: " + Plates.text(total: typed, bar: Plates.bar))
                            .foregroundStyle(Color.ppText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Plate calculator")
                    }
                    Spacer(minLength: 0)
                    Image.pixel(.chevronRight, size: 16)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .foregroundStyle(Color.brand)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            // Reps: one tap on the plan's range, −/+ for anything else.
            VStack(spacing: DS.Space.s) {
                HStack {
                    Text("Reps")
                    Spacer()
                    Text("\(reps)")
                        .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                        .foregroundStyle(Color.ppText)
                        .contentTransition(.numericText(value: Double(reps)))
                        .animation(.snappy(duration: 0.25), value: reps)
                        .accessibilityLabel("\(reps) reps")
                }
                HStack(spacing: DS.Space.s) {
                    repStepButton(-1)
                    ForEach(repChoices, id: \.self) { value in
                        repChip(value)
                    }
                    repStepButton(1)
                }
            }
            .hapticOnChange(of: reps)

            // Done for today with fewer sets than planned (2 today, 3 next time…).
            if let day, onSetAdded != nil, !targetReached, !todayWorking.isEmpty {
                Button {
                    Haptics.success()
                    withAnimation(.spring) {
                        TodayChanges.shared.finishEarly(exercise.name, day: day, sets: todayWorking.count)
                    }
                    RestTimer.shared.nextHint = nextName.map { "Next: \($0)" } ?? "Last exercise done"
                } label: {
                    // A quiet link, not a second big button: the bottom button stays the one main action.
                    HStack(spacing: DS.Space.s) {
                        Image.pixel(.flag, size: 16)
                        Text("Finish exercise · \(todayWorking.count) \(todayWorking.count == 1 ? "set" : "sets") today")
                            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: DS.Size.minTap)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Counts this exercise as done today with the sets you've logged. Your plan stays the same.")
            }

            if let day, let finishedEarlyAt {
                HStack(spacing: 8) {
                    Text("Finished at \(finishedEarlyAt) of \(plannedTarget) sets today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") {
                        Haptics.tap()
                        withAnimation(.spring) { TodayChanges.shared.reopen(exercise.name, day: day) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// Last time's set at the position you're about to log.
    private var ghostSet: WorkoutSet? {
        todayWorking.count < lastTime.count ? lastTime[todayWorking.count] : nil
    }

    /// How the numbers you've typed compare with last time's set (the "set duel").
    private struct DuelStatus {
        let text: String
        let color: Color
        let result: DuelResult
    }

    /// Live duel status for the chip, or nil while the weight box is empty.
    private func duelStatus(_ ghost: WorkoutSet) -> DuelStatus? {
        guard let kg = Double(userInput: weightText).map(Units.toKg) else { return nil }
        let result = SetDuel.result(weightKg: kg, reps: reps, against: ghost)
        switch result {
        case .win:
            return DuelStatus(text: "WINNING", color: .ppDone, result: result)
        case .tie:
            return DuelStatus(text: "TIED, +1 rep wins", color: .ppFat, result: result)
        case .lose:
            // Fewest extra reps at this weight that would win.
            if let need = (reps + 1...reps + 10).first(where: {
                SetDuel.result(weightKg: kg, reps: $0, against: ghost) == .win }) {
                let more = need - reps
                return DuelStatus(text: "\(more) \(more == 1 ? "rep" : "reps") to win", color: .secondary, result: result)
            }
            return DuelStatus(text: "add weight to win", color: .secondary, result: result)
        }
    }

    /// "Last 40 × 8 · WINNING": last time's set at this position, plus the live set duel.
    /// Tap to copy last time's numbers. Warm-ups don't duel, so then it's just "Last 40 × 8".
    private func lastChip(_ ghost: WorkoutSet) -> some View {
        let isSame = Double(userInput: weightText).map { abs(Units.toKg($0) - ghost.weight) < 0.05 } == true
            && reps == ghost.reps
        let duel = logAsWarmup ? nil : duelStatus(ghost)
        let last = "\(Units.number(ghost.weight)) × \(ghost.reps)"
        return Button {
            guard !isSame else { return }
            Haptics.select()
            weightText = Units.number(ghost.weight)
            reps = ghost.reps
        } label: {
            HStack(spacing: 6) {
                Image.pixel(isSame ? .check : .copy, size: 16)
                    .foregroundStyle(isSame ? Color.secondary : Color.brand)
                Text("Last \(last)")
                    .foregroundStyle(isSame ? Color.secondary : Color.brand)
                if let duel {
                    Text("· \(duel.text)")
                        .foregroundStyle(duel.color)
                        .popOnChange(of: duel.text, scale: 1.2)
                        .breathe(duel.result == .win, amount: 0.08)
                }
            }
            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color.ppLine.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: duel?.text)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Last time \(last)" + (duel.map { ", set duel: \($0.text)" } ?? ""))
        .accessibilityHint(isSame ? "Already filled in" : "Fills in last time's numbers")
    }

    private var logTitle: String {
        if logAsWarmup { return "Log warm-up" }
        return targetReached ? "Log extra set" : "Log set \(todayWorking.count + 1) of \(target)"
    }

    /// Quick rep choices from the plan's range (8–10 → 8 9 10, 6–12 → 6 8 10 12).
    private var repChoices: [Int] {
        let low = max(repsLow, 1)
        let high = max(repsHigh, low)
        let all = Array(low...high)
        guard all.count > 4 else { return all }
        let step = Double(high - low) / 3
        return Array(Set((0...3).map { low + Int((Double($0) * step).rounded()) })).sorted()
    }

    private func repChip(_ value: Int) -> some View {
        let selected = value == reps
        // No haptic here: `.hapticOnChange(of: reps)` on the row already clicks.
        return Button {
            reps = value
        } label: {
            Text("\(value)")
                .font(.pixel(DS.TextSize.callout, relativeTo: .body))
                .foregroundStyle(selected ? Color.ppOnAccent : Color.ppText)
                .frame(maxWidth: .infinity, minHeight: DS.Size.minTap)
                .background(selected ? Color.ppText : Color.ppLine.opacity(DS.Opacity.fill), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(value) reps")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func repStepButton(_ direction: Int) -> some View {
        Button {
            reps = min(max(reps + direction, 1), 100)
        } label: {
            Image.pixel(direction < 0 ? .minus : .plus, size: 16)
                .foregroundStyle(Color.ppText)
                .frame(width: DS.Size.minTap, height: DS.Size.minTap)
                .background(Color.ppLine.opacity(DS.Opacity.fill), in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(direction < 0 ? "One rep less" : "One rep more")
    }

    private func stepButton(_ direction: Double) -> some View {
        Button { nudgeWeight(direction * weightStep) } label: {
            Image.pixel(direction < 0 ? .minus : .plus)
                .foregroundStyle(Color.ppText)
                .frame(width: 48, height: 48)
                .background(Color.ppLine.opacity(0.08), in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(direction < 0 ? "Minus \(weightStep.plain) \(Units.symbol)" : "Plus \(weightStep.plain) \(Units.symbol)")
    }

    private func label(for set: WorkoutSet) -> String {
        if let badge = set.kind.badge { return badge }
        let index = todayWorking.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0
        return "\(index + 1)"
    }

    private func previous(for set: WorkoutSet) -> String {
        guard !set.isWarmup,
              let index = todayWorking.firstIndex(where: { $0.persistentModelID == set.persistentModelID })
        else { return "" }
        return previousText(index: index)
    }

    /// Last session's set at this position, e.g. "40 × 8".
    private func previousText(index: Int) -> String {
        guard index >= 0, index < lastTime.count else { return "–" }
        let set = lastTime[index]
        return "\(Units.number(set.weight)) × \(set.reps)"
    }

    // MARK: Next exercise / finish

    @ViewBuilder
    private var nextSection: some View {
        if !targetReached, let day, onSetAdded != nil {
            // Too tired, sore, or out of time: skip the rest of this exercise today.
            Section {
                Button {
                    Haptics.warning()
                    let upNext = nextName
                    if let onSkipped {
                        onSkipped(exercise.name, upNext)
                    } else {
                        TodayChanges.shared.skip(exercise.name, day: day)
                        if let onNext, upNext != nil {
                            onNext()
                        } else {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image.pixel(.close, size: 16)
                        Text(nextName.map { "Skip · go to \($0)" } ?? "Skip this exercise")
                            .font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Skips this exercise for today only. Your plan stays the same.")
            } footer: {
                Text(todayWorking.isEmpty
                     ? "Skipping only affects today. Your plan stays the same."
                     : "Sets you've already logged are kept. Skipping only affects today.")
            }
            .listRowBackground(Color.ppCard)
        }
        if targetReached, nextName == nil, canLog {
            Section {
                HStack(spacing: 10) {
                    PixelBuddy(mood: .flex, size: 40, action: .cheer)
                    Text("Last exercise of the day — workout complete!")
                        .foregroundStyle(Color.ppDone)
                }
            }
            .listRowBackground(Color.ppCard)
        }
    }

    // MARK: Bottom button

    /// Log set → Next exercise → Finish workout, always in the same spot.
    private var actionDock: some View {
        Group {
            if !targetReached || addingExtra {
                Button(action: addSet) {
                    HStack(spacing: DS.Space.s) {
                        Image.pixel(.check, size: 16)
                        Text(logTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .disabled(Double(userInput: weightText) == nil)
                .accessibilityHint("Logs \(weightText) \(Units.symbol) × \(reps)")
            } else if let nextName, let onNext {
                Button {
                    Haptics.press()
                    onNext()
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Text("Next: \(nextName)")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image.pixel(.arrowRight, size: 16)
                    }
                }
                // A beat after the last set, so a double tap on "Log set" doesn't jump ahead.
                .disabled(justLogged)
            } else {
                Button {
                    Haptics.success()
                    ActiveWorkout.shared.finish()
                    showSummary = true
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Image.pixel(.flag, size: 16)
                        Text("Finish workout")
                    }
                }
                .disabled(justLogged)
            }
        }
        .buttonStyle(.primary)
        .xpPop(trigger: logCount, text: popText)
        .animation(DS.Motion.spring, value: targetReached)
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, DS.Space.s)
        .padding(.bottom, DS.Space.s)
        .background(alignment: .bottom) {
            // Soft fade so the list doesn't show through behind the button.
            LinearGradient(colors: [Color.ppBackground.opacity(0), Color.ppBackground],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: Preview note

    @ViewBuilder
    private var previewSection: some View {
        if !canLog {
            Section {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image.pixel(.eye, size: 16)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(previewNote ?? "Just looking. Sets are logged during a workout on the Workout tab.")
                            .font(.subheadline)
                            .foregroundStyle(Color.ppText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let previewActionTitle, let onPreviewAction {
                            Button {
                                Haptics.tap()
                                onPreviewAction()
                            } label: {
                                Text(previewActionTitle)
                                    .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                                    .foregroundStyle(Color.brand)
                                    .frame(minHeight: DS.Size.minTap)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Space.xs)
            }
            .listRowBackground(Color.ppCard)
        }
    }

    // MARK: Chart + history

    @ViewBuilder
    private var chartSection: some View {
        if days.count > 1 {
            Section {
                Chart(days.reversed()) { day in
                    LineMark(x: .value("Date", day.day, unit: .day),
                             y: .value(Units.symbol, Units.display(day.best)))
                    PointMark(x: .value("Date", day.day, unit: .day),
                              y: .value(Units.symbol, Units.display(day.best)))
                }
                .drawIn()
                .foregroundStyle(Color.brand)
                .frame(height: 180)
                .padding(.vertical, 8)
            } header: {
                PPHeader("Best weight per day")
            }
            .listRowBackground(Color.ppCard)
        }
    }

    @ViewBuilder
    private var historySections: some View {
        if days.isEmpty {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image.pixel(.calendar)
                        .foregroundStyle(Color.brand)
                    Text("No sets yet. Your history and chart appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                PPHeader("History")
            }
            .listRowBackground(Color.ppCard)
        }
        ForEach(days.filter { !calendar.isDateInToday($0.day) }) { group in
            Section {
                ForEach(group.sets) { set in
                    Button { editingSet = set } label: {
                        HStack {
                            if let badge = set.kind.badge {
                                Text(badge)
                                    .font(.pixel(DS.TextSize.caption))
                                    .foregroundStyle(Color.ppCarbs)
                                    .frame(width: 18)
                            }
                            Text("\(Units.weight(set.weight)) × \(set.reps)")
                                .font(.pixel(DS.TextSize.callout))
                                .foregroundStyle(set.isWarmup ? Color.secondary : Color.ppText)
                            if !set.isWarmup && set.weight == exercise.bestWeight && set.weight > 0 {
                                Image.pixel(.star, size: 16)
                                    .foregroundStyle(Color.ppFat)
                                    .accessibilityLabel("Personal best")
                            }
                            Spacer()
                            Text(set.date, style: .time)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // In workout mode a sideways swipe changes exercise, so delete is via tap → Delete there.
                .onDelete(perform: deleteAction(for: group))
            } header: {
                PPHeader(group.day.formatted(.dateTime.weekday(.wide).day().month()))
            }
            .listRowBackground(Color.ppCard)
        }
    }

    // MARK: - Actions

    private func nudgeWeight(_ step: Double) {
        Haptics.select()
        let current = Double(userInput: weightText) ?? 0
        weightText = max(0, current + step).plain
        nudges += 1
    }

    private func addSet() {
        guard let typed = Double(userInput: weightText) else { return }
        let weight = Units.toKg(typed)   // always stored in kg
        let kind: SetKind = logAsWarmup ? .warmup : .working

        // Personal record? (Working sets only, and only once there's history to beat.)
        let previous = exercise.workingSets
        var pr: String?
        if kind == .working, !previous.isEmpty {
            let bestWeight = previous.map(\.weight).max() ?? 0
            let bestRepsAtWeight = previous.filter { abs($0.weight - weight) < 0.01 }.map(\.reps).max() ?? 0
            if weight > bestWeight + 0.01 {
                pr = "New PR! \(Units.weight(weight))"
            } else if abs(weight - bestWeight) < 0.01 && weight > 0 && reps > bestRepsAtWeight {
                pr = "New PR! \(Units.weight(weight)) × \(reps)"
            } else if weight > 0 {
                // Lighter but more reps can still be your strongest set ever.
                let bestMax = previous.map(\.estimatedMax).max() ?? 0
                let newMax = reps <= 1 ? weight : weight * (1 + Double(reps) / 30)   // Epley, same as estimatedMax
                if newMax > bestMax + 0.01 {
                    pr = "New PR! Est. 1RM \(Units.weight(newMax))"
                }
            }
        }

        // Set duel against the same set last time.
        let isRecord = pr != nil
        let setIndex = todayWorking.count
        // Warm-ups don't duel (same as targets and records).
        let duel = kind == .working ? ghostSet.map { SetDuel.result(weightKg: weight, reps: reps, against: $0) } : nil

        justLogged = true
        let newSet = WorkoutSet(reps: reps, weight: weight, kind: kind)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            exercise.sets.append(newSet)
        }
        ActiveWorkout.shared.noteSetLogged(day: day)
        if duel == .win {
            let xp = SetDuel.recordWin(exercise: exercise.name, setIndex: setIndex)
            let won = xp > 0 ? "Set duel won! +\(xp) XP" : "Set duel won!"
            pr = pr.map { "\($0) · duel won" } ?? won
        } else if duel == .tie, pr == nil {
            pr = "Tied with last time. One more rep next set!"
        }
        weightFocused = false
        onSetAdded?()

        if autoRest {
            RestTimer.shared.nextHint = nextHint()
            RestTimer.shared.start(for: exercise.name)
        }
        // An extra set is one at a time: the card closes again and the bottom button goes back to "Next".
        if addingExtra { withAnimation(DS.Motion.spring) { addingExtra = false } }

        SFX.play(isRecord ? .record : (duel == .win ? .duelWon : .setLogged))
        // Floating reward over the button.
        if isRecord {
            popText = "New PR! 🏆"
        } else if duel == .win {
            popText = "+\(SetDuel.xp) XP"
        } else if kind == .warmup {
            popText = "+1 warm-up"
        } else {
            popText = todayWorking.count >= target ? "✓ Target done" : "+1 set"
        }
        logCount += 1

        // Mis-tap? Undo takes the set back out. (Duel XP already paid stays; it's capped per day.)
        let owner = exercise
        let store = context
        let logged = kind == .warmup ? "Warm-up logged" : "Set logged"
        let startedRest = autoRest
        UndoCenter.shared.show("\(logged) · \(Units.weight(weight)) × \(reps)") {
            // The set didn't happen, so neither does the rest it started.
            if startedRest { RestTimer.shared.stop() }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                owner.sets.removeAll { $0 === newSet }
                store.delete(newSet)
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            justLogged = false
        }
        if let pr {
            hapticSuccess()
            withAnimation(.spring) { prMessage = pr }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { prMessage = nil }
            }
        } else {
            Haptics.press()
        }
    }

    /// Swipe-to-delete for a day of history (off in workout mode).
    private func deleteAction(for group: DayGroup) -> ((IndexSet) -> Void)? {
        guard !canLog else { return nil }
        return { offsets in deleteWithUndo(offsets.map { group.sets[$0] }) }
    }

    /// Deletes sets from the history, with an Undo toast that puts them back.
    private func deleteWithUndo(_ doomed: [WorkoutSet]) {
        guard !doomed.isEmpty else { return }
        let copies = doomed.map { (reps: $0.reps, weight: $0.weight, date: $0.date, kind: $0.kind) }
        Haptics.warning()
        for set in doomed { context.delete(set) }
        let owner = exercise
        UndoCenter.shared.show(doomed.count == 1 ? "Set deleted" : "\(doomed.count) sets deleted") {
            for copy in copies {
                owner.sets.append(WorkoutSet(reps: copy.reps, weight: copy.weight, date: copy.date, kind: copy.kind))
            }
        }
    }

    /// "Next: Set 3 · 40 kg × 8", or the next exercise once this one's done.
    private func nextHint() -> String {
        let done = todayWorking.count
        if done < target {
            return "Next: Set \(done + 1) · \(weightText) \(Units.symbol) × \(reps)"
        }
        if let nextName { return "Next: \(nextName)" }
        return "Last exercise done"
    }

    /// Start from today's suggestion, otherwise from your last set.
    private func prefill() {
        guard weightText.isEmpty else { return }
        if let today = todayWorking.last {
            weightText = Units.number(today.weight)
            reps = today.reps
        } else if let suggestion {
            weightText = Units.number(suggestion.weight)
            reps = suggestion.reps
        } else if let last = exercise.lastSet {
            weightText = Units.number(last.weight)
            reps = last.reps
        } else {
            reps = repsLow
        }
    }
}

// MARK: - Pieces

/// One row of the set table: set number | last time | today | ✓
private struct SetTableRow: View {
    let label: String
    let previous: String
    let today: String
    let done: Bool
    let warmup: Bool
    /// The set you just logged: its badge stamps in and the numbers slide in.
    var stampIn = false

    @State private var landed = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.pixel(DS.TextSize.subhead))
                .foregroundStyle(warmup ? Color.ppOnAccent : (done ? Color.ppOnAccent : Color.ppText))
                .frame(width: 28, height: 28)
                .background(warmup ? Color.ppCarbs : (done ? Color.ppDone : Color.ppLine.opacity(0.12)),
                            in: RoundedRectangle(cornerRadius: DS.Radius.xs))
                .scaleEffect(landed ? 1 : 1.8)
                .rotationEffect(.degrees(landed ? 0 : -12))
                .frame(width: 34, alignment: .leading)
            Text(previous)
                .font(.pixel(DS.TextSize.subhead))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(today)
                .font(.pixel(DS.TextSize.callout))
                .foregroundStyle(Color.ppText)
                .frame(width: 110, alignment: .trailing)
                .offset(x: landed ? 0 : 30)
                .opacity(landed ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .onAppear {
            guard stampIn, !reduceMotion else { return }
            landed = false
            // Next tick, so the "big" state is drawn first and the spring has something to animate from.
            Task { withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { landed = true } }
        }
    }
}

/// Little filled/empty dots: ●●○ = 2 of 3 sets.
struct SetDots: View {
    let done: Int
    let target: Int

    var body: some View {
        // Up to 8 dots; beyond that a "9/10" counter so the header never overflows.
        if max(target, done) > 8 {
            Text("\(done)/\(target)")
                .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                .foregroundStyle(done >= target ? Color.ppDone : Color.ppText)
        } else {
            HStack(spacing: 4) {
                ForEach(0..<max(target, done), id: \.self) { i in
                    Circle()
                        .fill(i >= target ? Color.brand : i < done ? Color.ppDone : Color.ppLine.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(done) of \(target) sets done")
        }
    }
}

private struct PRBanner: View {
    let message: String

    var body: some View {
        Label { Text(message) } icon: { Image.pixel(.trophy) }
            .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
            .foregroundStyle(Color.ppOnAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.ppFat, in: Capsule())
            .shadow(radius: 8)
    }
}

/// Change a logged set's weight, reps or type, or delete it.
struct EditSetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let set: WorkoutSet

    @State private var weightText = ""
    @State private var reps = 8
    @State private var kind: SetKind = .working
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Weight")
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                            .foregroundStyle(Color.ppText)
                        Text(Units.symbol).foregroundStyle(.secondary)
                    }
                    Stepper(value: $reps, in: 1...100) {
                        HStack {
                            Text("Reps")
                            Spacer()
                            Text("\(reps)").font(.pixel(DS.TextSize.title3)).foregroundStyle(Color.ppText)
                        }
                    }
                    Picker("Type", selection: $kind) {
                        ForEach(SetKind.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("Warm-ups don't count towards targets or records. Logged \(set.date.formatted(date: .abbreviated, time: .shortened)).")
                }
                .listRowBackground(Color.ppCard)

                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label { Text("Delete set") } icon: { Image.pixel(.trash) }
                    }
                }
                .listRowBackground(Color.ppCard)
            }
            .ppScreen()
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(Double(userInput: weightText) == nil)
                }
            }
            .confirmationDialog("Delete this set?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Haptics.warning()
                    let doomed = set
                    let owner = set.exercise
                    let copy = (reps: set.reps, weight: set.weight, date: set.date, kind: set.kind)
                    dismiss()
                    // Delete after the sheet has closed, so nothing still shows the set.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        context.delete(doomed)
                        // Undo puts an identical set back on the same exercise.
                        var undo: (() -> Void)?
                        if let owner {
                            undo = {
                                owner.sets.append(WorkoutSet(reps: copy.reps, weight: copy.weight,
                                                             date: copy.date, kind: copy.kind))
                            }
                        }
                        UndoCenter.shared.show("Set deleted", undo: undo)
                    }
                }
            }
            .onAppear {
                weightText = Units.number(set.weight)
                reps = set.reps
                kind = set.kind
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let typed = Double(userInput: weightText) else { return }
        set.weight = Units.toKg(typed)
        set.reps = reps
        set.kind = kind
        Haptics.success()
        dismiss()
    }
}

/// Free-text notes for an exercise.
private struct NotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color.ppCard, in: RoundedRectangle(cornerRadius: DS.Radius.tile))
                .padding(16)
                .background(AppBackground())
                .navigationTitle("Notes · \(exercise.name)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            exercise.notes = trimmed.isEmpty ? nil : trimmed
                            dismiss()
                        }
                    }
                }
                .onAppear { text = exercise.notes ?? "" }
        }
        .presentationDetents([.medium])
    }
}

/// Small capsule used in the Photo · How to · Note row.
private struct ToolChip: View {
    let icon: PixelGlyph
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image.pixel(icon, size: 16)
            Text(title).font(.pixel(DS.TextSize.subhead, relativeTo: .subheadline))
        }
        .foregroundStyle(Color.ppText)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.ppLine.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
    }
}
