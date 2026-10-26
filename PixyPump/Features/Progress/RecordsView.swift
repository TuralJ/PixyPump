import SwiftUI
import SwiftData

/// Your PRs for every exercise: heaviest set, best estimated 1-rep max,
/// most reps in a set and biggest single-day volume.
struct RecordsView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @AppStorage(Prefs.unit) private var unitRaw = "kg"

    private struct Record: Identifiable {
        let exercise: Exercise
        let heaviest: WorkoutSet
        let bestMax: WorkoutSet
        let mostReps: WorkoutSet
        let bestDayVolume: (day: Date, volume: Double)
        var id: PersistentIdentifier { exercise.persistentModelID }
    }

    private var records: [Record] {
        exercises.compactMap { exercise in
            let sets = exercise.workingSets.filter { $0.weight > 0 || $0.reps > 0 }
            guard let heaviest = sets.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }),
                  let bestMax = sets.max(by: { $0.estimatedMax < $1.estimatedMax }),
                  let mostReps = sets.max(by: { ($0.reps, $0.weight) < ($1.reps, $1.weight) })
            else { return nil }
            let byDay = Dictionary(grouping: sets) { Calendar.current.startOfDay(for: $0.date) }
                .map { (day: $0.key, volume: $0.value.reduce(0) { $0 + $1.volume }) }
            let bestDay = byDay.max { $0.volume < $1.volume } ?? (day: heaviest.date, volume: 0)
            return Record(exercise: exercise, heaviest: heaviest, bestMax: bestMax,
                          mostReps: mostReps, bestDayVolume: bestDay)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if records.isEmpty {
                    EmptyStateCard(icon: .trophy,
                                   title: "No PRs yet",
                                   message: "Your PRs (heaviest sets, best estimated 1-rep max and most reps) show up here as you train.")
                }
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    NavigationLink {
                        ExerciseDetailView(exercise: record.exercise)
                    } label: {
                        card(record)
                    }
                    .buttonStyle(.squish)
                    .staggeredAppear(index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("PRs")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }

    /// Set in the last 3 days: gets a gold shine and a NEW tag.
    private func isFresh(_ record: Record) -> Bool {
        [record.heaviest.date, record.bestMax.date, record.mostReps.date]
            .contains { Date.now.timeIntervalSince($0) < 3 * 86_400 }
    }

    private func card(_ record: Record) -> some View {
        let fresh = isFresh(record)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image.pixel(.trophy, size: 16).foregroundStyle(Color.ppFat)
                    .wobble(fresh, degrees: 8)
                Text(record.exercise.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.ppText)
                if fresh {
                    Text("NEW")
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                        .foregroundStyle(Color.ppBackground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.ppFat, in: Capsule())
                        .accessibilityLabel("New PR")
                }
                Spacer()
                Image.pixel(.chevronRight, size: 16).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                stat("Heaviest", "\(Units.weight(record.heaviest.weight)) × \(record.heaviest.reps)", record.heaviest.date)
                stat("Est. 1-rep max", Units.weight(record.bestMax.estimatedMax), record.bestMax.date)
                stat("Most reps", "\(record.mostReps.reps) × \(Units.weight(record.mostReps.weight))", record.mostReps.date)
                stat("Best day", "\(Units.volume(record.bestDayVolume.volume)) \(Units.symbol)", record.bestDayVolume.day)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .shimmer(fresh)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func stat(_ label: String, _ value: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                .foregroundStyle(Color.brand)
            Text(value)
                .font(.pixel(DS.TextSize.callout))
                .foregroundStyle(Color.ppText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
