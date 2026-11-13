import SwiftUI
import UIKit

// More ways to make PixyPump yours: theme packs you earn, app icons,
// confetti style, how big celebrations are.

// MARK: - Theme packs (earned)

/// A full look (accent + background + confetti + app icon) that you unlock by doing something.
nonisolated enum ThemePack: String, CaseIterable, Identifiable, Sendable {
    case volcano, ice, gold, midnight

    var id: String { rawValue }

    var name: String {
        switch self {
        case .volcano: return "Volcano"
        case .ice: return "Ice Age"
        case .gold: return "Gold Club"
        case .midnight: return "Night Owl"
        }
    }

    /// What you have to do to earn it.
    var requirement: String {
        switch self {
        case .volcano: return "Reach a 30-day streak"
        case .ice: return "Get saved by a streak freeze"
        case .gold: return "Finish 100 workouts"
        case .midnight: return "Train after 9 pm on 5 days"
        }
    }

    var goal: Int {
        switch self {
        case .volcano: return 30
        case .ice: return 1
        case .gold: return 100
        case .midnight: return 5
        }
    }

    var accent: AppTheme.Accent {
        switch self {
        case .volcano: return AppTheme.Accent(id: "pack-lava", name: "Lava", hex: 0xFF7A3D)
        case .ice: return AppTheme.Accent(id: "pack-frost", name: "Frost", hex: 0xC9F1FF)
        case .gold: return AppTheme.Accent(id: "pack-gold", name: "24K", hex: 0xFFD45E)
        case .midnight: return AppTheme.Accent(id: "pack-violet", name: "Violet", hex: 0xB4A2FF)
        }
    }

    var surface: AppTheme.Surface {
        switch self {
        case .volcano: return AppTheme.Surface(id: "pack-volcano", name: "Volcano", background: 0x120502, card: 0x2A0F08)
        case .ice: return AppTheme.Surface(id: "pack-glacier", name: "Glacier", background: 0x03090F, card: 0x10202C)
        case .gold: return AppTheme.Surface(id: "pack-vault", name: "Vault", background: 0x0C0903, card: 0x221B0A)
        case .midnight: return AppTheme.Surface(id: "pack-night", name: "Deep night", background: 0x04030C, card: 0x131026)
        }
    }

    var confetti: ConfettiStyle {
        switch self {
        case .volcano: return .flames
        case .ice: return .snow
        case .gold: return .coins
        case .midnight: return .stars
        }
    }

    var icon: AppIconChoice {
        switch self {
        case .volcano: return .flame
        case .ice: return .ice
        case .gold: return .gold
        case .midnight: return .midnight
        }
    }
}

/// How far you are towards each pack (all from your own history, so nothing to lose).
@MainActor
enum PackProgress {
    static func value(_ pack: ThemePack, sets: [WorkoutSet]) -> Int {
        switch pack {
        case .volcano: return DailyStreak.compute(sets: sets).best
        case .ice: return DailyStreak.compute(sets: sets).frozenDays.count
        case .gold: return GameStats(allSets: sets).workouts
        case .midnight:
            // Days whose first working set was at 21:00 or later.
            let cal = Calendar.current
            let firstByDay = Dictionary(grouping: sets.filter { !$0.isWarmup }) { cal.startOfDay(for: $0.date) }
                .compactMapValues { $0.map(\.date).min() }
            return firstByDay.values.filter { cal.component(.hour, from: $0) >= 21 }.count
        }
    }

    static func isUnlocked(_ pack: ThemePack, sets: [WorkoutSet]) -> Bool {
        Unlocks.everything || value(pack, sets: sets) >= pack.goal
    }
}

// MARK: - Confetti and celebrations

nonisolated enum ConfettiStyle: String, CaseIterable, Identifiable, Sendable {
    case squares, flames, snow, coins, stars

    static let key = "appConfetti"
    var id: String { rawValue }

    static var current: ConfettiStyle {
        ConfettiStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .squares
    }

    var name: String {
        switch self {
        case .squares: return "Pixels"
        case .flames: return "Flames"
        case .snow: return "Snow"
        case .coins: return "Coins"
        case .stars: return "Stars"
        }
    }

    var emoji: String {
        switch self {
        case .squares: return "🟦"
        case .flames: return "🔥"
        case .snow: return "❄️"
        case .coins: return "🪙"
        case .stars: return "✨"
        }
    }

    /// The pack that unlocks it (pixels are always yours).
    var pack: ThemePack? {
        switch self {
        case .squares: return nil
        case .flames: return .volcano
        case .snow: return .ice
        case .coins: return .gold
        case .stars: return .midnight
        }
    }
}

