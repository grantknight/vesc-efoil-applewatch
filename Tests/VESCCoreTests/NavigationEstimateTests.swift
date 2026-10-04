import Foundation
import XCTest
@testable import VESCCore

final class NavigationEstimateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func decliningTrend() -> ArrivalBatteryEstimator {
        var estimator = ArrivalBatteryEstimator()
        for index in 0...30 {
            let seconds = Double(index * 2)
            estimator.observe(percent: 80 - seconds * 0.02, source: "vesc", at: start.addingTimeInterval(seconds),
                              distanceMeters: 1000 - seconds * 5, isTelemetryFresh: true)
        }
        return estimator
    }

    func testKnownMeasuredTrendPredictsArrivalWithoutAssumingPackCapacity() throws {
        let estimator = decliningTrend()
        let prediction = try XCTUnwrap(estimator.prediction(etaSeconds: 600, now: start.addingTimeInterval(60)))
        XCTAssertEqual(prediction.arrivalPercent, 66.8, accuracy: 0.000001)
        XCTAssertEqual(prediction.depletionPercentPerSecond, 0.02, accuracy: 0.000001)
        XCTAssertEqual(prediction.observedSpanSeconds, 60)
        XCTAssertEqual(prediction.reserveShortfallPercent, 0)
        XCTAssertFalse(prediction.willExhaustBeforeArrival)
        XCTAssertEqual(prediction.secondsUntilEmpty, 3940, accuracy: 0.000001)
    }

    func testPredictionAccountsForElapsedTimeSinceLatestFreshObservation() throws {
        let estimator = decliningTrend()
        let prediction = try XCTUnwrap(estimator.prediction(etaSeconds: 600, now: start.addingTimeInterval(64)))
        XCTAssertEqual(prediction.arrivalPercent, 66.72, accuracy: 0.000001)
        XCTAssertEqual(prediction.secondsUntilEmpty, 3936, accuracy: 0.000001)
    }

    func testExhaustionAndReserveShortfallRemainExplicitInsteadOfClampingToZero() throws {
        let estimator = decliningTrend()
        let prediction = try XCTUnwrap(estimator.prediction(etaSeconds: 5000, reservePercent: 20, now: start.addingTimeInterval(60)))
        XCTAssertEqual(prediction.arrivalPercent, -21.2, accuracy: 0.000001)
        XCTAssertEqual(prediction.reserveShortfallPercent, 41.2, accuracy: 0.000001)
        XCTAssertTrue(prediction.willExhaustBeforeArrival)
        XCTAssertLessThan(prediction.secondsUntilEmpty, 5000)
        let reserve = try XCTUnwrap(estimator.prediction(etaSeconds: 3500, reservePercent: 20, now: start.addingTimeInterval(60)))
        XCTAssertEqual(reserve.arrivalPercent, 8.8, accuracy: 0.000001)
        XCTAssertEqual(reserve.reserveShortfallPercent, 11.2, accuracy: 0.000001)
        XCTAssertFalse(reserve.willExhaustBeforeArrival)
    }

    func testStaleFutureAndNonfinitePredictionTimesCannotProvideAnEstimate() {
        let estimator = decliningTrend()
        for now in [start.addingTimeInterval(67), start.addingTimeInterval(59), Date(timeIntervalSince1970: .infinity)] {
            XCTAssertNil(estimator.prediction(etaSeconds: 600, now: now))
        }
        for eta in [-1, .nan, .infinity, Double(Int.max)] {
            XCTAssertNil(estimator.prediction(etaSeconds: eta, now: start.addingTimeInterval(60)))
        }
        for reserve in [-1, 101, .nan, .infinity] {
            XCTAssertNil(estimator.prediction(etaSeconds: 600, reservePercent: reserve, now: start.addingTimeInterval(60)))
        }
    }

    func testShortSpanAndNoDestinationProgressRemainUnknown() {
        var short = ArrivalBatteryEstimator()
        for index in 0...29 {
            short.observe(percent: 80 - Double(index), source: "vesc", at: start.addingTimeInterval(Double(index * 2)),
                          distanceMeters: 1000 - Double(index * 5), isTelemetryFresh: true)
        }
        XCTAssertNil(short.prediction(etaSeconds: 100, now: start.addingTimeInterval(58)))
        for distanceStep in [0.0, 1.0, -5.0] {
            var noProgress = ArrivalBatteryEstimator()
            for index in 0...30 {
                noProgress.observe(percent: 80 - Double(index) * 0.04, source: "vesc", at: start.addingTimeInterval(Double(index * 2)),
                                   distanceMeters: 1000 - Double(index) * distanceStep, isTelemetryFresh: true)
            }
            XCTAssertNil(noProgress.prediction(etaSeconds: 600, now: start.addingTimeInterval(60)))
        }
    }

    func testFlatRisingAndHighlyVariableBatteryTrendsRemainUnknown() {
        for direction in [0.0, 1.0] {
            var estimator = ArrivalBatteryEstimator()
            for index in 0...30 {
                estimator.observe(percent: 70 + Double(index) * direction * 0.04, source: "vesc", at: start.addingTimeInterval(Double(index * 2)),
                                  distanceMeters: 1000 - Double(index * 5), isTelemetryFresh: true)
            }
            XCTAssertNil(estimator.prediction(etaSeconds: 600, now: start.addingTimeInterval(60)))
        }
        var noisy = ArrivalBatteryEstimator()
        for index in 0...30 {
            let percent = index == 0 ? 80 : index == 30 ? 79 : (index.isMultiple(of: 2) ? 90 : 60)
            noisy.observe(percent: Double(percent), source: "vesc", at: start.addingTimeInterval(Double(index * 2)),
                          distanceMeters: 1000 - Double(index * 5), isTelemetryFresh: true)
        }
        XCTAssertNil(noisy.prediction(etaSeconds: 600, now: start.addingTimeInterval(60)))
    }

    func testGapAndBatterySourceChangeDiscardOldTrend() {
        var gap = decliningTrend()
        gap.observe(percent: 78, source: "vesc", at: start.addingTimeInterval(70), distanceMeters: 600, isTelemetryFresh: true)
        XCTAssertEqual(gap.observationCount, 1)
        XCTAssertNil(gap.prediction(etaSeconds: 600, now: start.addingTimeInterval(70)))
        var changed = decliningTrend()
        changed.observe(percent: 78, source: "voltageEstimate", at: start.addingTimeInterval(62), distanceMeters: 690, isTelemetryFresh: true)
        XCTAssertEqual(changed.observationCount, 1)
        XCTAssertNil(changed.prediction(etaSeconds: 600, now: start.addingTimeInterval(62)))
        changed.reset()
        XCTAssertEqual(changed.observationCount, 0)
    }

    func testUnavailableBatteryGPSAndTelemetryInvalidatePreviouslyUsableTrend() {
        for condition in 0...5 {
            var estimator = decliningTrend()
            estimator.observe(percent: condition == 0 ? nil : condition == 1 ? .nan : condition == 2 ? 101 : 78,
                              source: condition == 3 ? nil : "vesc", at: start.addingTimeInterval(62),
                              distanceMeters: condition == 4 ? nil : 690, isTelemetryFresh: condition != 5)
            XCTAssertEqual(estimator.observationCount, 0)
            XCTAssertNil(estimator.prediction(etaSeconds: 600, now: start.addingTimeInterval(62)))
        }
    }

    func testDuplicateAndBackwardsObservationCannotReuseOrPoisonTrend() {
        var estimator = decliningTrend()
        estimator.observe(percent: 0, source: "vesc", at: start.addingTimeInterval(60), distanceMeters: 0, isTelemetryFresh: true)
        XCTAssertEqual(estimator.observationCount, 31)
        XCTAssertEqual(estimator.prediction(etaSeconds: 600, now: start.addingTimeInterval(60))?.arrivalPercent ?? 0, 66.8, accuracy: 0.000001)
        estimator.observe(percent: 78, source: "vesc", at: start.addingTimeInterval(59), distanceMeters: 690, isTelemetryFresh: true)
        XCTAssertEqual(estimator.observationCount, 0)
    }

    func testLongRunningEvidenceWindowRemainsBoundedAndOnlyUsesRecentObservations() {
        var estimator = ArrivalBatteryEstimator()
        for seconds in 0...1000 {
            estimator.observe(percent: 90 - Double(seconds) * 0.01, source: "vesc", at: start.addingTimeInterval(Double(seconds)),
                              distanceMeters: 10000 - Double(seconds) * 5, isTelemetryFresh: true)
        }
        XCTAssertLessThanOrEqual(estimator.observationCount, 181)
        XCTAssertEqual(estimator.prediction(etaSeconds: 600, now: start.addingTimeInterval(1000))?.observedSpanSeconds, 180)
    }

    func testCoordinateParsingAcceptsSignedDecimalPairsAndRejectsMalformedOrInvalidCoordinates() {
        XCTAssertEqual(NavigationEstimate.parseCoordinate("43.2, 27.6"), NavigationCoordinate(latitude: 43.2, longitude: 27.6))
        XCTAssertEqual(NavigationEstimate.parseCoordinate(" -43.2\n+27.6 "), NavigationCoordinate(latitude: -43.2, longitude: 27.6))
        XCTAssertEqual(NavigationEstimate.parseCoordinate("90;-180"), NavigationCoordinate(latitude: 90, longitude: -180))
        for text in ["", "43.2", "43.2,27.6,1", "latitude,longitude", "91,0", "0,181", "nan,0", "0,inf"] {
            XCTAssertNil(NavigationEstimate.parseCoordinate(text), text)
        }
    }

    func testGoldenGreatCircleDistanceAndCardinalBearings() throws {
        let origin = NavigationCoordinate(latitude: 0, longitude: 0)
        let east = NavigationCoordinate(latitude: 0, longitude: 1)
        XCTAssertEqual(try XCTUnwrap(NavigationEstimate.distanceMeters(from: origin, to: east)), 111_195.08, accuracy: 0.01)
        XCTAssertEqual(NavigationEstimate.bearingDegrees(from: origin, to: east), 90)
        XCTAssertEqual(NavigationEstimate.bearingDegrees(from: origin, to: NavigationCoordinate(latitude: 1, longitude: 0)), 0)
        XCTAssertEqual(NavigationEstimate.bearingDegrees(from: origin, to: NavigationCoordinate(latitude: 0, longitude: -1)), 270)
        XCTAssertEqual(NavigationEstimate.bearingDegrees(from: origin, to: NavigationCoordinate(latitude: -1, longitude: 0)), 180)
        XCTAssertEqual(NavigationEstimate.distanceMeters(from: origin, to: origin), 0)
        XCTAssertNil(NavigationEstimate.bearingDegrees(from: origin, to: origin))
        XCTAssertNil(NavigationEstimate.bearingDegrees(from: origin, to: NavigationCoordinate(latitude: 0, longitude: 180)))
    }

    func testDatelineAndAntipodalDistanceRemainFiniteAndBounded() throws {
        let nearDateline = try XCTUnwrap(NavigationEstimate.distanceMeters(from: NavigationCoordinate(latitude: 0, longitude: 179.9),
                                                                          to: NavigationCoordinate(latitude: 0, longitude: -179.9)))
        XCTAssertEqual(nearDateline, 22_239.016, accuracy: 0.01)
        let antipodal = try XCTUnwrap(NavigationEstimate.distanceMeters(from: NavigationCoordinate(latitude: 0, longitude: 0),
                                                                      to: NavigationCoordinate(latitude: 0, longitude: 180)))
        XCTAssertEqual(antipodal, 20_015_114.442, accuracy: 0.01)
        XCTAssertNil(NavigationEstimate.distanceMeters(from: NavigationCoordinate(latitude: .nan, longitude: 0), to: NavigationCoordinate(latitude: 0, longitude: 0)))
    }

    func testETAUsesOnlyValidGroundSpeedAndNeverPropellerRPM() {
        XCTAssertEqual(NavigationEstimate.etaSeconds(distanceMeters: 1000, speedMs: 5), 200)
        XCTAssertEqual(NavigationEstimate.etaSeconds(distanceMeters: 0, speedMs: 5), 0)
        for speed in [0, 0.5, -1, .nan, .infinity, 101] {
            XCTAssertNil(NavigationEstimate.etaSeconds(distanceMeters: 1000, speedMs: speed))
        }
        for distance in [-1, .nan, .infinity, Double.greatestFiniteMagnitude] {
            XCTAssertNil(NavigationEstimate.etaSeconds(distanceMeters: distance, speedMs: 5))
        }
        XCTAssertNil(NavigationEstimate.etaSeconds(distanceMeters: nil, speedMs: 5))
        XCTAssertNil(NavigationEstimate.etaSeconds(distanceMeters: 1000, speedMs: nil))
    }
}
