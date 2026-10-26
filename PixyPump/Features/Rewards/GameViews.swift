import SwiftUI
import SwiftData

/// Home header: your buddy, greeting, level and XP bar. Tap the buddy for a pep talk,
/// tap the level line to see how XP and rewards work.
struct BuddyHeader: View {
    let name: String
    let level: Level
    let mood: PixelBuddy.Mood
    var streak: DailyStreakState? = nil

    @State private var bounce = false
    @State private var line: String?
    /// Plays for a moment when you tap the buddy.
    @State private var tapAction: MascotAction?
    @State private var customising = false
    /// "How rewards work" sheet, opened from the level line.
    @State private var showingGuide = false
    /// Every so often the buddy does a little move on its own, so Home feels alive.
    @State private var idleAction: MascotAction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lines: [String] {
        switch mood {
        case .flex: return ["Look at those gains!", "Great work today.", "Strong!"]
        case .sleepy: return ["Rest days build muscle too.", "Zzz… recovering.", "See you next workout."]
        case .idle: return ["Let's lift!", "One set at a time.", "Ready when you are."]
        }
    }

    /// "320 XP to Level 5 · unlocks Mohawk hair"
    private var nextLine: String {
        var text = "\(level.xpToNext.spaced) XP to Level \(level.number + 1)"
        if let next = MascotOptions.nextUnlock(after: level.number), let first = next.names.first {
            text += next.level == level.number + 1 ? " · unlocks \(first)" : " · \(first) at Level \(next.level)"
        }
        return text
    }

    /// What VoiceOver reads for the level line.
    private var levelSummary: String {
        var text = "Level \(level.number), \(level.title). \(nextLine)"
        if let streak, streak.current > 0 { text += ". \(streak.current)-day streak" }
        return text
    }

    var body: some View {
        HStack(spacing: 14) {
            // Tap your buddy: a quick happy reaction, then the wardrobe opens.
            Button {
                Haptics.press()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { bounce = true }
                line = lines.randomElement()
                tapAction = mood == .sleepy ? .wave : [MascotAction.cheer, .flex, .lift].randomElement()
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.spring) { bounce = false }
                    try? await Task.sleep(for: .milliseconds(150))
                    customising = true
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { line = nil }
                    tapAction = nil
                }
            } label: {
                PixelBuddy(mood: mood, size: 60, action: tapAction ?? idleAction, backdrop: true)
                    .padding(4)
                    .background(Color.ppCard, in: RoundedRectangle(cornerRadius: DS.Radius.m))
                    // Little pencil so it's clear you can dress your buddy.
                    .overlay(alignment: .bottomTrailing) {
                        Image.pixel(.pencil, size: 11)
                            .foregroundStyle(Color.ppBackground)
                            .frame(width: 22, height: 22)
                            .background(Color.brand, in: Circle())
                            .overlay(Circle().strokeBorder(Color.ppBackground, lineWidth: 2))
                            .offset(x: 6, y: 6)
                    }
                    .scaleEffect(bounce ? 1.12 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your buddy")
            .accessibilityHint("Opens the buddy wardrobe to change how your buddy looks")
            .sheet(isPresented: $customising) {
                NavigationStack { BuddyEditorView() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(line ?? (name.isEmpty ? "Hello" : "Hello, \(name)"))
                    .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                    .foregroundStyle(Color.ppText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                // Level, XP bar and what's next: tap to learn how rewards work.
                Button {
                    Haptics.tap()
                    showingGuide = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("LV \(level.number) · \(level.title.uppercased())")
                                .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                                .foregroundStyle(Color.ppFat)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            XPBar(progress: level.progress)
                            if let streak, streak.current > 0 {
                                StreakChip(days: streak.current, secured: streak.securedToday)
                                    .popOnChange(of: streak.current, scale: 1.35)
                            }
                        }
                        // Rolls down as you earn XP anywhere in the app.
                        Text(nextLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText(value: Double(level.xpToNext)))
                            .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: level.xpToNext)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(levelSummary)
                .accessibilityHint("Shows how XP, levels and rewards work")
                .accessibilityAddTraits(.isButton)
            }
        }
        .sheet(isPresented: $showingGuide) {
            RewardsGuideSheet()
        }
        .task {
            // Idle life: a small wave/flex every ~12 s while Home is on screen.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 9...15)))
                guard tapAction == nil else { continue }
                idleAction = mood == .sleepy ? .sleepy : [MascotAction.wave, .flex, .lift].randomElement()
                try? await Task.sleep(for: .seconds(1.6))
                idleAction = nil
            }
        }
    }
}

/// Thin pixel-segment XP bar.
struct XPBar: View {
    let progress: Double
    var segments = 10
    /// Settings → Appearance → XP bar.
    var style: XPBarStyle = XPBarStyle.current