/// How big wins look: all the fun, a little, or just the numbers.
nonisolated enum CelebrationLevel: String, CaseIterable, Identifiable, Sendable {
    case full, subtle, minimal

    static let key = "celebrationLevel"
    var id: String { rawValue }

    static var current: CelebrationLevel {
        CelebrationLevel(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .full
    }

    var name: String {
        switch self {
        case .full: return "Full party"
        case .subtle: return "Subtle"
        case .minimal: return "Minimal"
        }
    }

    var detail: String {
        switch self {
        case .full: return "Confetti, buddy moves, floating XP and counters."
        case .subtle: return "A light sprinkle of confetti and quicker animations."
        case .minimal: return "No confetti or floating XP. Just the numbers."
        }
    }
}

// MARK: - App icons

nonisolated enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case pixel, classic, buddy, neon, gold, flame, ice, midnight

    var id: String { rawValue }

    /// The alternate icon's asset name (nil = the main icon).
    var assetName: String? {
        switch self {
        case .pixel: return nil
        default: return "AppIcon-" + rawValue.prefix(1).uppercased() + String(rawValue.dropFirst())
        }
    }

    /// Small copy of the icon to show in the picker (app icons can't be loaded as images).
    var previewName: String { "icon-preview-\(rawValue)" }

    var name: String {
        switch self {
        case .pixel: return "Pixel"
        case .classic: return "Classic"
        case .buddy: return "Buddy"
        case .neon: return "Neon"
        case .gold: return "Gold"
        case .flame: return "Flame"
        case .ice: return "Ice"
        case .midnight: return "Night"
        }
    }

    enum Unlock {
        case free
        case level(Int)
        case pack(ThemePack)
    }

    var unlock: Unlock {
        switch self {
        case .pixel, .classic, .buddy: return .free
        case .neon: return .level(6)
        case .gold: return .level(10)
        case .flame: return .pack(.volcano)
        case .ice: return .pack(.ice)
        case .midnight: return .pack(.midnight)
        }
    }

    @MainActor static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.assetName == name } ?? .pixel
    }

    @MainActor func apply() async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        do {
            try await UIApplication.shared.setAlternateIconName(assetName)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Pickers used on the Appearance screen

/// One earnable theme pack: preview swatch, name, what to do, and progress.
struct ThemePackCard: View {
    let pack: ThemePack
    let progress: Int
    let unlocked: Bool
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.s).fill(Color(hex: pack.surface.background))
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 5).fill(Color(hex: pack.surface.card)).frame(height: 18)
                        HStack(spacing: 6) {
                            Capsule().fill(Color(hex: pack.accent.hex)).frame(width: 40, height: 12)
                            Text(pack.confetti.emoji).font(.system(size: 12))
                        }
                    }
                    .padding(10)
                    if !unlocked {
                        RoundedRectangle(cornerRadius: DS.Radius.s).fill(Color.black.opacity(0.55))
                        Image(systemName: "lock.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ppFat)
                    }
                }
                .frame(height: 70)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .strokeBorder(selected ? Color(hex: pack.accent.hex) : Color.ppLine.opacity(0.12),
                                      lineWidth: selected ? 2.5 : 1)
                }
                Text(pack.name)
                    .font(.pixel(DS.TextSize.subhead))
                    .foregroundStyle(Color.ppText)
                Text(pack.requirement)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if unlocked {
                    Text(selected ? "IN USE" : "UNLOCKED · TAP TO USE")
                        .font(.pixel(DS.TextSize.caption))
                        .foregroundStyle(selected ? Color(hex: pack.accent.hex) : Color.ppDone)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ppLine.opacity(0.12))
                            Capsule().fill(Color.ppFat)
                                .frame(width: geo.size.width * min(Double(progress) / Double(pack.goal), 1))
                        }
                    }
                    .frame(height: 5)
                    Text("\(min(progress, pack.goal))/\(pack.goal)")
                        .font(.pixel(DS.TextSize.caption))
                        .foregroundStyle(Color.ppFat)
                }
            }
            .frame(width: 150, alignment: .leading)
            .padding(12)
            .glassCard(cornerRadius: DS.Radius.tile)
        }
        .buttonStyle(.squish)
        .accessibilityLabel("\(pack.name) theme. \(unlocked ? "Unlocked" : "Locked: \(pack.requirement), \(progress) of \(pack.goal)")")
    }
}

