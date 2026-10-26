import SwiftUI

// MARK: - Look

/// How your gym buddy looks. Saved as JSON in UserDefaults.
/// nonisolated (like the other Codable types) so `init(from:)` satisfies Decodable in any isolation mode.
nonisolated struct MascotLook: Codable, Equatable {
    var skin = "light"
    var hair = "spiky"
    var hairColor = "black"
    var top = "sky"
    var shorts = "charcoal"
    var headband = "white"
    var facialHair = "none"
    var eyewear = "none"
    var wristbands = false
    var belt = false
    var hat = "none"
    var backdrop = "none"
    var topStyle = "singlet"
    var bottomStyle = "shorts"
    var shoes = "white"
    var gloves = false

    static let guy = MascotLook()
    static let girl = MascotLook(hair: "ponytail", hairColor: "auburn", top: "pink")

    static let storageKey = "mascotLook.v1"

    init(skin: String = "light", hair: String = "spiky", hairColor: String = "black", top: String = "sky",
         shorts: String = "charcoal", headband: String = "white", facialHair: String = "none",
         eyewear: String = "none", wristbands: Bool = false, belt: Bool = false,
         hat: String = "none", backdrop: String = "none", topStyle: String = "singlet",
         bottomStyle: String = "shorts", shoes: String = "white", gloves: Bool = false) {
        self.skin = skin; self.hair = hair; self.hairColor = hairColor; self.top = top
        self.shorts = shorts; self.headband = headband; self.facialHair = facialHair
        self.eyewear = eyewear; self.wristbands = wristbands; self.belt = belt
        self.hat = hat; self.backdrop = backdrop
        self.topStyle = topStyle; self.bottomStyle = bottomStyle; self.shoes = shoes; self.gloves = gloves
    }

    private nonisolated enum CodingKeys: String, CodingKey {
        case skin, hair, hairColor, top, shorts, headband, facialHair, eyewear, wristbands, belt, hat, backdrop
        case topStyle, bottomStyle, shoes, gloves
    }

    /// Missing fields (from older versions) fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        skin = try c.decodeIfPresent(String.self, forKey: .skin) ?? skin
        hair = try c.decodeIfPresent(String.self, forKey: .hair) ?? hair
        hairColor = try c.decodeIfPresent(String.self, forKey: .hairColor) ?? hairColor
        top = try c.decodeIfPresent(String.self, forKey: .top) ?? top
        shorts = try c.decodeIfPresent(String.self, forKey: .shorts) ?? shorts
        headband = try c.decodeIfPresent(String.self, forKey: .headband) ?? headband
        facialHair = try c.decodeIfPresent(String.self, forKey: .facialHair) ?? facialHair
        eyewear = try c.decodeIfPresent(String.self, forKey: .eyewear) ?? eyewear
        wristbands = try c.decodeIfPresent(Bool.self, forKey: .wristbands) ?? wristbands
        belt = try c.decodeIfPresent(Bool.self, forKey: .belt) ?? belt
        hat = try c.decodeIfPresent(String.self, forKey: .hat) ?? hat
        backdrop = try c.decodeIfPresent(String.self, forKey: .backdrop) ?? backdrop
        topStyle = try c.decodeIfPresent(String.self, forKey: .topStyle) ?? topStyle
        bottomStyle = try c.decodeIfPresent(String.self, forKey: .bottomStyle) ?? bottomStyle
        shoes = try c.decodeIfPresent(String.self, forKey: .shoes) ?? shoes
        gloves = try c.decodeIfPresent(Bool.self, forKey: .gloves) ?? gloves
    }

    /// Decodes the saved look. Falls back to the old guy/girl choice.
    @MainActor static func decode(_ json: String) -> MascotLook {
        if let data = json.data(using: .utf8), let look = try? JSONDecoder().decode(MascotLook.self, from: data) {
            return look
        }
        return UserDefaults.standard.string(forKey: Prefs.mascot) == "girl" ? .girl : .guy
    }

    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The id chosen for a category.
    @MainActor func value(_ category: MascotCategory) -> String {
        switch category {
        case .skin: return skin
        case .hair: return hair
        case .hairColor: return hairColor
        case .top: return top
        case .shorts: return shorts
        case .headband: return headband
        case .facialHair: return facialHair
        case .eyewear: return eyewear
        case .hat: return hat
        case .backdrop: return backdrop
        case .topStyle: return topStyle
        case .bottomStyle: return bottomStyle
        case .shoes: return shoes
        }
    }

    @MainActor func with(_ category: MascotCategory, _ id: String) -> MascotLook {
        var l = self
        switch category {
        case .skin: l.skin = id
        case .hair: l.hair = id
        case .hairColor: l.hairColor = id
        case .top: l.top = id
        case .shorts: l.shorts = id
        case .headband: l.headband = id
        case .facialHair: l.facialHair = id
        case .eyewear: l.eyewear = id
        case .hat: l.hat = id
        case .backdrop: l.backdrop = id
        case .topStyle: l.topStyle = id
        case .bottomStyle: l.bottomStyle = id
        case .shoes: l.shoes = id
        }
        return l
    }

    /// A random look from what you've unlocked.
    @MainActor static func random(_ unlocks: MascotUnlocks) -> MascotLook {
        var look = MascotLook()
        for category in MascotCategory.allCases {
            let owned = category.options.filter { unlocks.owns($0, in: category) }
            var id = owned.randomElement()?.id ?? category.options[0].id
            // Keep extras occasional so random looks stay readable.
            if [.facialHair, .eyewear, .hat].contains(category), Int.random(in: 0..<3) > 0 { id = "none" }
            if category == .backdrop, Bool.random() { id = look.backdrop }
            look = look.with(category, id)
        }
        look.wristbands = unlocks.level >= MascotOptions.wristbandLevel && Bool.random()
        look.belt = unlocks.level >= MascotOptions.beltLevel && Bool.random()
        look.gloves = unlocks.level >= MascotOptions.glovesLevel && Int.random(in: 0..<3) == 0
        return look
    }

    /// Colours for the sprite characters.
    @MainActor var palette: [Character: Color] {
        let skin = MascotOptions.find(self.skin, in: MascotOptions.skins)
        let hair = MascotOptions.find(hairColor, in: MascotOptions.hairColors)
        let top = MascotOptions.find(self.top, in: MascotOptions.tops)
        let shorts = MascotOptions.find(self.shorts, in: MascotOptions.shorts)
        let band = MascotOptions.find(headband, in: MascotOptions.headbands)
        let shoe = MascotOptions.find(shoes, in: MascotOptions.shoes)
        return [
            "n": skin.color,                    // hands
            "e": shoe.color,                    // shoes
            "v": Color(hex: 0x2A2A33),          // lifting gloves
            "k": Color(hex: 0x05090A),
            "s": skin.color, "S": skin.shade,
            "r": Color(hex: 0xF09696),
            "w": .white,
            "g": Color(hex: 0x8A96A8),
            "h": hair.color, "H": hair.shade,
            "c": top.color, "C": top.shade, "o": top.color,
            "d": shorts.color, "D": shorts.shade,
            "m": Color(hex: 0xC8D0D8),
            "q": Color(hex: 0x4B5A7A), "Q": Color(hex: 0x7D8FB5),
            "y": Color(hex: 0xFFC94A), "Y": Color(hex: 0xD9A22E),
            "a": headband == "none" ? skin.color : band.color,
            "W": wristbands ? .white : skin.color,
            "B": belt ? Color(hex: 0xFFC94A) : shorts.color,
        ]
    }
}

