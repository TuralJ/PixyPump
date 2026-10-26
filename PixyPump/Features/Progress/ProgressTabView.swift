import SwiftUI
import SwiftData
import Charts

/// Progress tab: are you getting stronger? This week (missions, Journey), overview, body weight,
/// quick links to history, PRs and every exercise, then weekly volume, strength gains and achievements.
struct ProgressTabView: View {
    @Query(sort: \WorkoutSet.date) private var sets: [WorkoutSet]
    @Query private var exercises: [Exercise]
    @AppStorage(Prefs.unit) private var unitRaw = "kg"
    /// Weekly volume bars grow up from zero the first time you see them.
    @State private var barsGrown = false
    @State private var loggingWeight = false
    @State private var showYear = false
    @AppStorage("rewardsVersion") private var rewardsVersion = 0
    private let bodyWeight = BodyWeightStore.shared
    private let calendar = Calendar.current

    // MARK: Data

    private var working: [WorkoutSet] { sets.filter { !$0.isWarmup } }

    private var trainingDays: [Date] {
        Array(Set(working.map { calendar.startOfDay(for: $0.date) })).sorted()
    }

    private func weekStart(_ date: Date) -> Date {
        var cal = calendar
        cal.firstWeekday = 2   // Monday
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private struct Week: Identifiable {
        let start: Date
        let volume: Double
        let workouts: Int
        var id: Date { start }
    }

    /// The last 12 weeks, oldest first (empty weeks included).
    private var weeks: [Week] {
        let thisWeek = weekStart(.now)
        let starts = (0..<12).reversed().compactMap { calendar.date(byAdding: .day, value: -7 * $0, to: thisWeek) }
        let byWeek = Dictionary(grouping: working) { weekStart($0.date) }
        return starts.map { start in
            let list = byWeek[start] ?? []
            return Week(start: start,
                        volume: list.reduce(0) { $0 + $1.volume },
                        workouts: Set(list.map { calendar.startOfDay(for: $0.date) }).count)
        }
    }

    private func workouts(inMonthOf date: Date) -> Int {
        trainingDays.filter { calendar.isDate($0, equalTo: date, toGranularity: .month) }.count
    }

    private struct Gain: Identifiable {
        let exercise: Exercise
        let first: Double      // best estimated max on the first day (kg)
        let latest: Double     // best estimated max on the most recent day (kg)
        let firstDay: Date
        let sessions: Int
        var id: PersistentIdentifier { exercise.persistentModelID }
        var change: Double { latest - first }
    }

    /// Your most-trained exercises: estimated 1-rep max then vs now.
    private var gains: [Gain] {
        exercises.compactMap { exercise -> Gain? in
            let list = exercise.workingSets.filter { $0.weight > 0 }
            let byDay = Dictionary(grouping: list) { calendar.startOfDay(for: $0.date) }
            guard byDay.count >= 2,
                  let firstDay = byDay.keys.min(), let lastDay = byDay.keys.max(),
                  let first = byDay[firstDay]?.map(\.estimatedMax).max(),
                  let latest = byDay[lastDay]?.map(\.estimatedMax).max()
            else { return nil }
            return Gain(exercise: exercise, first: first, latest: latest, firstDay: firstDay, sessions: byDay.count)
        }
        .sorted { $0.sessions == $1.sessions ? $0.change > $1.change : $0.sessions > $1.sessions }
        .prefix(5)
        .map { $0 }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // This week first: the goals still in play (moved here from Home).
                    if !working.isEmpty {
                        thisWeek.staggeredAppear(0)
                    }
                    if working.isEmpty {
                        EmptyStateCard(icon: .chart,
                                       title: "Your progress lives here",
                                       message: "Log a few workouts and you'll see how much you lift each week, how much stronger you're getting, and your records.")
                    } else {
                        overview.staggeredAppear(0)
                    }
                    // Near the top so it's easy to find.
                    bodyWeightSection.staggeredAppear(1)
                    // History and PRs are used often, so they sit high up rather than at the very bottom.
                    moreLinks.staggeredAppear(2)
                    if !working.isEmpty {
                        weeklyChart.staggeredAppear(3)
                        if !gains.isEmpty { strength.staggeredAppear(4) }
                        achievements.staggeredAppear(5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton()
                }
            }
            .sheet(isPresented: $loggingWeight) { LogBodyWeightSheet() }
            .fullScreenCover(isPresented: $showYear) { YearReviewView() }
        }
    }

