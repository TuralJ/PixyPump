import SwiftUI
import SwiftData

// MARK: - Workout missions card (Workout tab): "This workout"

struct WorkoutMissionsCard: View {
    let missions: [WorkoutMission]

    private var available: Int { missions.filter { !$0.done }.reduce(0) { $0 + $1.xp } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This workout")
                    .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                    .foregroundStyle(Color.ppText)
                Spacer()
                Text(available > 0 ? "+\(available) XP to grab" : "All done!")
                    .font(.pixel(DS.TextSize.caption))
                    .foregroundStyle(available > 0 ? Color.ppFat : Color.ppDone)
            }
            ForEach(missions) { mission in
                MissionRow(title: mission.title, detail: mission.detail, xp: mission.xp, done: mission.done)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .animation(.spring, value: missions.map(\.done))
    }
}

/// One checklist line: box, title, detail and XP.
struct MissionRow: View {
    let title: String
    let detail: String
    let xp: Int
    let done: Bool
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(done ? Color.ppDone : Color.clear)
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .strokeBorder(done ? Color.ppDone : Color.ppLine.opacity(0.3), lineWidth: 2)
                if done {
                    Image.pixel(.check, size: 14).foregroundStyle(Color.ppBackground)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .frame(width: 24, height: 24)
            // Completed: the box stamps in.
            .stamp(done)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: done)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(done ? .secondary : Color.ppText)
                    // …and a line sweeps through the title.
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary)
                            .frame(height: 1.5)
                            .scaleEffect(x: done ? 1 : 0.001, anchor: .leading)
                            .animation(.easeOut(duration: 0.35).delay(0.15), value: done)
                    }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress, !done {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ppLine.opacity(0.1))
                            Capsule().fill(Color.ppFat)
                                .frame(width: geo.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 2)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
                }
            }
            Spacer(minLength: 8)
            Text("+\(xp)")
                .font(.pixel(DS.TextSize.footnote))
                .foregroundStyle(done ? Color.ppDone : Color.ppFat)
                // The XP floats up the moment it's won.
                .xpPop(trigger: done ? 1 : 0, text: done ? "+\(xp) XP" : "")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail), \(xp) XP\(done ? ", done" : "")")
    }
}

// MARK: - Win pop-ups, shown over any screen

/// "Mission complete!" while you train and "Challenge won!" for daily challenges.
private struct MissionToastHost: ViewModifier {
    @Query(sort: \WorkoutSet.date) private var allSets: [WorkoutSet]
    @Query(sort: \FoodEntry.date) private var food: [FoodEntry]
    @AppStorage("goalKcal") private var goalKcal = 2500.0
    @AppStorage("goalProtein") private var goalProtein = 160.0
    @State private var toast: Toast?
    /// Whether today counted for the streak last time we looked (to celebrate the moment it does).
    @State private var wasSecured: Bool?
    /// Bumped whenever XP is paid here, so Home redraws with it.
    @AppStorage("rewardsVersion") private var rewardsVersion = 0
    @Environment(\.scenePhase) private var scenePhase
    private let workout = ActiveWorkout.shared

    struct Toast: Equatable {
        let id: String
        let kicker: String
        let title: String
        let xp: Int
    }

    /// Workout missions finished so far (only while a workout is running).
    private var doneMissionIDs: [String] {
        guard workout.isInProgress, let day = workout.day else { return [] }
        return WorkoutMissions.list(planDay: day, allSets: allSets, finishedEarly: false, minutes: nil)
            .filter(\.done).map(\.id)
    }

    private var daily: [DailyChallenge] {
        DailyChallenges.today(.init(sets: allSets, food: food, goalKcal: goalKcal, goalProtein: goalProtein))
    }

