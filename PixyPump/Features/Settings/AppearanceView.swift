import SwiftUI
import SwiftData

/// Settings → Appearance, in three groups: Colours, Your stuff and Feel.
/// Changes show in the previews on this screen straight away and apply to the whole app
/// when Settings closes. (Applying them sooner would redraw the tabs underneath, and that
/// would close the Settings sheet while you're still choosing.)
struct AppearanceView: View {
    @Query(sort: \WorkoutSet.date) private var allSets: [WorkoutSet]
    @AppStorage(AppTheme.accentKey) private var accentID = "ice"
    @AppStorage(AppTheme.surfaceKey) private var surfaceID = "midnight"
    @AppStorage(AppTheme.headingKey) private var headings = "pixel"
    @AppStorage(ConfettiStyle.key) private var confettiID = "squares"
    @AppStorage(CelebrationLevel.key) private var celebration = "full"
    @AppStorage(RestSkin.key) private var restSkin = "bar"
    @AppStorage(XPBarStyle.key) private var xpBarStyle = "segments"
    @AppStorage(PlateColors.key) private var plateColors = "pastel"
    @AppStorage(ProfileBanner.key) private var profileBanner = "none"
    /// Which buddy backdrops you own (they double as profile banners).
    @State private var mascotUnlocks = MascotUnlocks(level: 1, chaptersDone: 0, items: [])
    @State private var level = 1
    @State private var lockedHint: String?
    /// Progress towards each theme pack (worked out when the screen opens).
    @State private var packProgress: [ThemePack: Int] = [:]
    @State private var iconChoice: AppIconChoice = .pixel
    /// Plays a confetti preview when you pick a style or celebration size.
    @State private var confettiPreview = 0

    private func unlocked(_ pack: ThemePack) -> Bool {
        DevMode.unlockAll || (packProgress[pack] ?? 0) >= pack.goal
    }

    /// Accent colours you can pick: the standard ones plus those from packs you've earned.
    private var accentChoices: [AppTheme.Accent] {
        AppTheme.accents + ThemePack.allCases.filter(unlocked).map(\.accent)
    }

    private var surfaceChoices: [AppTheme.Surface] {
        AppTheme.surfaces + ThemePack.allCases.filter(unlocked).map(\.surface)
    }