    // MARK: Sections

    /// "This week": workouts and weight lifted, weekly missions and the Journey.
    private var thisWeek: some View {
        let _ = rewardsVersion   // redraw when missions pay out
        let stats = GameStats(allSets: sets)
        let current = weeks.last
        let planned = max(Routine.days.count, 1)
        return VStack(alignment: .leading, spacing: 14) {
            PPHeader("This week")
            HStack(spacing: 12) {
                StatTile(value: "\(current?.workouts ?? 0)/\(planned)",
                         label: "workouts", icon: .calendar, color: .ppFlame)
                StatTile(value: Units.volume(current?.volume ?? 0),
                         label: "\(Units.symbol) lifted", icon: .dumbbell, color: .brand)
            }
            if Routine.dayCount > 0 {
                WeeklyMissionsCard(missions: WeeklyMissions.current(stats: stats))
            }
            NavigationLink {
                JourneyView()
            } label: {
                JourneyCard(progress: stats.journey)
            }
            .buttonStyle(.squish)
        }
    }

    private var overview: some View {
        let thisMonth = workouts(inMonthOf: .now)
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: .now).map { workouts(inMonthOf: $0) } ?? 0
        let totalVolume = working.reduce(0) { $0 + $1.volume }
        return VStack(alignment: .leading, spacing: 14) {
            PPHeader("Since you started")
            HStack(spacing: 12) {
                StatTile(value: "\(trainingDays.count)",
                         label: trainingDays.count == 1 ? "workout" : "workouts",
                         icon: .dumbbell, color: .brand)
                StatTile(value: Units.volume(totalVolume),
                         label: "\(Units.symbol) lifted", icon: .trendingUp, color: .ppDone)
            }
            Text(monthText(this: thisMonth, last: lastMonth))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func monthText(this: Int, last: Int) -> String {
        let first = trainingDays.first.map { "Training since \($0.formatted(.dateTime.day().month(.wide).year()))" } ?? ""
        let month = "\(this) \(this == 1 ? "workout" : "workouts") this month (\(last) last month)"
        return first.isEmpty ? month : "\(month) · \(first)"
    }

    private var weeklyChart: some View {
        let data = weeks
        let current = data.last
        let previous = data.dropLast().last
        return VStack(alignment: .leading, spacing: 14) {
            PPHeader("Weekly volume")
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Units.volume(current?.volume ?? 0)) \(Units.symbol)")
                        .font(.pixel(DS.TextSize.title, relativeTo: .title2))
                        .foregroundStyle(Color.ppText)
                    Text("this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let previous, previous.volume > 0, let current {
                        let change = (current.volume - previous.volume) / previous.volume * 100
                        Text("\(change >= 0 ? "+" : "")\(Int(change.rounded()))% vs last week")
                            .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                            .foregroundStyle(change >= 0 ? Color.ppDone : Color.secondary)
                            .accessibilityLabel("\(change >= 0 ? "Up" : "Down") \(abs(Int(change.rounded()))) percent versus last week")
                    }
                }
                let top = max(data.map { Units.display($0.volume) }.max() ?? 0, 1)
                Chart(data) { week in
                    // This week's bar is drawn in a different colour; VoiceOver says so in words.
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear),
                            y: .value(Units.symbol, barsGrown ? Units.display(week.volume) : 0))
                        .foregroundStyle(week.start == current?.start ? Color.ppText : Color.brand.opacity(0.7))
                        .cornerRadius(3)
                        .accessibilityLabel(week.start == current?.start
                                            ? "This week"
                                            : "Week of \(week.start.formatted(.dateTime.day().month(.abbreviated)))")
                        .accessibilityValue("\(Units.volume(week.volume)) \(Units.symbol)")
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.ppLine.opacity(0.08))
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: 0...(top * 1.1))
                .frame(height: 160)
                .onAppear {
                    guard !barsGrown else { return }
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.15)) { barsGrown = true }
                }
                Text("Weight × reps of all your sets. Up over the weeks = getting stronger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .glassCard(cornerRadius: DS.Radius.card)
        }
    }

    private var strength: some View {
        VStack(alignment: .leading, spacing: 14) {
            PPHeader("Getting stronger")
            VStack(spacing: 0) {
                ForEach(Array(gains.enumerated()), id: \.element.id) { index, gain in
                    NavigationLink {
                        ExerciseDetailView(exercise: gain.exercise)
                    } label: {
                        gainRow(gain)
                    }
                    .buttonStyle(.plain)
                    if index < gains.count - 1 {
                        Rectangle().fill(Color.ppLine.opacity(0.08)).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glassCard(cornerRadius: DS.Radius.card)
            Text("Estimated 1-rep max, first day vs latest.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func gainRow(_ gain: Gain) -> some View {
        let up = Units.display(gain.change)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(gain.exercise.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                Text("\(Units.weight(gain.first)) → \(Units.weight(gain.latest)) · since \(gain.firstDay.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(changeLabel(up))
                .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                .foregroundStyle(up > 0 ? Color.ppDone : Color.secondary)
            Image.pixel(.chevronRight, size: 16)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func changeLabel(_ value: Double) -> String {
        if value > 0 { return "+" + value.plain }
        if value < 0 { return "−" + abs(value).plain }
        return "±0"
    }

    /// Level, badges and the year-in-review.
    private var achievements: some View {
        let stats = GameStats(allSets: sets)
        let earned = Badge.all.filter { $0.earned(stats) }
        return VStack(alignment: .leading, spacing: 14) {
            PPHeader("Achievements")
            NavigationLink {
                BadgeBookView()
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("LV \(stats.level.number) · \(stats.level.title.uppercased())")
                            .font(.pixel(DS.TextSize.body, relativeTo: .headline))
                            .foregroundStyle(Color.ppFat)
                        Spacer()
                        Text("\(earned.count)/\(Badge.all.count) badges")
                            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                        Image.pixel(.chevronRight, size: 16).foregroundStyle(.secondary)
                    }
                    XPBar(progress: stats.level.progress, segments: 20)
                    Text("👻 Duels won: \(SetDuel.totalWins) sets · \(ExerciseDuels.totalWins) exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        // Earned ones first.
                        let earnedIDs = Set(earned.map(\.id))
                        let ordered = earned + Badge.all.filter { !earnedIDs.contains($0.id) }
                        ForEach(Array(ordered.prefix(6))) { badge in
                            BadgeSticker(badge: badge, earned: badge.earned(stats), size: 44)
                        }
                    }
                }
                .padding(18)
                .glassCard(cornerRadius: DS.Radius.card)
            }
            .buttonStyle(.plain)

            Button { Haptics.tap(); showYear = true } label: {
                HStack(spacing: 12) {
                    Image.pixel(.star).foregroundStyle(Color.ppFat)
                    Text("Your \(String(Calendar.current.component(.year, from: .now))) so far")
                        .foregroundStyle(Color.ppText)
                    Spacer()
                    Image.pixel(.chevronRight, size: 16).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .glassCard(cornerRadius: DS.Radius.card)
            }
            .buttonStyle(.plain)
        }
    }

    private var bodyWeightSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PPHeader("Body weight")
                Spacer()
                if !bodyWeight.entries.isEmpty {
                    NavigationLink {
                        BodyWeightView()
                    } label: {
                        HStack(spacing: 4) {
                            Text("All").font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                            Image.pixel(.chevronRight, size: 16)
                        }
                        .foregroundStyle(Color.brand)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("All weigh-ins")
                }
            }
            if bodyWeight.entries.isEmpty {
                EmptyStateCard(icon: .scale,
                               title: "Track your body weight",
                               message: "Log your weight a few times a week. You'll see the trend and a 7-day average, so daily ups and downs don't throw you off.",
                               buttonTitle: "Log weight") { loggingWeight = true }
            } else {
                BodyWeightCard(store: bodyWeight, showButton: true) { loggingWeight = true }
            }
        }
    }

    private var moreLinks: some View {
        VStack(spacing: 0) {
            link("Workout history", icon: .calendar) { HistoryView() }
            divider
            link("PRs", icon: .trophy) { RecordsView() }
            divider
            link("All exercises", icon: .list) { ExerciseListView() }
        }
        .padding(.horizontal, 16)
        .glassCard(cornerRadius: DS.Radius.card)
    }

    private var divider: some View {
        Rectangle().fill(Color.ppLine.opacity(0.08)).frame(height: 1)
    }

    private func link<Destination: View>(_ title: String, icon: PixelGlyph,
                                          @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image.pixel(icon).foregroundStyle(Color.brand)
                Text(title).foregroundStyle(Color.ppText)
                Spacer()
                Image.pixel(.chevronRight, size: 16).foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
