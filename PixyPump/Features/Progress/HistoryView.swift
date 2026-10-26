import SwiftUI
import SwiftData

// MARK: - Sessions (one per training day)

/// Everything you logged on one day.
struct WorkoutSession: Identifiable {
    let day: Date
    /// Sets in the order you did them.
    let sets: [WorkoutSet]

    var id: Date { day }

    /// Working sets (warm-ups not counted).
    var setCount: Int { sets.filter { !$0.isWarmup }.count }
    var volume: Double { sets.reduce(0) { $0 + $1.volume } }

    /// First set to last set, plus a couple of minutes for the last rest.
    var minutes: Int? {
        guard sets.count > 1, let first = sets.first?.date, let last = sets.last?.date else { return nil }
        return Int((last.timeIntervalSince(first) / 60).rounded()) + 2
    }

    /// Exercises in the order you did them, each with its sets.
    var exercises: [ExerciseLog] {
        var order: [String] = []
        var groups: [String: [WorkoutSet]] = [:]
        for set in sets {
            let name = set.exercise?.name ?? "Deleted exercise"
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(set)
        }
        return order.map { ExerciseLog(name: $0, sets: groups[$0] ?? []) }
    }

    /// Which day of your split this looks like (the one with the most matching exercises).
    @MainActor var routineDay: Int? {
        let names = Set(sets.compactMap { $0.exercise?.name.lowercased() })
        var best: (day: Int, matches: Int)? = nil
        for (index, day) in Routine.days.enumerated() {
            let matches = day.filter { names.contains($0.lowercased()) }.count
            if matches > (best?.matches ?? 0) { best = (index + 1, matches) }
        }
        return best?.day
    }

    @MainActor var title: String {
        guard let day = routineDay else { return "Workout" }
        return "Day \(day) · \(Routine.dayName(day))"
    }

    /// Splits all logged sets into sessions, newest first.
    static func all(from sets: [WorkoutSet]) -> [WorkoutSession] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sets) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { WorkoutSession(day: $0.key, sets: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.day > $1.day }
    }
}

/// One exercise inside a session.
struct ExerciseLog: Identifiable {
    let name: String
    let sets: [WorkoutSet]
    var id: String { name }
    var exercise: Exercise? { sets.first?.exercise }
    var volume: Double { sets.reduce(0) { $0 + $1.volume } }
}

@MainActor
private func kg(_ value: Double) -> String { Units.volume(value) }

// MARK: - History screen

/// Calendar of the days you trained, plus every session, newest first.
struct HistoryView: View {
    @AppStorage(Prefs.unit) private var unitRaw = "kg"
    @Query(sort: \WorkoutSet.date, order: .reverse) private var allSets: [WorkoutSet]

    @State private var month: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var opened: WorkoutSession?
    @State private var pendingDelete: WorkoutSession?
    @Environment(\.modelContext) private var context

    var body: some View {
        let sessions = WorkoutSession.all(from: allSets)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 18) {
                    MonthCalendar(month: $month, trainedDays: Set(sessions.map(\.day))) { day in
                        if let session = sessions.first(where: { $0.day == day }) {
                            Haptics.tap()
                            opened = session
                        }
                    }
                    monthSummary(sessions)
                }
                .padding(16)
                .glassCard(cornerRadius: DS.Radius.hero)

                if sessions.isEmpty {
                    EmptyStateCard(
                        icon: .calendar,
                        title: "No workouts yet",
                        message: "Every set you log shows up here, grouped by day. Training days light up on the calendar."
                    )
                }

