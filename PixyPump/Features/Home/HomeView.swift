import UIKit
import SwiftUI
import SwiftData

/// Home tab: just today. One big workout card, three small tiles (calories, weight, challenges)
/// and at most one reminder. Week-scale things (missions, Journey, weekly stats) live on Progress.
struct HomeView: View {
    @Environment(\.selectTab) private var selectTab

    @Query private var exercises: [Exercise]
    @Query(sort: \WorkoutSet.date) private var sets: [WorkoutSet]
    @Query(sort: \FoodEntry.date) private var foodEntries: [FoodEntry]
    @State private var showSettings = false
    @State private var loggingWeight = false
    @State private var showingChallenges = false
    @AppStorage(AuthStore.nudgeDismissedKey) private var authNudgeDismissed = false
    @AppStorage(ProfileBanner.key) private var profileBanner = "none"
    @State private var editingPlan = false
    @State private var planStartDay: Int?
    @State private var showSummary = false
    @State private var levelUp: LevelUpMoment?
    @AppStorage(Backup.lastBackupKey) private var lastBackupAt = 0.0

    /// Nudge to back up if you have data and haven't backed up for a week.
    private var needsBackup: Bool {
        guard !sets.isEmpty || !foodEntries.isEmpty else { return false }
        return Date.now.timeIntervalSince1970 - lastBackupAt > 7 * 24 * 3600
    }

    @AppStorage(Prefs.unit) private var unitRaw = "kg"
    @AppStorage(Prefs.userName) private var userName = ""
    @AppStorage("lastTrainedDay") private var lastDay = 0
    @AppStorage("lastTrainedAt") private var lastTrainedAt = 0.0
    @AppStorage("workoutOpenNext") private var openNextRequested = false
    private let workout = ActiveWorkout.shared
    @AppStorage("goalKcal") private var goalKcal = 2500.0
    @AppStorage("goalProtein") private var goalProtein = 160.0
    @AppStorage("rewardsVersion") private var rewardsVersion = 0
    /// Mystery bag being opened full-screen (only when you tap a bag — never by itself).
    @State private var openingBag: PendingBag?
    /// A level-up that's waiting for the current big moment (summary, bag) to finish.
    @State private var pendingLevelUp: LevelUpMoment?
    /// Keeps the summary, level-up and bag reveal from stacking on top of each other.
    private let moments = MomentQueue.shared

    struct PendingBag: Identifiable {
        let id: String
    }
    @AppStorage("goalCarbs") private var goalCarbs = 280.0
    @AppStorage("goalFat") private var goalFat = 75.0

    private let calendar = Calendar.current

    // MARK: Today's workout

    /// The day the app suggests (next in the rotation).
    /// Based on what you actually trained last (see TrainingLog).
    private var suggestion: DaySuggestion { Routine.suggestion(from: sets) }
    private var suggestedDay: Int { TrainingLog.day(on: .now) ?? suggestion.day }
    /// A different day you picked on the Start card (before starting).
    @State private var pickedDay: Int?
    /// You can switch days until the workout has started.
    private var canPickDay: Bool {
        if case .notStarted = workout.phase { return Routine.dayCount > 1 }
        return false
    }
    private var todayDay: Int {
        if let day = workout.day { return day }
        if canPickDay, let pickedDay, pickedDay >= 1, pickedDay <= Routine.dayCount { return pickedDay }
        return suggestedDay
    }
    private var todayExercises: [String] { Routine.todayExercises(onDay: todayDay) }

