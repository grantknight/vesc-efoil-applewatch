import Foundation
import XCTest
@testable import VESCCore

final class RideStoreTests: XCTestCase {
    private var directory: URL!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func sample(_ seconds: Double, speed: Double? = 5, current: Double = 10) -> RideSample {
        RideSample(timestamp: start.addingTimeInterval(seconds), batteryVoltage: 50, inputCurrent: current,
                   controllerTemperatureC: 35, motorTemperatureC: 40, batteryPercent: 80, speedMs: speed)
    }

    func testCompletedRideSurvivesRestartWithSummaries() throws {
        let store = try RideStore(directory: directory)
        let ride = try store.startRide(at: start)
        try store.record(sample(0))
        try store.record(sample(2))
        try store.endRide(at: start.addingTimeInterval(4))
        let reloaded = try RideStore(directory: directory)
        XCTAssertNil(reloaded.activeRide)
        XCTAssertEqual(reloaded.rides.count, 1)
        let result = try XCTUnwrap(reloaded.rides.first)
        XCTAssertEqual(result.id, ride.id)
        XCTAssertEqual(result.totalSampleCount, 2)
        XCTAssertEqual(result.duration, 4)
        XCTAssertEqual(result.energyWh, 1000 / 3600, accuracy: 0.000001)
        XCTAssertEqual(result.distanceMeters, 10)
        XCTAssertEqual(result.averageWatts, 500)
        XCTAssertFalse(result.interrupted)
    }

    func testInterruptedRideRecoversAtLastPersistedUpdateAndDoesNotResumeSilently() throws {
        let store = try RideStore(directory: directory)
        let original = try store.startRide(at: start)
        try store.record(sample(6))
        let reloaded = try RideStore(directory: directory)
        let recovered = try XCTUnwrap(reloaded.rides.first)
        XCTAssertEqual(recovered.id, original.id)
        XCTAssertTrue(recovered.interrupted)
        XCTAssertEqual(recovered.endedAt, start.addingTimeInterval(6))
        XCTAssertEqual(recovered.duration, 6)
        XCTAssertNil(reloaded.activeRide)
        let again = try RideStore(directory: directory)
        XCTAssertEqual(again.rides, reloaded.rides)
        XCTAssertNotEqual(try again.startRide(at: start.addingTimeInterval(100)).id, original.id)
    }

