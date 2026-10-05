import Foundation
import Combine

/// Observable watch adapter. Bluetooth delegates and UI call this object on the main queue.
final class SessionLogger: ObservableObject {
    static let shared = SessionLogger()
    @Published private(set) var isRecording = false
    @Published private(set) var rides: [RideSession] = []
    @Published private(set) var activeRide: RideSession?
    @Published private(set) var storageError: String?
    private var store: RideStore?
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Foiling/Rides", isDirectory: true)
        retryLoad()
    }

    func retryLoad() {
        precondition(Thread.isMainThread)
        // Retrying a failed write must not reload/recover the current active recording.
        guard store == nil else { return }
        do { store = try RideStore(directory: directory); refresh(); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    func startRide() { perform { try $0.startRide() } }
    func endRide() { perform { try $0.endRide() } }
    func deleteRide(id: UUID) { perform { try $0.deleteRide(id: id) } }
    func connectionChanged(isConnected: Bool) {
        // A connection notification may not write anything; it must not hide a failed checkpoint.
        perform(clearErrorOnSuccess: false) { try $0.connectionChanged(isConnected: isConnected) }
    }
    func record(rt: VESCRtStats, speedMs: Double? = nil) {
        guard isRecording, rt.isFresh(maxAge: 6) else { return }
        let sample = RideSample(timestamp: Date(), batteryVoltage: rt.batteryVoltage,
                                inputCurrent: rt.inputCurrent, controllerTemperatureC: rt.mosTemperature,
                                motorTemperatureC: rt.motorTemperature, batteryPercent: rt.batteryPercentIsAvailable ? rt.batteryPercent : nil,
                                speedMs: speedMs)
        perform { try $0.record(sample) }
    }
    private func perform<T>(clearErrorOnSuccess: Bool = true, _ action: (RideStore) throws -> T) {
        precondition(Thread.isMainThread)
        guard let store else {
            storageError = storageError ?? "Ride storage is unavailable. Retry loading before starting a ride."
            return
        }
        do { _ = try action(store); refresh(); if clearErrorOnSuccess { storageError = nil } }
        catch { storageError = error.localizedDescription; refresh() }
    }
    private func refresh() {
        activeRide = store?.activeRide
        isRecording = activeRide != nil
        rides = store?.rides ?? []
    }
}
