import SwiftUI
import SwiftData
import UserNotifications

/// "Workout done" screen: time, sets, volume and new records,
/// with a pixel share card and (optionally) saving to Apple Health.
struct WorkoutSummaryView: View {
    /// Which day to summarise (today by default).
    var day: Date = .now
    /// Celebrate with a message and confetti (when you've just finished, not when looking back).
    var celebrate = true

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSet.date) private var allSets: [WorkoutSet]
    @AppStorage(Prefs.unit) private var unitRaw = "kg"
    @AppStorage(HealthSync.enabledKey) private var healthOn = false
    @State private var healthMessage: String?
    @State private var savingToHealth = false
    @State private var shareImage: Image?
    @State private var newBadges: [Badge] = []
    @AppStorage(Prefs.userName) private var userName = ""
    @State private var message: FinishMessage?
    // Rewards for this workout.
    @State private var reward: WorkoutReward?
    @State private var bonusLines: [XPLine] = []
    @State private var xpBefore: Int?
    @State private var xpAfter: Int?
    @State private var bagPrize: String?
    @State private var journey: Journey.Progress?
    /// Looking back from History: what this workout earned at the time.
    @State private var storedEntry: XPEntry?
    /// Each exercise vs last time.
    @State private var duels: [ExerciseDuel] = []
    @State private var setDuelWins = 0
    /// Notification permission, to offer reminders at this happy moment (only if never asked).
    @State private var notificationStatus: UNAuthorizationStatus?

    private var session: WorkoutSession? {
        let start = Calendar.current.startOfDay(for: day)
        return WorkoutSession.all(from: allSets).first { $0.day == start }
    }

    /// Start → Finish time when you used the buttons today, otherwise first → last set.
    private var minutes: Int? {
        if let session, Calendar.current.isDateInToday(session.day),
           let timed = ActiveWorkout.shared.minutesToday {
            return timed
        }
        return session?.minutes
    }

    /// The previous session on the same plan day, to compare against.
    private var previous: WorkoutSession? {
        guard let session, let planDay = session.routineDay else { return nil }
        return WorkoutSession.all(from: allSets).first { $0.day < session.day && $0.routineDay == planDay }
    }

    struct Record: Identifiable {
        let id = UUID()
        let name: String
        let kind: String
        let value: String
    }

    /// Records set in this workout: heaviest weight, best estimated 1-rep max,
    /// most reps at a weight, and the biggest workout ever.
    private var records: [Record] {
        guard let session else { return [] }
        var list: [Record] = session.exercises.compactMap { log -> Record? in
            guard let exercise = log.exercise else { return nil }
            let today = log.sets.filter { !$0.isWarmup && $0.weight > 0 }
            let before = exercise.workingSets.filter { $0.date < session.day && $0.weight > 0 }
            guard !before.isEmpty,
                  let heaviest = today.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { return nil }
            let bestWeight = before.map(\.weight).max() ?? 0
            if heaviest.weight > bestWeight + 0.01 {
                return Record(name: log.name, kind: "Heaviest ever",
                              value: "\(Units.weight(heaviest.weight)) × \(heaviest.reps)")
            }
            let bestMax = before.map(\.estimatedMax).max() ?? 0
            if let top = today.max(by: { $0.estimatedMax < $1.estimatedMax }), top.estimatedMax > bestMax + 0.01 {
                return Record(name: log.name, kind: "Best estimated 1-rep max",
                              value: Units.weight(top.estimatedMax))
            }
            for set in today.sorted(by: { $0.reps > $1.reps }) {
                let previous = before.filter { abs($0.weight - set.weight) < 0.01 }.map(\.reps).max()
                if let previous, set.reps > previous {
                    return Record(name: log.name, kind: "Most reps at \(Units.weight(set.weight))",
                                  value: "\(set.reps) reps")
                }
            }
            return nil
        }
        let earlier = WorkoutSession.all(from: allSets).filter { $0.day < session.day }
        if let bestVolume = earlier.map(\.volume).max(), session.volume > bestVolume {
            list.append(Record(name: "Whole workout", kind: "Biggest workout ever",
                               value: "\(Units.volume(session.volume)) \(Units.symbol)"))
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let session {
                    content(session)
                } else {
                    EmptyStateCard(icon: .dumbbell,
                                   title: "Nothing logged yet",
                                   message: "Log a set and your workout summary shows up here.")
                        .padding(16)
                }
            }
            .scrollIndicators(.hidden)
            .overlay { if message != nil { PixelConfetti() } }
            .background(AppBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Apple Health", isPresented: Binding(get: { healthMessage != nil },
                                                       set: { if !$0 { healthMessage = nil } })) {
                Button("OK") { healthMessage = nil }
            } message: {
                Text(healthMessage ?? "")
            }
            .task(id: session?.setCount) { renderShareImage() }
            .task {
                guard celebrate else { return }
                notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
            .task {
                if !celebrate, let session {
                    storedEntry = XPLedger.entry(on: session.day)
                    duels = ExerciseDuels.list(on: session.day, allSets: allSets)
                }
            }
            // One big moment at a time: Home holds a level-up or bag until this closes.
            .onDisappear { MomentQueue.shared.isBusy = false }
            .onAppear {
                MomentQueue.shared.isBusy = true
                // Celebrate badges earned since you last looked (once).
                let fresh = BadgeLog.newlyEarned(GameStats(allSets: allSets))
                if !fresh.isEmpty {
                    newBadges = fresh
                    BadgeLog.markSeen(fresh.map(\.id))
                }
                if celebrate, message == nil, let session {
                    message = makeMessage(session)
                    if Calendar.current.isDateInToday(session.day) { grantReward(session) }
                    Haptics.success()
                    SFX.play(.workoutComplete)
                } else if !fresh.isEmpty {
                    Haptics.success()
                }
            }
        }
    }

    /// Works out and saves this workout's XP, pays out finished weekly missions
    /// and journey chapters, and remembers the before/after for the XP bar.
    private func grantReward(_ session: WorkoutSession) {
        let before = GameStats(allSets: allSets)
        let earlier = XPLedger.entry(on: session.day)
        xpBefore = before.xp - (before.dayXP[session.day] ?? 0)
        let workout = ActiveWorkout.shared
        let missions: [WorkoutMission] = (workout.day ?? session.routineDay).map {
            WorkoutMissions.list(planDay: $0, on: session.day, allSets: allSets,
                                 finishedEarly: workout.finishedEarlyToday, minutes: minutes)
        } ?? []
        // A week or more since your last workout: comeback bonus (double XP).
        let previousDay = before.days.last { $0 < session.day }
        let comeback = previousDay.map {
            (Calendar.current.dateComponents([.day], from: $0, to: session.day).day ?? 0) >= 7
        } ?? false
        let earned = WorkoutReward.make(missions: missions, recordCount: records.count,
                                        volumeKg: session.volume, streakWeeks: before.streak.current,
                                        comeback: comeback)
        XPLedger.set(XPEntry(total: earned.total, completed: earned.completed, lines: earned.lines,
                             multiplier: earned.multiplier, bag: earlier?.bag), on: session.day)
        duels = ExerciseDuels.list(on: session.day, allSets: allSets)
        setDuelWins = SetDuel.winsToday()
        let duelXP = ExerciseDuels.bank(duels, on: session.day)
        let middle = GameStats(allSets: allSets)
        bonusLines = duelXP + WeeklyMissions.bank(WeeklyMissions.current(stats: middle)) + Journey.bank(middle.journey)
        let after = GameStats(allSets: allSets)
        xpAfter = after.xp
        journey = after.journey
        bagPrize = earlier?.bag
        reward = earned
    }

    private func openBag(on day: Date) -> GymBag.Result {
        let result = GymBag.open(on: day, shieldsLeft: GameStats(allSets: allSets).streak.shieldsLeft)
        if case .xp(let xp) = result.prize { xpAfter = (xpAfter ?? 0) + xp }
        xpAfter = (xpAfter ?? 0) + result.bonusXP
        return result
    }

    private func makeMessage(_ session: WorkoutSession) -> FinishMessage {
        let stats = GameStats(allSets: allSets)
        let cal = Calendar.current
        let before = WorkoutSession.all(from: allSets).first { $0.day < session.day }
        let gap = before.flatMap { cal.dateComponents([.day], from: $0.day, to: session.day).day }
        let facts = FinishMessage.Facts(
            name: userName.trimmingCharacters(in: .whitespaces),
            workoutCount: stats.days.filter { $0 <= session.day }.count,
            recordCount: records.count,
            volumeChangeKg: previous.map { session.volume - $0.volume },
            daysSinceLast: gap,
            streakWeeks: stats.streak.current,
            minutes: minutes,
            seed: cal.ordinality(of: .day, in: .era, for: session.day) ?? 0)
        return FinishMessage.make(facts)
    }

    private func content(_ session: WorkoutSession) -> some View {
        // Results first (what you did, records, how it compares), then one rewards area,
        // then the smaller extras. The reminder offer comes last.
        VStack(alignment: .leading, spacing: 20) {
            if let message {
                CelebrationHeader(message: message)
            }
            SummaryCardView(session: session, minutes: minutes, recordCount: records.count,
                            showTitle: message == nil)

            // Earned a gym bag? Right under your stats, so it's still visible without scrolling.
            if let reward, reward.completed {
                GymBagCard(earned: true, openedPrize: bagPrize) { openBag(on: session.day) }
                    .staggeredAppear(0)
            }

            if !records.isEmpty {
                recordsCard
            }

            if let previous {
                volumeComparison(session, previous: previous)
            }

            // Rewards: XP, the bag (if not earned), duels and your journey, together.
            if let reward {
                XPEarnedCard(lines: reward.lines, multiplier: reward.multiplier, total: reward.total,
                             bonus: bonusLines, xpBefore: xpBefore, xpAfter: xpAfter)
                if !reward.completed {
                    GymBagCard(earned: false, openedPrize: bagPrize) { openBag(on: session.day) }
                }
                if !duels.isEmpty || setDuelWins > 0 {
                    DuelsCard(duels: duels, setWins: setDuelWins)
                }
                if let journey {
                    NavigationLink {
                        JourneyView()
                    } label: {
                        JourneyCard(progress: journey)
                    }
                    .buttonStyle(.plain)
                }
            } else if let storedEntry {
                XPEarnedCard(lines: storedEntry.lines, multiplier: storedEntry.multiplier,
                             total: storedEntry.total, animate: false)
            }
            if reward == nil && !duels.isEmpty {
                DuelsCard(duels: duels)
            }

            if let planDay = session.routineDay, Calendar.current.isDateInToday(session.day) {
                let skipped = TodayChanges.shared.skipped(in: Routine.exercises(onDay: planDay), day: planDay)
                if !skipped.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image.pixel(.close, size: 16).foregroundStyle(.secondary)
                        Text("Skipped today: " + skipped.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: DS.Radius.card)
                }
            }

            if !newBadges.isEmpty {
                NewBadgesCard(badges: newBadges)
            }

            VStack(spacing: 12) {
                if let shareImage {
                    ShareLink(item: shareImage,
                              preview: SharePreview("My \(AppInfo.name) workout", image: shareImage)) {
                        HStack(spacing: 8) {
                            Image.pixel(.share, size: 16)
                            Text("Share")
                        }
                    }
                    .buttonStyle(.primary)
                }

                if healthOn && HealthSync.isConfigured {
                    Button { saveToHealth(session) } label: {
                        HStack(spacing: 8) {
                            Image.pixel(.heart, size: 16)
                            Text(HealthSync.alreadySaved(session.day) ? "Saved to Apple Health" : "Save to Apple Health")
                        }
                        .font(.pixel(DS.TextSize.callout))
                        .foregroundStyle(Color.ppText)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.ppLine.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(savingToHealth || HealthSync.alreadySaved(session.day))
                }
            }

            // Offer reminders at this happy moment (only if we've never asked).
            if reward != nil && notificationStatus == .notDetermined {
                ReminderPromptCard {
                    let granted = (try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                    notificationStatus = granted ? .authorized : .denied
                    if granted { NotificationPlanner.reschedule(sets: allSets) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// Records you set today, right below the stats.
    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PPHeader("New PRs")
            ForEach(records) { record in
                HStack(spacing: 12) {
                    Image.pixel(.trophy, size: 16).foregroundStyle(Color.ppFat)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.name).foregroundStyle(Color.ppText)
                        Text(record.kind).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(record.value)
                        .font(.pixel(DS.TextSize.body))
                        .foregroundStyle(Color.ppFat)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
    }

    /// "1,200 kg more than last Push" — compared with the last time you did this plan day.
    private func volumeComparison(_ session: WorkoutSession, previous: WorkoutSession) -> some View {
        let change = session.volume - previous.volume
        return HStack(spacing: 12) {
            Image.pixel(.trendingUp)
                .foregroundStyle(change >= 0 ? Color.ppDone : Color.ppCarbs)
            Text(change >= 0
                 ? "\(Units.volume(change)) \(Units.symbol) more than last \(session.title.components(separatedBy: " · ").last ?? "time")"
                 : "\(Units.volume(-change)) \(Units.symbol) less than last time — rest well and come back stronger")
                .font(.subheadline)
                .foregroundStyle(Color.ppText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: DS.Radius.card)
    }

    private func saveToHealth(_ session: WorkoutSession) {
        guard var start = session.sets.first?.date, let lastSet = session.sets.last?.date else { return }
        var end = lastSet.addingTimeInterval(120)   // a couple of minutes for the last rest
        if Calendar.current.isDateInToday(session.day),
           case let .finished(startedAt, finishedAt) = ActiveWorkout.shared.phase {
            start = startedAt
            end = finishedAt
        }
        savingToHealth = true
        Task {
            do {
                try await HealthSync.saveWorkout(start: start, end: end)
                Haptics.success()
                healthMessage = "Saved as a strength training workout."
            } catch {
                healthMessage = error.localizedDescription
            }
            savingToHealth = false
        }
    }

    /// Turns the summary card into a picture for sharing.
    private func renderShareImage() {
        guard let session else { shareImage = nil; return }
        let card = SummaryCardView(session: session, minutes: minutes, recordCount: records.count,
                                   forSharing: true, level: GameStats(allSets: allSets).level)
            .frame(width: 360)
            .padding(20)
            .background(Color.ppBackground)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }
}

/// The big pixel summary card (also used as the share picture).
private struct SummaryCardView: View {
    let session: WorkoutSession
    let minutes: Int?
    let recordCount: Int
    var forSharing = false
    /// Hidden under the celebration headline, so it doesn't say "done" twice.
    var showTitle = true
    /// Shown on the share picture, game-score style.
    var level: Level? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if forSharing {
                HStack(spacing: 12) {
                    PixelBuddy(mood: .flex, size: 56, animated: false)
                    if let level {
                        Text("LV \(level.number) · \(level.title.uppercased())")
                            .font(.pixel(DS.TextSize.subhead))
                            .foregroundStyle(Color.ppFat)
                    }
                }
            }
            if forSharing || showTitle {
                Text(forSharing ? "WORKOUT COMPLETE" : "Workout done")
                    .font(.pixel(DS.TextSize.display, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text("\(session.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(session.title)")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)

            Rectangle().fill(Color.ppLine.opacity(0.1)).frame(height: 1)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                // On screen the totals tick up one after another; the share picture stays still.
                stat(minutes.map { "\($0)" } ?? "–", "minutes", count: minutes, delay: 0.2)
                stat("\(session.sets.filter { !$0.isWarmup }.count)", "sets",
                     count: session.sets.filter { !$0.isWarmup }.count, delay: 0.45)
                stat(Units.volume(session.volume), "\(Units.symbol) lifted",
                     count: Int(Units.display(session.volume).rounded()), delay: 0.7)
                stat("\(recordCount)", recordCount == 1 ? "new record" : "new records",
                     count: recordCount, delay: 0.95)
            }

            if forSharing {
                HStack(spacing: 6) {
                    Image.pixel(.dumbbell, size: 16)
                    Text(AppInfo.name.uppercased()).font(.pixel(DS.TextSize.footnote))
                    Spacer()
                    Text("PRESS START").font(.pixel(DS.TextSize.caption)).foregroundStyle(Color.ppFat)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: DS.Radius.hero)
    }

    @ViewBuilder
    private func statValue(_ value: String, count: Int?, delay: Double) -> some View {
        if !forSharing, let count, count > 0 {
            CountUpText(target: count, font: .pixel(DS.TextSize.title, relativeTo: .title), delay: delay, duration: 0.7, ticks: true)
        } else {
            Text(value)
                .font(.pixel(DS.TextSize.title, relativeTo: .title))
                .foregroundStyle(Color.ppText)
        }
    }

    private func stat(_ value: String, _ label: String, count: Int? = nil, delay: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            statValue(value, count: count, delay: delay)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
    }
}
