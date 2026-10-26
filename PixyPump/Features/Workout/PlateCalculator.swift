import SwiftUI

// MARK: - Plate maths (everything here is in the unit you see: kg or lb)

@MainActor
enum Plates {
    /// Plates found in most gyms, heaviest first.
    static var available: [Double] {
        Units.current == .kg ? [25, 20, 15, 10, 5, 2.5, 1.25] : [45, 35, 25, 10, 5, 2.5]
    }

    /// Bar choices (0 = no bar, e.g. a plate-loaded machine).
    static var barOptions: [Double] {
        Units.current == .kg ? [20, 15, 10, 0] : [45, 35, 25, 0]
    }

    private static var barKey: String { "barWeight.\(Units.symbol)" }
    private static let exercisesKey = "plateExercises"

    /// The bar you usually use (20 kg / 45 lb by default).
    static var bar: Double {
        get {
            let saved = UserDefaults.standard.object(forKey: barKey) as? Double
            return saved ?? (Units.current == .kg ? 20 : 45)
        }
        set { UserDefaults.standard.set(newValue, forKey: barKey) }
    }

    /// Plates for ONE side to reach `total`, heaviest first, plus anything that can't be made.
    static func perSide(total: Double, bar: Double) -> (plates: [Double], leftover: Double) {
        var side = (total - bar) / 2
        // A mistyped huge number (or inf) would otherwise loop for ages.
        guard side > 0.001, side.isFinite, side < 5_000 else { return ([], 0) }
        var plates: [Double] = []
        for plate in available {
            while side >= plate - 0.001 {
                plates.append(plate)
                side -= plate
            }
        }
        return (plates, side < 0.01 ? 0 : side * 2)
    }

    /// "20 + 10 + 2.5" or "empty bar".
    static func text(total: Double, bar: Double) -> String {
        guard total > bar + 0.001 else { return total + 0.001 >= bar ? "Just the bar" : "Less than the bar" }
        guard total.isFinite, total < bar + 10_000 else { return "Too heavy to load" }
        let result = perSide(total: total, bar: bar)
        var text = result.plates.map(\.plain).joined(separator: " + ")
        if result.leftover > 0 { text += " (+\(result.leftover.plain) \(Units.symbol) can't be loaded)" }
        return text
    }

    // Exercises where you've used the plate calculator show the plates under the weight.
    static func usesPlates(_ exercise: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: exercisesKey) ?? []).contains(exercise.lowercased())
    }

    static func setUsesPlates(_ exercise: String, _ on: Bool) {
        var list = Set(UserDefaults.standard.stringArray(forKey: exercisesKey) ?? [])
        if on { list.insert(exercise.lowercased()) } else { list.remove(exercise.lowercased()) }
        UserDefaults.standard.set(Array(list).sorted(), forKey: exercisesKey)
    }
}

// MARK: - Plate calculator sheet

