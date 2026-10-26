import SwiftUI
import UIKit

/// Full-screen gym bag reveal: tap it, it shakes harder and harder while the glow turns
/// the rarity colour, then bursts open to show what you won.
struct MysteryBagView: View {
    let subtitle: String
    /// Rolls and pays out the prize (called once, when you tap the bag).
    let open: () -> GymBag.Result
    /// Called on close with the result (nil if you left without opening).
    var onClose: (GymBag.Result?) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MascotLook.storageKey) private var lookJSON = ""

    private enum Phase { case idle, charging, revealed }
    @State private var phase: Phase = .idle
    @State private var result: GymBag.Result?
    @State private var shake = 0.0
    @State private var scale = 1.0
    @State private var glow = 0.0
    @State private var flash = 0.0
    @State private var bob = false
    @State private var spin = false
    @State private var pulse = false
    @State private var shownReveal = false

    private var rarityColor: Color { result.map { Color(hex: $0.rarity.hex) } ?? .white }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()   // ds-allow: reveal is always on black

            // Glow: white while idle, shifting to the rarity colour as it charges.
            RadialGradient(colors: [Color.white.opacity(0.18 * (1 - glow)), .clear],
                           center: .center, startRadius: 0, endRadius: 360)
                .ignoresSafeArea()
            RadialGradient(colors: [rarityColor.opacity(0.6 * glow), .clear],
                           center: .center, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            LightRays(color: glow > 0 ? rarityColor : .white, strength: 0.07 + 0.12 * glow)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                header
                Spacer(minLength: 0)
                if phase == .revealed, let result {
                    reveal(result)
                } else {
                    bag
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if phase == .revealed { PixelConfetti(duration: 3.2) }

            Color.white.opacity(flash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { bob = true }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // MARK: Pieces

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Text("GYM BAG")
                    .font(.pixel(DS.TextSize.title, relativeTo: .title))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            if phase == .idle {
                Button {
                    Haptics.tap()
                    onClose(nil)
                    dismiss()
                } label: {
                    Image.pixel(.close, size: 16)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Open later")
            }
        }
    }

    private var bag: some View {
        PixelBag(open: false)
            .frame(width: 220, height: 220)
            .shadow(color: rarityColor.opacity(0.4 + 0.5 * glow), radius: 30 + 30 * glow)
            .scaleEffect(scale)
            .rotationEffect(.degrees(shake))
            .offset(y: phase == .idle ? (bob ? -10 : 10) : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: start)
            .accessibilityElement()
            .accessibilityLabel("Gym bag")
            .accessibilityHint("Double tap to open")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .idle:
            Text("Tap the bag to open")
                .font(.pixel(DS.TextSize.body))
                .foregroundStyle(.white.opacity(pulse ? 0.95 : 0.45))
                .padding(.bottom, 24)
        case .charging:
            Text(" ")
                .font(.pixel(DS.TextSize.body))
                .padding(.bottom, 24)
        case .revealed:
            VStack(spacing: 8) {
                if let result, case .item(let category, let option) = result.prize {
                    Button {
                        Haptics.success()
                        lookJSON = MascotLook.decode(lookJSON).with(category, option.id).encoded
                        close()
                    } label: { Text("Wear it now") }
                        .buttonStyle(.primary)
                    Button("Collect", action: close)
                        .font(.pixel(DS.TextSize.body))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Button(action: close) { Text("Collect") }
                        .buttonStyle(.primary)
                }
            }
            .opacity(shownReveal ? 1 : 0)
        }
    }

    private func reveal(_ result: GymBag.Result) -> some View {
        VStack(spacing: 16) {
            Text(result.rarity.bagName.uppercased())
                .font(.pixel(DS.TextSize.title3, relativeTo: .title2))
                .foregroundStyle(Color.black)   // ds-allow: text on rarity colour
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Color(hex: result.rarity.hex), in: Capsule())
                .shadow(color: Color(hex: result.rarity.hex).opacity(0.8), radius: 16)
                .scaleEffect(shownReveal ? 1 : 0.3)

            prizeVisual(result.prize)
                .frame(height: 190)
                .scaleEffect(shownReveal ? 1 : 0.5)

            VStack(spacing: 6) {
                Text(result.prize.title)
                    .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(result.prize.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                if result.bonusXP > 0 {
                    Text("+\(result.bonusXP) XP too!")
                        .font(.pixel(DS.TextSize.body))
                        .foregroundStyle(Color.ppFat)
                }
            }
            .opacity(shownReveal ? 1 : 0)
        }
    }

    @ViewBuilder
    private func prizeVisual(_ prize: GymBag.Prize) -> some View {
        switch prize {
        case .xp(let xp):
            VStack(spacing: 10) {
                Image.pixel(.star, size: 96).foregroundStyle(Color.ppFat)
                Text("+\(xp) XP").font(.pixel(DS.TextSize.largeTitle, relativeTo: .largeTitle)).foregroundStyle(Color.ppFat)
            }
        case .shield:
            Text("❄️").font(.system(size: 120))   // ds-allow: emoji size
                .accessibilityLabel("Streak freeze")
        case .item(let category, let option):
            PixelMascot(look: MascotLook.decode(lookJSON).with(category, option.id), action: .cheer, size: 180)
                .background {
                    if category == .backdrop { BuddyBackdrop(id: option.id, cornerRadius: 28) }
                }
        }
    }

    // MARK: The opening

    private func start() {
        guard phase == .idle else { return }
        phase = .charging
        UserDefaults.standard.set(true, forKey: GettingStarted.bagKey)
        let rolled = open()          // the prize is decided (and saved) the moment you tap
        result = rolled
        SFX.play(.gymBag)
        Task {
            if !reduceMotion {
                // Shake harder and harder, glow building up.
                for i in 0..<14 {
                    let strength = 3 + Double(i) * 0.9
                    withAnimation(.easeInOut(duration: 0.06)) {
                        shake = i.isMultiple(of: 2) ? strength : -strength
                        scale = 1 + Double(i) * 0.012
                        glow = Double(i + 1) / 14
                    }
                    let style: UIImpactFeedbackGenerator.FeedbackStyle = i < 5 ? .light : i < 10 ? .medium : .heavy
                    UIImpactFeedbackGenerator(style: style).impactOccurred()
                    try? await Task.sleep(for: .milliseconds(75))
                }
            } else {
                withAnimation(.easeInOut(duration: 0.4)) { glow = 1 }
                try? await Task.sleep(for: .milliseconds(400))
            }
            // Burst.
            withAnimation(.easeOut(duration: 0.08)) { flash = 1 }
            try? await Task.sleep(for: .milliseconds(90))
            shake = 0
            scale = 1
            phase = .revealed
            Haptics.success()
            SFX.play(rolled.rarity >= .epic ? .levelUp : .mission)
            withAnimation(.easeOut(duration: 0.55)) { flash = 0 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shownReveal = true }
        }
    }

    private func close() {
        onClose(result)
        dismiss()
    }
}

