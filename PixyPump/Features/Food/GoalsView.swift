import SwiftUI

// MARK: - The maths

/// Works out daily calories and macros from a few facts about you (Mifflin-St Jeor).
struct GoalCalculator {
    var sex: String          // "male" / "female"
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var activity: Int        // index into `activityLevels`
    var goal: String         // "lose" / "maintain" / "gain"

    static let activityLevels: [(title: String, detail: String, factor: Double)] = [
        ("Mostly sitting", "Desk job, little walking, no workouts", 1.2),
        ("Lightly active", "1–3 workouts a week", 1.375),
        ("Active", "3–5 workouts a week", 1.55),
        ("Very active", "6–7 workouts a week", 1.725),
        ("Physical job + training", "On your feet all day and you train", 1.9),
    ]

    var bmr: Double {
        // Mifflin-St Jeor; "other" uses the midpoint of the male and female formulas.
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == "male" ? 5 : sex == "female" ? -161 : -78)
    }

    /// Calories that keep your weight the same.
    var maintenance: Double {
        bmr * Self.activityLevels[min(max(activity, 0), Self.activityLevels.count - 1)].factor
    }

    var kcal: Double {
        let factor = goal == "lose" ? 0.8 : goal == "gain" ? 1.1 : 1.0
        return (maintenance * factor / 10).rounded() * 10
    }
    var protein: Double { ((goal == "lose" ? 2.2 : 2.0) * weightKg).rounded() }
    var fat: Double { max(0.8 * weightKg, 0.25 * kcal / 9).rounded() }
    var carbs: Double { max(0, (kcal - protein * 4 - fat * 9) / 4).rounded() }
}

// MARK: - Step-by-step goals (used in onboarding and from Settings)

