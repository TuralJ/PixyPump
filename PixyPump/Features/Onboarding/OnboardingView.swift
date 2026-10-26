import SwiftUI
import UserNotifications

/// Asks ContentView to switch tabs from places that can't reach `selectTab`.
/// The welcome flow is a full-screen cover, which sits outside the tab view's
/// environment, so its `selectTab` is the do-nothing default.
/// ContentView watches this key, switches tab, then clears it back to -1.
enum TabRequest {
    /// AppStorage key holding the wanted `AppTab.rawValue` (-1 = nothing pending).
    static let key = "requestedTab"

    static func send(_ tab: AppTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: key)
    }
}

/// First-launch setup, kept short: you and your units, your body, then the plan
/// questions → a plan built for you, then optional Apple Health, calorie goals
/// and rest alerts. Everything can be changed later.
struct OnboardingView: View {
    @AppStorage(Prefs.userName) private var userName = ""
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(Prefs.lengthUnit) private var lengthRaw = "cm"
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @AppStorage(HealthSync.enabledKey) private var healthOn = false

    @AppStorage("profileSex") private var sex = "male"
    @AppStorage("profileAge") private var age = 25
    @AppStorage("profileBirthDate") private var birthStamp = 0.0
    @AppStorage("profileHeight") private var height = 175.0
    @AppStorage("profileWeight") private var weight = 75.0

    @AppStorage("goalKcal") private var goalKcal = 2500.0
    @AppStorage("goalProtein") private var goalProtein = 160.0
    @AppStorage("goalCarbs") private var goalCarbs = 280.0
    @AppStorage("goalFat") private var goalFat = 75.0
    @AppStorage("goalsSetUp") private var goalsSetUp = false

    @State private var answers = PlanAnswers()
    /// Privacy Policy / Terms opened from the welcome screen.
    @State private var legal: LegalDocument?
    @State private var index = 0
    /// Decided once when onboarding opens, so the steps don't shift after you sign in.
    @State private var askForAccount = !AuthStore.shared.isSignedIn
    @State private var nameText = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var loadingHealthWeight = false
    /// You skipped "Your body", so calories are only a rough estimate.
    @State private var skippedProfile = false
    @FocusState private var nameFocused: Bool
    /// The plan built at the "Your plan" step (for the final summary).
    @State private var builtPlan: GeneratedPlan?
    /// Usually the do-nothing default here (see `TabRequest`), but harmless to call too.
    @Environment(\.selectTab) private var selectTab
    @AppStorage("workoutOpenNext") private var openWorkoutNext = false
    /// Same keys Home and Workout use to remember the last day you trained.
    @AppStorage("lastTrainedDay") private var lastTrainedDay = 0
    @AppStorage("lastTrainedAt") private var lastTrainedAt = 0.0

    enum Step: Hashable {
        case welcome
        /// Name plus units, on one screen.
        case you
        /// Sex, birth date, height and weight, on one screen.
        case profile
        case plan(PlanStep)
        /// Optional account: "Save your progress" (Apple, Google or email).
        case account
        case health, calories, alerts
        /// "You're all set!" — the reward at the end.
        case done
    }

    private var steps: [Step] {
        var list: [Step] = [.welcome, .you, .profile]
        list += PlanStep.allCases.map { .plan($0) }
        // Right after seeing your plan: the moment you most want to keep it.
        if askForAccount { list.append(.account) }
        if HealthSync.isConfigured { list.append(.health) }
        list += [.calories, .alerts, .done]
        return list
    }

