import Foundation
import XCTest
@testable import VESCCore

final class NavigationFormatTests: XCTestCase {
    private func prediction(arrival: Double, reserve: Double = 20) -> ArrivalBatteryPrediction {
        ArrivalBatteryPrediction(arrivalPercent: arrival, reserveShortfallPercent: max(0, reserve - arrival),
                                 willExhaustBeforeArrival: arrival < 0, secondsUntilEmpty: 600,
                                 observedSpanSeconds: 90, depletionPercentPerSecond: 0.02)
    }

    func testDistanceIsCompactAndUnavailableIsADash() {
        XCTAssertEqual(NavigationFormat.distance(nil), "—")
        XCTAssertEqual(NavigationFormat.distance(-1), "—")
        XCTAssertEqual(NavigationFormat.distance(.nan), "—")
        XCTAssertEqual(NavigationFormat.distance(.infinity), "—")
        XCTAssertEqual(NavigationFormat.distance(0), "0 m")
        XCTAssertEqual(NavigationFormat.distance(919.4), "919 m")
        XCTAssertEqual(NavigationFormat.distance(1240), "1.24 km")
        XCTAssertEqual(NavigationFormat.distance(12_440), "12.4 km")
    }

    func testDurationDropsLeadingZerosAndSwitchesToHours() {
        XCTAssertEqual(NavigationFormat.duration(nil), "—")
        XCTAssertEqual(NavigationFormat.duration(-5), "—")
        XCTAssertEqual(NavigationFormat.duration(.nan), "—")
        XCTAssertEqual(NavigationFormat.duration(0), "0:00")
        XCTAssertEqual(NavigationFormat.duration(180), "3:00")
        XCTAssertEqual(NavigationFormat.duration(3599.4), "59:59")
        XCTAssertEqual(NavigationFormat.duration(3900), "1h 05m")
        XCTAssertEqual(NavigationFormat.duration(400_000), "—")
    }

    func testUnavailablePredictionNeverLooksLikeAPercentage() {
        let summary = ArrivalBatterySummary(prediction: nil, reservePercent: 20)
        XCTAssertEqual(summary.level, .unavailable)
        XCTAssertEqual(summary.glance, "—")
        XCTAssertFalse(summary.detail.contains("%"))
    }

    func testAboveReserveRoundsDownAndNamesTheReserve() {
        let summary = ArrivalBatterySummary(prediction: prediction(arrival: 64.9), reservePercent: 20)
        XCTAssertEqual(summary.level, .aboveReserve)
        XCTAssertEqual(summary.glance, "~64%")
        XCTAssertEqual(summary.detail, "Arrival ~64% · reserve 20%")
        XCTAssertTrue(summary.spoken.contains("above the 20 percent reserve"))
    }

    func testJustBelowReserveIsFlaggedAndShortfallRoundsUp() {
        let summary = ArrivalBatterySummary(prediction: prediction(arrival: 19.5), reservePercent: 20)
        XCTAssertEqual(summary.level, .belowReserve)
        XCTAssertEqual(summary.glance, "~19%")
        XCTAssertEqual(summary.detail, "Arrival ~19% · 1% under 20% reserve")
        XCTAssertTrue(summary.spoken.contains("below the 20 percent reserve"))
    }

    func testExhaustionIsExplicitAndNeverAZeroPercent() {
        let summary = ArrivalBatterySummary(prediction: prediction(arrival: -3), reservePercent: 20)
        XCTAssertEqual(summary.level, .exhaustedBeforeArrival)
        XCTAssertEqual(summary.glance, "Empty")
        XCTAssertEqual(summary.detail, "Battery runs out before arrival")
        XCTAssertFalse(summary.glance.contains("0%"))
    }

    func testZeroReserveAndInvalidReserveStayConsistent() {
        XCTAssertEqual(ArrivalBatterySummary(prediction: prediction(arrival: 3, reserve: 0), reservePercent: 0).level, .aboveReserve)
        let invalid = ArrivalBatterySummary(prediction: prediction(arrival: 30, reserve: 0), reservePercent: .nan)
        XCTAssertEqual(invalid.detail, "Arrival ~30% · reserve 0%")
    }

    func testDistanceRoundsHalfAwayFromZeroLikeThePreview() {
        // Same text as the browser preview's Math.round at exact binary ties and unit edges.
        XCTAssertEqual(NavigationFormat.distance(999.4), "999 m")
        XCTAssertEqual(NavigationFormat.distance(999.5), "1.00 km")
        XCTAssertEqual(NavigationFormat.distance(1125), "1.13 km")
        XCTAssertEqual(NavigationFormat.distance(9994.9), "9.99 km")
        XCTAssertEqual(NavigationFormat.distance(9995), "10.0 km")
        XCTAssertEqual(NavigationFormat.distance(10250), "10.3 km")
    }
}