// MARK: - Options and unlocks

enum MascotCategory: String, CaseIterable {
    case skin, hair, hairColor, top, shorts, headband, facialHair, eyewear, hat, backdrop
    case topStyle, bottomStyle, shoes

    var options: [MascotOption] {
        switch self {
        case .skin: return MascotOptions.skins
        case .hair: return MascotOptions.hairStyles
        case .hairColor: return MascotOptions.hairColors
        case .top: return MascotOptions.tops
        case .shorts: return MascotOptions.shorts
        case .headband: return MascotOptions.headbands
        case .facialHair: return MascotOptions.facialHair
        case .eyewear: return MascotOptions.eyewear
        case .hat: return MascotOptions.hats
        case .backdrop: return MascotOptions.backdrops
        case .topStyle: return MascotOptions.topStyles
        case .bottomStyle: return MascotOptions.bottomStyles
        case .shoes: return MascotOptions.shoes
        }
    }

    /// "Pink top", "Cap hat"… for unlock messages.
    var itemNoun: String {
        switch self {
        case .skin: return "skin"
        case .hair: return "hair"
        case .hairColor: return "hair colour"
        case .top: return "top"
        case .shorts: return "shorts"
        case .headband: return "headband"
        case .facialHair: return "facial hair"
        case .eyewear: return "eyewear"
        case .hat: return "hat"
        case .backdrop: return "backdrop"
        case .topStyle: return ""
        case .bottomStyle: return ""
        case .shoes: return "shoes"
        }
    }