    private var doneDailyIDs: [String] { daily.filter(\.isDone).map(\.id) }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    HStack(spacing: 10) {
                        PixelBuddy(mood: .flex, size: 40, action: .flex)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(toast.kicker)
                                .font(.pixel(DS.TextSize.footnote))
                                .foregroundStyle(Color.ppDone)
                            Text(toast.title)
                                .font(.subheadline)
                                .foregroundStyle(Color.ppText)
                        }
                        Spacer(minLength: 8)
                        Text("+\(toast.xp) XP")
                            .font(.pixel(DS.TextSize.subhead))
                            .foregroundStyle(Color.ppFat)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.ppCard, in: RoundedRectangle(cornerRadius: DS.Radius.tile))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(Color.ppDone.opacity(0.6), lineWidth: 1.5))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { self.toast = nil } }
                    .accessibilityElement(children: .combine)
                }
            }
            .onChange(of: doneMissionIDs) { old, new in
                guard let id = new.first(where: { !old.contains($0) }), !old.isEmpty || new.count == 1,
                      let day = workout.day,
                      let mission = WorkoutMissions.list(planDay: day, allSets: allSets, finishedEarly: false, minutes: nil)
                        .first(where: { $0.id == id }) else { return }
                show(Toast(id: "m-\(id)", kicker: "Mission complete!", title: mission.title, xp: mission.xp))
            }
            .onChange(of: doneDailyIDs) { _, _ in refresh() }
            .onChange(of: allSets.count) { _, _ in refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh(silently: true) }
                // Leaving the app: plan the next week of nudges from today's progress.
                if phase == .background { NotificationPlanner.reschedule(sets: allSets) }
            }
            .onAppear {
                refresh(silently: true)
                NotificationPlanner.reschedule(sets: allSets)
            }
    }

    /// Pays out finished daily challenges and streak milestones (once each), celebrates them,
    /// and keeps the evening streak reminder up to date.
    private func refresh(silently: Bool = false) {
        let won = DailyChallenges.bank(daily)
        let swept = DailyChallenges.bankSweep(daily)
        let streak = DailyStreak.compute(sets: allSets)
        let milestone = DailyStreak.bankMilestones(streak)
        // Every streak milestone also earns a gym bag (it waits on Home until you open it).
        if let milestone { GymBag.addPending("streak:\(milestone)") }
        if !won.isEmpty || milestone != nil || swept { rewardsVersion += 1 }
        DailyStreak.updateReminder(streak)

        defer { wasSecured = streak.securedToday }
        guard !silently else { return }
        if let milestone {
            show(Toast(id: "s-\(milestone)", kicker: "\(milestone)-day streak! 🔥",
                       title: "You earned a gym bag 🎁", xp: DailyStreakState.milestoneXP(milestone)), sound: .levelUp)
        } else if wasSecured == false && streak.securedToday {
            show(Toast(id: "s-day", kicker: "Streak extended! 🔥",
                       title: "Day \(streak.current) secured" + (won.first.map { " · \($0.title)" } ?? ""),
                       xp: won.reduce(0) { $0 + $1.xp }), sound: .streak)
        } else if swept {
            show(Toast(id: "sweep", kicker: "Clean sweep! 🧹", title: "All 3 challenges won today",
                       xp: DailyChallenges.sweepXP + won.reduce(0) { $0 + $1.xp }), sound: .streak)
        } else if let first = won.first {
            show(Toast(id: "d-\(first.id)", kicker: "Challenge won!", title: first.title,
                       xp: won.reduce(0) { $0 + $1.xp }))
        }
    }

    private func show(_ item: Toast, sound: SFX = .mission) {
        Haptics.success()
        SFX.play(sound)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { toast = item }
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            withAnimation { if toast == item { toast = nil } }
        }
    }
}

extension View {
    /// Pops up "Mission complete!" and "Challenge won!" with your buddy.
    func missionToasts() -> some View { modifier(MissionToastHost()) }
}

// MARK: - Daily challenges card (Home)

