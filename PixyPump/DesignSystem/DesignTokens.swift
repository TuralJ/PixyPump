import SwiftUI

// PixyPump design tokens: the only place sizes, radii, spacing and timings are decided.
// Screens use these names instead of raw numbers, so the whole app changes together
// and new screens automatically follow the same rules. See docs/DESIGN_SYSTEM.md.
//
// Colours live in Theme.swift (Color.brand, .ppText, .ppCard, .ppLine …).
// Pixel font: Font.pixel(DS.TextSize.body). Icons: Image.pixel(.glyph).

nonisolated enum DS {

    /// Spacing scale (padding, stack spacing). 4-point grid.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Side margin of every screen.
        static let screen: CGFloat = 16
    }

    /// Corner radii. Cards use `card`; big hero cards use `hero`.
    enum Radius {
        /// Tiny chips, badges, sprite tiles.
        static let xs: CGFloat = 8
        /// Inputs, small buttons, thumbnails.
        static let s: CGFloat = 12
        /// Small cards and tiles.
        static let m: CGFloat = 16
        /// Compact cards (rows, banners).
        static let tile: CGFloat = 20
        /// Standard card.
        static let card: CGFloat = 24
        /// Big hero cards (today's workout, calories).
        static let hero: CGFloat = 32
    }

    /// Pixel-font sizes. Never go below `caption` (12): it's the accessibility minimum.
    enum TextSize {
        static let caption: CGFloat = 12
        static let footnote: CGFloat = 13
        static let subhead: CGFloat = 14
        static let body: CGFloat = 15
        static let callout: CGFloat = 16
        static let headline: CGFloat = 18
        static let title3: CGFloat = 20
        static let title2: CGFloat = 24
        static let title: CGFloat = 28
        static let largeTitle: CGFloat = 34
        static let display: CGFloat = 44
        static let hero: CGFloat = 56
        static let jumbo: CGFloat = 64
    }

    /// Fixed sizes that must stay consistent.
    enum Size {
        /// Minimum tap target (Apple HIG).
        static let minTap: CGFloat = 44
        /// Primary button height.
        static let button: CGFloat = 52
        /// Hairline borders.
        static let hairline: CGFloat = 1
    }

    /// Animation timings.
    enum Motion {
        static let quick: Double = 0.15
        static let standard: Double = 0.3
        static let slow: Double = 0.6
        /// Default spring for things appearing or changing.
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
        /// Bouncier spring for rewards (stamps, pops).
        static let bouncy = Animation.spring(response: 0.3, dampingFraction: 0.55)
    }

    /// Opacity levels used with Color.ppLine for tracks, fills and borders.
    enum Opacity {
        static let fill: Double = 0.08
        static let border: Double = 0.15
        static let track: Double = 0.25
        static let disabled: Double = 0.35
    }
}

/// App identity in one place: change the name here, not in strings.
nonisolated enum AppInfo {
    static let name = "PixyPump"
}