                ForEach(byMonth(sessions), id: \.month) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        PPHeader(group.month.formatted(.dateTime.month(.wide).year()))
                        ForEach(group.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                            // Long-press, or use the ··· button, to delete a workout.
                            .contextMenu {
                                Button(role: .destructive) { pendingDelete = session } label: {
                                    Label { Text("Delete workout") } icon: { Image.pixel(.trash) }
                                }
                            }
                            .accessibilityAction(named: "Delete workout") { pendingDelete = session }
                            // Sits in the gap SessionRow leaves just left of its chevron.
                            .overlay(alignment: .trailing) {
                                Menu {
                                    Button(role: .destructive) { pendingDelete = session } label: {
                                        Label { Text("Delete workout") } icon: { Image.pixel(.trash) }
                                    }
                                } label: {
                                    Image.pixel(.more, size: 20)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("More for this workout")
                                .padding(.trailing, SessionRow.menuInset)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Delete this workout?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDelete) { session in
            Button(session.sets.count == 1 ? "Delete 1 set" : "Delete \(session.sets.count) sets", role: .destructive) {
                Haptics.warning()
                withAnimation { WorkoutDeleter.delete(session, context: context) }
            }
        } message: { session in
            Text("Everything you logged on \(session.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) is removed, including PRs set that day. You can undo this for a few seconds.")
        }
        .navigationDestination(isPresented: Binding(
            get: { opened != nil },
            set: { if !$0 { opened = nil } })) {
            if let opened {
                SessionDetailView(session: opened)
            }
        }
    }

    private func monthSummary(_ sessions: [WorkoutSession]) -> some View {
        let calendar = Calendar.current
        let inMonth = sessions.filter { calendar.isDate($0.day, equalTo: month, toGranularity: .month) }
        return HStack(spacing: 0) {
            summaryValue("\(inMonth.count)", "workouts")
            summaryValue("\(inMonth.reduce(0) { $0 + $1.setCount })", "sets")
            summaryValue(kg(inMonth.reduce(0) { $0 + $1.volume }), "\(Units.symbol) lifted")
        }
    }

    private func summaryValue(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                .foregroundStyle(Color.ppText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private struct MonthGroup {
        let month: Date
        let sessions: [WorkoutSession]
    }

    private func byMonth(_ sessions: [WorkoutSession]) -> [MonthGroup] {
        let calendar = Calendar.current
        var groups: [MonthGroup] = []
        for session in sessions {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: session.day)) ?? session.day
            if let last = groups.last, last.month == start {
                groups[groups.count - 1] = MonthGroup(month: start, sessions: last.sessions + [session])
            } else {
                groups.append(MonthGroup(month: start, sessions: [session]))
            }
        }
        return groups
    }
}

// MARK: - Month calendar

private struct MonthCalendar: View {
    @Binding var month: Date
    let trainedDays: Set<Date>
    let onSelect: (Date) -> Void

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2   // Monday
        return cal
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(month, equalTo: .now, toGranularity: .month)
    }

