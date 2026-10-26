import SwiftUI
import Observation

// MARK: - Saved answers

/// Your plan answers, remembered so you can re-run the builder later.
@MainActor @Observable
final class PlanAnswers {
    var goals: Set<TrainingGoal> { didSet { save() } }
    var experience: LiftingExperience { didSet { save() } }
    var days: Int { didSet { save() } }
    var minutes: Int { didSet { save() } }
    var equipment: Set<Equipment> { didSet { save() } }
    var focus: Set<MuscleArea> { didSet { save() } }
    var avoid: Set<AvoidOption> { didSet { save() } }

    init() {
        let d = UserDefaults.standard
        if let saved = d.stringArray(forKey: "planGoals") {
            goals = Set(saved.compactMap(TrainingGoal.init(rawValue:)))
        } else if let old = TrainingGoal(rawValue: d.string(forKey: "planGoal") ?? "") {
            goals = [old]
        } else {
            goals = [.muscle]
        }
        experience = LiftingExperience(rawValue: d.string(forKey: "planExperience") ?? "") ?? .new
        days = d.object(forKey: "planDays") as? Int ?? 3
        minutes = d.object(forKey: "planMinutes") as? Int ?? 45
        if let saved = d.stringArray(forKey: "planEquipment") {
            equipment = Set(saved.compactMap(Equipment.init(rawValue:)))
        } else {
            equipment = Set(Equipment.allCases)
        }
        focus = Set((d.stringArray(forKey: "planFocus") ?? []).compactMap(MuscleArea.init(rawValue:)))
        avoid = Set((d.stringArray(forKey: "planAvoid") ?? []).compactMap(AvoidOption.init(rawValue:)))
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(goals.map(\.rawValue).sorted(), forKey: "planGoals")
        d.set(experience.rawValue, forKey: "planExperience")
        d.set(days, forKey: "planDays")
        d.set(minutes, forKey: "planMinutes")
        d.set(equipment.map(\.rawValue).sorted(), forKey: "planEquipment")
        d.set(focus.map(\.rawValue).sorted(), forKey: "planFocus")
        d.set(avoid.map(\.rawValue).sorted(), forKey: "planAvoid")
    }

    var inputs: PlanInputs {
        PlanInputs(goals: goals, experience: experience, days: days, minutes: minutes,
                   equipment: equipment, focus: focus, avoid: avoid)
    }

    /// Replaces your training plan with the generated one (history is kept).
    func apply(_ plan: GeneratedPlan) {
        RoutineStore.shared.days = plan.days
        UserDefaults.standard.set(plan.restSeconds, forKey: Prefs.restSeconds)
    }
}

// MARK: - Steps

/// The plan questions, in order. Kept to a handful of screens:
/// days and minutes share one ("schedule"), focus and avoid share another ("extras").
/// Raw values must stay 0, 1, 2… with no gaps (the Settings builder steps through them).
enum PlanStep: Int, CaseIterable, Hashable {
    case goal, experience, schedule, equipment, extras, result
}

/// One question (or the result) of the plan builder.
struct PlanQuestionScreen: View {
    let step: PlanStep
    @Bindable var answers: PlanAnswers

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch step {
            case .goal:
                WizardTitle("What are your goals?")
                hint("Pick one or more. We'll set your reps, sets and rest times around them.")
                ForEach(TrainingGoal.allCases) { goal in
                    ChoiceCard(selected: answers.goals.contains(goal), title: goal.title, detail: goal.detail) {
                        // Multi-select, but always keep at least one.
                        if answers.goals.contains(goal) {
                            if answers.goals.count > 1 { answers.goals.remove(goal) }
                        } else {
                            answers.goals.insert(goal)
                        }
                    }
                }

            case .experience:
                WizardTitle("How long have you been lifting?")
                hint("Beginners get simpler plans with fewer sets.")
                ForEach(LiftingExperience.allCases) { level in
                    ChoiceCard(selected: answers.experience == level, title: level.title, detail: level.detail) {
                        answers.experience = level
                    }
                }

            case .schedule:
                WizardTitle("How often, and how long?")
                hint("Be realistic — consistency beats big plans.")
                Text("Days a week")
                    .font(.subheadline)
                    .foregroundStyle(Color.ppText)
                numberRow(Array(2...6), selected: answers.days,
                          label: { "\($0)" }, spoken: { "\($0) days a week" }) { answers.days = $0 }
                Text(daysHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Minutes per workout")
                    .font(.subheadline)
                    .foregroundStyle(Color.ppText)
                    .padding(.top, 10)
                numberRow([30, 45, 60, 75, 90], selected: answers.minutes,
                          label: { $0 >= 90 ? "90+" : "\($0)" }, spoken: { "\($0) minutes" }) { answers.minutes = $0 }
                Text("Including rest. About \(PlanGenerator.exerciseCount(minutes: answers.minutes)) exercises.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            case .equipment:
                WizardTitle("What equipment do you have?")
                hint("Pick a quick option, or tick exactly what you have.")
                ForEach(EquipmentPreset.allCases) { preset in
                    ChoiceCard(selected: answers.equipment == preset.equipment, title: preset.title,
                               detail: preset.equipment.isEmpty ? "Bodyweight only"
                                   : preset.equipment.map(\.title).sorted().joined(separator: ", ")) {
                        answers.equipment = preset.equipment
                    }
                }
                Text("Or pick exactly:")
                    .font(.subheadline)
                    .foregroundStyle(Color.ppText)
                    .padding(.top, 6)
                ChipGrid(items: Equipment.allCases, title: \.title,
                         isOn: { answers.equipment.contains($0) },
                         toggle: { answers.equipment.formSymmetricDifference([$0]) })

            case .extras:
                WizardTitle("Anything to focus on or avoid?")
                hint("Optional. Leave it all empty for a balanced plan.")
                Text("Extra work for")
                    .font(.subheadline)
                    .foregroundStyle(Color.ppText)
                ChipGrid(items: MuscleArea.allCases, title: \.title,
                         isOn: { answers.focus.contains($0) },
                         toggle: { answers.focus.formSymmetricDifference([$0]) })
                Text("Go easy on (we'll swap in safer moves)")
                    .font(.subheadline)
                    .foregroundStyle(Color.ppText)
                    .padding(.top, 10)
                ForEach(AvoidOption.allCases) { option in
                    ChoiceCard(selected: answers.avoid.contains(option), title: option.title, detail: option.detail) {
                        answers.avoid.formSymmetricDifference([option])
                    }
                }

            case .result:
                PlanResultView(plan: PlanGenerator.make(answers.inputs))
            }
        }
    }