    private var step: Step { steps[min(index, steps.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StepBar(current: index, total: steps.count - 1)
                // Optional "about me" questions can be skipped from the top.
                if canSkipFromTop {
                    Button {
                        Haptics.tap()
                        skippedProfile = true
                        advance()
                    } label: {
                        Text("Skip")
                            .font(.pixel(DS.TextSize.subhead, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .opacity(index == 0 || step == .done ? 0 : 1)

            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            buttons
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .background(AppBackground())
        .animation(.snappy, value: index)
        .onAppear {
            nameText = userName
            if birthStamp > 0 { birthDate = Date(timeIntervalSince1970: birthStamp) }
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 8) {
            // The account step has its own sign-in buttons; "Continue" appears once you're in.
            if step != .account || AuthStore.shared.isSignedIn {
                Button { primary() } label: { Text(primaryTitle) }
                    .buttonStyle(.primary)
            }
            if let secondaryTitle {
                Button { Haptics.tap(); secondary() } label: {
                    Text(secondaryTitle)
                        .font(.pixel(DS.TextSize.body))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Needed to build the plan: goals, experience, schedule, equipment (and units, which have defaults).
    /// Optional: name, your body, focus/avoid, Health, calories, alerts.
    private var canSkipFromTop: Bool {
        step == .profile
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .plan(.extras): return "Build my plan"
        case .plan(.result): return "Use this plan"
        case .health: return "Connect Apple Health"
        case .calories: return "Use these goals"
        case .alerts: return "Allow rest alerts"
        case .done: return Routine.dayCount > 0 ? "Start Day 1 · \(Routine.dayName(1))" : "Let's go!"
        default: return "Continue"
        }
    }

    /// Optional steps get "Skip" (always that one word); others get "Back".
    private var secondaryTitle: String? {
        switch step {
        case .welcome: return nil
        case .done: return "Look around first"
        case .account: return AuthStore.shared.isSignedIn ? nil : "Skip for now"
        case .health, .calories, .alerts: return "Skip"
        default: return "Back"
        }
    }

    // MARK: Screens

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .you: youScreen
        case .profile: profileScreen
        case .plan(let planStep): PlanQuestionScreen(step: planStep, answers: answers)
        case .account:
            if let user = AuthStore.shared.user {
                VStack(alignment: .leading, spacing: 16) {
                    PixelBuddy(mood: .flex, size: 96, action: .cheer, backdrop: true)
                    Text("You're in! 🎉")
                        .font(.pixel(DS.TextSize.title, relativeTo: .title))
                        .foregroundStyle(Color.ppText)
                    Text("Signed in with \(user.provider.title). Your progress is saved to your account.")
                        .foregroundStyle(.secondary)
                }
            } else {
                SaveProgressView(embedded: true) { advance() }
            }
        case .health: healthScreen
        case .calories: caloriesScreen
        case .alerts: alertsScreen
        case .done: DoneScreen(name: userName, plan: builtPlan,
                               kcal: goalsSetUp ? goalKcal : nil,
                               protein: goalsSetUp ? goalProtein : nil)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(AppInfo.name)
                .padding(.top, 24)
                .font(.pixel(DS.TextSize.hero, relativeTo: .largeTitle))
                .foregroundStyle(Color.ppText)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("Answer a few quick questions and we'll build a training plan around you.")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick your gym buddy")
                    .font(.subheadline)
                    .foregroundStyle(Color.ppText)
                MascotPicker(size: 88)
                Text("They'll lift, flex and cheer with you. Change anytime in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature(.dumbbell, "A plan built for your goal, time and equipment")
                feature(.clock, "Rest alarm that rings even on silent")
                feature(.fire, "Calories and macros with barcode scanning")
                feature(.save, "No account — everything stays on your iPhone")
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("By continuing, you agree to our")
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    // Labels padded out to 44 pt tall so they're easy to tap.
                    Button { legal = .terms } label: {
                        Text("Terms of Use").frame(minHeight: 44).contentShape(Rectangle())
                    }
                    Text("and").foregroundStyle(.secondary)
                    Button { legal = .privacy } label: {
                        Text("Privacy Policy").frame(minHeight: 44).contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brand)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .sheet(item: $legal) { document in
            NavigationStack {
                LegalView(document: document)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { legal = nil }
                        }
                    }
            }
        }
    }

    private func feature(_ icon: PixelGlyph, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image.pixel(icon).foregroundStyle(Color.brand)
            Text(text).foregroundStyle(Color.ppText)
        }
    }

    /// Name and units together: quick, and all of it has sensible defaults.
    private var youScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            WizardTitle("Let's set you up")
            VStack(alignment: .leading, spacing: 8) {
                Text("Your first name").font(.subheadline).foregroundStyle(Color.ppText)
                TextField("Optional", text: $nameText)
                    .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                    .foregroundStyle(Color.ppText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit { nameFocused = false }
                    .padding(18)
                    .glassCard(cornerRadius: DS.Radius.tile)
                Text("For the greeting on Home. Leave it empty if you like.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PixelSegments(title: "Weights you lift", selection: $unitRaw,
                          options: [("kg", "Kilograms"), ("lb", "Pounds")])
            PixelSegments(title: "Height & body measurements", selection: $lengthRaw,
                          options: [("cm", "Centimetres"), ("in", "Inches")])
            Text("Change any of this later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Sex, birth date, height and weight on one screen (used for calories).
    private var profileScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            WizardTitle("Your body")
            Text("Used to estimate your calories. A rough number is fine, and it stays on your phone.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PixelSegments(title: "Sex", selection: $sex,
                          options: [("male", "Male"), ("female", "Female"), ("other", "Other")])

            HStack {
                Text("Birth date").foregroundStyle(Color.ppText)
                Spacer()
                DatePicker("Birth date", selection: $birthDate,
                           in: (Calendar.current.date(byAdding: .year, value: -90, to: .now) ?? .distantPast) ...
                               (Calendar.current.date(byAdding: .year, value: -13, to: .now) ?? .now),
                           displayedComponents: .date)
                    .labelsHidden()
            }
            .padding(16)
            .frame(minHeight: 44)
            .glassCard(cornerRadius: DS.Radius.tile)

            numberCard("Height", value: heightText, unit: nil,
                       less: "Shorter", more: "Taller") { direction in
                let step = lengthRaw == "in" ? 2.54 : 1
                height = min(230, max(120, height + direction * step))
            }

            numberCard("Weight", value: Units.display(weight).plain, unit: Units.symbol,
                       less: "Less weight", more: "More weight") { direction in
                let step = Units.current == .kg ? 0.5 : 1
                let shown = max(30, Units.display(weight) + direction * step)
                weight = Units.toKg(shown)
            }

            if HealthSync.isConfigured {
                Button {
                    loadingHealthWeight = true
                    Task {
                        if let kg = await HealthSync.latestBodyWeightKg() {
                            weight = (kg * 10).rounded() / 10
                            Haptics.success()
                        }
                        loadingHealthWeight = false
                    }
                } label: {
                    Label { Text(loadingHealthWeight ? "Reading Apple Health…" : "Import weight from Apple Health") }
                        icon: { Image.pixel(.heart) }
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(loadingHealthWeight)
            }
        }
    }

    private var heightText: String {
        if lengthRaw == "in" {
            let inches = Int((height / 2.54).rounded())
            return "\(inches / 12)′ \(inches % 12)″"
        }
        return "\(Int(height.rounded())) cm"
    }

    /// A big number with − and + either side (52 pt buttons, hold to repeat).
    private func numberCard(_ label: String, value: String, unit: String?,
                            less: String, more: String,
                            nudge: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 12) {
            nudgeButton(-1, label: less, nudge: nudge)
            VStack(spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.pixel(DS.TextSize.largeTitle, relativeTo: .title))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            nudgeButton(1, label: more, nudge: nudge)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.tile)
    }

    private func nudgeButton(_ direction: Double, label: String,
                             nudge: @escaping (Double) -> Void) -> some View {
        Button {
            Haptics.select()
            nudge(direction)
        } label: {
            Image.pixel(direction < 0 ? .minus : .plus)
                .foregroundStyle(Color.ppText)
                .frame(width: 52, height: 52)
                .background(Color.ppLine.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private var healthScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image.pixel(.heart, size: 48).foregroundStyle(Color.ppProtein)
            WizardTitle("Connect Apple Health?")
            Text("\(AppInfo.name) can save your workouts to Apple Health as strength training and read your latest body weight. You choose exactly what to share on the next screen.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Skip to decide later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var calc: GoalCalculator {
        let activity: Int
        switch answers.days {
        case ...3: activity = 1
        case 4...5: activity = 2
        default: activity = 3
        }
        // Fat loss wins (you can still build muscle while losing fat); then muscle; else maintain.
        let goal: String
        if answers.goals.contains(.fatLoss) {
            goal = "lose"
        } else if answers.goals.contains(.muscle) {
            goal = "gain"
        } else {
            goal = "maintain"
        }
        return GoalCalculator(sex: sex, age: age, heightCm: height, weightKg: weight, activity: activity, goal: goal)
    }

    private var caloriesScreen: some View {
        let c = calc
        return VStack(alignment: .leading, spacing: 16) {
            WizardTitle("Your daily calories")
            Text(skippedProfile
                 ? "A rough estimate, because you skipped some details about you. Add them later in Settings → Goals for a better number."
                 : "Based on your answers. Use them to track food, or skip if you only want to track workouts.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(c.kcal).spaced) kcal")
                    .font(.pixel(DS.TextSize.display, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ppText)
                Text("You burn about \(Int(c.maintenance).spaced) kcal a day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: DS.Radius.card)
            MacroExplainRow(name: "Protein", grams: c.protein, color: .ppProtein,
                            text: "Builds and repairs muscle. Try to hit it every day.")
            MacroExplainRow(name: "Carbs", grams: c.carbs, color: .ppCarbs,
                            text: "Fuel for training.")
            MacroExplainRow(name: "Fat", grams: c.fat, color: .ppFat,
                            text: "Needed for hormones and health.")
        }
    }

    private var alertsScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image.pixel(.bell, size: 48).foregroundStyle(Color.ppFat)
            WizardTitle("Know when rest is over")
            Text("The rest timer can buzz or ring when it's time for your next set, even with your phone locked. iOS will ask you to allow this.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Skip to decide later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Navigation

    private func primary() {
        Haptics.press()
        switch step {
        case .you:
            userName = nameText.trimmingCharacters(in: .whitespaces)
            nameFocused = false
        case .profile:
            birthStamp = birthDate.timeIntervalSince1970
            age = Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? age
            BodyWeightStore.shared.log(kg: weight)
        case .plan(.result):
            let plan = PlanGenerator.make(answers.inputs)
            answers.apply(plan)
            builtPlan = plan
        case .health:
            healthOn = true
            Task { _ = await HealthSync.requestAccess() }
        case .calories:
            let c = calc
            goalKcal = c.kcal
            goalProtein = c.protein
            goalCarbs = c.carbs
            goalFat = c.fat
            goalsSetUp = true
        case .alerts:
            Task {
                if #available(iOS 26.0, *), RestAlarm.isConfigured { _ = await RestAlarm.isAllowed() }
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
        case .done:
            // Straight into the first workout, same as Home's Start button:
            // start Day 1, ask the Workout tab to open its first exercise,
            // switch to that tab, then close the welcome flow.
            Haptics.success()
            if Routine.dayCount > 0 {
                if !ActiveWorkout.shared.isInProgress {
                    ActiveWorkout.shared.start(day: 1)
                    lastTrainedDay = 1
                    lastTrainedAt = Date.now.timeIntervalSince1970
                }
                openWorkoutNext = true
            }
            // Works from inside this full-screen cover (ContentView watches the key).
            TabRequest.send(.workout)
            selectTab(.workout)
            onboarded = true
            return
        default:
            break
        }
        advance()
    }

    private func secondary() {
        switch step {
        case .done:
            onboarded = true       // "Look around first": land on Home
        case .account, .health, .calories, .alerts:
            advance()          // skip this optional step
        default:
            if index > 0 { index -= 1 }
        }
    }

    private func advance() {
        if index < steps.count - 1 {
            index += 1
        } else {
            onboarded = true
        }
    }
}

// MARK: - "You're all set!"

/// The reward at the end of onboarding: buddy celebration, a welcome gift that
/// lands you on level 2 (with an unlock), your game plan and the first 3 steps.
private struct DoneScreen: View {
    let name: String
    let plan: GeneratedPlan?
    let kcal: Double?
    let protein: Double?

    /// Gets you to level 2 straight away, so something unlocks on day one.
    static let welcomeXP = 200

    @State private var appeared = false
    @State private var giftShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 10) {
                PixelBuddy(mood: .flex, size: 150, action: .celebrate, backdrop: true)
                    .scaleEffect(appeared ? 1 : 0.5)
                Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "You're all set!" : "You're all set, \(name)!")
                    .font(.pixel(DS.TextSize.title, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ppText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your plan is ready and your buddy is pumped. Here's your game plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            // Welcome gift.
            HStack(spacing: 14) {
                PixelBag(open: giftShown)
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(giftShown ? 0 : -8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome gift: +\(Self.welcomeXP) XP")
                        .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                        .foregroundStyle(Color.ppFat)
                    Text("You're level 2 already. Pink hair is unlocked for your buddy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .glassCard(cornerRadius: DS.Radius.card)
            .scaleEffect(giftShown ? 1 : 0.9)
            .opacity(giftShown ? 1 : 0)

            // Your plan in one glance.
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR PLAN")
                    .font(.pixel(DS.TextSize.caption))
                    .foregroundStyle(Color.brand)
                Text(plan?.splitName ?? "\(Routine.dayCount)-day plan")
                    .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                    .foregroundStyle(Color.ppText)
                planRow(.calendar, "\(Routine.dayCount) \(Routine.dayCount == 1 ? "day" : "days") a week"
                        + (plan.map { " · about \($0.minutes) min" } ?? ""))
                if Routine.dayCount > 0 {
                    planRow(.dumbbell, "Day 1: \(Routine.dayName(1)) · \(Routine.exercises(onDay: 1).count) exercises")
                }
                if let kcal, let protein {
                    planRow(.fire, "\(Int(kcal).spaced) kcal · \(Int(protein)) g protein a day")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: DS.Radius.card)

            // First steps (short and winnable).
            VStack(alignment: .leading, spacing: 12) {
                Text("FIRST WEEK CHECKLIST")
                    .font(.pixel(DS.TextSize.caption))
                    .foregroundStyle(Color.brand)
                step(1, "Do Day 1", "Every set you log races your past self.")
                step(2, "Win a daily challenge", "Starts your 🔥 streak today.")
                step(3, "Finish every set", "Earns your first gym bag.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: DS.Radius.card)

            Text("Everything can be changed later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .overlay { PixelConfetti() }
        .onAppear {
            BonusXP.award("welcome", xp: Self.welcomeXP)
            Haptics.success()
            SFX.play(.workoutComplete)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            Task {
                try? await Task.sleep(for: .milliseconds(1300))
                Haptics.success()
                SFX.play(.mission)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { giftShown = true }
            }
        }
    }

    private func planRow(_ glyph: PixelGlyph, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image.pixel(glyph, size: 16).foregroundStyle(Color.brand)
            Text(text).font(.subheadline).foregroundStyle(Color.ppText)
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.pixel(DS.TextSize.subhead))
                .foregroundStyle(Color.ppBackground)
                .frame(width: 26, height: 26)
                .background(Color.ppFat, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(Color.ppText)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Big pixel segmented choice

/// A pixel-styled stand-in for the system segmented control: every option is
/// at least 48 pt tall, so it's easy to hit. Options are (tag, label) pairs.
private struct PixelSegments: View {
    let title: String
    @Binding var selection: String
    let options: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Color.ppText)
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    let on = selection == option.0
                    Button {
                        Haptics.select()
                        selection = option.0
                    } label: {
                        Text(option.1)
                            .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(on ? Color.ppOnAccent : Color.ppText)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(on ? Color.brand : Color.ppLine.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: DS.Radius.s))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(option.1)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
