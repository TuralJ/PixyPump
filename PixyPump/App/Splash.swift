import SwiftUI
import UIKit

// Animated splash: the pixel hammer from the app icon flies together pixel by pixel,
// lands with a clank, then PIXYPUMP pops in letter by letter. About 2 seconds; tap to skip.
// The system launch screen before it is the same dark colour, so it feels like one motion.

struct SplashView: View {
    let onFinish: () -> Void

    @State private var start = Date.now
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let title = Array(AppInfo.name.uppercased())
    /// When the hammer lands (seconds after launch).
    private static let landAt = 0.85
    private static let total = 2.1

    var body: some View {
        ZStack {
            Color(hex: 0x030707).ignoresSafeArea()
            TimelineView(.animation(paused: finished)) { context in
                let t = reduceMotion ? 10 : context.date.timeIntervalSince(start)
                VStack(spacing: 34) {
                    hammer(at: t)
                    titleRow(at: t)
                }
                .offset(x: shake(at: t))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task {
            if reduceMotion {
                try? await Task.sleep(for: .seconds(0.6))
                finish()
                return
            }
            // The clank when the hammer lands.
            try? await Task.sleep(for: .seconds(Self.landAt))
            guard !finished else { return }
            if Haptics.enabled { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
            SFX.play(.setLogged)
            try? await Task.sleep(for: .seconds(Self.total - Self.landAt))
            finish()
        }
        .accessibilityElement()
        .accessibilityLabel(AppInfo.name)
        .accessibilityAddTraits(.isImage)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    // MARK: Hammer

    private func hammer(at t: Double) -> some View {
        let rows = SplashArt.rows
        let cols = rows.first?.count ?? 0
        let cell: CGFloat = 7
        // A little bounce right when it lands.
        let since = t - Self.landAt
        let bounce = since > 0 && since < 0.35 ? 1 + 0.12 * sin(since / 0.35 * .pi) : 1
        return Canvas { context, _ in
            var index = 0
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    index += 1
                    guard let hex = SplashArt.palette[ch] else { continue }
                    // Each pixel starts somewhere off to the side and flies home,
                    // sweeping in from the bottom-left (handle) to the top-right (head).
                    let seed = Double((index * 7919) % 1000) / 1000
                    let delay = Double(x + (rows.count - y)) / Double(cols + rows.count) * 0.45
                    let p = min(max((t - delay) / 0.38, 0), 1)
                    let eased = 1 - pow(1 - p, 3)
                    let angle = seed * 2 * .pi
                    let distance = 160 + 140 * seed
                    let dx = cos(angle) * distance * (1 - eased)
                    let dy = sin(angle) * distance * (1 - eased)
                    let rect = CGRect(x: CGFloat(x) * cell + dx, y: CGFloat(y) * cell + dy,
                                      width: cell, height: cell)
                    context.opacity = p
                    context.fill(Path(rect), with: .color(Color(hex: hex)))
                }
            }
            // A shine sweeping diagonally across the hammer once it has landed.
            let shine = (t - Self.landAt - 0.15) / 0.45
            if shine > 0 && shine < 1 {
                let span = Double(cols + rows.count)
                let center = shine * (span + 8) - 4
                for (y, row) in rows.enumerated() {
                    for (x, ch) in row.enumerated() where ch != "." && ch != "a" {
                        let d = abs(Double(x + (rows.count - y)) - center)
                        guard d < 3 else { continue }
                        context.opacity = 0.6 * (1 - d / 3)
                        context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                     with: .color(.white))
                    }
                }
            }
        }
        .frame(width: CGFloat(cols) * cell, height: CGFloat(rows.count) * cell)
        .scaleEffect(bounce)
    }

    /// A tiny screen shake on landing.
    private func shake(at t: Double) -> CGFloat {
        let since = t - Self.landAt
        guard since > 0, since < 0.2 else { return 0 }
        return CGFloat(sin(since * 90) * 4 * (1 - since / 0.2))
    }

    // MARK: Title

    private func titleRow(at t: Double) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(Array(Self.title.enumerated()), id: \.offset) { i, letter in
                    let appear = t - (Self.landAt + 0.1 + Double(i) * 0.055)
                    let p = min(max(appear / 0.22, 0), 1)
                    let pop = p < 1 ? 1 + 0.6 * (1 - p) : 1
                    Text(String(letter))
                        .font(.pixel(DS.TextSize.largeTitle, relativeTo: .largeTitle))
                        .foregroundStyle(Color(hex: 0xEEF4FF))
                        .opacity(p)
                        .scaleEffect(pop)
                        .offset(y: (1 - p) * -14)
                }
            }
            // Blinks like an old arcade cabinet.
            let blinkStart = Self.landAt + 0.7
            Text("PRESS START")
                .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                .foregroundStyle(Color(hex: 0xFFF4BC))
                .opacity(t < blinkStart ? 0 : (Int((t - blinkStart) / 0.28) % 2 == 0 ? 1 : 0.25))
        }
    }
}

/// The app icon's hammer as pixels (from the 32×32 icon art).
enum SplashArt {
    static let rows: [String] = [
        "........aa..............",
        ".......abca....aaa......",
        "......abbbca..abbca.....",
        ".....abbbbdca.abddca....",
        ".....aebbdddcaaedffca...",
        "......aedddddcaaefggca..",
        ".......aedddffcaaegghba.",
        "........aedffffcaaehhiba",
        ".........aefffggcaaeiija",
        "..........aefggggcaaejja",
        "..........aaegggghbaaaa.",
        ".........akkaegghhhba...",
        "........akkllaehhhhiba..",
        ".......akkllllaehhiiiba.",
        "......akkllllmaaeiiijjba",
        ".....akkllllma..aeijjjja",
        "....akkllllma....aejjjja",
        "...akkllllma......aejja.",
        "..akkllllma........aaa..",
        ".akkllllma..............",
        "akkllllma...............",
        "akllllma................",
        "allllma.................",
        ".allma..................",
        "..aaa...................",
    ]
    static let palette: [Character: UInt32] = [
        "a": 0x060608,
        "b": 0x4094FC,
        "c": 0x5AC1FF,
        "d": 0x3A89F3,
        "e": 0x1D4C95,
        "f": 0x3480EB,
        "g": 0x2E77E3,
        "h": 0x296FDB,
        "i": 0x2467D4,
        "j": 0x1F5FCD,
        "k": 0xFFFFFF,
        "l": 0xDEE0E4,
        "m": 0x91A4BA,
    ]
}

/// The app icon's hammer, still (for the paywall and anywhere the logo is needed in the app).
struct PixelHammer: View {
    /// Size of one pixel in points.
    var cell: CGFloat = 4

    var body: some View {
        let rows = SplashArt.rows
        let cols = rows.first?.count ?? 0
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    guard let hex = SplashArt.palette[ch] else { continue }
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(hex: hex)))
                }
            }
        }
        .frame(width: CGFloat(cols) * cell, height: CGFloat(rows.count) * cell)
        .accessibilityHidden(true)
    }
}