struct DailyChallengesCard: View {
    let challenges: [DailyChallenge]
    /// Tapping the unfinished "Weigh in today" challenge opens the weigh-in sheet.
    var onWeighIn: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(challenges) { challenge in
                let row = MissionRow(title: challenge.title,
                                     detail: challenge.isDone ? "Won · XP added"
                                         : (challenge.id == "weigh" && onWeighIn != nil ? "Tap to log your weight" : challenge.detail),
                                     xp: challenge.xp, done: challenge.isDone, progress: challenge.progress)
                if challenge.id == "weigh", !challenge.isDone, let onWeighIn {
                    Button {
                        Haptics.tap()
                        onWeighIn()
                    } label: { row.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                } else {
                    row
                }
            }
            let done = challenges.filter(\.isDone).count
            Text(done == challenges.count ? "Clean sweep! +\(DailyChallenges.sweepXP) XP bonus won 🧹"
                 : done == challenges.count - 1 ? "One more for the clean sweep: +\(DailyChallenges.sweepXP) XP bonus"
                 : "Win all 3 for a +\(DailyChallenges.sweepXP) XP clean-sweep bonus.")
                .font(.caption2)
                .foregroundStyle(done >= challenges.count - 1 ? Color.ppFat : .secondary)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
    }
}

// MARK: - Duels card (workout summary)

struct DuelsCard: View {
    let duels: [ExerciseDuel]
    var setWins: Int = 0