    var body: some View {
        // Reading the stored values here makes the screen redraw with each change.
        let _ = (accentID, surfaceID, headings, confettiID, celebration, restSkin, xpBarStyle, plateColors, profileBanner)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                preview

                // MARK: Colours
                groupHeader("Colours", "Theme packs, accent, background and headings.")
                // Earnable looks.
                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Theme packs")
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(ThemePack.allCases) { pack in
                                ThemePackCard(pack: pack,
                                              progress: packProgress[pack] ?? 0,
                                              unlocked: unlocked(pack),
                                              selected: accentID == pack.accent.id && surfaceID == pack.surface.id) {
                                    applyPack(pack)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    Text("Each pack changes the colours, confetti and app icon. Earn them by training.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Accent colour")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 12) {
                        ForEach(accentChoices) { accent in
                            accentButton(accent)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Background")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(surfaceChoices) { surface in
                            surfaceButton(surface)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Headings")
                    Picker("Headings", selection: $headings) {
                        Text("Pixel").tag("pixel")
                        Text("Clean").tag("clean")
                    }
                    .pickerStyle(.segmented)
                    Text("Pixel is the classic \(AppInfo.name) look. Clean uses a rounded font that's easier to read.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Your stuff
                groupHeader("Your stuff", "Icon, banner and the little things you see while training.")
                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("App icon")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 14) {
                        ForEach(AppIconChoice.allCases) { choice in
                            let lock = iconLock(choice)
                            AppIconTile(choice: choice, locked: lock != nil, lockText: lock ?? "",
                                        selected: iconChoice == choice) {
                                pickIcon(choice, lockText: lock)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Profile banner")
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(MascotOptions.backdrops) { option in
                                bannerTile(option)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    Text("The scene behind your buddy and name on Home. Unlock more by playing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("XP bar")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(XPBarStyle.allCases) { style in
                            styleTile(name: style.name, unlockLevel: style.unlockLevel,
                                      selected: xpBarStyle == style.rawValue) {
                                xpBarStyle = style.rawValue
                            } preview: {
                                XPBar(progress: 0.6, style: style)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Rest timer")
                    HStack(spacing: 10) {
                        ForEach(RestSkin.allCases) { skin in
                            styleTile(name: skin.name, unlockLevel: skin.unlockLevel,
                                      selected: restSkin == skin.rawValue) {
                                restSkin = skin.rawValue
                            } preview: {
                                RestSkinIcon(skin: skin, left: 0.45)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Plates")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(PlateColors.allCases) { colors in
                            styleTile(name: colors.name, unlockLevel: colors.unlockLevel,
                                      selected: plateColors == colors.rawValue) {
                                plateColors = colors.rawValue
                            } preview: {
                                HStack(alignment: .center, spacing: 2) {
                                    ForEach(0..<5, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(colors.color(i))
                                            .frame(width: 6, height: 26 - CGFloat(i) * 4)
                                    }
                                }
                            }
                        }
                    }
                    Text("Used in Plate Stack and the plate calculator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Confetti")
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(ConfettiStyle.allCases) { style in
                                confettiChip(style)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                // MARK: Feel
                groupHeader("Feel", "How big the celebrations are.")
                VStack(alignment: .leading, spacing: 10) {
                    PPHeader("Celebrations")
                    Picker("Celebrations", selection: $celebration) {
                        ForEach(CelebrationLevel.allCases) { level in
                            Text(level.name).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: celebration) { _, _ in confettiPreview += 1 }
                    Text((CelebrationLevel(rawValue: celebration) ?? .full).detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Haptics.tap()
                    accentID = "ice"
                    surfaceID = "midnight"
                    headings = "pixel"
                    confettiID = "squares"
                    celebration = "full"
                    restSkin = "bar"
                    xpBarStyle = "segments"
                    plateColors = "pastel"
                    profileBanner = "none"
                } label: {
                    Text("Back to the original look")
                        .font(.subheadline)
                        .foregroundStyle(Color.brand)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)

                Text("Changes apply when you close Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .tint(Color.brand)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            level = DevMode.unlockAll ? 999 : GameStats(allSets: allSets).level.number
            packProgress = Dictionary(uniqueKeysWithValues: ThemePack.allCases.map {
                ($0, PackProgress.value($0, sets: allSets))
            })
            iconChoice = AppIconChoice.current
            mascotUnlocks = GameStats(allSets: allSets).unlocks
        }
        // Preview of the confetti you picked (unless celebrations are set to Minimal).
        .overlay {
            if confettiPreview > 0 {
                PixelConfetti(duration: 1.8).id(confettiPreview)
            }
        }
    }

    // MARK: Group headers

    /// A big heading over a group of pickers ("Colours", "Your stuff", "Feel").
    private func groupHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                .foregroundStyle(Color.brand)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Packs, icons, confetti

    private func applyPack(_ pack: ThemePack) {
        guard unlocked(pack) else {
            Haptics.warning()
            let left = pack.goal - (packProgress[pack] ?? 0)
            withAnimation { lockedHint = "\(pack.name): \(pack.requirement.lowercased()) (\(left) to go)" }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { lockedHint = nil }
            }
            return
        }
        Haptics.success()
        accentID = pack.accent.id
        surfaceID = pack.surface.id
        confettiID = pack.confetti.rawValue
        confettiPreview += 1
        // The matching icon too.
        Task {
            if await pack.icon.apply() { iconChoice = pack.icon }
        }
    }

    /// Nil when unlocked, otherwise a short "LV 6" / "PACK" label.
    private func iconLock(_ choice: AppIconChoice) -> String? {
        switch choice.unlock {
        case .free: return nil
        case .level(let n): return level >= n ? nil : "LV \(n)"
        case .pack(let pack): return unlocked(pack) ? nil : pack.name.uppercased()
        }
    }

    private func pickIcon(_ choice: AppIconChoice, lockText: String?) {
        if lockText != nil {
            Haptics.warning()
            let hint: String
            switch choice.unlock {
            case .level(let n): hint = "\(choice.name) icon unlocks at Level \(n)"
            case .pack(let pack): hint = "\(choice.name) icon comes with \(pack.name): \(pack.requirement.lowercased())"
            case .free: hint = ""
            }
            withAnimation { lockedHint = hint }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { lockedHint = nil }
            }
            return
        }
        Haptics.select()
        Task {
            if await choice.apply() { iconChoice = choice }
        }
    }

    /// A small picker tile with a live preview, locked until `unlockLevel`.
    private func styleTile<Preview: View>(name: String, unlockLevel: Int, selected: Bool,
                                          pick: @escaping () -> Void,
                                          @ViewBuilder preview: () -> Preview) -> some View {
        let locked = level < unlockLevel
        return Button {
            if locked { showLocked(name, level: unlockLevel); return }
            Haptics.select()
            pick()
        } label: {
            VStack(spacing: 8) {
                preview()
                    .frame(height: 30)
                    .opacity(locked ? 0.35 : 1)
                Text(locked ? "\(name) · LV \(unlockLevel)" : name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.ppText : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(Color.ppLine.opacity(0.05), in: RoundedRectangle(cornerRadius: DS.Radius.s))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .strokeBorder(selected ? Color.brand : Color.ppLine.opacity(0.12), lineWidth: selected ? 2.5 : 1)
            }
        }
        .buttonStyle(.squish)
        .accessibilityLabel(name + (locked ? ", locked" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bannerTile(_ option: MascotOption) -> some View {
        let locked = !(DevMode.unlockAll || mascotUnlocks.owns(option, in: .backdrop))
        let selected = profileBanner == option.id
        return Button {
            if locked {
                Haptics.warning()
                withAnimation { lockedHint = "\(option.name) \(option.unlock.hint)" }
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { lockedHint = nil }
                }
                return
            }
            Haptics.select()
            profileBanner = option.id
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if option.id == "none" {
                        RoundedRectangle(cornerRadius: DS.Radius.xs).fill(Color.ppCard)
                        Text("None").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        BuddyBackdrop(id: option.id, cornerRadius: 10)
                    }
                    if locked {
                        RoundedRectangle(cornerRadius: DS.Radius.xs).fill(Color.black.opacity(0.55))
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.ppFat)   // ds-allow: icon size
                    }
                }
                .frame(width: 96, height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.xs)
                        .strokeBorder(selected ? Color.brand : Color.ppLine.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                }
                Text(option.name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.ppText : .secondary)
            }
        }
        .buttonStyle(.squish)
        .accessibilityLabel(option.name + " banner" + (locked ? ", locked" : ""))
    }

    private func confettiChip(_ style: ConfettiStyle) -> some View {
        let locked = style.pack.map { !unlocked($0) } ?? false
        let selected = confettiID == style.rawValue
        return Button {
            if locked, let pack = style.pack {
                Haptics.warning()
                withAnimation { lockedHint = "\(style.name) comes with \(pack.name)" }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { lockedHint = nil }
                }
                return
            }
            Haptics.select()
            confettiID = style.rawValue
            confettiPreview += 1
        } label: {
            HStack(spacing: 6) {
                Text(locked ? "🔒" : style.emoji)
                Text(style.name).font(.pixel(DS.TextSize.footnote))
            }
            .foregroundStyle(selected ? Color.ppBackground : (locked ? Color.secondary : Color.ppText))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(selected ? Color.brand : Color.ppLine.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.squish)
        .accessibilityLabel(style.name + " confetti" + (locked ? ", locked" : ""))
    }

    // MARK: Preview

    /// A mini Home card in the chosen look.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PixelBuddy(mood: .flex, size: 52, animated: false, backdrop: true)
                    .padding(4)
                    .background(Color.ppCard, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hello!")
                        .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                        .foregroundStyle(Color.ppText)
                    XPBar(progress: 0.6)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.ppLine.opacity(0.1), lineWidth: 6)
                    Circle().trim(from: 0, to: 0.7)
                        .stroke(Color.brand, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("70%").font(.pixel(DS.TextSize.footnote)).foregroundStyle(Color.ppText)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day 1 · Bench & Rows")
                        .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                        .foregroundStyle(Color.ppText)
                    Text("9/21 sets · ~30 min left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Text("Continue")
                    .font(.pixel(DS.TextSize.body))
                    .foregroundStyle(Color.ppBackground)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Color.brand, in: Capsule())
                Spacer()
                Text("History ›")
                    .font(.pixel(DS.TextSize.footnote))
                    .foregroundStyle(Color.brand)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .padding(12)
        .background(Color.ppBackground, in: RoundedRectangle(cornerRadius: DS.Radius.hero))
        .overlay(alignment: .bottom) {
            if let lockedHint {
                Text(lockedHint)
                    .font(.caption)
                    .foregroundStyle(Color.ppOnAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.ppFat, in: Capsule())
                    .offset(y: 14)
                    .transition(.opacity)
            }
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.25), value: accentID)
        .animation(.easeInOut(duration: 0.25), value: surfaceID)
    }

    // MARK: Pickers

    private func showLocked(_ name: String, level needed: Int) {
        Haptics.warning()
        withAnimation { lockedHint = "\(name) unlocks at Level \(needed)" }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { lockedHint = nil }
        }
    }

    private func accentButton(_ accent: AppTheme.Accent) -> some View {
        let locked = level < accent.unlockLevel
        let selected = accentID == accent.id
        return Button {
            if locked { showLocked(accent.name, level: accent.unlockLevel); return }
            Haptics.select()
            accentID = accent.id
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(hex: accent.hex)).frame(width: 40, height: 40)
                    if locked {
                        Circle().fill(Color.black.opacity(0.55)).frame(width: 40, height: 40)
                        Text("LV \(accent.unlockLevel)").font(.pixel(DS.TextSize.caption))
                            .lineLimit(1).fixedSize()
                            .foregroundStyle(Color.ppFat)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(selected ? Color.ppText : Color.ppLine.opacity(0.15), lineWidth: selected ? 3 : 1)
                        .frame(width: 48, height: 48)
                }
                .frame(width: 48, height: 48)
                Text(accent.name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.ppText : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.name + (locked ? ", locked" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func surfaceButton(_ surface: AppTheme.Surface) -> some View {
        let locked = level < surface.unlockLevel
        let selected = surfaceID == surface.id
        return Button {
            if locked { showLocked(surface.name, level: surface.unlockLevel); return }
            Haptics.select()
            surfaceID = surface.id
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.s).fill(Color(hex: surface.background))
                    RoundedRectangle(cornerRadius: DS.Radius.xs).fill(Color(hex: surface.card))
                        .padding(10)
                    if locked {
                        RoundedRectangle(cornerRadius: DS.Radius.s).fill(Color.black.opacity(0.5))
                        Text("LV \(surface.unlockLevel)").font(.pixel(DS.TextSize.caption)).foregroundStyle(Color.ppFat)
                    }
                }
                .frame(height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .strokeBorder(selected ? Color.brand : Color.ppLine.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                }
                Text(surface.name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.ppText : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(surface.name + " background" + (locked ? ", locked" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
