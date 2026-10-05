import Foundation
import XCTest
@testable import VESCCore

final class BMSCellSnapshotTests: XCTestCase {
    private let id = UUID(uuidString: "D7468AAB-FD58-4D23-84D1-FC24DB501201")!
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testCompleteMeasuredTwelveCellSetPreservesOrderAndNumericSummary() throws {
        let cells = [3.91, 3.92, 3.90, 3.94, 3.93, 3.91, 3.92, 3.90, 3.93, 3.92, 3.91, 3.92]
        let snapshot = try XCTUnwrap(BMSCellSnapshot(deviceID: id, cellVoltages: cells, measuredAt: timestamp))
        XCTAssertEqual(snapshot.deviceID, id)
        XCTAssertEqual(snapshot.measuredAt, timestamp)
        XCTAssertEqual(snapshot.cellVoltages, cells)
        XCTAssertEqual(snapshot.cellCount, 12)
        XCTAssertEqual(snapshot.minVoltage, 3.90, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.maxVoltage, 3.94, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.deltaMillivolts, 40, accuracy: 0.000_001)
    }

    func testMissingExtraAndEmptyCellsCannotClaimFullPackOrBalancedSummary() {
        for count in [0, 1, 11, 13, 50] {
            XCTAssertNil(BMSCellSnapshot(deviceID: id, cellVoltages: Array(repeating: 3.92, count: count), measuredAt: timestamp))
        }
    }

    func testNonFiniteNegativeAndOutOfBoundsVoltageRejectEntireSnapshot() {
        for value in [Double.nan, .infinity, -.infinity, -0.001, -3.9, 6.01, Double.greatestFiniteMagnitude] {
            var cells = Array(repeating: 3.92, count: 12)
            cells[7] = value
            XCTAssertNil(BMSCellSnapshot(deviceID: id, cellVoltages: cells, measuredAt: timestamp))
        }
    }

    func testZeroOrVeryLowReportedCellIsPreservedAsCriticalMeasurement() throws {
        for value in [0.0, 0.1] {
            var cells = Array(repeating: 3.92, count: 12)
            cells[4] = value
            let snapshot = try XCTUnwrap(BMSCellSnapshot(deviceID: id, cellVoltages: cells, measuredAt: timestamp))
            XCTAssertEqual(snapshot.cellVoltages[4], value)
            XCTAssertEqual(snapshot.minVoltage, value)
            XCTAssertEqual(snapshot.maxVoltage, 3.92)
            XCTAssertEqual(snapshot.deltaMillivolts, (3.92 - value) * 1000, accuracy: 0.000_001)
        }
    }

    func testDeclaredCellCountsAreBoundedWithoutAssumingFourteenSeries() throws {
        for count in [1, 12, 14, 50] {
            let snapshot = try XCTUnwrap(BMSCellSnapshot(deviceID: id, cellVoltages: Array(repeating: 3.92, count: count), measuredAt: timestamp, expectedCellCount: count))
            XCTAssertEqual(snapshot.cellCount, count)
        }
        for count in [-1, 0, 51, Int.max] {
            XCTAssertNil(BMSCellSnapshot(deviceID: id, cellVoltages: [], measuredAt: timestamp, expectedCellCount: count))
        }
    }

    func testFreshnessRejectsFutureStaleAndInvalidClocksWithoutRefreshingTimestamp() throws {
        let snapshot = try XCTUnwrap(BMSCellSnapshot(deviceID: id, cellVoltages: Array(repeating: 3.92, count: 12), measuredAt: timestamp))
        XCTAssertTrue(snapshot.isFresh(at: timestamp))
        XCTAssertTrue(snapshot.isFresh(at: timestamp.addingTimeInterval(9.999)))
        XCTAssertFalse(snapshot.isFresh(at: timestamp.addingTimeInterval(10)))
        XCTAssertFalse(snapshot.isFresh(at: timestamp.addingTimeInterval(-0.001)))
        XCTAssertFalse(snapshot.isFresh(at: Date(timeIntervalSince1970: .nan)))
        for age in [Double.nan, .infinity, 0, -1] { XCTAssertFalse(snapshot.isFresh(at: timestamp, maxAge: age)) }
        XCTAssertEqual(snapshot.measuredAt, timestamp)
        XCTAssertNil(BMSCellSnapshot(deviceID: id, cellVoltages: Array(repeating: 3.92, count: 12), measuredAt: Date(timeIntervalSince1970: .infinity)))
    }

    func testStandardBatteryPercentageIsOneBoundedByteNotCellMeasurements() {
        for value in [0, 1, 76, 100] { XCTAssertEqual(BMSStandardValue.batteryPercent(Data([UInt8(value)])), value) }
        for data in [Data(), Data([101]), Data([255]), Data([76, 0]), Data(repeating: 76, count: 12)] {
            XCTAssertNil(BMSStandardValue.batteryPercent(data))
        }
    }

    func testStandardIdentityTextMustBeBoundedValidReadableUTF8() {
        XCTAssertEqual(BMSStandardValue.deviceText(Data("  Battery maker  ".utf8)), "Battery maker")
        XCTAssertEqual(BMSStandardValue.deviceText(Data("Model 12S".utf8)), "Model 12S")
        for data in [Data(), Data("   ".utf8), Data([0xFF]), Data("maker\nspoof".utf8), Data([0]), Data(repeating: 65, count: 129)] {
            XCTAssertNil(BMSStandardValue.deviceText(data))
        }
    }
}
