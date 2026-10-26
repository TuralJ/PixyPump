import SwiftUI
import UIKit

import CoreText

// MARK: - Colours (from the Figma "pixel" design)

extension Color {
    /// Hex helper: Color(hex: 0xEEF4FF)
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// Accent (rings, links, toggles, charts). Pale ice blue unless you pick another in Appearance.
    /// In light mode it's a deeper shade so it still stands out on white.
    nonisolated static var brand: Color {
        AppTheme.isLight ? Color(hex: AppTheme.accent.hex).deeper : Color(hex: AppTheme.accent.hex)
    }
    /// Page background: near-black with a hint of teal by default (Figma, 6 Oct).
    nonisolated static var ppBackground: Color { Color(hex: AppTheme.surface.background) }
    /// Big text and the main buttons: off-white in dark mode, ink in light mode.
    nonisolated static var ppText: Color { AppTheme.isLight ? Color(hex: 0x161A21) : Color(hex: 0xEEF4FF) }
    /// Hairlines, tracks and soft fills: white in dark mode, black in light mode (always used with opacity).
    nonisolated static var ppLine: Color { AppTheme.isLight ? .black : .white }
    /// Text and icons sitting on an accent-coloured chip or button.
    nonisolated static var ppOnAccent: Color { AppTheme.isLight ? .white : .black }
    /// Soft mint for small labels ("kcal left").
    nonisolated static var ppMint: Color { AppTheme.isLight ? Color(hex: 0x2F8F80) : Color(hex: 0x8BCABF) }
    /// Macro colours.
    nonisolated static var ppProtein: Color { AppTheme.isLight ? Color(hex: 0x3E6FA8) : Color(hex: 0xA1C0E0) }
    nonisolated static var ppCarbs: Color { AppTheme.isLight ? Color(hex: 0xA77B2E) : Color(hex: 0xD8BD92) }
    nonisolated static var ppFat: Color { AppTheme.isLight ? Color(hex: 0xB07D00) : Color(hex: 0xFFF4BC) }
    /// Deep green used on white ("NEXT").
    static let ppGreen = Color(hex: 0x438239)
    /// Done / success.
    nonisolated static var ppDone: Color { AppTheme.isLight ? Color(hex: 0x2E9E5B) : Color(hex: 0x9FE0B0) }
    /// Card / list-row colour: a touch lighter than the background, same tint.
    nonisolated static var ppCard: Color { Color(hex: AppTheme.surface.card) }
    /// XP "hearts" bar.
    static let ppHeart = Color(hex: 0xFF6B7A)
    /// Flame gradient ends (XP flame bar).
    static let ppFlameLight = Color(hex: 0xFFE07A)
    static let ppFlameDeep = Color(hex: 0xE5482A)
    /// Quiet grey for inactive tiles.
    static let ppMuted = Color(hex: 0x4D4F62)
    /// Streak flame.
    nonisolated static var ppFlame: Color { AppTheme.isLight ? Color(hex: 0xE07800) : Color(hex: 0xFF9F0A) }

    /// A deeper, more saturated version (pastel accents on a light background).
    nonisolated var deeper: Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(1, s * 1.9 + 0.15)), brightness: Double(b * 0.62), opacity: Double(a))
    }
}

// MARK: - Appearance (Settings → Appearance)

/// The look you picked: accent colour, background theme and heading style.
/// Some themes unlock with your level.
nonisolated enum AppTheme {
    nonisolated struct Accent: Identifiable, Sendable {
        let id: String
        let name: String
        let hex: UInt32
        var unlockLevel = 1
    }

    nonisolated struct Surface: Identifiable, Sendable {
        let id: String
        let name: String
        let background: UInt32
        let card: UInt32
        var unlockLevel = 1
        /// Light background: the whole app switches to dark text.
        var isLight = false
    }

    static let accentKey = "appAccent"
    static let surfaceKey = "appSurface"
    static let headingKey = "appHeadings"

    static let accents: [Accent] = [
        Accent(id: "ice", name: "Ice", hex: 0xB0DCF7),
        Accent(id: "mint", name: "Mint", hex: 0x9FE0B0),
        Accent(id: "pink", name: "Pink", hex: 0xF7A8C4),
        Accent(id: "lavender", name: "Lavender", hex: 0xC7B4F5),
        Accent(id: "sunny", name: "Sunny", hex: 0xFFE07A),
        Accent(id: "coral", name: "Coral", hex: 0xFF9A8A),
        Accent(id: "neon", name: "Neon", hex: 0x5CF0A0, unlockLevel: 6),
        Accent(id: "gold", name: "Gold", hex: 0xFFC94A, unlockLevel: 10),
    ]

    static let surfaces: [Surface] = [
        Surface(id: "midnight", name: "Midnight", background: 0x030707, card: 0x121616),
        Surface(id: "black", name: "True black", background: 0x000000, card: 0x101010),
        Surface(id: "navy", name: "Navy", background: 0x050914, card: 0x121A2C),
        Surface(id: "plum", name: "Plum", background: 0x0C0611, card: 0x1D1325),
        Surface(id: "forest", name: "Forest", background: 0x040A06, card: 0x111D15),
        Surface(id: "ember", name: "Ember", background: 0x0F0705, card: 0x221410, unlockLevel: 8),
        Surface(id: "royal", name: "Royal", background: 0x0D0A02, card: 0x221B08, unlockLevel: 15),
    ]

    static var accent: Accent {
        let id = UserDefaults.standard.string(forKey: accentKey)
        // Includes the colours from theme packs you've earned.
        return (accents + ThemePack.allCases.map(\.accent)).first { $0.id == id } ?? accents[0]
    }

    static var surface: Surface {
        let id = UserDefaults.standard.string(forKey: surfaceKey)
        return (surfaces + ThemePack.allCases.map(\.surface)).first { $0.id == id } ?? surfaces[0]
    }

    /// A light background is picked (light mode).
    static var isLight: Bool { surface.isLight }

    /// Headings in a clean rounded font instead of the pixel font.
    static var cleanHeadings: Bool { UserDefaults.standard.string(forKey: headingKey) == "clean" }

    /// Changes whenever any appearance setting changes (used to redraw the app).
    static var signature: String {
        "\(accent.id)-\(surface.id)-\(cleanHeadings)-\(ConfettiStyle.current.rawValue)-"
            + "\(XPBarStyle.current.rawValue)-\(PlateColors.current.rawValue)-\(RestSkin.current.rawValue)"
    }
}

