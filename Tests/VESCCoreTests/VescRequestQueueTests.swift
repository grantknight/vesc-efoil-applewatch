import Foundation
import XCTest
@testable import VESCCore

final class VescRequestQueueTests: XCTestCase {
    private let realtime = Data([50, 0, 0, 0x89, 0x89])
    private let setup = Data([51, 0, 0, 1, 0x40])
    private let statistics = Data([128, 4, 0xfc])

    func testOneCreditAtATimePreservesSecondaryQueriesAndPollOrder() {
        var queue = VescRequestQueue()
        for request in [realtime, setup, statistics] { XCTAssertTrue(queue.enqueue(request)) }
        XCTAssertEqual(queue.takeNext(), realtime)
        queue.complete() // Radio accepts one write, then advertises no further capacity.
        // Another poll must append realtime behind the queries waiting for capacity.
        XCTAssertTrue(queue.enqueue(realtime))
        XCTAssertTrue(queue.enqueue(setup))
        XCTAssertTrue(queue.enqueue(statistics))
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.takeNext(), setup)
        queue.complete() // Ready callback returns another single credit.
        XCTAssertEqual(queue.takeNext(), statistics)
        queue.complete()
        XCTAssertEqual(queue.takeNext(), realtime)
        queue.complete()
        XCTAssertNil(queue.takeNext())
    }

    func testAcknowledgedWriteHoldsSingleFlightUntilCompletion() {
        var queue = VescRequestQueue()
        queue.enqueue(realtime)
        queue.enqueue(setup)
        XCTAssertEqual(queue.takeNext(), realtime)
        XCTAssertNil(queue.takeNext(), "A second write must not start before acknowledgement")
        for _ in 0..<100 { XCTAssertTrue(queue.enqueue(realtime)) }
        XCTAssertEqual(queue.count, 2, "The in-flight command must not be duplicated by later polls")
        XCTAssertEqual(queue.inFlight, realtime)
        queue.complete()
        XCTAssertEqual(queue.takeNext(), setup)
    }

    func testRepeatedBlockedPollsRemainBoundedAndKeepCommandOrder() {
        var queue = VescRequestQueue()
        for _ in 0..<1000 {
            for request in [realtime, setup, statistics] { XCTAssertTrue(queue.enqueue(request)) }
            XCTAssertEqual(queue.count, 3)
        }
        for expected in [realtime, setup, statistics] {
            XCTAssertEqual(queue.takeNext(), expected)
            queue.complete()
        }
        XCTAssertEqual(queue.count, 0)
    }

    func testReplacingPendingMaskKeepsItsPosition() {
        var queue = VescRequestQueue()
        queue.enqueue(realtime)
        queue.enqueue(setup)
        queue.enqueue(statistics)
        let onlyBatteryLevel = Data([51, 0, 0, 1, 0])
        XCTAssertTrue(queue.enqueue(onlyBatteryLevel))
        XCTAssertEqual(queue.takeNext(), realtime)
        queue.complete()
        XCTAssertEqual(queue.takeNext(), onlyBatteryLevel)
        queue.complete()
        XCTAssertEqual(queue.takeNext(), statistics)
    }

    func testMalformedAndControlCommandsNeverEnterTheTransmitQueue() {
        var queue = VescRequestQueue()
        let invalidRequests = [Data(), Data([5, 0, 0, 0, 1]), // COMM_SET_DUTY is never permitted.
                               Data([50]), Data([50, 0, 0, 0, 0]), Data([50, 0, 0, 0, 4]),
                               Data([50, 0, 0, 9, 0x8b, 0]), Data([51, 0, 0, 0, 1]),
                               Data([128, 0, 0]), Data([128, 0xff, 0xff]), Data([128, 0, 0, 4, 0xfc])]
        for request in invalidRequests { XCTAssertFalse(queue.enqueue(request), "Rejected payload \(request)") }
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.takeNext())
        XCTAssertTrue(queue.enqueue(realtime), "Malformed requests must not poison subsequent valid queries")
    }

    func testFaultMaskIsReadOnlyAndUnknownSelectiveFieldsAreRejected() {
        var queue = VescRequestQueue()
        XCTAssertTrue(queue.enqueue(Data([50, 0, 0, 0x80, 0]))) // One fault byte requested.
        XCTAssertTrue(queue.enqueue(realtime)) // Pending primary replaces smaller query.
        XCTAssertEqual(queue.takeNext(), realtime)
        queue.complete()
        XCTAssertFalse(queue.enqueue(Data([50, 0, 1, 0, 0]))) // Unsupported PID position bit16.
        XCTAssertEqual(queue.count, 0)
    }
    func testDisconnectResetDropsPendingAndInFlightQueries() {
        var queue = VescRequestQueue()
        queue.enqueue(realtime)
        queue.enqueue(setup)
        queue.enqueue(statistics)
        XCTAssertEqual(queue.takeNext(), realtime)
        queue.reset()
        XCTAssertNil(queue.inFlight)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.takeNext())
        XCTAssertTrue(queue.enqueue(setup))
        XCTAssertEqual(queue.takeNext(), setup, "New connection must start without an old in-flight blockage")
    }
}