    func key(_ id: String) -> String { "\(rawValue):\(id)" }

    /// "Pink top", "Hoodie", "Red shoes".
    func label(for option: MascotOption) -> String {
        itemNoun.isEmpty ? option.name : "\(option.name) \(itemNoun)"
    }
}

/// How an item is unlocked.
enum MascotUnlock: Equatable {
    case free
    case level(Int)
    /// Finish this journey chapter.
    case chapter(Int)
    /// Only found in gym bags.
    case bag

    /// Short tag for locked items: "LV 5", "CH 2", "BAG".
    var tag: String {
        switch self {
        case .free: return ""
        case .level(let n): return "LV \(n)"
        case .chapter(let n): return "CH \(n)"
        case .bag: return "BAG"
        }
    }

    var hint: String {
        switch self {
        case .free: return ""
        case .level(let n): return "unlocks at level \(n)"
        case .chapter(let n): return "unlocks when you finish journey chapter \(n)"
        case .bag: return "can only be found in gym bags"
        }
    }
}

struct MascotOption: Identifiable {
    let id: String
    let name: String
    var color: Color = .clear
    var shade: Color = .clear
    var unlock: MascotUnlock = .free
}

/// What you've earned so far.
struct MascotUnlocks {
    var level: Int
    var chaptersDone: Int
    var items: Set<String>

    static let everything = MascotUnlocks(level: 999, chaptersDone: 999, items: [])

    func owns(_ option: MascotOption, in category: MascotCategory) -> Bool {
        switch option.unlock {
        case .free: return true
        case .level(let n): return level >= n
        case .chapter(let n): return chaptersDone >= n
        case .bag: return items.contains(category.key(option.id)) || level >= 999
        }
    }
}

enum MascotOptions {
    static let wristbandLevel = 5
    static let beltLevel = 10
    static let glovesLevel = 3

    private static func c(_ id: String, _ name: String, _ main: UInt32, _ shade: UInt32,
                          _ unlock: MascotUnlock = .free) -> MascotOption {
        MascotOption(id: id, name: name, color: Color(hex: main), shade: Color(hex: shade), unlock: unlock)
    }