/// Asks about you one question at a time, then shows suggested calories and macros
/// with a plain explanation of each.
struct GoalsWizardView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("goalKcal") private var goalKcal = 2500.0
    @AppStorage("goalProtein") private var goalProtein = 160.0
    @AppStorage("goalCarbs") private var goalCarbs = 280.0
    @AppStorage("goalFat") private var goalFat = 75.0

    @AppStorage("profileSex") private var sex = "male"
    @AppStorage("profileAge") private var age = 25
    @AppStorage("profileHeight") private var height = 180.0
    @AppStorage("profileWeight") private var weight = 80.0
    @AppStorage("profileActivity") private var activity = 2
    @AppStorage("profileGoal") private var goal = "maintain"
    @AppStorage(Prefs.unit) private var unitRaw = "kg"

    /// Called after "Use these goals" (onboarding moves on).
    var onDone: (() -> Void)? = nil

    init(onDone: (() -> Void)? = nil) {
        self.onDone = onDone
    }

    @State private var step = 0
    private let stepCount = 5

    private var calc: GoalCalculator {
        GoalCalculator(sex: sex, age: age, heightCm: height, weightKg: weight, activity: activity, goal: goal)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StepBar(current: step + 1, total: stepCount)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                ScrollView {
                    Group {
                        switch step {
                        case 0: aboutYou
                        case 1: body1
                        case 2: activityStep
                        case 3: goalStep
                        default: result
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)

                VStack(spacing: 12) {
                    Button { next() } label: { Text(step == stepCount - 1 ? "Use these goals" : "Continue") }
                        .buttonStyle(.primary)
                    if step > 0 {
                        Button {
                            Haptics.tap()
                            withAnimation(.snappy) { step -= 1 }
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
        }
    }

    // MARK: Steps

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 16) {
            WizardTitle("A bit about you")
            Text("Your body uses energy differently depending on these. We only use them to suggest your numbers; nothing leaves your phone.")
                .foregroundStyle(.secondary)
            // Same three options as onboarding. "Other" uses the midpoint of the
            // male and female formulas (see GoalCalculator.bmr).
            Picker("Sex", selection: $sex) {
                Text("Male").tag("male")
                Text("Female").tag("female")
                Text("Other").tag("other")
            }
            .pickerStyle(.segmented)
            .padding(.top, 8)
            numberCard("Age", value: "\(age)", unit: "years") {
                Stepper("Age", value: $age, in: 14...90).labelsHidden()
            }
        }
    }

    private var body1: some View {
        VStack(alignment: .leading, spacing: 16) {
            WizardTitle("Height and weight")
            Text("A rough number is fine. You can update your weight any time on the Progress tab.")
                .foregroundStyle(.secondary)
            numberCard("Height", value: "\(Int(height))", unit: "cm") {
                Stepper("Height", value: $height, in: 120...230, step: 1).labelsHidden()
            }
            numberCard("Weight", value: Units.display(weight).plain, unit: Units.symbol) {
                Stepper("Weight",
                        value: Binding(get: { Units.display(weight) },
                                       set: { weight = Units.toKg($0) }),
                        in: 30...300, step: Units.current == .kg ? 0.5 : 1).labelsHidden()
            }
            if HealthSync.isConfigured {
                Button {
                    Task {
                        if let kg = await HealthSync.latestBodyWeightKg() {
                            weight = (kg * 10).rounded() / 10
                            Haptics.success()
                        }
                    }
                } label: {
                    Label { Text("Use my weight from Apple Health") } icon: { Image.pixel(.heart) }
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var activityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            WizardTitle("How active are you?")
            Text("Count your workouts and how much you move during a normal week.")
                .foregroundStyle(.secondary)
            ForEach(GoalCalculator.activityLevels.indices, id: \.self) { i in
                ChoiceCard(selected: activity == i,
                           title: GoalCalculator.activityLevels[i].title,
                           detail: GoalCalculator.activityLevels[i].detail) { activity = i }
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            WizardTitle("What's your goal?")
            ChoiceCard(selected: goal == "lose", title: "Lose fat",
                       detail: "Eat a bit less than you burn (about 20% under). Lose around 0.5 kg a week while keeping muscle.") { goal = "lose" }
            ChoiceCard(selected: goal == "maintain", title: "Stay the same",
                       detail: "Eat about what you burn. Good for getting stronger without changing your weight.") { goal = "maintain" }
            ChoiceCard(selected: goal == "gain", title: "Build muscle",
                       detail: "Eat a little more than you burn (about 10% over), so your body has material to grow.") { goal = "gain" }
        }
    }

    private var result: some View {
        let c = calc
        let goalNote: String = goal == "lose" ? "Eating this much puts you in a gentle deficit."
            : goal == "gain" ? "Eating this much gives you a small surplus to build muscle."
            : "Eating this much keeps your weight steady."
        return VStack(alignment: .leading, spacing: 16) {
            WizardTitle("Your daily target")
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(c.kcal).spaced) kcal")
                    .font(.pixel(DS.TextSize.display, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ppText)
                Text("You burn about \(Int(c.maintenance).spaced) kcal a day. \(goalNote)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: DS.Radius.card)

            Text("Those calories come from three macros:")
                .font(.subheadline)
                .foregroundStyle(Color.ppText)
                .padding(.top, 4)
            MacroExplainRow(name: "Protein", grams: c.protein, color: .ppProtein,
                            text: "Builds and repairs muscle. The most important one: try to hit it every day.")
            MacroExplainRow(name: "Carbs", grams: c.carbs, color: .ppCarbs,
                            text: "Your main fuel for training. Rice, potatoes, bread, fruit.")
            MacroExplainRow(name: "Fat", grams: c.fat, color: .ppFat,
                            text: "Needed for hormones and health. Oils, nuts, eggs, fish.")
            Text("It's an estimate. Watch your weight for 2–3 weeks and adjust by 100–200 kcal if it doesn't move the way you want. You can change these in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pieces

    private func numberCard<Control: View>(_ label: String, value: String, unit: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.pixel(DS.TextSize.title, relativeTo: .title)).foregroundStyle(Color.ppText)
                    Text(unit).foregroundStyle(.secondary)
                }
            }
            Spacer()
            control()
        }
        .padding(18)
        .glassCard(cornerRadius: DS.Radius.tile)
    }

    private func next() {
        Haptics.press()
        if step < stepCount - 1 {
            withAnimation(.snappy) { step += 1 }
        } else {
            let c = calc
            goalKcal = c.kcal
            goalProtein = c.protein
            goalCarbs = c.carbs
            goalFat = c.fat
            UserDefaults.standard.set(true, forKey: "goalsSetUp")
            Haptics.success()
            onDone?()
            dismiss()
        }
    }
}

/// One macro with its target and what it's for.
struct MacroExplainRow: View {
    let name: String
    let grams: Double
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(color).frame(width: 10, height: 10).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(name).foregroundStyle(Color.ppText)
                    Spacer()
                    Text("\(Int(grams)) g").font(.pixel(DS.TextSize.callout)).foregroundStyle(color)
                }
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.tile)
    }
}

// MARK: - Settings: your goals (editable), with the step-by-step calculator one tap away

struct GoalsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("goalKcal") private var goalKcal = 2500.0
    @AppStorage("goalProtein") private var goalProtein = 160.0
    @AppStorage("goalCarbs") private var goalCarbs = 280.0
    @AppStorage("goalFat") private var goalFat = 75.0
    @State private var showWizard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { Haptics.tap(); showWizard = true } label: {
                        HStack(spacing: 14) {
                            Image.pixel(.target, size: 32).foregroundStyle(Color.brand)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Work out my goals")
                                    .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                                    .foregroundStyle(Color.ppText)
                                Text("Answer 4 quick questions and get suggested numbers")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image.pixel(.chevronRight, size: 16).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.ppCard)

                Section {
                    goalRow("Calories", value: $goalKcal, unit: "kcal")
                    goalRow("Protein", value: $goalProtein, unit: "g")
                    goalRow("Carbs", value: $goalCarbs, unit: "g")
                    goalRow("Fat", value: $goalFat, unit: "g")
                } header: {
                    PPHeader("Your daily goals")
                } footer: {
                    Text("Already know your numbers? Type them here. Protein builds muscle, carbs fuel your training, fat keeps you healthy. 1 g of protein or carbs = 4 kcal, 1 g of fat = 9 kcal.")
                }
                .listRowBackground(Color.ppCard)
            }
            .ppScreen()
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showWizard) { GoalsWizardView() }
        }
    }

    private func goalRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            TextField("0", value: value, format: .number.grouping(.never))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared onboarding pieces

/// Thin progress bar: "step 2 of 4".
struct StepBar: View {
    let current: Int   // 1-based
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.ppText : Color.ppLine.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current) of \(total)")
    }
}

struct WizardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.pixel(DS.TextSize.title, relativeTo: .largeTitle))
            .foregroundStyle(Color.ppText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Tappable option card with a tick when selected.
struct ChoiceCard: View {
    let selected: Bool
    let title: String
    let detail: String
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image.pixel(selected ? .check : .plus, size: 16)
                    .foregroundStyle(selected ? Color.ppOnAccent : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(selected ? Color.brand : Color.ppLine.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                            .foregroundStyle(Color.ppText)
                        if let badge {
                            Text(badge)
                                .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                                .foregroundStyle(Color.ppOnAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.ppDone, in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .glassCard(cornerRadius: DS.Radius.tile)
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                    .strokeBorder(selected ? Color.brand : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