    func testEmptyRideIsRecoverable() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        let reloaded = try RideStore(directory: directory)
        XCTAssertTrue(try XCTUnwrap(reloaded.rides.first).interrupted)
        XCTAssertEqual(reloaded.rides.first?.duration, 0)
    }

    func testDisconnectKeepsRideButNeverIntegratesAcrossGap() throws {
        let store = try RideStore(directory: directory)
        let original = try store.startRide(at: start)
        try store.record(sample(0))
        try store.record(sample(2))
        try store.connectionChanged(isConnected: false, at: start.addingTimeInterval(3))
        try store.connectionChanged(isConnected: false, at: start.addingTimeInterval(4))
        try store.record(sample(4))
        try store.connectionChanged(isConnected: true, at: start.addingTimeInterval(5))
        try store.record(sample(6))
        try store.record(sample(8))
        let ride = try XCTUnwrap(store.activeRide)
        XCTAssertEqual(ride.id, original.id)
        XCTAssertEqual(ride.totalSampleCount, 4)
        XCTAssertEqual(ride.disconnectionCount, 1)
        XCTAssertEqual(ride.distanceMeters, 20)
        XCTAssertEqual(ride.observedSeconds, 4)
        XCTAssertEqual(ride.energyWh, 2000 / 3600, accuracy: 0.000001)
    }

    func testStaleSampleGapExcludedWithoutExplicitDisconnect() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        try store.record(sample(0))
        try store.record(sample(11))
        try store.record(sample(13))
        XCTAssertEqual(store.activeRide?.distanceMeters, 10)
        XCTAssertEqual(store.activeRide?.observedSeconds, 2)
    }

    func testMissingGPSDoesNotFabricateDistanceOrSpeedButPowerStillLogs() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        try store.record(sample(0, speed: nil))
        try store.record(sample(2, speed: 5))
        try store.record(sample(4, speed: nil))
        XCTAssertEqual(store.activeRide?.distanceMeters, 0)
        XCTAssertEqual(store.activeRide?.maxSpeedMs, 5)
        XCTAssertEqual(store.activeRide?.observedSeconds, 4)
        XCTAssertEqual(store.activeRide?.energyWh ?? 0, 2000 / 3600, accuracy: 0.000001)
    }

    func testRegenerationDoesNotBecomePositiveConsumption() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        try store.record(sample(0, current: -10))
        try store.record(sample(2, current: -10))
        XCTAssertEqual(store.activeRide?.energyWh, 0)
        XCTAssertEqual(store.activeRide?.maxWatts, 0)
    }

    func testTrapezoidalIntegrationAndTimeWeightedAverage() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        try store.record(sample(0, speed: 2, current: 0))
        try store.record(sample(2, speed: 4, current: 20))
        try store.record(sample(6, speed: 6, current: 20))
        XCTAssertEqual(store.activeRide?.distanceMeters, 26)
        XCTAssertEqual(store.activeRide?.averageWatts ?? 0, 5000 / 6, accuracy: 0.000001)
        XCTAssertEqual(store.activeRide?.energyWh ?? 0, 5000 / 3600, accuracy: 0.000001)
    }

    func testRetainedSamplesAreBoundedWithoutLosingLifetimeSummary() throws {
        let store = try RideStore(directory: directory, maxRetainedSamples: 3)
        try store.startRide(at: start)
        for i in 0...10 { try store.record(sample(Double(i))) }
        let ride = try XCTUnwrap(store.activeRide)
        XCTAssertEqual(ride.samples.count, 3)
        XCTAssertEqual(ride.totalSampleCount, 11)
        XCTAssertEqual(ride.samples.first?.timestamp, start.addingTimeInterval(8))
        XCTAssertEqual(ride.distanceMeters, 50)
        XCTAssertEqual(ride.energyWh, 5000 / 3600, accuracy: 0.000001)
        try store.endRide(at: start.addingTimeInterval(11))
        XCTAssertEqual(try RideStore(directory: directory).rides.first?.totalSampleCount, 11)
    }

    func testDuplicateAndBackwardsSamplesCannotDoubleCount() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        try store.record(sample(2))
        try store.record(sample(2))
        XCTAssertThrowsError(try store.record(sample(1)))
        XCTAssertEqual(store.activeRide?.totalSampleCount, 1)
        XCTAssertEqual(store.activeRide?.energyWh, 0)
        XCTAssertThrowsError(try store.endRide(at: start.addingTimeInterval(1)))
        XCTAssertNotNil(store.activeRide)
    }

    func testInvalidTelemetryIsRejectedWithoutPoisoningDiskOrMemory() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        var invalid = sample(1)
        invalid.inputCurrent = .nan
        XCTAssertThrowsError(try store.record(invalid))
        invalid = sample(1, speed: .infinity)
        XCTAssertThrowsError(try store.record(invalid))
        invalid = sample(1)
        invalid.batteryPercent = 101
        XCTAssertThrowsError(try store.record(invalid))
        invalid = sample(1)
        invalid.batteryVoltage = 0
        XCTAssertThrowsError(try store.record(invalid))
        XCTAssertEqual(store.activeRide?.totalSampleCount, 0)
        try store.record(sample(2))
        XCTAssertEqual(try RideStore(directory: directory).rides.first?.totalSampleCount, 1)
    }

    func testFailedStartDoesNotPretendRecordingStarted() throws {
        let store = try RideStore(directory: directory, writeData: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try store.startRide(at: start))
        XCTAssertNil(store.activeRide)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testFailedCheckpointAndEndPreserveLastSuccessfulRideAndAllowRetry() throws {
        var fail = false
        let store = try RideStore(directory: directory, writeData: { data, url in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        try store.startRide(at: start)
        try store.record(sample(0))
        let checkpoint = store.activeRide
        fail = true
        XCTAssertThrowsError(try store.record(sample(2)))
        XCTAssertEqual(store.activeRide, checkpoint)
        XCTAssertThrowsError(try store.endRide(at: start.addingTimeInterval(3)))
        XCTAssertEqual(store.activeRide, checkpoint)
        XCTAssertTrue(store.rides.isEmpty)
        fail = false
        try store.record(sample(2))
        try store.endRide(at: start.addingTimeInterval(3))
        XCTAssertEqual(try RideStore(directory: directory).rides.first?.totalSampleCount, 2)
    }

    func testCorruptFileBlocksLoadAndPreservesAllBytes() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        let url = directory.appendingPathComponent("broken.json")
        let original = Data("{invalid".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try RideStore(directory: directory))
        XCTAssertEqual(try Data(contentsOf: url), original)
        // Active checkpoint was not silently finalized while another archive was corrupt.
        let activeURL = directory.appendingPathComponent(try XCTUnwrap(store.activeRide).id.uuidString + ".json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: activeURL)) as? [String: Any])
        let saved = try XCTUnwrap(object["ride"] as? [String: Any])
        XCTAssertNil(saved["endedAt"])
    }

    func testUnknownSchemaIsNeverOverwritten() throws {
        let store = try RideStore(directory: directory)
        let ride = try store.startRide(at: start)
        let url = directory.appendingPathComponent(ride.id.uuidString + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["schemaVersion"] = 999
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: url)
        XCTAssertThrowsError(try RideStore(directory: directory))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testHistoryIsNewestFirstAndOnlyExplicitDeletionRemovesSavedRide() throws {
        let store = try RideStore(directory: directory)
        let first = try store.startRide(at: start)
        try store.endRide(at: start.addingTimeInterval(1))
        let second = try store.startRide(at: start.addingTimeInterval(2))
        try store.endRide(at: start.addingTimeInterval(3))
        let loaded = try RideStore(directory: directory)
        XCTAssertEqual(loaded.rides.map(\.id), [second.id, first.id])
        try loaded.deleteRide(id: first.id)
        XCTAssertEqual(try RideStore(directory: directory).rides.map(\.id), [second.id])
        try loaded.deleteRide(id: UUID())
        XCTAssertEqual(loaded.rides.count, 1)
    }

    func testFailedDeleteDoesNotRemoveHistoryInMemory() throws {
        let store = try RideStore(directory: directory)
        let ride = try store.startRide(at: start)
        try store.endRide(at: start)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(ride.id.uuidString + ".json"))
        XCTAssertThrowsError(try store.deleteRide(id: ride.id))
        XCTAssertEqual(store.rides.count, 1)
    }

    func testStartingTwiceDoesNotAbandonRideAndEndingInactiveThrows() throws {
        let store = try RideStore(directory: directory)
        XCTAssertThrowsError(try store.endRide(at: start))
        let ride = try store.startRide(at: start)
        XCTAssertThrowsError(try store.startRide(at: start))
        XCTAssertEqual(store.activeRide?.id, ride.id)
    }

    func testSubzeroTemperatureExtremaRemainAccurate() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        var cold = sample(0)
        cold.controllerTemperatureC = -20
        cold.motorTemperatureC = -10
        try store.record(cold)
        XCTAssertEqual(store.activeRide?.maxControllerTemperatureC, -20)
        XCTAssertEqual(store.activeRide?.maxMotorTemperatureC, -10)
    }
    func testUnknownBatteryIsNotRecordedAsAnEmptyBattery() throws {
        let store = try RideStore(directory: directory)
        try store.startRide(at: start)
        var unknown = sample(0)
        unknown.batteryPercent = nil
        try store.record(unknown)
        XCTAssertNil(store.activeRide?.startBatteryPercent)
        XCTAssertNil(store.activeRide?.endBatteryPercent)
        try store.record(sample(2))
        XCTAssertEqual(store.activeRide?.startBatteryPercent, 80)
        XCTAssertEqual(store.activeRide?.endBatteryPercent, 80)
        try store.endRide(at: start.addingTimeInterval(3))
        XCTAssertEqual(try RideStore(directory: directory).rides.first?.samples.first?.batteryPercent, nil)
    }
}