    static let skins = [
        c("porcelain", "Porcelain", 0xFCE0C8, 0xE2B896),
        c("light", "Light", 0xF2C6A0, 0xD6A07A),
        c("tan", "Tan", 0xD9A066, 0xB57F4C),
        c("brown", "Brown", 0xA8714A, 0x875632),
        c("deep", "Deep", 0x6E4630, 0x553422),
    ]
    static let hairStyles = [
        MascotOption(id: "spiky", name: "Spiky"),
        MascotOption(id: "short", name: "Short"),
        MascotOption(id: "buzz", name: "Buzz cut"),
        MascotOption(id: "ponytail", name: "Ponytail"),
        MascotOption(id: "bun", name: "Bun"),
        MascotOption(id: "long", name: "Long"),
        MascotOption(id: "curly", name: "Curly"),
        MascotOption(id: "bald", name: "Bald"),
        MascotOption(id: "mohawk", name: "Mohawk", unlock: .level(5)),
    ]
    static let hairColors = [
        c("black", "Black", 0x2B2B3A, 0x505064),
        c("brown", "Brown", 0x5A3825, 0x7E5338),
        c("auburn", "Auburn", 0x7A3E2B, 0xA55F41),
        c("blonde", "Blonde", 0xE8C670, 0xF6E0A0),
        c("ginger", "Ginger", 0xD2692F, 0xE8925A),
        c("grey", "Grey", 0xA8ACB4, 0xD0D4DA),
        c("pink", "Pink", 0xF7A8C4, 0xFFC8DC, .level(2)),
        c("blue", "Blue", 0x6FA8DC, 0xA5CCF0, .level(7)),
        c("purple", "Purple", 0x9B6FE0, 0xC2A3F5, .level(11)),
        c("green", "Green", 0x5CC46B, 0x8FE09A, .level(14)),
        c("platinum", "Platinum", 0xE8E8F0, 0xFFFFFF, .level(17)),
        c("fire", "Fire", 0xFF6A2A, 0xFFB347, .bag),
    ]
    static let tops = [
        c("sky", "Sky", 0xB0DCF7, 0x78AFD7),
        c("pink", "Pink", 0xF7A8C4, 0xD7789B),
        c("mint", "Mint", 0x9FE0B0, 0x6FBF86),
        c("red", "Red", 0xE05A5A, 0xB53C3C),
        c("purple", "Purple", 0xB79CF0, 0x8E70D0),
        c("sunny", "Sunny", 0xFFE07A, 0xE0B84A),
        c("black", "Black", 0x3A3F48, 0x23272E),
        c("white", "White", 0xF0F0F0, 0xC8CCD0),
        c("neon", "Neon", 0x39E48A, 0x22B868, .level(6)),
        c("orange", "Orange", 0xFF9F45, 0xD97A22, .level(9)),
        c("gold", "Gold", 0xFFC94A, 0xD9A22E, .level(10)),
        c("teal", "Teal", 0x3CC6C0, 0x23A09A, .level(13)),
        c("lavender", "Lavender", 0xD9C8FF, 0xB39EE6, .level(19)),
        c("hotpink", "Hot pink", 0xFF5FA2, 0xD93F82, .bag),
    ]
    static let shorts = [
        c("charcoal", "Charcoal", 0x3A4652, 0x262F38),
        c("navy", "Navy", 0x2E3F6E, 0x1F2B4E),
        c("red", "Red", 0x9E3A3A, 0x7A2A2A),
        c("grey", "Grey", 0x8A9099, 0x6A7079),
        c("mint", "Mint", 0x6FBF86, 0x4E9A65, .level(12)),
        c("pink", "Pink", 0xD7789B, 0xB5587A, .level(16)),
        c("galaxy", "Galaxy", 0x4B2A8C, 0x32185E, .bag),
    ]
    static let headbands = [
        MascotOption(id: "none", name: "None"),
        c("white", "White", 0xFFFFFF, 0xFFFFFF),
        c("sky", "Sky", 0xB0DCF7, 0xB0DCF7),
        c("pink", "Pink", 0xF7A8C4, 0xF7A8C4),
        c("red", "Red", 0xE05A5A, 0xE05A5A),
        c("black", "Black", 0x3A3F48, 0x3A3F48),
        c("gold", "Gold", 0xFFC94A, 0xFFC94A, .level(15)),
        c("neon", "Neon", 0x39E48A, 0x39E48A, .level(18)),
        c("lime", "Lime", 0xB8F04A, 0xB8F04A, .bag),
    ]
    static let facialHair = [
        MascotOption(id: "none", name: "None"),
        MascotOption(id: "moustache", name: "Moustache"),
        MascotOption(id: "goatee", name: "Goatee"),
        MascotOption(id: "beard", name: "Beard"),
    ]
    static let eyewear = [
        MascotOption(id: "none", name: "None"),
        MascotOption(id: "glasses", name: "Glasses"),
        MascotOption(id: "sunglasses", name: "Shades", unlock: .level(3)),
    ]
    static let hats = [
        MascotOption(id: "none", name: "None"),
        MascotOption(id: "cap", name: "Cap", unlock: .level(4)),
        MascotOption(id: "beanie", name: "Beanie", unlock: .level(8)),
        MascotOption(id: "crown", name: "Crown", unlock: .level(30)),
    ]
    /// Gym clothes. Colours come from "Top" and "Bottoms".
    static let topStyles = [
        MascotOption(id: "singlet", name: "Singlet"),
        MascotOption(id: "tee", name: "T-shirt"),
        MascotOption(id: "crop", name: "Crop top"),
        MascotOption(id: "shirtless", name: "Shirtless"),
        MascotOption(id: "long", name: "Long sleeve", unlock: .level(3)),
        MascotOption(id: "hoodie", name: "Hoodie", unlock: .level(6)),
    ]
    static let bottomStyles = [
        MascotOption(id: "shorts", name: "Shorts"),
        MascotOption(id: "joggers", name: "Joggers"),
        MascotOption(id: "bike", name: "Cycling shorts", unlock: .level(4)),
    ]
    static let shoes = [
        c("white", "White", 0xFFFFFF, 0xD0D4DA),
        c("black", "Black", 0x2A2D33, 0x15171A),
        c("grey", "Grey", 0x9AA0A8, 0x6A7079),
        c("red", "Red", 0xE05A5A, 0xB53C3C, .level(5)),
        c("blue", "Blue", 0x6FA8DC, 0x4A7FB5, .level(7)),
        c("neon", "Neon", 0x5CF0A0, 0x39C47A, .level(9)),
        c("gold", "Gold", 0xFFC94A, 0xD9A22E, .bag),
    ]

