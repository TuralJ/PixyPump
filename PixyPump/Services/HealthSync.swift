import Foundation
import HealthKit

/// Apple Health: save finished workouts, read your latest body weight.
/// Needs the HealthKit capability and two Info settings in Xcode (see READ ME);
/// until they're there, everything here quietly does nothing.
@MainActor
enum HealthSync {
    static let enabledKey = "healthSyncOn"
    private static let savedDaysKey = "healthSavedDays"
    private static let store = HKHealthStore()

    /// iOS closes the app if Health is used without these texts — so check first.
    static var isConfigured: Bool {
        HKHealthStore.isHealthDataAvailable()
            && Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil
            && Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks once (iOS remembers the answer).
    static func requestAccess() async -> Bool {
        guard isConfigured else { return false }
        let workout = HKObjectType.workoutType()
        let bodyMass = HKQuantityType(.bodyMass)
        do {
            // Only what's used: save workouts, read body weight.
            try await store.requestAuthorization(toShare: [workout], read: [bodyMass])
            return true
        } catch {
            return false
        }
    }

    // MARK: Workouts

    static func alreadySaved(_ day: Date) -> Bool {
        savedDays.contains(dayKey(day))
    }

    /// Saves a strength-training workout from the first to the last set.
    static func saveWorkout(start: Date, end: Date) async throws {
        guard isConfigured else { throw HealthError.notSetUp }
        _ = await requestAccess()
        let workout = HKWorkout(activityType: .traditionalStrengthTraining,
                                start: start,
                                end: max(end, start.addingTimeInterval(60)))
        try await store.save(workout)
        var days = savedDays
        days.insert(dayKey(start))
        UserDefaults.standard.set(Array(days), forKey: savedDaysKey)
    }

    /// Removes every workout PixyPump saved to Apple Health (only ours — never other apps').
    /// Returns how many were deleted.
    static func deleteSavedWorkouts() async -> Int {
        guard isConfigured else { return 0 }
        let ours = HKQuery.predicateForObjects(from: HKSource.default())
        let count = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            // @Sendable: HealthKit calls this on its own queue, not the main thread.
            store.deleteObjects(of: HKObjectType.workoutType(), predicate: ours) { @Sendable _, deleted, _ in
                continuation.resume(returning: deleted)
            }
        }
        UserDefaults.standard.removeObject(forKey: savedDaysKey)
        return count
    }

    /// Whether any workout has been saved to Health from this app.
    static var hasSavedWorkouts: Bool { !savedDays.isEmpty }

    // MARK: Body weight

    /// Latest body weight in kg, if you've logged one in Health.
    static func latestBodyWeightKg() async -> Double? {
        guard isConfigured, await requestAccess() else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    // MARK: Helpers

    private static var savedDays: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: savedDaysKey) ?? [])
    }

    private static func dayKey(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}

nonisolated enum HealthError: LocalizedError {
    case notSetUp
    var errorDescription: String? {
        "Apple Health isn't switched on for \(AppInfo.name) yet. Add the HealthKit capability and the two Health texts in Xcode (see the READ ME)."
    }
}