    var body: some View {
        switch style {
        case .segments: segmentsBar
        case .hearts: heartsBar
        case .battery: batteryBar
        case .flame: flameBar
        }
    }

    private var p: Double { min(max(progress, 0), 1) }

    /// Five pixel hearts filling up, like a health bar.
    private var heartsBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let fill = min(max(p * 5 - Double(i), 0), 1)
                ZStack {
                    Image.pixel(.heart, size: 10).foregroundStyle(Color.ppLine.opacity(0.18))
                    Image.pixel(.heart, size: 10).foregroundStyle(Color.ppHeart)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: 10 * fill)
                        }
                }
                .animation(.snappy.delay(Double(i) * 0.05), value: progress)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(Int(p * 100)) percent to next level")
    }

    /// A little battery charging up.
    private var batteryBar: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Color.ppLine.opacity(0.5), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1)
                    .fill(p > 0.2 ? Color.ppDone : Color.ppFlame)
                    .frame(width: max(0, 40 * p))
                    .padding(2)
            }
            .frame(width: 44, height: 10)
            Rectangle().fill(Color.ppLine.opacity(0.5)).frame(width: 2, height: 4)
        }
        .animation(.snappy, value: progress)
        .accessibilityElement()
        .accessibilityLabel("\(Int(p * 100)) percent to next level")
    }

    /// A pixel bar that turns hotter as it fills, with a flame at the tip.
    private var flameBar: some View {
        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ppLine.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [Color.ppFlameLight, Color.ppFlame, Color.ppFlameDeep],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 50 * p)
            }
            .frame(width: 50, height: 6)
            Text("🔥").font(.system(size: 8 + 6 * p))   // ds-allow: emoji grows with XP
        }
        .animation(.snappy, value: progress)
        .accessibilityElement()
        .accessibilityLabel("\(Int(p * 100)) percent to next level")
    }

    private var segmentsBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(Double(i) < progress * Double(segments) ? Color.ppFat : Color.ppLine.opacity(0.15))
                    .frame(width: 6, height: 6)
                    // Segments light up one after another when XP comes in.
                    .animation(.snappy.delay(Double(i) * 0.04), value: progress)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(Int(progress * 100)) percent to next level")
    }
}

// MARK: - Level up

struct LevelUpView: View {
    @Environment(\.dismiss) private var dismiss
    let level: Level

