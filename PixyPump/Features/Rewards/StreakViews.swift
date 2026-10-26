import SwiftUI

/// Home's streak card: how long it is, whether today's done, a countdown while
/// it's at risk, the last 7 days, freezes and the next milestone.
struct StreakCard: View {
    let state: DailyStreakState
    /// Bumped when today gets secured: plays the spark ring once.
    @State private var burstCount = 0
    /// Week dots fill in one by one when the card first shows.
    @State private var dotsShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// After 20:00 with nothing done yet: the flame starts to wobble.
    private var lateAndAtRisk: Bool {
        state.atRisk && Calendar.current.component(.hour, from: .now) >= 20
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                flame
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                        .foregroundStyle(state.atRisk ? Color.ppFlame : Color.ppText)
                    if state.securedToday {
                        Text("See you tomorrow for day \(state.current + 1).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        // Live countdown to midnight.
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text("Train or win 1 challenge · \(Self.timeLeft(context.date)) left")
                                .font(.caption)
                                .foregroundStyle(state.atRisk ? Color.ppText : .secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            weekRow

            HStack(spacing: 12) {
                if state.freezes > 0 {
                    Label("\(state.freezes) \(state.freezes == 1 ? "freeze" : "freezes") ready", systemImage: "snowflake")
                        .foregroundStyle(Color.brand)
                        .accessibilityLabel("\(state.freezes) streak \(state.freezes == 1 ? "freeze" : "freezes") ready"
                                            + (state.bagFreezes > 0 ? ", \(state.bagFreezes) from gym bags" : ""))
                } else {
                    Text("7 days in a row earns a freeze ❄️")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let next = state.nextMilestone {
                    Text("\(next - state.current) to \(next) days · +\(DailyStreakState.milestoneXP(next)) XP + 🎁")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .overlay {
            if state.atRisk {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(Color.ppFlame.opacity(0.7), lineWidth: 1.5)
                    // Late in the day the warning border breathes.
                    .phaseAnimator(lateAndAtRisk && !reduceMotion ? [0.35, 1.0] : [1.0]) { view, glow in
                        view.opacity(glow)
                    } animation: { _ in .easeInOut(duration: 1.1) }
            }
        }
        .accessibilityElement(children: .combine)
        .onChange(of: state.securedToday) { was, now in
            guard !was, now, !reduceMotion else { return }
            burstCount += 1
        }
        .onAppear {
            guard !dotsShown else { return }
            dotsShown = true
        }
    }

    private var title: String {
        if state.securedToday { return "Day \(state.current) secured!" }
        if state.current > 0 { return "Don't lose your \(state.current)-day streak" }
        return "Start a streak today"
    }

    private var flame: some View {
        VStack(spacing: 0) {
            Text("🔥")
                .font(.system(size: 30))   // ds-allow: emoji size
                .grayscale(state.securedToday ? 0 : 1)
                .opacity(state.securedToday ? 1 : 0.55)
                // Ignites: grey → colour with a pop when today is secured.
                .animation(.easeOut(duration: 0.5), value: state.securedToday)
                .popOnChange(of: state.securedToday, scale: 1.5)
                .wobble(lateAndAtRisk)
                .background {
                    // A ring of sparks bursting out.
                    Circle()
                        .strokeBorder(Color.ppFlame, lineWidth: 3)
                        .keyframeAnimator(initialValue: SparkRing(), trigger: burstCount) { view, ring in
                            view.scaleEffect(ring.scale).opacity(ring.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(0.4, duration: 0.01)
                                CubicKeyframe(2.3, duration: 0.7)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(1, duration: 0.01)
                                CubicKeyframe(0, duration: 0.7)
                            }
                        }
                        .allowsHitTesting(false)
                }
            Text("\(state.current)")
                .font(.pixel(DS.TextSize.headline))
                .foregroundStyle(state.securedToday ? Color.ppFlame : Color.ppText)
                .contentTransition(.numericText(value: Double(state.current)))
                .animation(.snappy(duration: 0.4), value: state.current)
        }
        .frame(width: 52)
    }

    /// Mon–Sun style row of the last 7 days.
    private var weekRow: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        return HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let isToday = day == today
                let secured = state.securedDays.contains(day) && (dotsShown || reduceMotion)
                let frozen = state.frozenDays.contains(day) && (dotsShown || reduceMotion)
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(secured ? Color.ppFlame : (frozen ? Color.brand.opacity(0.35) : Color.ppLine.opacity(0.08)))
                        if secured {
                            Image.pixel(.check, size: 12).foregroundStyle(Color.ppBackground)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                        } else if frozen {
                            Image(systemName: "snowflake").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.brand)   // ds-allow: icon size
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(width: 26, height: 26)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(index) * 0.07), value: dotsShown)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: secured)
                    .overlay {
                        if isToday && !secured {
                            Circle().strokeBorder(Color.ppFlame, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        }
                    }
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(isToday ? Color.ppText : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// "5h 12m" until midnight.
    static func timeLeft(_ now: Date) -> String {
        let cal = Calendar.current
        guard let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return "" }
        let minutes = max(0, Int(midnight.timeIntervalSince(now) / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// Small flame + number for headers.
struct StreakChip: View {
    let days: Int
    let secured: Bool

    var body: some View {
        HStack(spacing: 2) {
            Text("🔥").font(.system(size: 12)).grayscale(secured ? 0 : 1)   // ds-allow: emoji size
            Text("\(days)")
                .font(.pixel(DS.TextSize.caption))
                .foregroundStyle(secured ? Color.ppFlame : .secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("\(days)-day streak\(secured ? "" : ", not secured today")")
    }
}

/// Asks for notifications at a happy moment (after a workout), explaining why first.
struct ReminderPromptCard: View {
    let allow: @MainActor () async -> Void
    @State private var asking = false

    var body: some View {
        HStack(spacing: 14) {
            PixelBuddy(mood: .idle, size: 52, action: .wave)
            VStack(alignment: .leading, spacing: 6) {
                Text("Want a nudge on training days?")
                    .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                    .foregroundStyle(Color.ppText)
                Text("Your buddy reminds you at your usual time and warns you before your 🔥 streak ends. One a day, max.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    asking = true
                    Task {
                        await allow()
                        asking = false
                    }
                } label: {
                    Text("Turn on reminders")
                        .font(.pixel(DS.TextSize.footnote))
                        .foregroundStyle(Color.ppBackground)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(asking)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: DS.Radius.card)
    }
}

/// Values for the streak card's spark ring (invisible until it plays).
private struct SparkRing {
    var scale: CGFloat = 0.4
    var opacity: Double = 0
}
