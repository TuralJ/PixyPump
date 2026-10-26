import SwiftUI
import SwiftData

/// First-week checklist on Home. It starts with one step already ticked (a head
/// start makes people far more likely to finish) and ends with an Epic gym bag.
/// It's called "First week checklist" everywhere.
struct StarterStep: Identifiable {
    let id: String
    let title: String
    let done: Bool
}

@MainActor
enum GettingStarted {
    static let claimedKey = "starterClaimed"
    /// Set when you change anything in the buddy editor.
    static let buddyKey = "starterBuddyCustomised"
    /// Set when you open your first gym bag.
    static let bagKey = "starterBagOpened"

    static var isClaimed: Bool { UserDefaults.standard.bool(forKey: claimedKey) }

    static func steps(sets: [WorkoutSet], food: [FoodEntry]) -> [StarterStep] {
        let defaults = UserDefaults.standard
        let challengeWon = BonusXP.all.keys.contains { $0.hasPrefix("daily:") }
        return [
            StarterStep(id: "plan", title: "Build your plan", done: true),
            StarterStep(id: "workout", title: "Do your first workout", done: sets.contains { !$0.isWarmup }),
            StarterStep(id: "challenge", title: "Win a daily challenge", done: challengeWon),
            StarterStep(id: "buddy", title: "Dress up your buddy", done: defaults.bool(forKey: buddyKey)),
            StarterStep(id: "meal", title: "Log a meal", done: !food.isEmpty),
            StarterStep(id: "weigh", title: "Weigh in", done: !BodyWeightStore.shared.entries.isEmpty),
            StarterStep(id: "bag", title: "Open a gym bag", done: defaults.bool(forKey: bagKey)),
        ]
    }

    /// All done: hand out the Epic bag (once).
    static func claim() {
        guard !isClaimed else { return }
        UserDefaults.standard.set(true, forKey: claimedKey)
        GymBag.addPending("starter")
    }
}

/// Home card: "First week checklist 3/7 · 🎁 Epic gym bag at the end".
struct StarterChecklistCard: View {
    let steps: [StarterStep]
    let claim: () -> Void

    var body: some View {
        let done = steps.filter(\.done).count
        let complete = done == steps.count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("First week checklist")
                    .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text("\(done)/\(steps.count) · 🎁 Epic gym bag")
                    .font(.pixel(DS.TextSize.caption))
                    .foregroundStyle(Color.ppFat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ppLine.opacity(0.1))
                    Capsule().fill(Color.ppFat)
                        .frame(width: geo.size.width * Double(done) / Double(max(steps.count, 1)))
                }
            }
            .frame(height: 6)

            if complete {
                Button(action: claim) {
                    HStack(spacing: 8) {
                        PixelBag().frame(width: 24, height: 24)
                        Text("Claim your Epic gym bag")
                    }
                }
                .buttonStyle(.primary)
            } else {
                // Show what's left first: unfinished things nag.
                let ordered = steps.filter { !$0.done } + steps.filter(\.done)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(ordered) { step in
                        HStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(step.done ? Color.ppDone : Color.clear)
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(step.done ? Color.ppDone : Color.ppLine.opacity(0.3), lineWidth: 1.5)
                                if step.done {
                                    Image.pixel(.check, size: 10).foregroundStyle(Color.ppBackground)
                                }
                            }
                            .frame(width: 16, height: 16)
                            Text(step.title)
                                .font(.caption)
                                .foregroundStyle(step.done ? .secondary : Color.ppText)
                                .strikethrough(step.done, color: .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                if steps.count - done == 1 {
                    Text("One more and the Epic gym bag is yours!")
                        .font(.caption)
                        .foregroundStyle(Color.ppFat)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(Color.ppFat.opacity(complete ? 0.8 : 0.25), lineWidth: 1.5)
        }
    }
}
