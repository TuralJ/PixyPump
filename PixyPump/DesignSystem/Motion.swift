import SwiftUI

// Small reusable micro-animations, all switched off when "Reduce Motion" is on.
// Kept short and snappy so they feel rewarding without slowing you down.

// MARK: - Numbers

/// A number that rolls like an odometer when it changes ("1 240" → "1 255").
struct RollingNumber: View {
    let value: Int
    var font: Font = .pixel(DS.TextSize.callout)
    var color: Color = .ppText
    var spaced = true
    var prefix = ""
    var suffix = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(prefix + (spaced ? value.spaced : "\(value)") + suffix)
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: value)
    }
}

/// Counts up from 0 to `target` once it appears (summary totals, XP earned).
struct CountUpText: View {
    let target: Int
    var font: Font = .pixel(DS.TextSize.title3)
    var color: Color = .ppText
    var prefix = ""
    var suffix = ""
    var delay: Double = 0
    var duration: Double = 0.8
    /// Light tick haptics while counting.
    var ticks = false
    /// Called once the count reaches the end.
    var onFinish: (() -> Void)? = nil

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(prefix + shown.spaced + suffix)
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .accessibilityLabel(prefix + target.spaced + suffix)
            .task(id: target) {
                guard !reduceMotion, target > 0, CelebrationLevel.current != .minimal else {
                    shown = target
                    onFinish?()
                    return
                }
                shown = 0
                try? await Task.sleep(for: .seconds(delay))
                let steps = min(24, max(target, 1))
                for step in 1...steps {
                    guard !Task.isCancelled else { return }
                    // Ease-out: fast at first, settling at the end.
                    let t = Double(step) / Double(steps)
                    let eased = 1 - pow(1 - t, 3)
                    withAnimation(.snappy(duration: 0.12)) { shown = Int((Double(target) * eased).rounded()) }
                    if ticks, step % 3 == 0 { Haptics.select() }
                    try? await Task.sleep(for: .seconds(duration / Double(steps)))
                }
                shown = target
                onFinish?()
            }
    }
}

// MARK: - Floating "+XP"

extension View {
    /// Each time `trigger` changes, a little "+5 XP" floats up from this view and fades.
    func xpPop(trigger: Int, text: String, color: Color = .ppFat) -> some View {
        modifier(XPPopModifier(trigger: trigger, text: text, color: color))
    }
}

private struct XPPopModifier: ViewModifier {
    let trigger: Int
    let text: String
    let color: Color
    @State private var pops: [UUID] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack {
                    ForEach(pops, id: \.self) { id in
                        FloatingLabel(text: text, color: color) {
                            pops.removeAll { $0 == id }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion, !text.isEmpty, CelebrationLevel.current != .minimal else { return }
                pops.append(UUID())
            }
    }
}

private struct FloatingLabel: View {
    let text: String
    let color: Color
    let done: () -> Void
    @State private var up = false

    var body: some View {
        Text(text)
            .font(.pixel(DS.TextSize.body))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .fixedSize()
            .offset(y: up ? -46 : -6)
            .opacity(up ? 0 : 1)
            .scaleEffect(up ? 1.1 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) { up = true }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    done()
                }
            }
    }
}

// MARK: - Appear / attention

extension View {
    /// Fades and slides up a little on first appear, `index` × 45 ms after the screen opens.
    func staggeredAppear(_ index: Int) -> some View {
        modifier(StaggerModifier(index: index))
    }

    /// When `isOn` turns true: a quick stamp (big → normal with a bounce). Great for ✓ marks.
    func stamp(_ isOn: Bool) -> some View {
        modifier(StampModifier(isOn: isOn))
    }

    /// A short bounce every time `value` changes (numbers, flames, badges).
    func popOnChange<V: Equatable>(of value: V, scale: CGFloat = 1.18) -> some View {
        modifier(PopModifier(value: value, scale: scale))
    }

    /// Gently grows and shrinks while `active` ("tap me next").
    func breathe(_ active: Bool, amount: CGFloat = 0.03) -> some View {
        modifier(BreatheModifier(active: active, amount: amount))
    }

    /// Small side-to-side wobble while `active` (streak at risk).
    func wobble(_ active: Bool, degrees: Double = 5) -> some View {
        modifier(WobbleModifier(active: active, degrees: degrees))
    }

    /// A gold shine sweeping across, a couple of times (new records).
    func shimmer(_ active: Bool, color: Color = .ppFat) -> some View {
        modifier(ShimmerModifier(active: active, color: color))
    }

    /// Reveals the view left to right when it appears (charts drawing in).
    func drawIn(duration: Double = 0.9, delay: Double = 0.1) -> some View {
        modifier(DrawInModifier(duration: duration, delay: delay))
    }

    /// Grows up from the bottom when it appears (bar charts), staggered by `index`.
    func growIn(_ index: Int) -> some View {
        modifier(GrowInModifier(index: index))
    }
}

private struct StaggerModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(Double(min(index, 10)) * 0.045)) {
                    shown = true
                }
            }
    }
}

private struct StampModifier: ViewModifier {
    let isOn: Bool
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isOn) { _, on in
                guard on, !reduceMotion else { return }
                scale = 1.7
                // Next tick, so the big frame is drawn before springing back.
                Task { withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { scale = 1 } }
            }
    }
}

private struct PopModifier<V: Equatable>: ViewModifier {
    let value: V
    let scale: CGFloat
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(popped ? scale : 1)
            .onChange(of: value) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { popped = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(160))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { popped = false }
                }
            }
    }
}

private struct BreatheModifier: ViewModifier {
    let active: Bool
    let amount: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.phaseAnimator([false, true]) { view, up in
                view.scaleEffect(up ? 1 + amount : 1)
            } animation: { _ in .easeInOut(duration: 0.9) }
        } else {
            content
        }
    }
}

private struct WobbleModifier: ViewModifier {
    let active: Bool
    let degrees: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.phaseAnimator([0.0, degrees, 0.0, -degrees, 0.0, 0.0, 0.0]) { view, angle in
                view.rotationEffect(.degrees(angle), anchor: .bottom)
            } animation: { _ in .easeInOut(duration: 0.12) }
        } else {
            content
        }
    }
}

private struct ShimmerModifier: ViewModifier {
    let active: Bool
    let color: Color
    @State private var x: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, color.opacity(0.45), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.45)
                            .offset(x: x * geo.size.width)
                            .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
                    .clipped()
                    .task {
                        for _ in 0..<2 {
                            x = -0.5
                            try? await Task.sleep(for: .milliseconds(30))   // let the reset draw first
                            withAnimation(.easeInOut(duration: 0.9)) { x = 1.1 }
                            try? await Task.sleep(for: .seconds(1.3))
                        }
                    }
                }
            }
    }
}

private struct DrawInModifier: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask {
                Rectangle().scaleEffect(x: shown || reduceMotion ? 1 : 0.001, anchor: .leading)
            }
            .onAppear {
                guard !shown else { return }
                withAnimation(.easeOut(duration: duration).delay(delay)) { shown = true }
            }
    }
}

private struct GrowInModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(y: shown || reduceMotion ? 1 : 0.02, anchor: .bottom)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

// MARK: - Buttons

/// Any tappable card or chip: squishes a little while pressed.
struct SquishButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SquishButtonStyle {
    static var squish: SquishButtonStyle { SquishButtonStyle() }
}