    private var daysHint: String {
        switch answers.days {
        case 2, 3: return "Full-body workouts: every muscle, every session."
        case 4: return "Upper body and lower body on alternate days."
        case 5: return "Upper / lower plus push, pull and legs."
        default: return "Push, pull and legs, twice a week."
        }
    }

    /// A row of big pixel number buttons (2 3 4 5 6, or 30 45 60…), one picked.
    private func numberRow(_ values: [Int], selected: Int,
                           label: @escaping (Int) -> String,
                           spoken: @escaping (Int) -> String,
                           pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { n in
                Button {
                    Haptics.select()
                    pick(n)
                } label: {
                    Text(label(n))
                        .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(selected == n ? Color.ppOnAccent : Color.ppText)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(selected == n ? Color.brand : Color.ppLine.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.m))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken(n))
                .accessibilityAddTraits(selected == n ? .isSelected : [])
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 4)
    }
}

/// Multi-select chips in a wrapping grid.
struct ChipGrid<Item: Hashable>: View {
    let items: [Item]
    let title: KeyPath<Item, String>
    let isOn: (Item) -> Bool
    let toggle: (Item) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.self) { item in
                let on = isOn(item)
                Button {
                    Haptics.select()
                    toggle(item)
                } label: {
                    HStack(spacing: 8) {
                        Image.pixel(on ? .check : .plus, size: 16)
                        Text(item[keyPath: title])
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(on ? Color.ppOnAccent : Color.ppText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(on ? Color.brand : Color.ppLine.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.s))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// "Your plan": summary, the reasons behind it, and every day's exercises.
struct PlanResultView: View {
    let plan: GeneratedPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WizardTitle("Your plan")
            Text("\(plan.days.count) days a week · \(plan.splitName) · ~\(plan.minutes) min")
                .font(.subheadline)
                .foregroundStyle(Color.brand)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(plan.reasons, id: \.self) { reason in
                    HStack(alignment: .top, spacing: 10) {
                        Image.pixel(.check, size: 16).foregroundStyle(Color.ppDone)
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(Color.ppText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: DS.Radius.tile)

            ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Day \(index + 1) · \(day.name)")
                        .font(.pixel(DS.TextSize.callout, relativeTo: .headline))
                        .foregroundStyle(Color.ppText)
                    ForEach(day.items) { item in
                        HStack {
                            Text(item.name).font(.subheadline).foregroundStyle(Color.ppText)
                            Spacer()
                            Text("\(item.sets) × \(item.repsText)")
                                .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: DS.Radius.tile)
            }

            Text("You can swap exercises, sets and reps any time with the pencil button on the Workout tab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Settings: build a new plan

/// The plan questions on their own, from Settings → Training plan.
struct PlanBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answers = PlanAnswers()
    @State private var step: PlanStep = .goal
    @State private var confirmReplace = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StepBar(current: step.rawValue + 1, total: PlanStep.allCases.count)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                ScrollView {
                    PlanQuestionScreen(step: step, answers: answers)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                VStack(spacing: 12) {
                    Button {
                        Haptics.press()
                        if step == .result {
                            confirmReplace = true
                        } else if let next = PlanStep(rawValue: step.rawValue + 1) {
                            withAnimation(.snappy) { step = next }
                        }
                    } label: {
                        Text(step == .result ? "Use this plan"
                             : step == .extras ? "Build my plan" : "Continue")
                    }
                        .buttonStyle(.primary)
                    if step != .goal {
                        Button {
                            Haptics.tap()
                            if let prev = PlanStep(rawValue: step.rawValue - 1) {
                                withAnimation(.snappy) { step = prev }
                            }
                        } label: {
                            Text("Back")
                                .font(.pixel(DS.TextSize.body))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Replace your current plan?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Use the new plan") {
                    answers.apply(PlanGenerator.make(answers.inputs))
                    Haptics.success()
                    dismiss()
                }
                Button("Keep my plan", role: .cancel) {}
            } message: {
                Text("Your workout history stays. Only the days and exercises in your plan change.")
            }
        }
    }
}
