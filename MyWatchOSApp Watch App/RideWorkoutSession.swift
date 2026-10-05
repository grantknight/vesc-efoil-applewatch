import Foundation
import Combine
import HealthKit

/// Keeps Foil Assist running with the wrist down while a ride records.
///
/// watchOS suspends an ordinary app soon after the wrist is lowered, which stops Bluetooth
/// telemetry, GPS and ride logging. A water-sports workout session is the supported way for an
/// app to keep running in the background. It runs only while a ride is recording and ends when
/// the ride is saved. No workout, heart rate or other sample is written to the Health app.
final class RideWorkoutSession: NSObject, ObservableObject, HKWorkoutSessionDelegate {
    enum Status: Equatable {
        case inactive, starting, running
        case unavailable(String)

        var rideNote: String {
            switch self {
            case .inactive: return ""
            case .starting: return "Starting background running…"
            case .running: return "Keeps logging with your wrist down."
            case .unavailable(let reason): return "\(reason). Logging pauses when the screen sleeps."
            }
        }
    }

    static let shared = RideWorkoutSession()
    @Published private(set) var status: Status = .inactive
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var recordingObserver: AnyCancellable?
    private var startTimeout: Timer?

    /// True until the one-time Health permission has been answered.
    var needsPermission: Bool {
        HKHealthStore.isHealthDataAvailable()
            && healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .notDetermined
    }

    /// Asked from Settings ahead of a ride, so the sheet need not appear at the water's edge.
    func requestPermission(completion: @escaping () -> Void = {}) {
        guard needsPermission else { completion(); return }
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { [weak self] _, _ in
            DispatchQueue.main.async { self?.objectWillChange.send(); completion() }
        }
    }

    /// Starts and stops with the ride; the logger stays the single owner of recording state.
    func follow(_ logger: SessionLogger) {
        guard recordingObserver == nil else { return }
        recordingObserver = logger.$isRecording.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if recording { self?.start() } else { self?.stop() }
            }
    }

    private func start() {
        guard session == nil, status != .starting else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable("Background running unavailable on this Watch")
            return
        }
        status = .starting
        // An unanswered permission sheet must not leave the ride claiming to start forever.
        startTimeout?.invalidate()
        startTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self, self.status == .starting else { return }
            self.status = .unavailable("Background running did not start")
        }
        // Sharing workouts is the permission a workout session requires. Nothing is saved.
        requestPermission { [weak self] in self?.begin() }
    }

    private func begin() {
        // The ride may have been saved while the permission sheet was showing.
        guard status == .starting else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .waterSports
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self
            self.session = session
            // Status turns to running only when HealthKit confirms the session is running.
            session.startActivity(with: Date())
        } catch {
            startTimeout?.invalidate()
            status = .unavailable("Background running could not start")
        }
    }

    private func stop() {
        startTimeout?.invalidate()
        status = .inactive
        let ending = session
        session = nil
        ending?.end()
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self, workoutSession === self.session else { return }
            if toState == .running {
                self.startTimeout?.invalidate()
                self.status = .running
                return
            }
            guard toState == .ended || toState == .stopped else { return }
            // Ended by the system (for example another workout app took over) while still riding.
            self.session = nil
            self.status = .unavailable("Background running stopped")
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, workoutSession === self.session else { return }
            self.startTimeout?.invalidate()
            self.session = nil
            self.status = .unavailable("Background running is not allowed")
        }
    }
}