    /// Blank slots before the 1st, then every day of the month.
    private var cells: [Date?] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let days: [Date?] = range.map { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
        return Array(repeating: nil, count: lead) + days
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { shift(-1) } label: {
                    Image.pixel(.chevronLeft).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                    .foregroundStyle(Color.ppText)
                Spacer()
                Button { shift(1) } label: {
                    Image.pixel(.chevronRight).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next month")
                .disabled(isCurrentMonth)
                .opacity(isCurrentMonth ? 0.3 : 1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ppText)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdayLetters[i])
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let trained = trainedDays.contains(day)
        let isToday = calendar.isDateInToday(day)
        return Button { if trained { onSelect(day) } } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.pixel(DS.TextSize.body))
                .foregroundStyle(trained ? Color.ppOnAccent : (day > .now ? Color.ppLine.opacity(0.25) : Color.ppText))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                        .fill(trained ? Color.brand : Color.clear)
                }
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                            .strokeBorder(Color.ppText, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!trained)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (trained ? ", workout" : ""))
    }

    private func shift(_ months: Int) {
        Haptics.select()
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        }
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: WorkoutSession

    /// Where the history list puts its ··· menu: padding (16) + chevron (16) + spacing (14).
    static let menuInset: CGFloat = 46

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(session.day.formatted(.dateTime.day()))
                    .font(.pixel(DS.TextSize.title, relativeTo: .title))
                    .foregroundStyle(Color.ppText)
                Text(session.day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                    .foregroundStyle(Color.secondary)
            }
            .frame(width: 52)

            Rectangle()
                .fill(Color.ppLine.opacity(0.1))
                .frame(width: 1, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // Room for the ··· menu laid over the row.
            Color.clear.frame(width: 44, height: 44)
            Image.pixel(.chevronRight, size: 16)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts = ["\(session.setCount) sets", "\(kg(session.volume)) \(Units.symbol)"]
        if let minutes = session.minutes { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - One session in detail

struct SessionDetailView: View {
    let session: WorkoutSession
    @State private var showSummary = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private var prCount: Int {
        session.exercises.reduce(0) { $0 + (prSet(in: $1) == nil ? 0 : 1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 14) {
                    Text(session.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.pixel(DS.TextSize.display, relativeTo: .largeTitle))
                        .foregroundStyle(Color.ppText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(session.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    HStack(spacing: 8) {
                        stat("\(session.exercises.count)", "exercises")
                        stat("\(session.setCount)", "sets")
                        stat(kg(session.volume), Units.symbol)
                        if let minutes = session.minutes { stat("\(minutes)", "min") }
                    }
                    if prCount > 0 {
                        Label {
                            Text(prCount == 1 ? "1 PR" : "\(prCount) PRs")
                        } icon: {
                            Image.pixel(.trophy, size: 16)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.ppFat)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .glassCard(cornerRadius: DS.Radius.hero)

                // Exercises
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, log in
                    exerciseCard(index: index, log: log)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.tap(); showSummary = true } label: { Image.pixel(.share) }
                    .accessibilityLabel("Summary and share")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { confirmDelete = true } label: { Image.pixel(.trash) }
                    .accessibilityLabel("Delete workout")
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(session.sets.count == 1 ? "Delete 1 set" : "Delete \(session.sets.count) sets", role: .destructive) {
                Haptics.warning()
                let doomed = session
                dismiss()
                // Delete after going back, so this screen never shows removed sets.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    WorkoutDeleter.delete(doomed, context: context)
                }
            }
        } message: {
            Text("Everything you logged this day is removed, including PRs set that day. You can undo this for a few seconds.")
        }
        .sheet(isPresented: $showSummary) { WorkoutSummaryView(day: session.day, celebrate: false) }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.pixel(DS.TextSize.subhead)).foregroundStyle(Color.ppText)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.ppLine.opacity(0.08), in: Capsule())
    }

    private func exerciseCard(index: Int, log: ExerciseLog) -> some View {
        let pr = prSet(in: log)
        return VStack(alignment: .leading, spacing: 12) {
            // Name (tap to open the exercise with its full history and chart)
            Group {
                if let exercise = log.exercise {
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                    } label: {
                        exerciseTitle(index: index, log: log, showChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    exerciseTitle(index: index, log: log, showChevron: false)
                }
            }

            Rectangle().fill(Color.ppLine.opacity(0.08)).frame(height: 1)

            ForEach(Array(log.sets.enumerated()), id: \.offset) { number, set in
                HStack(spacing: 12) {
                    Text(set.kind.badge ?? "\(number + 1)")
                        .font(.pixel(DS.TextSize.footnote))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .leading)
                    Text("\(Units.weight(set.weight)) × \(set.reps)")
                        .font(.pixel(DS.TextSize.callout))
                        .foregroundStyle(Color.ppText)
                    if let pr, pr === set {
                        Image.pixel(.star, size: 16)
                            .foregroundStyle(Color.ppFat)
                            .accessibilityLabel("Personal record")
                    }
                    Spacer()
                    Text(set.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
    }

    private func exerciseTitle(index: Int, log: ExerciseLog, showChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.pixel(DS.TextSize.body))
                .foregroundStyle(Color.ppText)
                .frame(width: 32, height: 32)
                .background(Color.ppLine.opacity(0.16), in: RoundedRectangle(cornerRadius: DS.Radius.xs))
            VStack(alignment: .leading, spacing: 2) {
                Text(log.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.ppText)
                Text("\(log.sets.count) sets · \(kg(log.volume)) \(Units.symbol)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if showChevron {
                Image.pixel(.chevronRight, size: 16).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    /// The heaviest set of this exercise on this day, if it beat everything before it.
    private func prSet(in log: ExerciseLog) -> WorkoutSet? {
        guard let exercise = log.exercise,
              let top = log.sets.filter({ !$0.isWarmup }).max(by: { $0.weight < $1.weight }) else { return nil }
        let before = exercise.workingSets.filter { $0.date < session.day }.map(\.weight)
        guard let previousBest = before.max(), top.weight > previousBest else { return nil }
        return top
    }
}

/// Removes a whole day's workout, then offers Undo for a few seconds.
@MainActor
enum WorkoutDeleter {
    /// A plain copy of one set, so Undo can rebuild it.
    private struct SetSnapshot {
        let reps: Int
        let weight: Double
        let date: Date
        let kindRaw: String?
        let exercise: Exercise?
    }

    static func delete(_ session: WorkoutSession, context: ModelContext) {
        // Copy everything first: deleted sets can't be read afterwards.
        let snapshots = session.sets.map {
            SetSnapshot(reps: $0.reps, weight: $0.weight, date: $0.date,
                        kindRaw: $0.kindRaw, exercise: $0.exercise)
        }
        let day = session.day
        let planDay = TrainingLog.day(on: day)
        let xp = XPLedger.entry(on: day)

        for set in session.sets { context.delete(set) }
        TrainingLog.remove(on: day)   // keeps "up next" right
        XPLedger.set(nil, on: day)     // and its XP
        if Calendar.current.isDateInToday(day) { ActiveWorkout.shared.reset() }
        try? context.save()

        UndoCenter.shared.show("Workout deleted") {
            for snapshot in snapshots {
                let set = WorkoutSet(reps: snapshot.reps, weight: snapshot.weight, date: snapshot.date)
                set.kindRaw = snapshot.kindRaw
                context.insert(set)
                // Re-attach to its exercise, unless that was deleted too.
                if let exercise = snapshot.exercise, !exercise.isDeleted, exercise.modelContext != nil {
                    set.exercise = exercise
                }
            }
            if let planDay { TrainingLog.record(day: planDay, on: day) }
            if let xp { XPLedger.set(xp, on: day) }
            try? context.save()
        }
    }
}