/// Build the weight by tapping plates (per side), or see what to load for a total.
struct PlateCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exerciseName: String
    /// The weight field on the exercise screen (in your unit).
    @Binding var weightText: String

    @State private var bar: Double = 20
    @State private var side: [Double] = []
    @State private var showPlates = true

    private var total: Double { bar + side.reduce(0, +) * 2 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 18) {
                        VStack(spacing: 4) {
                            Text("\(total.plain) \(Units.symbol)")
                                .font(.pixel(DS.TextSize.display, relativeTo: .largeTitle))
                                .foregroundStyle(Color.ppText)
                                .contentTransition(.numericText())
                            Text(side.isEmpty ? "Bar only" : "Per side: " + side.map(\.plain).joined(separator: " + "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        BarbellPicture(plates: side)
                            .frame(height: 90)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } footer: {
                    Text("Tap a plate below to add it to each side. Tap the picture to take the last plate off.")
                }
                .listRowBackground(Color.ppCard)
                .onTapGesture {
                    guard !side.isEmpty else { return }
                    Haptics.select()
                    withAnimation(.snappy) { _ = side.removeLast() }
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                        ForEach(Plates.available, id: \.self) { plate in
                            Button {
                                Haptics.select()
                                withAnimation(.snappy) {
                                    side.append(plate)
                                    side.sort(by: >)
                                }
                            } label: {
                                Text(plate.plain)
                                    .font(.pixel(DS.TextSize.callout))
                                    .foregroundStyle(Color.ppText)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Color.ppLine.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.s))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Add \(plate.plain) \(Units.symbol) each side")
                        }
                    }
                    .padding(.vertical, 4)
                    if !side.isEmpty {
                        // Same as tapping the picture, but easy to find (and to reach with VoiceOver).
                        Button {
                            Haptics.select()
                            withAnimation(.snappy) { _ = side.removeLast() }
                        } label: {
                            Label { Text("Take last plate off") } icon: { Image.pixel(.minus) }
                        }
                        Button(role: .destructive) {
                            Haptics.warning()
                            withAnimation(.snappy) { side = [] }
                        } label: {
                            Label { Text("Take all plates off") } icon: { Image.pixel(.trash) }
                        }
                    }
                } header: {
                    PPHeader("Add plates (each side)")
                }
                .listRowBackground(Color.ppCard)

                Section {
                    Picker("Bar", selection: $bar) {
                        ForEach(Plates.barOptions, id: \.self) { option in
                            Text(option == 0 ? "None" : "\(option.plain) \(Units.symbol)").tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: bar) { _, value in Plates.bar = value }
                    Toggle("Show plates on this exercise", isOn: $showPlates)
                } header: {
                    PPHeader("Bar")
                } footer: {
                    Text("Pick “None” for plate-loaded machines.")
                }
                .listRowBackground(Color.ppCard)

                Section {
                    Button {
                        Haptics.success()
                        weightText = total.plain
                        Plates.setUsesPlates(exerciseName, showPlates)
                        dismiss()
                    } label: {
                        Text("Use \(total.plain) \(Units.symbol)")
                    }
                    .buttonStyle(.primary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .ppScreen()
            .navigationTitle("Plate calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Plates.setUsesPlates(exerciseName, showPlates)
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    /// Starts from the weight already typed on the exercise screen.
    private func load() {
        bar = Plates.bar
        showPlates = true
        let typed = Double(userInput: weightText) ?? 0
        let result = Plates.perSide(total: typed, bar: bar)
        side = result.plates
    }
}

/// Simple side view of a loaded barbell: bigger plates are taller.
private struct BarbellPicture: View {
    let plates: [Double]

    var body: some View {
        let heaviest = Plates.available.first ?? 25
        GeometryReader { geo in
            let midY = geo.size.height / 2
            ZStack {
                // The bar
                Capsule()
                    .fill(Color.ppLine.opacity(0.35))
                    .frame(width: geo.size.width, height: 6)
                    .position(x: geo.size.width / 2, y: midY)
                // Plates on both sides, from the middle outwards
                HStack(spacing: 3) {
                    ForEach(Array(plates.reversed().enumerated()), id: \.offset) { _, plate in
                        plateView(plate, heaviest: heaviest, maxHeight: geo.size.height)
                    }
                    Rectangle().fill(Color.ppLine.opacity(0.6)).frame(width: 6, height: 26)  // collar
                    Spacer(minLength: 40)
                    Rectangle().fill(Color.ppLine.opacity(0.6)).frame(width: 6, height: 26)
                    ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                        plateView(plate, heaviest: heaviest, maxHeight: geo.size.height)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .clipped()
    }

    private func plateView(_ plate: Double, heaviest: Double, maxHeight: CGFloat) -> some View {
        let ratio = 0.35 + 0.65 * min(plate / heaviest, 1)
        return RoundedRectangle(cornerRadius: 3)
            .fill(color(plate, heaviest: heaviest))
            .frame(width: plate >= heaviest * 0.4 ? 12 : 8, height: maxHeight * ratio)
    }

    private func color(_ plate: Double, heaviest: Double) -> Color {
        // Heaviest plate gets the first colour of your plate set (Settings → Appearance).
        let colors = PlateColors.current
        switch plate / heaviest {
        case 0.9...: return colors.color(0)
        case 0.7..<0.9: return colors.color(1)
        case 0.5..<0.7: return colors.color(2)
        case 0.3..<0.5: return colors.color(3)
        default: return colors.color(4)
        }
    }
}
