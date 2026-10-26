import SwiftUI
import Charts
import Observation

// MARK: - Body weight log

/// One weigh-in (always stored in kg).
nonisolated struct BodyWeightEntry: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var kg: Double
}

/// Your weigh-ins, saved on the phone (and in backups).
@MainActor @Observable
final class BodyWeightStore {
    static let shared = BodyWeightStore()
    static let key = "bodyWeight.v1"

    /// Oldest first.
    private(set) var entries: [BodyWeightEntry] {
        didSet { save() }
    }

    private init() {
        entries = Self.load()
    }

    private static func load() -> [BodyWeightEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([BodyWeightEntry].self, from: data) else { return [] }
        return saved.sorted { $0.date < $1.date }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Adds a weigh-in. One per day: logging again on the same day replaces it.
    func log(kg: Double, on date: Date = .now) {
        var list = entries.filter { !Calendar.current.isDate($0.date, inSameDayAs: date) }
        list.append(BodyWeightEntry(date: date, kg: kg))
        entries = list.sorted { $0.date < $1.date }
        // Keep the calorie calculator's weight up to date.
        if Calendar.current.isDateInToday(date) || date >= (entries.last?.date ?? date) {
            UserDefaults.standard.set(kg, forKey: "profileWeight")
        }
    }

    func delete(_ entry: BodyWeightEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    /// Puts a deleted weigh-in back exactly as it was (used by Undo).
    /// Skips it if that day has been logged again in the meantime.
    func restore(_ entry: BodyWeightEntry) {
        guard !entries.contains(where: {
            $0.id == entry.id || Calendar.current.isDate($0.date, inSameDayAs: entry.date)
        }) else { return }
        entries = (entries + [entry]).sorted { $0.date < $1.date }
    }

    func removeAll() { entries = [] }

    /// Picks up weigh-ins written by "Restore from backup".
    func reloadFromDisk() { entries = Self.load() }

    var latest: BodyWeightEntry? { entries.last }

    /// Average of the last 7 days of weigh-ins — smooths out daily water swings.
    var weeklyAverage: Double? {
        guard let last = entries.last else { return nil }
        let from = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: last.date)) ?? last.date
        let recent = entries.filter { $0.date >= from }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.kg } / Double(recent.count)
    }

    /// Change versus about 30 days before the latest weigh-in
    /// (or versus your first weigh-in, if that's at least a week old).
    var changeOver30Days: Double? {
        guard let last = entries.last,
              let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: last.date),
              let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: last.date)
        else { return nil }
        if let then = entries.last(where: { $0.date <= cutoff }) { return last.kg - then.kg }
        if let first = entries.first, first.date <= weekAgo { return last.kg - first.kg }
        return nil
    }

    /// Wording for the change: "since 12 Sep" when it's not a full month.
    var changeSinceDate: Date? {
        guard let last = entries.last,
              let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: last.date) else { return nil }
        return entries.last(where: { $0.date <= cutoff })?.date ?? entries.first?.date
    }

    // MARK: Backup

    /// Plain JSON for the backup file.
    var backupJSON: [[String: Any]] {
        entries.map { ["date": $0.date.timeIntervalSince1970, "kg": $0.kg] }
    }

    /// Adds weigh-ins from a backup (days you already have are kept). Returns how many were added.
    @discardableResult
    func merge(backup list: [[String: Any]]) -> Int {
        var added = 0
        var all = entries
        for item in list {
            let seconds = (item["date"] as? Double) ?? (item["date"] as? Int).map(Double.init)
            let kg = (item["kg"] as? Double) ?? (item["kg"] as? Int).map(Double.init)
            // Hand-edited backups: a huge or infinite number would crash the number formatting on every launch.
            guard let seconds, let kg, kg > 0, kg < 100_000,
                  seconds.isFinite, seconds >= 0, seconds < 4_102_444_800 else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            guard !all.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else { continue }
            all.append(BodyWeightEntry(date: date, kg: kg))
            added += 1
        }
        if added > 0 { entries = all.sorted { $0.date < $1.date } }
        return added
    }
}