    static let backdrops = [
        MascotOption(id: "none", name: "Plain"),
        MascotOption(id: "gym", name: "Gym", unlock: .chapter(1)),
        MascotOption(id: "sunset", name: "Sunset", unlock: .chapter(2)),
        MascotOption(id: "ocean", name: "Beach", unlock: .chapter(3)),
        MascotOption(id: "forest", name: "Forest", unlock: .chapter(4)),
        MascotOption(id: "arena", name: "Arena", unlock: .chapter(5)),
        MascotOption(id: "night", name: "Night", unlock: .level(20)),
        MascotOption(id: "space", name: "Space", unlock: .level(25)),
        MascotOption(id: "disco", name: "Disco", unlock: .bag),
    ]

    static func find(_ id: String, in options: [MascotOption]) -> MascotOption {
        options.first { $0.id == id } ?? options[0]
    }

    /// Items only found in gym bags.
    static var bagItems: [(MascotCategory, MascotOption)] {
        MascotCategory.allCases.flatMap { category in
            category.options.filter { $0.unlock == .bag }.map { (category, $0) }
        }
    }

    /// What reaching `level` unlocks, for the level-up screen and "next unlock".
    static func unlocks(at level: Int) -> [String] {
        var names: [String] = []
        for category in MascotCategory.allCases {
            for option in category.options where option.unlock == .level(level) {
                names.append(category.label(for: option))
            }
        }
        if level == wristbandLevel { names.append("Wristbands") }
        if level == beltLevel { names.append("Gold lifting belt") }
        if level == glovesLevel { names.append("Lifting gloves") }
        // App themes (Settings → Appearance).
        for accent in AppTheme.accents where accent.unlockLevel == level { names.append("\(accent.name) accent colour") }
        for surface in AppTheme.surfaces where surface.unlockLevel == level { names.append("\(surface.name) app background") }
        return names
    }

    /// The next level (after `level`) that unlocks something, and what.
    static func nextUnlock(after level: Int) -> (level: Int, names: [String])? {
        for next in (level + 1)...(level + 40) {
            let names = unlocks(at: next)
            if !names.isEmpty { return (next, names) }
        }
        return nil
    }
}

// MARK: - Backdrops