    private func exercise(named name: String) -> Exercise? {
        exercises.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func setsToday(_ name: String) -> Int {
        exercise(named: name)?.workingSetsToday.count ?? 0
    }

    /// Done = all target sets logged today.
    private func doneToday(_ name: String) -> Bool {
        setsToday(name) >= Routine.targetSets(for: name, onDay: todayDay)
    }

    private var doneCount: Int { todayExercises.filter { doneToday($0) }.count }

    // MARK: Food

    private var todayFood: Nutrition {
        foodEntries.filter { calendar.isDateInToday($0.date) }
            .reduce(Nutrition()) { $0 + $1.nutrition }
    }

    // MARK: Body

    var body: some View {
        let stats = GameStats(allSets: sets)
        let weekly = WeeklyMissions.current(stats: stats)
        let daily = DailyChallenges.today(.init(sets: sets, food: foodEntries,
                                                goalKcal: goalKcal, goalProtein: goalProtein))
        let _ = rewardsVersion   // redraw when challenges or streak milestones pay out
        let streak = DailyStreak.compute(sets: sets)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(stats)
                        .staggeredAppear(0)

                    // The one big thing: today's workout.
                    workoutHero
                        .staggeredAppear(1)

                    // Three small glances, each one tap from what it's about.
                    todayTiles(daily: daily)
                        .staggeredAppear(2)

                    // At most one reminder, the most important first.
                    reminder(streak: streak)
                        .staggeredAppear(3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                checkProgress(stats: stats, weekly: weekly)
            }
            .fullScreenCover(item: $openingBag, onDismiss: { moments.isBusy = false }) { bag in
                MysteryBagView(subtitle: GymBag.subtitle(for: bag.id)) {
                    GymBag.openPending(bag.id, shieldsLeft: GameStats(allSets: sets).streak.shieldsLeft)
                } onClose: { _ in
                    rewardsVersion += 1   // redraw with the new XP / item
                }
            }
            .onChange(of: stats.xp) { _, _ in checkProgress(stats: stats, weekly: weekly) }
            .fullScreenCover(item: $levelUp, onDismiss: { moments.isBusy = false }) { level in
                LevelUpView(level: level.level)
            }
            // The summary or a bag just closed: now it's the waiting level-up's turn.
            .onChange(of: moments.isBusy) { _, busy in
                if !busy { showPendingLevelUp() }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $loggingWeight) { LogBodyWeightSheet() }
            .sheet(isPresented: $showingChallenges) {
                ChallengesSheet(streak: streak, challenges: daily)
            }
            .sheet(isPresented: $editingPlan) { RoutineEditorView(startDay: planStartDay) }
            .sheet(isPresented: $showSummary, onDismiss: {
                // The summary just paid out XP: celebrate a level-up straight away.
                let fresh = GameStats(allSets: sets)
                checkProgress(stats: fresh, weekly: WeeklyMissions.current(stats: fresh))
            }) { WorkoutSummaryView() }
            // Once a workout starts, forget the picked day (the workout remembers it).
            .onChange(of: workout.isInProgress) { _, started in
                if started { pickedDay = nil }
            }
        }
    }

    private func openPlan(day: Int?) {
        Haptics.tap()
        planStartDay = day
        editingPlan = true
    }