// MARK: - Screens

/// Log today's weight: big number, −/+ 0.1 buttons.
struct LogBodyWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date.now
    @State private var loadingHealth = false
    @FocusState private var focused: Bool

    private var step: Double { Units.current == .kg ? 0.1 : 0.2 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        nudge(-1)
                        HStack(spacing: 6) {
                            TextField("0", text: $text)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.pixel(DS.TextSize.largeTitle, relativeTo: .largeTitle))
                                .foregroundStyle(Color.ppText)
                                .focused($focused)
                                .accessibilityLabel("Body weight in \(Units.symbol)")
                            Text(Units.symbol).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        nudge(1)
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Weigh in at the same time each day. The 7-day average shows the real trend.")
                }
                .listRowBackground(Color.ppCard)

                if HealthSync.isConfigured {
                    Section {
                        Button {
                            loadingHealth = true
                            Task {
                                if let kg = await HealthSync.latestBodyWeightKg() {
                                    text = Units.number(kg)
                                }
                                loadingHealth = false
                            }
                        } label: {
                            Label { Text(loadingHealth ? "Reading Apple Health…" : "Use my latest weight from Apple Health") }
                                icon: { Image.pixel(.heart) }
                        }
                        .disabled(loadingHealth)
                    }
                    .listRowBackground(Color.ppCard)
                }
            }
            .ppScreen()
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled((Double(userInput: text) ?? 0) <= 0)
                }
            }
            .onAppear {
                if let last = BodyWeightStore.shared.latest {
                    text = Units.number(last.kg)
                } else if let profile = UserDefaults.standard.object(forKey: "profileWeight") as? Double {
                    text = Units.number(profile)
                }
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func nudge(_ direction: Double) -> some View {
        Button {
            Haptics.select()
            let current = Double(userInput: text) ?? 0
            text = max(0, ((current + direction * step) * 10).rounded() / 10).plain
        } label: {
            Image.pixel(direction < 0 ? .minus : .plus)
                .foregroundStyle(Color.ppText)
                .frame(width: 48, height: 48)
                .background(Color.ppLine.opacity(0.08), in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(direction < 0 ? "Less" : "More")
    }

    private func save() {
        guard let typed = Double(userInput: text), typed > 0 else { return }
        BodyWeightStore.shared.log(kg: Units.toKg(typed), on: date)
        Haptics.success()
        dismiss()
    }
}

/// Full body-weight history: chart, weekly average and every weigh-in.
struct BodyWeightView: View {
    @AppStorage(Prefs.unit) private var unitRaw = "kg"
    @State private var logging = false
    private let store = BodyWeightStore.shared

    var body: some View {
        List {
            Section {
                if store.entries.isEmpty {
                    EmptyStateCard(icon: .scale,
                                   title: "No weigh-ins yet",
                                   message: "Log your weight a few times a week. \(AppInfo.name) shows the trend and your weekly average, so daily ups and downs don't throw you off.",
                                   buttonTitle: "Log weight") { logging = true }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } else {
                    BodyWeightCard(store: store, showButton: true) { logging = true }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            if !store.entries.isEmpty {
                Section {
                    ForEach(store.entries.reversed()) { entry in
                        HStack {
                            Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                            Spacer()
                            Text(Units.weight(entry.kg))
                                .font(.pixel(DS.TextSize.callout))
                                .foregroundStyle(Color.ppText)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Haptics.warning()
                                store.delete(entry)
                                UndoCenter.shared.show("Weigh-in deleted") {
                                    BodyWeightStore.shared.restore(entry)
                                }
                            } label: {
                                Label { Text("Delete") } icon: { Image.pixel(.trash) }
                            }
                        }
                    }
                } header: {
                    PPHeader("All weigh-ins")
                } footer: {
                    Text("Swipe left on a weigh-in to delete it.")
                }
                .listRowBackground(Color.ppCard)
            }
        }
        .ppScreen()
        .navigationTitle("Body weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { logging = true } label: { Image.pixel(.plus) }
                    .accessibilityLabel("Log weight")
            }
        }
        .sheet(isPresented: $logging) { LogBodyWeightSheet() }
    }
}

/// Latest weight, weekly average, 30-day change and a small trend chart.
struct BodyWeightCard: View {
    let store: BodyWeightStore
    var showButton = false
    var onLog: () -> Void = {}

    /// Last 90 days of weigh-ins for the chart.
    private var recent: [BodyWeightEntry] {
        let from = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        return store.entries.filter { $0.date >= from }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.latest.map { Units.weight($0.kg) } ?? "–")
                        .font(.pixel(DS.TextSize.title, relativeTo: .title))
                        .foregroundStyle(Color.ppText)
                        // A new weigh-in lands with a bounce.
                        .contentTransition(.numericText(value: store.latest?.kg ?? 0))
                        .animation(.snappy, value: store.latest?.kg)
                        .popOnChange(of: store.latest?.id, scale: 1.12)
                    if let latest = store.latest {
                        Text(Calendar.current.isDateInToday(latest.date)
                             ? "Today"
                             : latest.date.formatted(.relative(presentation: .named)).capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let avg = store.weeklyAverage {
                        Text("7-day avg \(Units.weight(avg))")
                            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                            .foregroundStyle(Color.brand)
                    }
                    if let change = store.changeOver30Days {
                        Text(changeText(change))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if recent.count > 1 {
                let values = recent.map { Units.display($0.kg) }
                let low = (values.min() ?? 0) - 1
                let high = (values.max() ?? 0) + 1
                Chart(recent) { entry in
                    LineMark(x: .value("Date", entry.date, unit: .day),
                             y: .value(Units.symbol, Units.display(entry.kg)))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", entry.date, unit: .day),
                              y: .value(Units.symbol, Units.display(entry.kg)))
                        .symbolSize(18)
                }
                .chartYScale(domain: low...high)
                .foregroundStyle(Color.brand)
                .frame(height: 120)
                .drawIn()
            }

            if showButton {
                Button(action: onLog) {
                    HStack(spacing: 8) {
                        Image.pixel(.plus, size: 16)
                        Text("Log weight")
                    }
                }
                .buttonStyle(.primary)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: DS.Radius.card)
    }

    private func changeText(_ kg: Double) -> String {
        let since = store.changeSinceDate.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "a month ago"
        let value = Units.display(abs(kg))
        if value < 0.1 { return "No change since \(since)" }
        return "\(kg > 0 ? "+" : "−")\(value.plain) \(Units.symbol) since \(since)"
    }
}

/// One-tap weigh-in row: your latest weight and a big "Log weight" button.
struct WeighInRow: View {
    let onLog: () -> Void
    private let store = BodyWeightStore.shared

    private var weighedToday: Bool {
        store.latest.map { Calendar.current.isDateInToday($0.date) } ?? false
    }

    var body: some View {
        Button(action: {
            Haptics.tap()
            onLog()
        }) {
            HStack(spacing: 14) {
                Image.pixel(.scale, size: 24)
                    .foregroundStyle(Color.brand)
                    .frame(width: 40, height: 40)
                    .background(Color.brand.opacity(0.15), in: RoundedRectangle(cornerRadius: DS.Radius.s))
                VStack(alignment: .leading, spacing: 2) {
                    Text(weighedToday ? "Weighed in today" : "Body weight")
                        .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                        .foregroundStyle(Color.ppText)
                    Text(store.latest.map { "Last: \(Units.weight($0.kg))" } ?? "Track your body weight trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image.pixel(weighedToday ? .check : .plus, size: 14)
                        .stamp(weighedToday)
                    Text(weighedToday ? "Update" : "Log weight").font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                }
                .foregroundStyle(weighedToday ? Color.ppText : Color.ppBackground)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(weighedToday ? Color.ppLine.opacity(0.1) : Color.brand, in: Capsule())
            }
            .padding(14)
            .glassCard(cornerRadius: DS.Radius.card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weighedToday ? "Update today's weight" : "Log weight")
    }
}
