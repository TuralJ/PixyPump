import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String
    var createdAt: Date

    /// Picture chosen from the phone's photo library (overrides any bundled image).
    /// No longer used (exercise pictures were removed). Kept so existing saved data still opens.
    @Attribute(.externalStorage) var imageData: Data? = nil

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.exercise)
    var sets: [WorkoutSet] = []

    /// Your own notes, e.g. "seat on 4, close grip". Optional so old data still opens.
    var notes: String? = nil

    init(name: String) {
        self.name = name
        self.createdAt = .now
    }
}

@Model
final class WorkoutSet {
    var reps: Int
    var weight: Double   // kg
    var date: Date
    var exercise: Exercise?
    /// Warm-up, drop set or to failure (nil = normal working set). Optional so old data still opens.
    var kindRaw: String? = nil

    init(reps: Int, weight: Double, date: Date = .now, kind: SetKind = .working) {
        self.reps = reps
        self.weight = weight
        self.date = date
        self.kindRaw = kind == .working ? nil : kind.rawValue
    }
}

/// What kind of set it was. Only working sets count towards targets, records and volume.
nonisolated enum SetKind: String, CaseIterable, Identifiable, Sendable {
    case working, warmup, drop, failure
    var id: String { rawValue }

    var title: String {
        switch self {
        case .working: return "Working set"
        case .warmup: return "Warm-up"
        case .drop: return "Drop set"
        case .failure: return "To failure"
        }
    }

    /// One letter shown instead of the set number.
    var badge: String? {
        switch self {
        case .working: return nil
        case .warmup: return "W"
        case .drop: return "D"
        case .failure: return "F"
        }
    }
}

extension WorkoutSet {
    var kind: SetKind {
        get { SetKind(rawValue: kindRaw ?? "") ?? .working }
        set { kindRaw = newValue == .working ? nil : newValue.rawValue }
    }
    var isWarmup: Bool { kind == .warmup }
    /// Weight × reps (0 for warm-ups).
    var volume: Double { isWarmup ? 0 : weight * Double(reps) }
    /// Estimated one-rep max (Epley formula).
    var estimatedMax: Double { reps <= 1 ? weight : weight * (1 + Double(reps) / 30) }
}

extension Exercise {
    var lastSet: WorkoutSet? { workingSets.max { $0.date < $1.date } }
    var bestWeight: Double { workingSets.map(\.weight).max() ?? 0 }
    /// Everything except warm-ups.
    var workingSets: [WorkoutSet] { sets.filter { !$0.isWarmup } }
    /// Working sets logged today, in order.
    var workingSetsToday: [WorkoutSet] {
        workingSets.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date < $1.date }
    }
}

extension Double {
    /// Parses "82.5" or "82,5" (Polish keyboards use a comma).
    init?(userInput: String) {
        let cleaned = userInput
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, abs(value) < 100_000 else { return nil }
        self = value
    }
}