/// The little scene behind your buddy.
struct BuddyBackdrop: View {
    let id: String
    var cornerRadius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let (top, bottom) = Self.colors(id)
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: [top, bottom]),
                                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let px = max(2, size.width / 40)
            func dot(_ x: Double, _ y: Double, _ color: Color, _ s: Double = 1) {
                context.fill(Path(CGRect(x: x * size.width, y: y * size.height, width: px * s, height: px * s)),
                             with: .color(color))
            }
            let stars: [(Double, Double)] = [(0.1, 0.12), (0.28, 0.3), (0.5, 0.08), (0.72, 0.22), (0.88, 0.1),
                                             (0.18, 0.5), (0.82, 0.45), (0.62, 0.38), (0.4, 0.2)]
            switch id {
            case "gym":
                context.fill(Path(CGRect(x: 0, y: size.height * 0.8, width: size.width, height: size.height * 0.2)),
                             with: .color(Color(hex: 0x3C4654)))
                for i in 0..<5 { dot(0.08 + Double(i) * 0.2, 0.84, Color(hex: 0x4E5968), 3) }
            case "sunset":
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.55, y: size.height * 0.45,
                                                    width: size.width * 0.35, height: size.width * 0.35)),
                             with: .color(Color(hex: 0xFFE07A).opacity(0.85)))
                context.fill(Path(CGRect(x: 0, y: size.height * 0.78, width: size.width, height: size.height * 0.22)),
                             with: .color(Color(hex: 0x6B2E4F)))
            case "ocean":
                context.fill(Path(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.16)),
                             with: .color(Color(hex: 0x2E6FD8)))
                context.fill(Path(CGRect(x: 0, y: size.height * 0.78, width: size.width, height: size.height * 0.22)),
                             with: .color(Color(hex: 0xE8D29A)))
                for i in 0..<4 { dot(0.1 + Double(i) * 0.25, 0.64, .white.opacity(0.7), 2) }
            case "forest":
                for i in 0..<5 {
                    let x = (0.05 + Double(i) * 0.22) * size.width
                    var tree = Path()
                    tree.move(to: CGPoint(x: x, y: size.height * 0.8))
                    tree.addLine(to: CGPoint(x: x + size.width * 0.09, y: size.height * 0.35))
                    tree.addLine(to: CGPoint(x: x + size.width * 0.18, y: size.height * 0.8))
                    context.fill(tree, with: .color(Color(hex: 0x1F5A38)))
                }
                context.fill(Path(CGRect(x: 0, y: size.height * 0.8, width: size.width, height: size.height * 0.2)),
                             with: .color(Color(hex: 0x2F7D4F)))
            case "arena":
                var beam = Path()
                beam.move(to: CGPoint(x: size.width * 0.5, y: 0))
                beam.addLine(to: CGPoint(x: size.width * 0.15, y: size.height))
                beam.addLine(to: CGPoint(x: size.width * 0.85, y: size.height))
                context.fill(beam, with: .color(.white.opacity(0.12)))
                context.fill(Path(CGRect(x: 0, y: size.height * 0.82, width: size.width, height: size.height * 0.18)),
                             with: .color(Color(hex: 0x6B4E16)))
            case "night":
                for s in stars { dot(s.0, s.1, .white.opacity(0.8)) }
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.7, y: size.height * 0.08,
                                                    width: size.width * 0.16, height: size.width * 0.16)),
                             with: .color(Color(hex: 0xFFF4BC)))
            case "space":
                for s in stars { dot(s.0, s.1, .white.opacity(0.9)) }
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.06, y: size.height * 0.55,
                                                    width: size.width * 0.28, height: size.width * 0.28)),
                             with: .color(Color(hex: 0xB79CF0)))
            case "disco":
                let colors: [Color] = [Color(hex: 0xFF5FA2), Color(hex: 0x39E48A), Color(hex: 0xFFE07A), Color(hex: 0x6FA8DC)]
                for (i, s) in stars.enumerated() { dot(s.0, s.1 + 0.3, colors[i % colors.count], 2) }
            default:
                break
            }
        }
        .clipShape(shape)
    }

    static func colors(_ id: String) -> (Color, Color) {
        switch id {
        case "gym": return (Color(hex: 0x1E2630), Color(hex: 0x2A3340))
        case "sunset": return (Color(hex: 0xFF9A62), Color(hex: 0xF25F8C))
        case "ocean": return (Color(hex: 0x63C5F2), Color(hex: 0xA8E2FA))
        case "forest": return (Color(hex: 0x9FD8A8), Color(hex: 0x5DAA6E))
        case "arena": return (Color(hex: 0x2A1E08), Color(hex: 0x8C6A22))
        case "night": return (Color(hex: 0x141B3A), Color(hex: 0x2D2A6E))
        case "space": return (Color(hex: 0x0B0B1E), Color(hex: 0x2B1055))
        case "disco": return (Color(hex: 0x3A1258), Color(hex: 0x7A1E6E))
        default: return (Color.ppCard, Color.ppCard)
        }
    }
}

// MARK: - Actions

/// What the buddy is doing. Each action is a little flip-book of frames.
enum MascotAction: Equatable, CaseIterable {
    case idle, sleepy, lift, flex, cheer, wave
    /// Lifts the bar overhead, cheers, then keeps flexing. For "workout done" moments.
    case celebrate

    struct Step {
        let frame: Int
        let seconds: Double
    }

    // Frame numbers in MascotSprites.
    private static let idle0 = 0, idle1 = 1, sleepy0 = 2
    private static let lift0 = 3, lift1 = 4, lift2 = 5, lift3 = 6
    private static let flex0 = 7, flex1 = 8, cheer0 = 9, cheer1 = 10, wave0 = 11, wave1 = 12

    var steps: [Step] {
        typealias A = MascotAction
        let lift = [Step(frame: A.lift0, seconds: 0.5), Step(frame: A.lift1, seconds: 0.3),
                    Step(frame: A.lift2, seconds: 0.35), Step(frame: A.lift3, seconds: 0.7)]
        let cheer = [Step(frame: A.cheer0, seconds: 0.18), Step(frame: A.cheer1, seconds: 0.18)]
        let flex = [Step(frame: A.flex0, seconds: 0.45), Step(frame: A.flex1, seconds: 0.45)]
        let idle = [Step(frame: A.idle0, seconds: 0.9), Step(frame: A.idle1, seconds: 0.9)]
        switch self {
        case .idle: return idle
        case .sleepy: return [Step(frame: A.sleepy0, seconds: 1)]
        case .lift: return lift + [Step(frame: A.idle0, seconds: 0.6)]
        case .flex: return flex
        case .cheer: return cheer
        case .wave: return [Step(frame: A.wave0, seconds: 0.3), Step(frame: A.wave1, seconds: 0.3)]
        case .celebrate: return lift + cheer + cheer + cheer + flex + flex + idle
        }
    }

