import SwiftUI
import SwiftData

/// Dress up your gym buddy. Items unlock with levels, journey chapters and gym bags.
struct BuddyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSet.date) private var allSets: [WorkoutSet]
    @AppStorage(MascotLook.storageKey) private var lookJSON = ""

    @State private var look = MascotLook()
    @State private var loaded = false
    @State private var previewAction: MascotAction = .wave
    @State private var lockedHint: String?
    @State private var unlocks = MascotUnlocks(level: 1, chaptersDone: 0, items: [])
    @State private var tab: EditorTab = .body
    @State private var bump = false

    enum EditorTab: String, CaseIterable, Identifiable {
        case body = "Body", hair = "Hair", outfit = "Outfit", face = "Face", extras = "Extras"
        var id: String { rawValue }
    }

    private let previewActions: [(String, MascotAction)] = [
        ("Wave", .wave), ("Lift", .lift), ("Flex", .flex), ("Cheer", .cheer), ("Chill", .idle),
    ]

    var body: some View {
        // The buddy stays pinned on top; only the options underneath scroll,
        // so you always see every change as you make it.
        VStack(spacing: 0) {
            preview
                .padding(.horizontal, 16)
                .padding(.top, 8)
            tabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            TabView(selection: $tab) {
                ForEach(EditorTab.allCases) { tab in
                    ScrollView {
                        page(tab)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                    .tag(tab)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(AppBackground())
        .navigationTitle("Your buddy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            guard !loaded else { return }
            look = MascotLook.decode(lookJSON)
            unlocks = GameStats(allSets: allSets).unlocks
            loaded = true
        }
        .onChange(of: look) {
            // Saved as you go, so Home and the celebrations update straight away.
            lookJSON = look.encoded
            guard loaded else { return }
            UserDefaults.standard.set(true, forKey: GettingStarted.buddyKey)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { bump = true }
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bump = false }
            }
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private func page(_ tab: EditorTab) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            switch tab {
            case .body:
                section("Skin") { swatches(.skin) }
                section("Start from") {
                    HStack(spacing: 8) {
                        smallButton("Guy") { look = .guy.with(.backdrop, look.backdrop) }
                        smallButton("Girl") { look = .girl.with(.backdrop, look.backdrop) }
                    }
                }
            case .hair:
                section("Style") { figures(.hair) }
                section("Colour") { swatches(.hairColor) }
            case .outfit:
                section("Top") {
                    figures(.topStyle, closeUp: false)
                    swatches(.top)
                }
                section("Bottoms") {
                    figures(.bottomStyle, closeUp: false)
                    swatches(.shorts)
                }
                section("Shoes") { swatches(.shoes) }
                section("Headband") { swatches(.headband) }
            case .face:
                section("Hat") { figures(.hat) }
                section("Facial hair") { figures(.facialHair) }
                section("Eyewear") { figures(.eyewear) }
            case .extras:
                section("Backdrop") { backdrops }
                section("Gear") {
                    VStack(spacing: 10) {
                        gearToggle("Wristbands", isOn: $look.wristbands, unlockLevel: MascotOptions.wristbandLevel)
                        gearToggle("Gold lifting belt", isOn: $look.belt, unlockLevel: MascotOptions.beltLevel)
                        gearToggle("Lifting gloves", isOn: $look.gloves, unlockLevel: MascotOptions.glovesLevel)
                    }
                }
                Text("Levels unlock new items, journey chapters unlock backdrops, and gym bags hide a few rare ones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(EditorTab.allCases) { item in
                Button {
                    Haptics.select()
                    withAnimation(.snappy) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(.pixel(DS.TextSize.footnote))
                        .foregroundStyle(tab == item ? Color.ppBackground : Color.ppText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(tab == item ? Color.brand : Color.ppLine.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 10) {
            PixelMascot(look: look, action: previewAction, size: 140)
                .id(previewAction)
                .background {
                    if look.backdrop != "none" { BuddyBackdrop(id: look.backdrop, cornerRadius: 24) }
                }
                .scaleEffect(bump ? 1.08 : 1, anchor: .bottom)
            HStack(spacing: 6) {
                ForEach(previewActions, id: \.0) { name, action in
                    Button {
                        Haptics.select()
                        previewAction = action
                    } label: {
                        Text(name)
                            .font(.pixel(DS.TextSize.caption))
                            .foregroundStyle(previewAction == action ? Color.ppBackground : Color.ppText)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(previewAction == action ? Color.brand : Color.ppLine.opacity(0.08),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: DS.Radius.card)
        .overlay(alignment: .topLeading) {
            Text("LV \(unlocks.level) · \(ownedCount)/\(totalCount) items")
                .font(.pixel(DS.TextSize.caption))
                .foregroundStyle(Color.ppFat)
                .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                look = MascotLook.random(unlocks)
                previewAction = .cheer
            } label: {
                Text("Shuffle")
                    .font(.pixel(DS.TextSize.caption))
                    .foregroundStyle(Color.ppText)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(Color.ppLine.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Random look")
        }
        .overlay(alignment: .bottom) {
            if let lockedHint {
                Text(lockedHint)
                    .font(.caption)
                    .foregroundStyle(Color.ppBackground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.ppFat, in: Capsule())
                    .offset(y: 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .zIndex(1)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.ppText)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.ppLine.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Pickers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PPHeader(title)
            content()
        }
    }

    /// Wardrobe collection: items you own vs all there are (plus the 3 bits of gear).
    private var ownedCount: Int {
        let items = MascotCategory.allCases.reduce(0) { total, category in
            total + category.options.filter { unlocks.owns($0, in: category) }.count
        }
        let gear = [MascotOptions.wristbandLevel, MascotOptions.beltLevel, MascotOptions.glovesLevel]
            .filter { unlocks.level >= $0 }.count
        return items + gear
    }
    private var totalCount: Int {
        MascotCategory.allCases.reduce(0) { $0 + $1.options.count } + 3
    }

    private func isLocked(_ option: MascotOption, _ category: MascotCategory) -> Bool {
        !unlocks.owns(option, in: category)
    }

    private func choose(_ option: MascotOption, _ category: MascotCategory) {
        if isLocked(option, category) {
            Haptics.warning()
            withAnimation { lockedHint = "\(option.name) \(option.unlock.hint)" }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { lockedHint = nil }
            }
            return
        }
        Haptics.select()
        look = look.with(category, option.id)
    }

    /// Round colour dots.
    private func swatches(_ category: MascotCategory) -> some View {
        let selected = look.value(category)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(category.options) { option in
                let locked = isLocked(option, category)
                Button { choose(option, category) } label: {
                    ZStack {
                        Circle()
                            .fill(option.id == "none" ? Color.ppLine.opacity(0.08) : option.color)
                            .frame(width: 40, height: 40)
                        if option.id == "none" {
                            Image.pixel(.close, size: 16).foregroundStyle(.secondary)
                        }
                        if locked {
                            Circle().fill(Color.black.opacity(0.55)).frame(width: 40, height: 40)
                            Text(option.unlock.tag.replacingOccurrences(of: " ", with: ""))
                                .font(.pixel(DS.TextSize.caption))
                                .foregroundStyle(Color.ppFat)
                        }
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(selected == option.id ? Color.brand : Color.ppLine.opacity(0.15),
                                          lineWidth: selected == option.id ? 3 : 1)
                            .frame(width: 46, height: 46)
                    }
                    .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name + (locked ? ", locked" : ""))
                .accessibilityAddTraits(selected == option.id ? .isSelected : [])
            }
        }
    }

    /// Close-ups of your buddy wearing each option.
    private func figures(_ category: MascotCategory, closeUp: Bool = true) -> some View {
        let selected = look.value(category)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(category.options) { option in
                let locked = isLocked(option, category)
                Button { choose(option, category) } label: {
                    VStack(spacing: 4) {
                        // Head-and-shoulders close-up, or the whole body for clothes.
                        PixelMascot(look: look.with(category, option.id), action: .idle,
                                    size: closeUp ? 120 : 64, animated: false)
                            .offset(y: closeUp ? 16 : 0)
                            .frame(width: 64, height: closeUp ? 60 : 64)
                            .clipped()
                            .opacity(locked ? 0.35 : 1)
                        Text(locked ? option.unlock.tag : option.name)
                            .font(.caption2)
                            .foregroundStyle(locked ? Color.ppFat : (selected == option.id ? Color.ppText : .secondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.ppCard, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.s)
                            .strokeBorder(selected == option.id ? Color.brand : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name + (locked ? ", locked" : ""))
                .accessibilityAddTraits(selected == option.id ? .isSelected : [])
            }
        }
    }

    /// Little scene tiles.
    private var backdrops: some View {
        let category = MascotCategory.backdrop
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(category.options) { option in
                let locked = isLocked(option, category)
                let selected = look.backdrop == option.id
                Button { choose(option, category) } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if option.id == "none" {
                                RoundedRectangle(cornerRadius: DS.Radius.xs).fill(Color.ppLine.opacity(0.06))
                            } else {
                                BuddyBackdrop(id: option.id, cornerRadius: 10)
                            }
                            if locked {
                                RoundedRectangle(cornerRadius: DS.Radius.xs).fill(Color.black.opacity(0.55))
                                Text(option.unlock.tag).font(.pixel(DS.TextSize.caption)).foregroundStyle(Color.ppFat)
                            }
                        }
                        .frame(height: 52)
                        Text(option.name)
                            .font(.caption2)
                            .foregroundStyle(selected ? Color.ppText : .secondary)
                            .lineLimit(1)
                    }
                    .padding(6)
                    .background(Color.ppCard, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.s)
                            .strokeBorder(selected ? Color.brand : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name + " backdrop" + (locked ? ", locked" : ""))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func gearToggle(_ title: String, isOn: Binding<Bool>, unlockLevel: Int) -> some View {
        let locked = unlocks.level < unlockLevel
        return HStack {
            Text(title).foregroundStyle(locked ? .secondary : Color.ppText)
            Spacer()
            if locked {
                Text("Unlocks at LV \(unlockLevel)")
                    .font(.pixel(DS.TextSize.caption))
                    .foregroundStyle(Color.ppFat)
            } else {
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .tint(Color.brand)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(Color.ppCard, in: RoundedRectangle(cornerRadius: DS.Radius.s))
    }
}
