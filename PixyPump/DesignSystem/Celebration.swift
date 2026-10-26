import SwiftUI

/// The "well done" message shown when you finish a workout.
/// Picks the most meaningful thing about this workout, so it feels personal, not canned.
struct FinishMessage {
    let title: String
    let line: String

    struct Facts {
        var name: String = ""
        /// Workouts ever, including this one.
        var workoutCount: Int
        var recordCount: Int
        /// Change in volume vs the last time you did this plan day (kg), if any.
        var volumeChangeKg: Double?
        /// Days since your workout before this one, if any.
        var daysSinceLast: Int?
        /// Weeks in a row you've hit your goal.
        var streakWeeks: Int
        var minutes: Int?
        /// Picks between equally good wordings, stable for the same workout.
        var seed: Int
    }

    @MainActor static func make(_ f: Facts) -> FinishMessage {
        let you = f.name.isEmpty ? "" : ", \(f.name)"
        let milestones: Set<Int> = [5, 10, 25, 50, 75, 100, 150, 200, 250, 300, 365, 500, 750, 1000]

        if f.workoutCount == 1 {
            return FinishMessage(title: "First one done!",
                                 line: "Every streak starts with day one\(you). See you next time.")
        }
        if f.recordCount > 0 {
            let what = f.recordCount == 1 ? "a new record" : "\(f.recordCount) new records"
            return FinishMessage(title: "New record!",
                                 line: "You set \(what) today\(you). Stronger than ever.")
        }
        if milestones.contains(f.workoutCount) {
            return FinishMessage(title: "Workout #\(f.workoutCount)!",
                                 line: f.workoutCount >= 50
                                    ? "That's not a phase anymore\(you). That's who you are."
                                    : "That's a habit forming\(you). Keep it rolling.")
        }
        if let gap = f.daysSinceLast, gap >= 10 {
            return FinishMessage(title: "Welcome back!",
                                 line: "The hardest part was showing up\(you), and you did.")
        }
        if let change = f.volumeChangeKg, change > 0 {
            return FinishMessage(title: "Leveling up!",
                                 line: "\(Units.volume(change)) \(Units.symbol) more than last time. Progress\(you)!")
        }
        if f.streakWeeks >= 2 {
            return FinishMessage(title: "\(f.streakWeeks) weeks strong!",
                                 line: "You keep showing up\(you). That's the whole secret.")
        }
        if let minutes = f.minutes, minutes <= 25 {
            return FinishMessage(title: "Short and done!",
                                 line: "A quick workout still counts\(you). Way better than none.")
        }
        let generic: [(String, String)] = [
            ("Nailed it!", "Another one in the books\(you)."),
            ("Workout done!", "Rest up\(you). Your muscles grow while you recover."),
            ("Great work!", "Future you says thanks\(you)."),
            ("Crushed it!", "That's how it's done\(you)."),
            ("Done and dusted!", "Drink some water and refuel\(you)."),
        ]
        let pick = generic[abs(f.seed) % generic.count]
        return FinishMessage(title: pick.0, line: pick.1)
    }
}

/// Big celebration at the top of the workout summary: your buddy flexing, a headline and a line.
struct CelebrationHeader: View {
    let message: FinishMessage
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            PixelBuddy(mood: .flex, size: 120, action: .celebrate, backdrop: true)
                .scaleEffect(shown ? 1 : 0.4)
                .rotationEffect(.degrees(shown ? 0 : -12))
            Text(message.title)
                .font(.pixel(DS.TextSize.title, relativeTo: .largeTitle))
                .foregroundStyle(Color.ppText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(message.line)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 16)
        .accessibilityElement(children: .combine)
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = true }
            }
        }
    }
}

/// Pixel confetti that rains down once, then disappears. Doesn't block taps.
struct PixelConfetti: View {
    var duration: Double = 2.6
    @State private var start = Date.now
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece {
        let x: Double       // 0...1 across the screen
        let delay: Double
        let speed: Double   // screens per second
        let drift: Double
        let size: Double
        let color: Color
    }

    /// Your confetti style (Settings → Appearance) and how big celebrations are.
    private let style = ConfettiStyle.current
    private let level = CelebrationLevel.current

    @State private var pieces: [Piece] = {
        let style = ConfettiStyle.current
        let colors: [Color]
        switch style {
        case .squares: colors = [.brand, .ppDone, .ppFat, .ppCarbs, .ppProtein, .ppFlame]
        case .flames: colors = [Color(hex: 0xFF7A3D), Color(hex: 0xFFB13D), Color(hex: 0xFFE07A), Color(hex: 0xE5482A)]
        case .snow: colors = [.white, Color(hex: 0xC9F1FF), Color(hex: 0xB0DCF7)]
        case .coins: colors = [Color(hex: 0xFFD45E), Color(hex: 0xFFC94A), Color(hex: 0xE0A82E)]
        case .stars: colors = [Color(hex: 0xB4A2FF), .white, Color(hex: 0xFFE07A), Color(hex: 0xF7A8C4)]
        }
        // Subtle: a light sprinkle.
        let count = CelebrationLevel.current == .subtle ? 24 : 70
        // Snow drifts down more slowly.
        let speeds: ClosedRange<Double> = style == .snow ? 0.25...0.45 : 0.45...0.8
        var rng = SystemRandomNumberGenerator()
        return (0..<count).map { i in
            Piece(x: Double.random(in: 0...1, using: &rng),
                  delay: Double.random(in: 0...0.6, using: &rng),
                  speed: Double.random(in: speeds, using: &rng),
                  drift: Double.random(in: -30...30, using: &rng),
                  size: style == .coins ? [8.0, 10.0, 12.0][i % 3] : [5.0, 6.0, 8.0][i % 3],
                  color: colors[i % colors.count])
        }
    }()

    var body: some View {
        if !reduceMotion && !finished && level != .minimal {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSince(start)
                    for p in pieces {
                        let local = t - p.delay
                        guard local > 0 else { continue }
                        let y = -20 + local * p.speed * size.height
                        guard y < size.height + 20 else { continue }
                        let x = p.x * size.width + sin(local * 3 + p.drift) * p.drift
                        let fade = max(0, min(1, (duration - t) / 0.6))
                        let rect = CGRect(x: x, y: y, width: p.size, height: p.size)
                        context.opacity = fade
                        context.fill(Self.shape(style, in: rect), with: .color(p.color))
                        if style == .coins {
                            // Pixel shine on each coin.
                            context.fill(Path(CGRect(x: rect.minX + p.size * 0.25, y: rect.minY + p.size * 0.2,
                                                     width: p.size * 0.2, height: p.size * 0.35)),
                                         with: .color(.white.opacity(0.7)))
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .seconds(duration))
                finished = true
            }
        }
    }
}

extension PixelConfetti {
    /// Blocky shapes for each confetti style.
    fileprivate static func shape(_ style: ConfettiStyle, in r: CGRect) -> Path {
        switch style {
        case .squares:
            return Path(r)
        case .coins, .snow:
            return Path(ellipseIn: r)
        case .flames:
            // A little pixel flame: tall diamond.
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY - r.height * 0.4))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
            return p
        case .stars:
            // A pixel plus/sparkle.
            let t = r.width / 3
            var p = Path()
            p.addRect(CGRect(x: r.minX + t, y: r.minY - t, width: t, height: r.height + 2 * t))
            p.addRect(CGRect(x: r.minX - t, y: r.minY + t, width: r.width + 2 * t, height: t))
            return p
        }
    }
}
