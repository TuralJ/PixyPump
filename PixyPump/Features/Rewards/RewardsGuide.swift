import SwiftUI

// "How rewards work": one short, friendly page that explains XP, levels, the daily
// streak, weekly missions, the journey, gym bags and duels in plain words.
// Opened from the level line on Home and from the level-up screen.

/// The guide itself (scrolls; put it inside a NavigationStack).
struct RewardsGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Everything you do in \(AppInfo.name) earns something. Here's the whole system on one page.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                section(.star, "XP and levels", lines: [
                    "XP fills your level bar. More XP, higher level.",
                    "A workout earns the most: +\(WorkoutReward.showUpXP) for showing up, +\(WorkoutMissions.completeXP) for finishing every set, plus PRs and weight lifted.",
                    "Daily challenges, weekly missions, duels and the journey add more on top.",
                    "Back after a week away? Your next workout earns double XP.",
                    "Hit your plan several weeks in a row and workouts earn up to ×1.5 XP (the weeks-on-plan bonus).",
                ]) {
                    HStack(spacing: 8) {
                        Text("LV 5")
                            .font(.pixel(DS.TextSize.caption))
                            .foregroundStyle(Color.ppFat)
                        XPBar(progress: 0.6, style: .segments)
                    }
                    .accessibilityHidden(true)
                }

                section(.fire, "Daily challenges and your streak", lines: [
                    "Three small challenges every day: one food, one training, one wildcard.",
                    "Win any one (or train) and today counts for your 🔥 streak. Win all 3 for a +\(DailyChallenges.sweepXP) XP clean sweep.",
                    "7 days in a row earns a ❄️ freeze (hold up to \(DailyStreak.maxFreezes)). A freeze saves your streak if you miss a day.",
                    "Gym bags can drop extra freezes too (hold up to \(DailyStreak.maxBagFreezes) more).",
                    "Streak milestones (3, 7, 14, 30 days…) pay XP and a gym bag.",
                ])

                section(.target, "Weekly missions", lines: [
                    "Three bigger goals that reset every Monday.",
                    "Each one pays XP once it's done.",
                    "Finish all 3 for +\(WeeklyMissions.sweepXP) XP and a gym bag.",
                ])

                section(.flag, "Journey", lines: [
                    "Every workout moves you one step along the map.",
                    "The last step of each chapter is a boss: finish every set in a workout to beat it.",
                    "Each chapter you clear pays bonus XP and unlocks a new backdrop for your buddy.",
                ])

                section(.dumbbell, "Gym bags", lines: [
                    "You earn one for finishing every set in a workout, for streak milestones, for clearing the weekly missions, and for the first week checklist.",
                    "Every bag rolls a rarity. Rarer bags give better prizes: bonus XP, a ❄️ streak freeze, or a buddy item you can only get from bags.",
                ]) {
                    rarityRow
                }

                section(.zap, "Duels", lines: [
                    "Your opponent is always you, last time.",
                    "Set duel: beat the same set from last time for +\(SetDuel.xp) XP (up to \(SetDuel.dailyXPCap) a day).",
                    "Exercise duel: lift more in total on an exercise than last time for +\(ExerciseDuels.xp) XP.",
                ])

                section(.trophy, "Unlocks", lines: [
                    "New levels unlock clothes and looks for your buddy. Tap your buddy on Home to dress it up.",
                    "Gym bags and journey chapters unlock extras you can't get any other way.",
                    "Badges are stickers for big moments, like your first PR or 100 workouts.",
                ]) {
                    HStack(spacing: 12) {
                        PixelBag().frame(width: 36, height: 36)
                        PixelBuddy(mood: .flex, size: 40)
                    }
                    .accessibilityHidden(true)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
    }

    /// The four rarities as coloured chips, e.g. "Epic gym bag".
    private var rarityRow: some View {
        let rarities: [GymBag.Rarity] = [.common, .rare, .epic, .legendary]
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                         alignment: .leading, spacing: 8) {
            ForEach(rarities, id: \.rawValue) { rarity in
                Text(rarity.bagName)
                    .font(.pixel(DS.TextSize.caption))
                    .foregroundStyle(Color.ppOnAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: rarity.hex), in: Capsule())
            }
        }
    }

    /// One card: a glyph, a heading, a few short lines and an optional little picture.
    private func section(_ glyph: PixelGlyph, _ title: String, lines: [String]) -> some View {
        section(glyph, title, lines: lines) { EmptyView() }
    }

    private func section<Extra: View>(_ glyph: PixelGlyph, _ title: String, lines: [String],
                                      @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image.pixel(glyph, size: 20)
                    .foregroundStyle(Color.ppFat)
                PPHeader(title)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Color.ppFat)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Color.ppText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            extra()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: DS.Radius.card)
    }
}

/// The guide in a sheet, with a Done button.
struct RewardsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RewardsGuideView()
                .navigationTitle("How rewards work")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
