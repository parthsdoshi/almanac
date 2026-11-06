import Foundation
import HealthKit

/// Saves finished lifts and logged bodyweight to Apple Health, when the switch in Settings is on.
/// Write-only: the app never reads anything from Health.
@MainActor
final class HealthService {
    static let shared = HealthService()
    static let enabledKey = "health.saveWorkouts"

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private var shareTypes: Set<HKSampleType> { [HKObjectType.workoutType(), HKQuantityType(.bodyMass)] }

    /// Asks once for permission to write workouts and bodyweight. True if workouts can be saved.
    func requestAccess() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [])
        } catch {
            return false
        }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    var canSaveWorkouts: Bool {
        Self.isAvailable && store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func save(_ session: WorkoutSession) async {
        guard Self.isEnabled, canSaveWorkouts else { return }
        let start = session.startDate
        guard start != .distantPast else { return }
        let end = start.addingTimeInterval(TimeInterval(max(60, session.durationSec)))
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([
                HKMetadataKeyIndoorWorkout: true,
                "ShebangWorkout": "Workout \(session.workout.rawValue)",
                "ShebangSets": session.sets.count,
            ])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Health is a nice-to-have; the session is already saved in the app.
        }
    }

    func saveBodyweight(_ lb: Double, on date: Date = .now) async {
        guard Self.isEnabled, Self.isAvailable,
              store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized else { return }
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass),
                                      quantity: HKQuantity(unit: .pound(), doubleValue: lb),
                                      start: date, end: date)
        try? await store.save(sample)
    }
}