    /// Where the loop restarts after the first play-through (celebrate lifts once, then loops the rest).
    var loopFrom: Int { self == .celebrate ? 4 : 0 }

    /// Single frame to show when not animating (Reduce Motion, share pictures, small previews).
    var stillFrame: Int {
        switch self {
        case .idle: return Self.idle0
        case .sleepy: return Self.sleepy0
        case .lift, .celebrate: return Self.lift3
        case .flex: return Self.flex0
        case .cheer: return Self.cheer0
        case .wave: return Self.wave0
        }
    }

    func frame(after elapsed: Double) -> Int {
        let steps = self.steps
        guard steps.count > 1 else { return steps.first?.frame ?? 0 }
        let intro = steps.reduce(0) { $0 + $1.seconds }
        var t = elapsed
        var from = 0
        if t >= intro {
            let loop = steps[loopFrom...].reduce(0) { $0 + $1.seconds }
            t = (t - intro).truncatingRemainder(dividingBy: max(loop, 0.01))
            from = loopFrom
        }
        for step in steps[from...] {
            if t < step.seconds { return step.frame }
            t -= step.seconds
        }
        return steps.last?.frame ?? 0
    }
}

// MARK: - Views

/// Draws and animates a buddy with a given look.
struct PixelMascot: View {
    var look: MascotLook
    var action: MascotAction = .idle
    var size: CGFloat = 64
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    var body: some View {
        let palette = look.palette
        Group {
            if animated && !reduceMotion && action.steps.count > 1 {
                TimelineView(.periodic(from: start, by: 0.05)) { context in
                    let index = action.frame(after: context.date.timeIntervalSince(start))
                    MascotFrame(look: look, frame: index, palette: palette)
                }
            } else {
                MascotFrame(look: look, frame: action.stillFrame, palette: palette)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: action) { start = .now }
        .accessibilityHidden(true)
    }
}

/// One frame: back hair, body, front hair, face parts, then arms and bar on top.
private struct MascotFrame: View {
    let look: MascotLook
    let frame: Int
    let palette: [Character: Color]