/// One app icon in the picker.
struct AppIconTile: View {
    let choice: AppIconChoice
    let locked: Bool
    let lockText: String
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 6) {
                ZStack {
                    Image(choice.previewName)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                    if locked {
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).fill(Color.black.opacity(0.6))
                            .frame(width: 60, height: 60)
                        VStack(spacing: 2) {
                            Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
                            Text(lockText).font(.pixel(DS.TextSize.caption)).minimumScaleFactor(0.6).lineLimit(1).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Color.ppFat)
                        .frame(width: 56)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)   // ds-allow: selection ring = tile radius + 3pt
                        .strokeBorder(selected ? Color.ppText : Color.clear, lineWidth: 3)
                        .frame(width: 68, height: 68)
                }
                .frame(width: 68, height: 68)
                Text(choice.name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.ppText : .secondary)
            }
        }
        .buttonStyle(.squish)
        .accessibilityLabel(choice.name + " app icon" + (locked ? ", locked" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Rest timer skins, XP bar styles, plate colours, profile banner

/// How the rest timer shows time running out.
nonisolated enum RestSkin: String, CaseIterable, Identifiable, Sendable {
    case bar, hourglass, barbell

    static let key = "restSkin"
    var id: String { rawValue }

    static var current: RestSkin { RestSkin(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .bar }

    var name: String {
        switch self {
        case .bar: return "Classic"
        case .hourglass: return "Hourglass"
        case .barbell: return "Barbell"
        }
    }

    var unlockLevel: Int {
        switch self {
        case .bar: return 1
        case .hourglass: return 4
        case .barbell: return 8
        }
    }
}

/// How your XP bar looks next to your level.
nonisolated enum XPBarStyle: String, CaseIterable, Identifiable, Sendable {
    case segments, hearts, battery, flame

    static let key = "xpBarStyle"
    var id: String { rawValue }

    static var current: XPBarStyle { XPBarStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .segments }

    var name: String {
        switch self {
        case .segments: return "Pixels"
        case .hearts: return "Hearts"
        case .battery: return "Battery"
        case .flame: return "Flame"
        }
    }

    var unlockLevel: Int {
        switch self {
        case .segments: return 1
        case .battery: return 3
        case .hearts: return 5
        case .flame: return 7
        }
    }
}

/// Plate colours for Plate Stack and the plate calculator.
nonisolated enum PlateColors: String, CaseIterable, Identifiable, Sendable {
    case pastel, competition, stealth, neon

    static let key = "plateColors"
    var id: String { rawValue }

    static var current: PlateColors { PlateColors(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .pastel }

    var name: String {
        switch self {
        case .pastel: return "Pastel"
        case .competition: return "Competition"
        case .stealth: return "Stealth"
        case .neon: return "Neon"
        }
    }

    var unlockLevel: Int {
        switch self {
        case .pastel, .competition: return 1
        case .stealth: return 4
        case .neon: return 9
        }
    }

    /// Seven colours: Plate Stack uses one per block shape; the calculator goes heaviest → lightest.
    var hexes: [UInt32] {
        switch self {
        case .pastel: return [0xB0DCF7, 0xFFE07A, 0xC7B4F5, 0x9FE0B0, 0xFF9A8A, 0xF7A8C4, 0xFF9F0A]
        // Like competition bumper plates: red 25, blue 20, yellow 15, green 10, white 5…
        case .competition: return [0xE23B3B, 0x2F6FE0, 0xF2C230, 0x2FA84F, 0xF2F2F2, 0x8C8C8C, 0x1E1E1E]
        case .stealth: return [0x4A4F57, 0x5C626B, 0x6E757F, 0x3A3E44, 0x80878F, 0x2E3136, 0x9AA1A8]
        case .neon: return [0x5CF0A0, 0xFF4FD8, 0x3DE8FF, 0xFFF04D, 0xA06BFF, 0xFF8A3D, 0x7DFF5C]
        }
    }

    func color(_ index: Int) -> Color {
        Color(hex: hexes[((index % hexes.count) + hexes.count) % hexes.count])
    }
}

/// The scene behind your buddy and name on Home (uses the buddy backdrops you've unlocked).
nonisolated enum ProfileBanner {
    static let key = "profileBanner"
    static var current: String { UserDefaults.standard.string(forKey: key) ?? "none" }
}