    var body: some View {
        let won = duels.filter { $0.result == .win }.count
        let lost = duels.filter { $0.result == .lose }.count
        let tied = duels.count - won - lost
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Duels vs last time")
                    .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                    .foregroundStyle(Color.ppText)
                Spacer()
                Text("\(won)W · \(lost)L" + (tied > 0 ? " · \(tied)T" : ""))
                    .font(.pixel(DS.TextSize.footnote))
                    .foregroundStyle(won >= lost ? Color.ppDone : .secondary)
            }
            if setWins > 0 {
                Text("👻 Set duels won today: \(setWins)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(duels) { duel in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(duel.name).font(.subheadline).foregroundStyle(Color.ppText)
                        Text("\(Units.volume(duel.todayKg)) vs \(Units.volume(duel.lastKg)) \(Units.symbol)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    resultChip(duel.result)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
    }

    private func resultChip(_ result: DuelResult) -> some View {
        let (text, color): (String, Color) = {
            switch result {
            case .win: return ("WON +\(ExerciseDuels.xp)", Color.ppDone)
            case .tie: return ("TIE", Color.ppFat)
            case .lose: return ("NEXT TIME", Color.ppLine.opacity(0.5))
            }
        }()
        return Text(text)
            .font(.pixel(DS.TextSize.caption))
            .foregroundStyle(result == .lose ? Color.ppText.opacity(0.7) : Color.ppBackground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(result == .lose ? Color.ppLine.opacity(0.1) : color, in: Capsule())
    }
}

// MARK: - Weekly missions card (Home)

struct WeeklyMissionsCard: View {
    let missions: [WeeklyMission]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(missions) { mission in
                MissionRow(title: mission.title,
                           detail: mission.isDone ? "Done · XP added" : "\(mission.detail) \(mission.progressText)",
                           xp: mission.xp, done: mission.isDone, progress: mission.progress)
            }
            let done = missions.filter(\.isDone).count
            Text(done == missions.count ? "Clean sweep! +\(WeeklyMissions.sweepXP) XP and a gym bag won 🎁"
                 : "\(done)/\(missions.count) weekly missions done · finish all 3 for +\(WeeklyMissions.sweepXP) XP and a gym bag")
                .font(.caption2)
                .foregroundStyle(done >= missions.count - 1 ? Color.ppFat : .secondary)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
    }
}

// MARK: - XP earned (workout summary)

struct XPEarnedCard: View {
    let lines: [XPLine]
    let multiplier: Double
    let total: Int
    /// Bonus lines paid on top (weekly missions, chapters).
    var bonus: [XPLine] = []
    var xpBefore: Int? = nil
    var xpAfter: Int? = nil
    var animate = true

    @State private var shown = 0
    @State private var barProgress: Double = 0
    @State private var counted = 0

    private var allLines: [XPLine] { lines + bonus }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("XP earned")
                    .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                    .foregroundStyle(Color.ppText)
                Spacer()
                Text("+\(animate ? counted : total + bonus.reduce(0) { $0 + $1.xp })")
                    .font(.pixel(DS.TextSize.title, relativeTo: .title))
                    .foregroundStyle(Color.ppFat)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            VStack(spacing: 8) {
                ForEach(Array(allLines.enumerated()), id: \.offset) { index, line in
                    if !animate || index < shown {
                        HStack {
                            Text(line.label).font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text("+\(line.xp)").font(.pixel(DS.TextSize.footnote)).foregroundStyle(Color.ppText)
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                if multiplier > 1 && (!animate || shown >= allLines.count) {
                    HStack {
                        // Weeks in a row on plan (not the daily 🔥 streak).
                        Text("Weeks-on-plan bonus").font(.subheadline).foregroundStyle(Color.brand)
                        Spacer()
                        Text("×" + String(format: "%.1f", multiplier)).font(.pixel(DS.TextSize.footnote)).foregroundStyle(Color.brand)
                    }
                    .transition(.opacity)
                }
            }
            if let xpBefore, let xpAfter {
                let before = Level(xp: xpBefore), after = Level(xp: xpAfter)
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ppLine.opacity(0.12))
                            Capsule().fill(Color.ppFat).frame(width: geo.size.width * barProgress)
                        }
                    }
                    .frame(height: 10)
                    Text(after.number > before.number
                         ? "Level up! You're now Level \(after.number) · \(after.title)"
                         : "Level \(after.number) · \(after.xpToNext.spaced) XP to Level \(after.number + 1)")
                        .font(.caption)
                        .foregroundStyle(after.number > before.number ? Color.ppFat : .secondary)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .onAppear(perform: play)
    }

    private func play() {
        let grand = total + bonus.reduce(0) { $0 + $1.xp }
        guard animate else {
            counted = grand
            if let xpAfter { barProgress = Level(xp: xpAfter).progress }
            return
        }
        if let xpBefore { barProgress = Level(xp: xpBefore).progress }
        Task {
            for i in 1...max(allLines.count, 1) {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { shown = i }
                Haptics.select()
            }
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.6)) { counted = grand }
            if let xpBefore, let xpAfter {
                let before = Level(xp: xpBefore), after = Level(xp: xpAfter)
                if after.number > before.number {
                    withAnimation(.easeIn(duration: 0.5)) { barProgress = 1 }
                    try? await Task.sleep(for: .milliseconds(550))
                    barProgress = 0
                    Haptics.success()
                    SFX.play(.levelUp)
                }
                withAnimation(.easeOut(duration: 0.7)) { barProgress = after.progress }
            }
        }
    }
}

// MARK: - Gym bag

struct GymBagCard: View {
    /// You finished every set (otherwise the bag stays locked).
    let earned: Bool
    /// What it gave, if already opened.
    let openedPrize: String?
    let open: () -> GymBag.Result

    @State private var showBag = false
    @State private var result: GymBag.Result?