    var body: some View {
        let back = clothesBack, front = clothesFront
        return Canvas { context, canvas in
            let cell = canvas.width / 28
            let partY = MascotSprites.headY[frame] - MascotSprites.partYOffset
            let partX = MascotSprites.partX

            func draw(_ rows: [String]?, x: Int = 0, y: Int = 0, fromRow: Int = 0) {
                guard let rows else { return }
                for (row, line) in rows.enumerated() where row >= fromRow {
                    for (column, ch) in line.enumerated() {
                        guard let color = palette[ch] else { continue }
                        let rect = CGRect(x: CGFloat(column + x) * cell, y: CGFloat(row + y) * cell,
                                          width: cell + 0.3, height: cell + 0.3)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }

            func drawPixels(_ pixels: [MascotSprites.Pixel]) {
                for p in pixels {
                    guard let color = palette[p.ch] else { continue }
                    context.fill(Path(CGRect(x: CGFloat(p.x) * cell, y: CGFloat(p.y) * cell,
                                             width: cell + 0.3, height: cell + 0.3)), with: .color(color))
                }
            }

            draw(MascotSprites.hairBack[look.hair], x: partX, y: partY)
            draw(MascotSprites.bodyBack[frame])
            drawPixels(back)
            // A cap or beanie hides any hair sticking up above the head.
            let covers = look.hat == "cap" || look.hat == "beanie"
            draw(MascotSprites.hairFront[look.hair], x: partX, y: partY,
                 fromRow: covers ? MascotSprites.hairRowsAboveHead : 0)
            draw(MascotSprites.faceParts[look.facialHair], x: partX, y: partY)
            draw(MascotSprites.faceParts[look.eyewear], x: partX, y: partY)
            draw(MascotSprites.hats[look.hat], x: partX, y: partY)
            draw(MascotSprites.bodyFront[frame])
            drawPixels(front)
        }
    }

    /// Clothing pixels for this frame (T-shirt sleeves, joggers, gloves…), behind and in front.
    private var clothesBack: [MascotSprites.Pixel] { clothes("back") }
    private var clothesFront: [MascotSprites.Pixel] { clothes("front") }

    private func clothes(_ layer: String) -> [MascotSprites.Pixel] {
        var keys: [String] = []
        if look.topStyle != "singlet" { keys.append("top:\(look.topStyle)") }
        if look.bottomStyle != "shorts" { keys.append("bottom:\(look.bottomStyle)") }
        if look.gloves { keys.append("gear:gloves") }
        return keys.flatMap { MascotSprites.clothingLayer("\($0):\(layer)", frame: frame) }
    }
}

extension MascotSprites {
    struct Pixel {
        let x: Int
        let y: Int
        let ch: Character
    }

    private static var decoded: [String: [[Pixel]]] = [:]

    /// One clothing layer's pixels for a frame (decoded once, then cached).
    static func clothingLayer(_ key: String, frame: Int) -> [Pixel] {
        if decoded[key] == nil {
            decoded[key] = (clothing[key] ?? []).map(decode)
        }
        let frames = decoded[key] ?? []
        return frame >= 0 && frame < frames.count ? frames[frame] : []
    }

    /// "8gc9gc…": x and y in base 36, then the colour character.
    private static func decode(_ text: String) -> [Pixel] {
        let chars = Array(text)
        return stride(from: 0, to: chars.count - 2, by: 3).compactMap { i in
            guard let x = Int(String(chars[i]), radix: 36), let y = Int(String(chars[i + 1]), radix: 36) else { return nil }
            return Pixel(x: x, y: y, ch: chars[i + 2])
        }
    }
}

/// Your buddy (customised in Settings), used all over the app.
struct PixelBuddy: View {
    enum Mood { case idle, flex, sleepy }
    var mood: Mood = .idle
    var size: CGFloat = 64
    /// Overrides the mood with a specific animation.
    var action: MascotAction? = nil
    var animated = true
    /// Draw the scene you picked behind the buddy.
    var backdrop = false

    @AppStorage(MascotLook.storageKey) private var lookJSON = ""

    var body: some View {
        let look = MascotLook.decode(lookJSON)
        PixelMascot(look: look, action: action ?? moodAction, size: size, animated: animated)
            .background {
                if backdrop && look.backdrop != "none" {
                    BuddyBackdrop(id: look.backdrop, cornerRadius: size * 0.2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if mood == .sleepy && action == nil {
                    Text("z")
                        .font(.pixel(size * 0.22))
                        .foregroundStyle(Color.brand)
                        .offset(x: -size * 0.1, y: size * 0.08)
                }
            }
    }

    private var moodAction: MascotAction {
        switch mood {
        case .idle: return .idle
        case .flex: return .flex
        case .sleepy: return .sleepy
        }
    }
}

/// Onboarding: quick guy/girl presets plus a "Customise" button.
struct MascotPicker: View {
    @AppStorage(MascotLook.storageKey) private var lookJSON = ""
    var size: CGFloat = 96
    @State private var editing = false

    var body: some View {
        let current = MascotLook.decode(lookJSON)
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                preset("Guy", .guy, current: current)
                preset("Girl", .girl, current: current)
            }
            Button {
                Haptics.tap()
                editing = true
            } label: {
                HStack(spacing: 8) {
                    PixelMascot(look: current, action: .idle, size: 28, animated: false)
                    Text("Customise your buddy")
                }
                .font(.pixel(DS.TextSize.subhead))
                .foregroundStyle(Color.ppText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.ppLine.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $editing) {
            NavigationStack { BuddyEditorView() }
        }
    }

    private func preset(_ label: String, _ look: MascotLook, current: MascotLook) -> some View {
        // A preset stays highlighted while your look is still close to it.
        let selected = current.hair == look.hair && current.top == look.top
        return Button {
            Haptics.select()
            lookJSON = look.encoded
        } label: {
            VStack(spacing: 6) {
                PixelMascot(look: look, action: selected ? .wave : .idle, size: size)
                Text(label)
                    .font(.pixel(DS.TextSize.subhead))
                    .foregroundStyle(selected ? Color.ppText : .secondary)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.ppCard, in: RoundedRectangle(cornerRadius: DS.Radius.tile))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.tile)
                    .strokeBorder(selected ? Color.brand : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) buddy")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