    @State private var appeared = false
    @State private var showingGuide = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("LEVEL UP!")
                .font(.pixel(DS.TextSize.display, relativeTo: .largeTitle))
                .foregroundStyle(Color.ppFat)
                .scaleEffect(appeared ? 1 : 0.4)
            PixelBuddy(mood: .flex, size: 180, action: .cheer)
                .scaleEffect(appeared ? 1 : 0.6)
            VStack(spacing: 8) {
                Text("Level \(level.number)")
                    .font(.pixel(DS.TextSize.largeTitle, relativeTo: .title))
                    .foregroundStyle(Color.ppText)
                Text(level.title.uppercased())
                    .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                    .foregroundStyle(Color.brand)
                let unlocked = MascotOptions.unlocks(at: level.number)
                if unlocked.isEmpty {
                    Text("Every workout and every kg you lift earns XP.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Text("New for your buddy: " + unlocked.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(Color.ppFat)
                        .padding(.top, 4)
                    Text("Dress up your buddy (tap it on Home) or change the app's look in Settings → Appearance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 4) {
                Button { dismiss() } label: { Text("Nice!") }
                    .buttonStyle(.primary)
                Button {
                    Haptics.tap()
                    showingGuide = true
                } label: {
                    Text("How rewards work")
                        .font(.subheadline)
                        .foregroundStyle(Color.brand)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showingGuide) {
            RewardsGuideSheet()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .background(AppBackground())
        .onAppear {
            Haptics.success()
            SFX.play(.levelUp)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { appeared = true }
        }
    }
}

// MARK: - Badges

/// One sticker: bright when earned, faded with a lock when not.
struct BadgeSticker: View {
    let badge: Badge
    let earned: Bool
    var size: CGFloat = 56

    var body: some View {
        Image.pixel(badge.glyph, size: size * 0.5)
            .foregroundStyle(earned ? Color.ppOnAccent : Color.ppLine.opacity(0.35))
            .frame(width: size, height: size)
            .background(earned ? Color.ppFat : Color.ppLine.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if !earned {
                    Image.pixel(.eyeOff, size: 16)
                        .foregroundStyle(Color.ppLine.opacity(0.4))
                        .padding(4)
                }
            }
    }
}

/// The sticker book: every badge, earned or still to go.
struct BadgeBookView: View {
    @Query(sort: \WorkoutSet.date) private var sets: [WorkoutSet]

    var body: some View {
        let stats = GameStats(allSets: sets)
        let earned = Badge.all.filter { $0.earned(stats) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(earned.count) of \(Badge.all.count) earned")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                    ForEach(Badge.all) { badge in
                        let has = badge.earned(stats)
                        VStack(spacing: 8) {
                            BadgeSticker(badge: badge, earned: has, size: 64)
                            Text(badge.title)
                                .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                                .foregroundStyle(has ? Color.ppText : .secondary)
                                .multilineTextAlignment(.center)
                            Text(badge.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .glassCard(cornerRadius: DS.Radius.tile)
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { BadgeLog.markSeen(earned.map(\.id)) }
    }
}

/// "New badge!" card on the workout summary.
struct NewBadgesCard: View {
    let badges: [Badge]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PPHeader(badges.count == 1 ? "New badge!" : "New badges!")
            ForEach(badges) { badge in
                HStack(spacing: 14) {
                    BadgeSticker(badge: badge, earned: true, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.title).font(.pixel(DS.TextSize.callout)).foregroundStyle(Color.ppText)
                        Text(badge.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: DS.Radius.card)
    }
}

// MARK: - Year in review

/// A few swipeable pixel slides about your year so far.
struct YearReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSet.date) private var sets: [WorkoutSet]

    private var year: Int { Calendar.current.component(.year, from: .now) }

    private struct Slide: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let caption: String
        let glyph: PixelGlyph
    }

    private var slides: [Slide] {
        let cal = Calendar.current
        let thisYear = sets.filter { !$0.isWarmup && cal.component(.year, from: $0.date) == year }
        let stats = GameStats(allSets: thisYear)
        let tonnes = stats.totalKg / 1000
        let cars = tonnes / 1.5
        let sessions = WorkoutSession.all(from: thisYear)
        let hours = Double(sessions.compactMap(\.minutes).reduce(0, +)) / 60

        let byName = Dictionary(grouping: thisYear) { $0.exercise?.name ?? "" }.filter { !$0.key.isEmpty }
        let strongest = byName.compactMap { name, list -> (String, Double)? in
            guard let best = list.map(\.estimatedMax).max() else { return nil }
            return (name, best)
        }.max { $0.1 < $1.1 }
        let favourite = byName.map { name, list in
            (name, Set(list.map { cal.startOfDay(for: $0.date) }).count)
        }.max { $0.1 < $1.1 }

        let allStats = GameStats(allSets: sets)
        let workoutsCaption = (stats.workouts == 1 ? "workout logged" : "workouts logged")
            + (hours >= 1 ? " · about \(Int(hours.rounded())) hours" : "")
        let carCount = Int(cars.rounded())
        var list: [Slide] = [
            Slide(label: "\(year) SO FAR", value: "\(stats.workouts)",
                  caption: workoutsCaption, glyph: .dumbbell),
            Slide(label: "YOU LIFTED",
                  value: tonnes >= 10 ? "\(Int(tonnes.rounded())) t" : "\(Units.volume(stats.totalKg)) \(Units.symbol)",
                  caption: carCount >= 1 ? "That's about \(carCount) \(carCount == 1 ? "car" : "cars")." : "Every set adds up.",
                  glyph: .trendingUp),
        ]
        if let strongest {
            list.append(Slide(label: "STRONGEST LIFT", value: Units.weight(strongest.1),
                              caption: "Estimated 1-rep max on \(strongest.0)", glyph: .trophy))
        }
        if let favourite {
            list.append(Slide(label: "YOUR FAVOURITE", value: favourite.0,
                              caption: "Trained on \(favourite.1) days", glyph: .star))
        }
        // The daily 🔥 streak is the app's one streak.
        let bestDays = DailyStreak.compute(sets: sets).best
        list.append(Slide(label: "BEST STREAK", value: "\(bestDays) \(bestDays == 1 ? "day" : "days")",
                          caption: "Level \(allStats.level.number) · \(allStats.level.title)",
                          glyph: .fire))
        return list
    }

    var body: some View {
        NavigationStack {
            TabView {
                ForEach(slides) { slide in
                    VStack(spacing: 20) {
                        Spacer()
                        Image.pixel(slide.glyph, size: 64).foregroundStyle(Color.ppFat)
                        Text(slide.label)
                            .font(.pixel(DS.TextSize.callout, relativeTo: .headline))
                            .foregroundStyle(Color.brand)
                        Text(slide.value)
                            .font(.pixel(DS.TextSize.hero, relativeTo: .largeTitle))
                            .foregroundStyle(Color.ppText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.4)
                            .padding(.horizontal, 24)
                        Text(slide.caption)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .multilineTextAlignment(.center)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
