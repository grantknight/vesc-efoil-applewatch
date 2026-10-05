import Foundation
import XCTest
@testable import VESCCore

final class BatteryConfigTests: XCTestCase {
    private let keys = ["BATTERY_CELL_COUNT", "BATTERY_USE_VESC_LEVEL", "BATTERY_MIN_V_PER_CELL", "BATTERY_MAX_V_PER_CELL"]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    // One method on purpose: `swift test --parallel` can run methods in separate processes that
    // share UserDefaults.standard, so these ordered checks must not race each other.
    func testTwelveSeriesDefaultSavedCountsAndVoltageClamping() {
        XCTAssertNil(UserDefaults.standard.object(forKey: "BATTERY_CELL_COUNT"))
        XCTAssertEqual(BatteryConfig.cellCount, 12)
        XCTAssertEqual(BatteryConfig.percent(fromVoltage: 12 * 3.3), 0, accuracy: 1e-9)
        XCTAssertEqual(BatteryConfig.percent(fromVoltage: 12 * 3.75), 50, accuracy: 1e-9)
        XCTAssertEqual(BatteryConfig.percent(fromVoltage: 12 * 4.2), 100, accuracy: 1e-9)

        XCTAssertEqual(BatteryConfig.percent(fromVoltage: 0), 0)
        XCTAssertEqual(BatteryConfig.percent(fromVoltage: -5), 0)
        XCTAssertEqual(BatteryConfig.percent(fromVoltage: 30), 0)
        XCTAssertEqual(BatteryConfig.percent(fromVoltage: 60), 100)
        XCTAssertTrue(BatteryConfig.useVescBatteryLevel, "VESC-reported level stays the default source")

        BatteryConfig.cellCount = 10
        XCTAssertEqual(BatteryConfig.cellCount, 10)
        BatteryConfig.cellCount = 99
        XCTAssertEqual(BatteryConfig.cellCount, 24)
        BatteryConfig.cellCount = 10
        XCTAssertEqual(BatteryConfig.percent(fromVoltage: 10 * 4.2), 100, accuracy: 1e-9)
    }
}
