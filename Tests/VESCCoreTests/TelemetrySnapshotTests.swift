import Foundation
import XCTest
@testable import VESCCore

final class TelemetrySnapshotTests: XCTestCase {
    private let sampleTime = Date(timeIntervalSince1970: 1_700_000_000)
    private func sample() -> TelemetrySnapshot {
        var snapshot = TelemetrySnapshot()
        snapshot.updatedAt = sampleTime
        snapshot.isConnected = true
        snapshot.watts = 850
        snapshot.batteryVoltage = 46.8
        snapshot.batteryPercent = 76
        snapshot.mosTempC = 42
        snapshot.motorTempC = 48
        return snapshot
    }

    func testCachedReadingExpiresAtSixtySecondsWithoutAnyAppPublication() {
        let snapshot = sample()
        XCTAssertTrue(snapshot.isFresh(at: sampleTime))
        XCTAssertTrue(snapshot.isFresh(at: sampleTime.addingTimeInterval(59.999)))
        XCTAssertFalse(snapshot.isFresh(at: sampleTime.addingTimeInterval(60)))
        XCTAssertFalse(snapshot.isFresh(at: sampleTime.addingTimeInterval(3600)))
        XCTAssertEqual(snapshot.updatedAt, sampleTime, "Checking freshness must not refresh the sample timestamp")
    }

    func testDisconnectedFutureAndUninitializedReadingsAreUnavailable() {
        var snapshot = sample()
        XCTAssertFalse(snapshot.isFresh(at: sampleTime.addingTimeInterval(-0.001)))
        snapshot.isConnected = false
        XCTAssertFalse(snapshot.isFresh(at: sampleTime))
        XCTAssertFalse(TelemetrySnapshot().isFresh(at: sampleTime))
    }

    func testUnknownBatteryAndGPSRoundTripWithoutInventingZero() throws {
        var snapshot = sample()
        snapshot.batteryPercent = nil
        snapshot.speed = nil
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TelemetrySnapshot.self, from: data)
        XCTAssertTrue(decoded.isValid)
        XCTAssertTrue(decoded.isFresh(at: sampleTime))
        XCTAssertNil(decoded.batteryPercent)
        XCTAssertNil(decoded.speed)
        XCTAssertEqual(decoded.watts, 850)
        XCTAssertEqual(decoded.updatedAt, sampleTime)
    }

    func testCorruptCacheCannotAppearFreshOrReachWidgetIntegerConversion() {
        let corruptions: [(String, (inout TelemetrySnapshot) -> Void)] = [
            ("non-finite watts", { $0.watts = .infinity }),
            ("overflowing watts", { $0.watts = Double.greatestFiniteMagnitude }),
            ("negative draw", { $0.watts = -1 }),
            ("invalid voltage", { $0.batteryVoltage = 201 }),
            ("invalid controller temperature", { $0.mosTempC = .nan }),
            ("invalid motor temperature", { $0.motorTempC = 301 }),
            ("negative battery", { $0.batteryPercent = -1 }),
            ("overfull battery", { $0.batteryPercent = 101 }),
            ("non-finite speed", { $0.speed = .nan }),
            ("negative speed", { $0.speed = -1 }),
            ("unknown unit", { $0.speedUnit = "furlongs" })
        ]
        for (name, mutate) in corruptions {
            var snapshot = sample()
            mutate(&snapshot)
            XCTAssertFalse(snapshot.isValid, name)
            XCTAssertFalse(snapshot.isFresh(at: sampleTime), name)
        }
    }

    func testSupportedUnitsAndBoundaryPercentagesRemainUsable() {
        for unit in ["mph", "kph", "ms", "knots"] {
            for battery in [0.0, 100.0] {
                var snapshot = sample()
                snapshot.speedUnit = unit
                snapshot.batteryPercent = battery
                XCTAssertTrue(snapshot.isValid)
                XCTAssertTrue(snapshot.isFresh(at: sampleTime))
            }
        }
    }
}