extension Notification.Name {
    /// Posted when Settings closes, so a new appearance is applied everywhere.
    static let appearanceMayHaveChanged = Notification.Name("appearanceMayHaveChanged")
}

// MARK: - Pixel font (Geist Pixel Square, SIL Open Font License)

enum PixelFont {
    nonisolated static let name = "GeistPixel-Square"

    /// Loads the font file that ships inside the app — no Info settings needed.
    @MainActor static func register() {
        guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Pixel font for the navigation bar titles and segmented controls.
    @MainActor static func styleSystemBars() {
        let text = AppTheme.isLight
            ? UIColor(red: 0x16 / 255, green: 0x1A / 255, blue: 0x21 / 255, alpha: 1)
            : UIColor(red: 0xEE / 255, green: 0xF4 / 255, blue: 1, alpha: 1)
        func font(_ size: CGFloat) -> UIFont? {
            guard AppTheme.cleanHeadings else { return UIFont(name: name, size: size) }
            let base = UIFont.systemFont(ofSize: size, weight: .bold)
            guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: rounded, size: size)
        }
        if let large = font(34), let small = font(18) {
            let bar = UINavigationBar.appearance()
            bar.largeTitleTextAttributes = [.font: large, .foregroundColor: text]
            bar.titleTextAttributes = [.font: small, .foregroundColor: text]
        }
        if let seg = font(13) {
            UISegmentedControl.appearance().setTitleTextAttributes([.font: seg], for: .normal)
        }
    }
}

extension Font {
    /// The pixel font at a fixed size that still grows with the phone's text size setting.
    /// With "Clean" headings (Settings → Appearance) it's a bold rounded system font instead.
    static func pixel(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if AppTheme.cleanHeadings {
            return .system(size: size * 0.92, weight: .bold, design: .rounded)
        }
        return .custom(PixelFont.name, size: size, relativeTo: style)
    }
}

// MARK: - Background, glass cards, buttons, headers

/// Plain near-black page background.
struct AppBackground: View {
    var body: some View {
        Color.ppBackground.ignoresSafeArea()
    }
}

extension View {
    /// Dark smoked-glass card, like the cards in the Figma design:
    /// a faint light-to-dark sheen over the background and a hairline edge.
    func glassCard(cornerRadius: CGFloat = DS.Radius.hero) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                shape.fill(LinearGradient(colors: [Color.ppLine.opacity(0.075), Color.ppLine.opacity(0.025)],
                                          startPoint: .top, endPoint: .bottom))
            )
            // Solid base underneath so the card is never see-through.
            .background(shape.fill(Color.ppBackground))
            .overlay(shape.strokeBorder(Color.ppLine.opacity(0.08), lineWidth: 1))
    }

    /// Lists and forms: hide the default grey and show the app background instead.
    func ppScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}

/// Big off-white capsule button with black pixel text ("Continue", "Add set").
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                .foregroundStyle(Color.ppOnAccent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.ppText, in: Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Section title in the pixel font: "TODAY'S FOOD".
struct PPHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
            .tracking(0.5)
            .foregroundStyle(Color.ppText)
    }
}

/// Settings keys shared across screens.
enum Prefs {
    /// Start the rest timer automatically after logging a set.
    static let autoRest = "autoStartRest"
    /// Last rest length you picked, in seconds.
    static let restSeconds = "restSeconds"
    /// Subtle vibrations on taps (on by default).
    static let haptics = "hapticsOn"
    /// "kg" or "lb".
    static let unit = "weightUnit"
    /// "km" or "mi" (for cardio distances).
    static let distanceUnit = "distanceUnit"
    /// "cm" or "in" (height and body measurements).
    static let lengthUnit = "lengthUnit"
    /// Your first name for the Home greeting (empty = just "Hello").
    static let userName = "userName"
    /// Which gym buddy you picked: "guy" or "girl".
    static let mascot = "mascot"
    /// Set once the welcome flow has been completed (or skipped).
    static let onboarded = "hasOnboarded"
}

/// Subtle vibrations for taps and changes. Turn off in Settings → "Vibrate on taps".
@MainActor
enum Haptics {
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: Prefs.haptics) as? Bool ?? true
    }

    /// Light tick for a button press.
    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Firmer press for big actions (Next exercise, start timer).
    static func press() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Tiny click when a value changes (tabs, days, reps, weight).
    static func select() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Double tap "done" feeling (food logged, PR, backup saved).
    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Gentle warning (something deleted).
    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Kept for older call sites.
@MainActor
func hapticSuccess() { Haptics.success() }

extension View {
    /// A tiny click whenever `value` changes.
    func hapticOnChange<V: Equatable>(of value: V) -> some View {
        onChange(of: value) { _, _ in Haptics.select() }
    }
}