/// Slowly turning light rays behind the bag.
private struct LightRays: View {
    let color: Color
    let strength: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(size.width, size.height)
            let rays = 14
            for i in 0..<rays {
                let a = Double(i) / Double(rays) * 2 * Double.pi
                let w = Double.pi / Double(rays) * 0.55
                var path = Path()
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + cos(a - w) * radius, y: center.y + sin(a - w) * radius))
                path.addLine(to: CGPoint(x: center.x + cos(a + w) * radius, y: center.y + sin(a + w) * radius))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(strength)))
            }
        }
    }
}

/// Home: bags you've earned and not opened yet.
struct MysteryBagsCard: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                PixelBag()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(count == 1 ? "A gym bag is waiting!" : "\(count) gym bags are waiting!")
                        .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                        .foregroundStyle(Color.ppText)
                    Text("Tap to open. Could be epic.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("Open")
                    .font(.pixel(DS.TextSize.subhead))
                    .foregroundStyle(Color.ppBackground)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.ppFat, in: Capsule())
            }
            .padding(16)
            .glassCard(cornerRadius: DS.Radius.card)
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(Color(hex: GymBag.Rarity.epic.hex).opacity(0.6), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Home: a bag that floats in the corner while one is waiting — bobbing, glowing, with a count.
struct FloatingBagButton: View {
    let count: Int
    let open: () -> Void

    @State private var bob = false
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .topTrailing) {
                PixelBag()
                    .frame(width: 46, height: 46)
                    .padding(10)
                    .background(Color.ppCard, in: Circle())
                    .overlay(Circle().strokeBorder(Color(hex: GymBag.Rarity.epic.hex), lineWidth: 2))
                    .shadow(color: Color(hex: GymBag.Rarity.epic.hex).opacity(glow ? 0.9 : 0.35), radius: glow ? 16 : 6)
                    .offset(y: bob ? -4 : 2)
                if count > 1 {
                    Text("\(count)")
                        .font(.pixel(DS.TextSize.caption))
                        .foregroundStyle(Color.ppBackground)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Color.ppFat, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count == 1 ? "Open your gym bag" : "Open your \(count) gym bags")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}