    private func header(_ stats: GameStats) -> some View {
        HStack(alignment: .top) {
            BuddyHeader(name: userName.trimmingCharacters(in: .whitespaces),
                        level: stats.level,
                        mood: buddyMood,
                        streak: DailyStreak.compute(sets: sets))
            Spacer(minLength: 8)
            Button { Haptics.tap(); showSettings = true } label: {
                Image.pixel(.gear)
                    .foregroundStyle(Color.ppText)
                    .frame(width: 44, height: 44)
                    .background(Color.ppCard, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, profileBanner == "none" ? 4 : 14)
        .padding(.top, profileBanner == "none" ? 6 : 14)
        .padding(.bottom, profileBanner == "none" ? 0 : 14)
        // Profile banner (Settings → Appearance): a scene behind your buddy and name.
        .background {
            if profileBanner != "none" {
                BuddyBackdrop(id: profileBanner, cornerRadius: 24)
                    .overlay {
                        // A veil in the page colour keeps your name readable in light and dark mode.
                        LinearGradient(colors: [Color.ppBackground.opacity(0.2), Color.ppBackground.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    }
            }
        }
    }

    // MARK: Today's workout

    @ViewBuilder
    private var workoutHero: some View {
        if Routine.dayCount == 0 {
            EmptyStateCard(
                icon: .dumbbell,
                title: "Let's build your plan",
                message: "Choose how many days you train and the exercises for each day. Your workout for today will show up right here.",
                buttonTitle: "Create your plan"
            ) { openPlan(day: nil) }
        } else if todayExercises.isEmpty {
            EmptyStateCard(
                icon: .plusBox,
                title: "Day \(todayDay) · \(Routine.dayName(todayDay))",
                message: "This day has no exercises yet. Add some and they'll show up here.",
                buttonTitle: "Add exercises"
            ) { openPlan(day: todayDay) }
        } else if workout.isFinished {
            doneTodayCard
        } else {
            workoutCard
        }
    }

    /// At least one workout done: a working set on an earlier day, or today's workout finished.
    private var hasCompletedWorkout: Bool {
        workout.isFinished || sets.contains { !$0.isWarmup && !calendar.isDateInToday($0.date) }
    }

    // MARK: Today tiles

    private func todayTiles(daily: [DailyChallenge]) -> some View {
        let kcalLeft = goalKcal - todayFood.kcal
        let latest = BodyWeightStore.shared.latest
        let weighedToday = latest.map { calendar.isDateInToday($0.date) } ?? false
        let won = daily.filter(\.isDone).count
        return HStack(spacing: DS.Space.m) {
            TodayTile(icon: .food, tint: .ppFlame,
                      value: Int(abs(kcalLeft).rounded()).formatted(),
                      label: kcalLeft >= 0 ? "kcal left" : "kcal over",
                      progress: goalKcal > 0 ? todayFood.kcal / goalKcal : nil) {
                selectTab(.food)
            }
            .accessibilityHint("Opens Calories")
            TodayTile(icon: .scale, tint: .brand,
                      value: latest.map { Units.number($0.kg) } ?? "–",
                      label: weighedToday ? "\(Units.symbol) · today ✓" : "Log weight",
                      progress: nil) {
                loggingWeight = true
            }
            TodayTile(icon: .target, tint: .ppFat,
                      value: "\(won)/\(daily.count)",
                      label: "Challenges",
                      progress: daily.isEmpty ? nil : Double(won) / Double(daily.count)) {
                showingChallenges = true
            }
        }
    }

    // MARK: One reminder

    /// Only the most important one shows: a waiting gym bag, the first-week checklist,
    /// a backup reminder, or saving your progress to an account.
    @ViewBuilder
    private func reminder(streak: DailyStreakState) -> some View {
        if !GymBag.pending.isEmpty {
            MysteryBagsCard(count: GymBag.pending.count, open: openNextBag)
        } else if !GettingStarted.isClaimed {
            StarterChecklistCard(steps: GettingStarted.steps(sets: sets, food: foodEntries)) {
                Haptics.success()
                GettingStarted.claim()
                rewardsVersion += 1
                openBag("starter")
            }
        } else if needsBackup {
            backupNudge
        } else if !AuthStore.shared.isSignedIn && !authNudgeDismissed
                    && (hasCompletedWorkout || streak.current >= 3) {
            SaveProgressCard(streak: streak.current)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Flexing after training today, sleepy the day after (recovery), ready otherwise.
    private var buddyMood: PixelBuddy.Mood {
        let hour = calendar.component(.hour, from: .now)
        let late = hour >= 22 || hour < 6
        guard let last = sets.last?.date else { return late ? .sleepy : .idle }
        if calendar.isDateInToday(last) { return .flex }
        // Night owl hours or the day after training: your buddy's resting too.
        if late || calendar.isDateInYesterday(last) { return .sleepy }
        return .idle
    }

    // MARK: Game moments

    /// Wraps a level so it can drive `fullScreenCover(item:)`.
    struct LevelUpMoment: Identifiable {
        let level: Level
        var id: Int { level.number }
    }

    /// Pays out finished weekly missions and journey chapters, and celebrates a new level once.
    private func checkProgress(stats: GameStats, weekly: [WeeklyMission]) {
        var level = stats.level
        if !sets.isEmpty {
            let paid = WeeklyMissions.bank(weekly) + Journey.bank(stats.journey)
            if !paid.isEmpty {
                Haptics.success()
                level = GameStats(allSets: sets).level   // include the XP just paid
            }
        }
        if LevelLog.seen == 0 {
            LevelLog.seen = level.number          // first launch: no fanfare for existing data
        } else if level.number > LevelLog.seen {
            LevelLog.seen = level.number
            pendingLevelUp = LevelUpMoment(level: level)
            showPendingLevelUp()
        }
    }

    /// Shows the waiting level-up, unless another big moment is on screen.
    /// If one is, `onChange(of: moments.isBusy)` calls this again once it closes.
    private func showPendingLevelUp() {
        guard pendingLevelUp != nil, !moments.isBusy, !showSummary,
              levelUp == nil, openingBag == nil else { return }
        Task {
            // Give the sheet that just closed a moment to slide away first.
            try? await Task.sleep(for: .milliseconds(450))
            guard let next = pendingLevelUp, !moments.isBusy, !showSummary,
                  levelUp == nil, openingBag == nil else { return }
            pendingLevelUp = nil
            moments.isBusy = true
            levelUp = next
        }
    }

    private func openNextBag() {
        Haptics.press()
        if let first = GymBag.pending.first { openBag(first) }
    }

    /// Opens a bag full-screen — only ever because you tapped it.
    private func openBag(_ id: String) {
        guard !moments.isBusy, levelUp == nil else { return }
        moments.isBusy = true
        openingBag = PendingBag(id: id)
    }

    private var backupNudge: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 10) {
                Image.pixel(.save)
                    .foregroundStyle(Color.ppCarbs)
                Text(lastBackupAt == 0 ? "Back up your data — you haven't yet"
                                       : "Time for a backup — it's been over a week")
                    .font(.subheadline)
                    .foregroundStyle(Color.ppText)
                Spacer(minLength: 0)
                Image.pixel(.chevronRight, size: 16)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .glassCard(cornerRadius: DS.Radius.card)
        }
        .buttonStyle(.plain)
    }

    // MARK: Workout card

    private var totalTargetSets: Int {
        todayExercises.reduce(0) { $0 + Routine.targetSets(for: $1, onDay: todayDay) }
    }

    private var doneSets: Int {
        todayExercises.reduce(0) { $0 + min(setsToday($1), Routine.targetSets(for: $1, onDay: todayDay)) }
    }

    private var workoutComplete: Bool { !todayExercises.isEmpty && doneCount == todayExercises.count }
    private var nextExercise: String? { todayExercises.first { !doneToday($0) } }

    /// Big pixel word: Start → Continue → Done.
    private var heroTitle: String {
        if workout.isFinished || workoutComplete { return "Done" }
        return (doneSets == 0 && !workout.isInProgress) ? "Start" : "Continue"
    }

    private var buttonTitle: String {
        if workoutComplete { return "Finish workout" }
        return (doneSets == 0 && !workout.isInProgress) ? "Start workout" : "Continue"
    }

    // MARK: After the workout

    private var nextDay: Int { Routine.dayCount > 0 ? todayDay % Routine.dayCount + 1 : 1 }

    private var todayWorkingSets: [WorkoutSet] {
        sets.filter { !$0.isWarmup && calendar.isDateInToday($0.date) }
    }

    /// Small "done" receipt: what you did today, no button.
    private var doneTodayCard: some View {
        let list = todayWorkingSets
        let volume = list.reduce(0) { $0 + $1.volume }
        var parts = ["\(list.count) sets", "\(Units.volume(volume)) \(Units.symbol)"]
        if let minutes = workout.minutesToday { parts.insert("\(minutes) min", at: 0) }
        return HStack(spacing: 14) {
            Image.pixel(.check, size: 16)
                .foregroundStyle(Color.ppBackground)
                .frame(width: 32, height: 32)
                .background(Color.ppDone, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY · DONE")
                    .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                    .foregroundStyle(Color.ppDone)
                Text("Day \(todayDay) · \(Routine.dayName(todayDay))")
                    .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                    .foregroundStyle(Color.ppText)
                Text(parts.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if Routine.dayCount > 1 {
                    Text("Tomorrow: Day \(nextDay) · \(Routine.dayName(nextDay))")
                        .font(.subheadline)
                        .foregroundStyle(Color.brand)
                        .padding(.top, DS.Space.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .strokeBorder(Color.ppDone.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    /// Tap "Day 1 · Bench & Rows ⌄" to train a different day; Start then tracks that day.
    private var dayPicker: some View {
        Menu {
            Picker("Day", selection: Binding(
                get: { todayDay },
                set: { day in
                    Haptics.select()
                    withAnimation(.snappy) { pickedDay = day }
                })) {
                ForEach(1...max(Routine.dayCount, 1), id: \.self) { d in
                    Text(d == suggestedDay
                         ? "Day \(d) · \(Routine.dayName(d)) · up next"
                         : "Day \(d) · \(Routine.dayName(d))")
                        .tag(d)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Day \(todayDay) · \(Routine.dayName(todayDay))")
                    .lineLimit(1)
                Image.pixel(.chevronDown, size: 16)
            }
            .font(.subheadline)
            .foregroundStyle(Color.brand)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color.ppLine.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .accessibilityLabel("Change day, currently Day \(todayDay), \(Routine.dayName(todayDay))")
    }

    private func heroAction() {
        Haptics.press()
        if workoutComplete {
            workout.finish()
            showSummary = true
        } else {
            // Start (or carry on) and open the next exercise on the Workout tab.
            if !workout.isInProgress {
                workout.start(day: todayDay)
                lastDay = todayDay
                lastTrainedAt = Date.now.timeIntervalSince1970
            }
            openNextRequested = true
            selectTab(.workout)
        }
    }

    /// About 2½ minutes per set (the set plus rest), rounded to 5 minutes.
    private func minutes(forSets sets: Int) -> Int {
        max(5, Int((Double(sets) * 2.5 / 5).rounded()) * 5)
    }

    /// "7 exercises · ~50 min" before you start; "9/21 sets · ~30 min left" during.
    private var planLine: String {
        if doneSets == 0 {
            let n = todayExercises.count
            return "\(n) \(n == 1 ? "exercise" : "exercises") · ~\(minutes(forSets: totalTargetSets)) min"
        }
        let left = max(totalTargetSets - doneSets, 0)
        return left == 0 ? "\(doneSets)/\(totalTargetSets) sets"
                         : "\(doneSets)/\(totalTargetSets) sets · ~\(minutes(forSets: left)) min left"
    }

    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Big title + which day it is
            VStack(alignment: .leading, spacing: 6) {
                Text(heroTitle)
                    .font(.pixel(DS.TextSize.jumbo, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if canPickDay, let reason = suggestion.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                HStack {
                    if canPickDay {
                        dayPicker
                    } else {
                        Text("Day \(todayDay) · \(Routine.dayName(todayDay))")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Text(planLine)
                        .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                        .foregroundStyle(Color.ppText.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 20)

            Rectangle()
                .fill(Color.ppLine.opacity(0.10))
                .frame(height: 1)
                .padding(.bottom, 20)

            // Just what's next (the whole list is on the Workout tab).
            if let next = nextExercise {
                nextExercisePeek(next)
                    .padding(.bottom, DS.Space.xl)
            }

            Button(action: heroAction) {
                HStack(spacing: DS.Space.s) {
                    Text(buttonTitle)
                    Image.pixel(.chevronRight)
                }
            }
            .buttonStyle(.primary)
        }
        .padding(24)
        .background(alignment: .top) {
            // Soft light glow at the top of the card.
            Ellipse()
                .fill(Color.ppMuted.opacity(0.4))
                .frame(width: 600, height: 260)
                .blur(radius: 90)
                .offset(y: -160)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous))
        .glassCard(cornerRadius: DS.Radius.hero)
        .animation(.spring, value: doneSets)
    }

    /// "NEXT · Squat · 0/3 · last 60 kg × 8" (or "FIRST" before you start).
    private func nextExercisePeek(_ name: String) -> some View {
        let target = Routine.targetSets(for: name, onDay: todayDay)
        let done = setsToday(name)
        return HStack(spacing: DS.Space.m) {
            Text(doneSets == 0 ? "FIRST" : "NEXT")
                .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                .foregroundStyle(Color.ppBackground)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs)
                .background(Color.ppText, in: Capsule())
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(name)
                    .font(.callout)
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                ExerciseStatusLine(done: done, target: target,
                                   last: done == 0 ? exercise(named: name)?.lastSet : nil)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Set progress in a fixed-width strip, so the row never grows:
/// 3 sets → 3 wide bars, 8 sets → 8 thin bars, more than 8 → one progress bar.
struct SetBars: View {
    let done: Int
    let target: Int
    var width: CGFloat = 56

    var body: some View {
        Group {
            if target > 8 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ppLine.opacity(0.25))
                        Capsule().fill(Color.ppText)
                            .frame(width: geo.size.width * min(Double(done) / Double(max(target, 1)), 1))
                    }
                }
            } else {
                HStack(spacing: target > 5 ? 2 : 4) {
                    ForEach(0..<max(target, 1), id: \.self) { i in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ppLine.opacity(0.25))
                            // Each dash fills left to right as its set is logged.
                            Capsule()
                                .fill(done >= target ? Color.ppDone : Color.ppText)
                                .scaleEffect(x: i < done ? 1 : 0.001, anchor: .leading)
                        }
                    }
                }
            }
        }
        .frame(width: width, height: 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: done)
        // Green isn't the only signal: VoiceOver says it too.
        .accessibilityElement()
        .accessibilityLabel(done >= target ? "\(done) of \(target) sets, done" : "\(done) of \(target) sets")
    }
}

/// Small number tile: icon, big pixel value, label.
struct StatTile: View {
    let value: String
    let label: String
    let icon: PixelGlyph
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image.pixel(icon)
                .foregroundStyle(color)
            Text(value)
                .font(.pixel(DS.TextSize.title, relativeTo: .title))
                .foregroundStyle(Color.ppText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.tile)
    }
}

// MARK: - Today tiles

/// Small square on Home: icon, big number, short label and an optional thin progress line.
struct TodayTile: View {
    let icon: PixelGlyph
    let tint: Color
    let value: String
    let label: String
    /// 0…1 (can go over 1), or nil for no line.
    let progress: Double?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Image.pixel(icon, size: 20)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ppLine.opacity(DS.Opacity.track))
                            Capsule().fill(progress > 1 ? Color.ppFlame : tint)
                                .frame(width: geo.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: DS.Space.xs)
                    .animation(DS.Motion.spring, value: progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.m)
            .glassCard(cornerRadius: DS.Radius.tile)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        }
        .buttonStyle(.squish)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Opened from the Challenges tile: your streak and today's three challenges.
struct ChallengesSheet: View {
    let streak: DailyStreakState
    let challenges: [DailyChallenge]
    @Environment(\.dismiss) private var dismiss
    @State private var loggingWeight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    StreakCard(state: streak)
                    PPHeader("Daily challenges")
                    DailyChallengesCard(challenges: challenges) { loggingWeight = true }
                    Text("Win one (or train) to keep your streak going.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.vertical, DS.Space.s)
            }
            .background(AppBackground())
            .navigationTitle("Today's challenges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $loggingWeight) { LogBodyWeightSheet() }
        }
        .presentationDetents([.medium, .large])
    }
}