    var body: some View {
        HStack(spacing: 14) {
            PixelBag(open: openedPrize != nil || result != nil)
                .frame(width: 64, height: 64)
                .opacity(earned ? 1 : 0.35)
                // Unopened: a gentle wiggle so it's hard to miss.
                .wobble(earned && openedPrize == nil && result == nil, degrees: 6)

            VStack(alignment: .leading, spacing: 4) {
                if let result {
                    Text("\(result.rarity.bagName): \(result.prize.title)")
                        .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                        .foregroundStyle(Color(hex: result.rarity.hex))
                    Text(result.prize.detail).font(.caption).foregroundStyle(.secondary)
                } else if let openedPrize {
                    Text("Gym bag opened").font(.pixel(DS.TextSize.body, relativeTo: .subheadline)).foregroundStyle(Color.ppText)
                    Text("You got: \(openedPrize)").font(.caption).foregroundStyle(.secondary)
                } else if earned {
                    Text("Gym bag earned!").font(.pixel(DS.TextSize.body, relativeTo: .subheadline)).foregroundStyle(Color.ppText)
                    Text("For finishing every set. Common, rare, epic or legendary?")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Gym bag locked").font(.pixel(DS.TextSize.body, relativeTo: .subheadline)).foregroundStyle(Color.ppText)
                    Text("Finish every set next time to earn one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if earned && openedPrize == nil && result == nil {
                Button {
                    Haptics.press()
                    showBag = true
                } label: {
                    Text("Open")
                        .font(.pixel(DS.TextSize.subhead))
                        .foregroundStyle(Color.ppBackground)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color.ppFat, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .fullScreenCover(isPresented: $showBag) {
            MysteryBagView(subtitle: "Workout reward", open: open) { opened in
                if let opened { result = opened }
            }
        }
    }
}

/// A little pixel duffel bag.
struct PixelBag: View {
    var open = false

    private static let rows = [
        "................",
        "................",
        "......kkkk......",
        ".....k....k.....",
        ".....k....k.....",
        "..kkkkkkkkkkkk..",
        ".kbbbbbbbbbbbbk.",
        ".kbwwwwwwwwwwbk.",
        ".kbbbbbbbbbbbbk.",
        ".kbbbbbyybbbbbk.",
        ".kbbbbbyybbbbbk.",
        ".kbbbbbbbbbbbbk.",
        ".kdbbbbbbbbbbdk.",
        "..kkkkkkkkkkkk..",
        "................",
        "................",
    ]

    var body: some View {
        let palette: [Character: Color] = [
            "k": Color(hex: 0x05090A), "b": Color.brand, "d": Color(hex: 0x78AFD7),   // ds-allow: pixel-art palette
            "w": open ? Color(hex: 0x05090A) : .white, "y": Color(hex: 0xFFC94A),   // ds-allow: pixel-art palette
        ]
        Canvas { context, size in
            let cell = size.width / 16
            for (y, row) in Self.rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let color = palette[ch] else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                             width: cell + 0.3, height: cell + 0.3)), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Journey card (Home and summary)

struct JourneyCard: View {
    let progress: Journey.Progress

    var body: some View {
        let chapter = progress.current
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("CH \(chapter.number)")
                        .font(.pixel(DS.TextSize.caption))
                        .foregroundStyle(Color.ppBackground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.brand, in: Capsule())
                    Text(chapter.name)
                        .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                        .foregroundStyle(Color.ppText)
                }
                JourneyPips(total: chapter.nodes, done: progress.step)
                Text(progress.atBoss
                     ? "Boss next: finish every set in your next workout to beat it"
                     : "\(progress.stepsToBoss) \(progress.stepsToBoss == 1 ? "workout" : "workouts") to the boss")
                    .font(.caption)
                    .foregroundStyle(progress.atBoss ? Color.ppFat : .secondary)
            }
            Spacer(minLength: 0)
            Image.pixel(.chevronRight, size: 16).foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
    }
}

struct JourneyPips: View {
    let total: Int
    let done: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                let boss = i == total - 1
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < done ? Color.ppDone : (i == done ? Color.brand : Color.ppLine.opacity(0.15)))
                    .frame(width: boss ? 14 : 10, height: boss ? 14 : 10)
                    .overlay {
                        if boss { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.ppFat, lineWidth: 1.5) }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(done + 1) of \(total)")
    }
}
