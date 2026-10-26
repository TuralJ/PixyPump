import Foundation

/// kg or lb, chosen in onboarding or Settings. Everything is *stored* in kg;
/// this only changes what you see and type.
nonisolated enum WeightUnit: String, CaseIterable, Identifiable, Sendable {
    case kg, lb
    var id: String { rawValue }
    var title: String { self == .kg ? "Kilograms (kg)" : "Pounds (lb)" }
}

@MainActor
enum Units {
    static let lbPerKg = 2.20462262

    static var current: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: Prefs.unit) ?? "") ?? .kg
    }

    /// "kg" or "lb".
    static var symbol: String { current.rawValue }

    /// Stored kg → number in your unit, rounded to 0.1.
    static func display(_ kg: Double) -> Double {
        let value = current == .kg ? kg : kg * lbPerKg
        return (value * 10).rounded() / 10
    }

    /// Number you typed (in your unit) → kg for storing.
    static func toKg(_ value: Double) -> Double {
        current == .kg ? value : value / lbPerKg
    }

    /// The −/+ button step: 2.5 kg or 5 lb.
    static var step: Double { current == .kg ? 2.5 : 5 }

    /// −/+ step for one exercise: barbell 2.5 kg, dumbbells 2 kg, machines 5 kg (5 / 5 / 10 lb).
    static func step(for exercise: String) -> Double {
        let equipment = ExerciseKind.equipment(exercise)
        return current == .kg ? equipment.stepKg : equipment.stepLb
    }

    /// "42.5" (no unit), for text fields.
    static func number(_ kg: Double) -> String { display(kg).plain }

    /// "42.5 kg" / "95 lb".
    static func weight(_ kg: Double) -> String { "\(display(kg).plain) \(symbol)" }

    /// Big totals without decimals: "6,240".
    static func volume(_ kg: Double) -> String {
        (current == .kg ? kg : kg * lbPerKg).spaced
    }
}

// MARK: - Big numbers: "8 672", never "8.672"

extension Int {
    /// Groups thousands with a space ("12 450"). Dots or commas read like decimals
    /// in some languages (Polish shows 2 240 as "2.240"), so we always use a space.
    nonisolated var spaced: String {
        let digits = String(abs(self))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(" ") }
            out.append(ch)
        }
        return self < 0 ? "−" + out : out
    }
}

extension Double {
    /// Rounded to a whole number, thousands grouped with a space.
    nonisolated var spaced: String {
        guard isFinite else { return "–" }
        return Int(rounded()).spaced
    }
}
