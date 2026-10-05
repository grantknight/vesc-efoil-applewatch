import Foundation
import XCTest
@testable import VESCCore

/// Deterministic SplitMix64 stream. TEST_SEED (101/202/303 in CI) changes every case, so each
/// clean CI job battle-tests different inputs while any failure stays reproducible.
struct StressRandom: RandomNumberGenerator {
    private var state: UInt64
    init(salt: UInt64) {
        let seed = UInt64(ProcessInfo.processInfo.environment["TEST_SEED"] ?? "101") ?? 101
        state = (seed &* 0x9E37_79B9_7F4A_7C15) ^ (salt &* 0xD1B5_4A32_D192_ED03)
    }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func bytes(_ count: Int) -> Data { Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &self) }) }
    mutating func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &self) < probability }
}

/// Randomised stress tests. Each asserts a property that must hold for every input, rather than
/// one expected output, so they find inputs nobody thought to write down.
final class StressTests: XCTestCase {
    private let realtimeWidths: [Int: Int] = [0: 2, 1: 2, 3: 4, 7: 4, 8: 2, 11: 4, 15: 1]
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: VESC replies

    func testRandomRepliesAreEitherRejectedOrEntirelyInRange() {
        var rng = StressRandom(salt: 1)
        let widths: [UInt8: [Int: Int]] = [50: realtimeWidths, 51: [6: 4, 8: 2],
                                           128: [2: 4, 3: 4, 4: 4, 5: 4, 6: 4, 7: 4, 10: 4]]
        for _ in 0..<30_000 {
            let command: UInt8 = [50, 51, 128, UInt8.random(in: 0...255, using: &rng)].randomElement(using: &rng)!
            var mask = UInt32.random(in: 0...UInt32.max, using: &rng)
            if let fields = widths[command], rng.chance(0.7) {
                mask = fields.keys.sorted().filter { _ in rng.chance(0.5) }.reduce(UInt32(0)) { $0 | (UInt32(1) << $1) }
            }
            let expected = widths[command].map { fields in
                fields.reduce(0) { $0 + ((mask & (UInt32(1) << $1.key)) != 0 ? $1.value : 0) }
            } ?? 0
            let length = rng.chance(0.25) ? Int.random(in: 0...40, using: &rng) : expected
            var bytes = VByteArray()
            bytes.vbAppendUInt8(command)
            bytes.vbAppendUInt32(mask)
            bytes.data.append(rng.bytes(length))
            guard let update = VescTelemetryDecoder.decode(bytes.data) else { continue }
            XCTAssertNotEqual(mask, 0)
            XCTAssertEqual(length, expected, "Accepted a reply whose length does not match its mask")
            func inRange(_ value: Double?, _ range: ClosedRange<Double>) -> Bool { value.map { $0.isFinite && range.contains($0) } ?? true }
            switch update {
            case .realtime(let rt):
                XCTAssertEqual(command, 50)
                XCTAssertTrue(inRange(rt.controllerTemperature, -100...250) && inRange(rt.motorTemperature, -100...250))
                XCTAssertTrue(inRange(rt.inputCurrent, -2000...2000) && inRange(rt.rpm, -1_000_000...1_000_000))
                XCTAssertTrue(inRange(rt.voltage, 0.1...200) && inRange(rt.wattHours, -1_000_000...1_000_000))
                XCTAssertEqual(rt.faultCode != nil, (mask & (1 << 15)) != 0)
                XCTAssertEqual(rt.isComplete, mask & 0x8989 == 0x8989)
            case .setup(let setup):
                XCTAssertEqual(command, 51)
                XCTAssertTrue(inRange(setup.speedMs, -200...200) && inRange(setup.batteryLevel, 0...1))
            case .statistics(let stats):
                XCTAssertEqual(command, 128)
                for value in [stats.avgPower, stats.maxPower, stats.avgCurrent, stats.maxCurrent,
                              stats.avgControllerTemperature, stats.maxControllerTemperature, stats.runTime] {
                    XCTAssertTrue(inRange(value, -1_000_000...100_000_000))
                }
            }
        }
    }

    func testEncodedRealtimeValuesRoundTripExactlyOrAreRejected() {
        var rng = StressRandom(salt: 2)
        var accepted = 0
        for _ in 0..<20_000 {
            let bits = realtimeWidths.keys.sorted().filter { _ in rng.chance(0.6) }
            guard !bits.isEmpty else { continue }
            var bytes = VByteArray()
            bytes.vbAppendUInt8(50)
            bytes.vbAppendUInt32(bits.reduce(UInt32(0)) { $0 | (UInt32(1) << $1) })
            var expected = RealtimeTelemetry()
            var allValid = true
            for bit in bits {
                let outOfRange = rng.chance(0.08)
                switch bit {
                case 0, 1:
                    let raw = outOfRange ? Int16.random(in: 2501...Int16.max, using: &rng) : Int16.random(in: -1000...2500, using: &rng)
                    bytes.vbAppendInt16(raw)
                    if bit == 0 { expected.controllerTemperature = Double(raw) / 10 } else { expected.motorTemperature = Double(raw) / 10 }
                case 3:
                    let raw = outOfRange ? Int32.random(in: 200_001...Int32.max, using: &rng) : Int32.random(in: -200_000...200_000, using: &rng)
                    bytes.vbAppendInt32(raw); expected.inputCurrent = Double(raw) / 100
                case 7:
                    let raw = outOfRange ? Int32.random(in: 1_000_001...Int32.max, using: &rng) : Int32.random(in: -1_000_000...1_000_000, using: &rng)
                    bytes.vbAppendInt32(raw); expected.rpm = Double(raw)
                case 8:
                    let raw = outOfRange ? Int16.random(in: Int16.min...0, using: &rng) : Int16.random(in: 1...2000, using: &rng)
                    bytes.vbAppendInt16(raw); expected.voltage = Double(raw) / 10
                case 11:
                    let raw = Int32.random(in: -2_000_000_000...2_000_000_000, using: &rng)
                    bytes.vbAppendInt32(raw); expected.wattHours = Double(raw) / 10000
                default:
                    let raw = UInt8.random(in: 0...255, using: &rng)
                    bytes.vbAppendUInt8(raw); expected.faultCode = raw
                }
                if outOfRange && bit != 11 && bit != 15 { allValid = false }
            }
            let decoded = VescTelemetryDecoder.decode(bytes.data)
            guard allValid else { XCTAssertNil(decoded, "Out-of-range value accepted"); continue }
            guard case .realtime(let rt) = decoded else { return XCTFail("Valid realtime reply rejected: \(bits)") }
            accepted += 1
            XCTAssertEqual(rt.controllerTemperature, expected.controllerTemperature)
            XCTAssertEqual(rt.motorTemperature, expected.motorTemperature)
            XCTAssertEqual(rt.inputCurrent, expected.inputCurrent)
            XCTAssertEqual(rt.rpm, expected.rpm)
            XCTAssertEqual(rt.voltage, expected.voltage)
            XCTAssertEqual(rt.wattHours, expected.wattHours)
            XCTAssertEqual(rt.faultCode, expected.faultCode)
        }
        XCTAssertGreaterThan(accepted, 5_000)
    }

    // MARK: Packet framing

    func testCorruptFramesAreDroppedWithoutLosingNeighbouringFrames() {
        var rng = StressRandom(salt: 3)
        for scenario in 0..<40 {
            let parser = Packet()
            var received: [Data] = []
            parser.packetReceived = { received.append($0) }
            var stream = Data()
            var intact: [Data] = []
            for _ in 0..<250 {
                let payload = rng.bytes(rng.chance(0.2) ? Int.random(in: 256...700, using: &rng) : Int.random(in: 1...120, using: &rng))
                var frame = parser.preparePacket(data: payload)
                let header = payload.count <= 255 ? 2 : 3
                if rng.chance(0.1) {
                    // Any error after the length bytes (payload, CRC or terminator) is detected.
                    let index = Int.random(in: header..<frame.count, using: &rng)
                    frame[index] ^= UInt8.random(in: 1...255, using: &rng)
                } else {
                    intact.append(payload)
                }
                stream.append(frame)
            }
            var offset = 0
            while offset < stream.count {
                let end = min(stream.count, offset + Int.random(in: 1...64, using: &rng))
                parser.processData(data: stream.subdata(in: offset..<end), at: 10)
                offset = end
            }
            XCTAssertEqual(received, intact, "Scenario \(scenario)")
        }
    }

    func testLinkRecoversAfterRandomNoiseOnceItGoesQuiet() {
        var rng = StressRandom(salt: 4)
        for scenario in 0..<1500 {
            let parser = Packet(fragmentTimeout: 1)
            var received: [Data] = []
            parser.packetReceived = { received.append($0) }
            // Noise is biased toward start bytes so false headers and long false lengths are common.
            let noise = Data((0..<Int.random(in: 0...400, using: &rng)).map { _ in
                rng.chance(0.2) ? UInt8.random(in: 2...4, using: &rng) : UInt8.random(in: 0...255, using: &rng)
            })
            var time = 10.0
            var offset = 0
            while offset < noise.count {
                let end = min(noise.count, offset + Int.random(in: 1...40, using: &rng))
                parser.processData(data: noise.subdata(in: offset..<end), at: time)
                time += 0.01
                offset = end
            }
            let payload = rng.bytes(Int.random(in: 1...300, using: &rng))
            let frame = parser.preparePacket(data: payload)
            time += 1.5
            offset = 0
            while offset < frame.count {
                let end = min(frame.count, offset + Int.random(in: 1...20, using: &rng))
                parser.processData(data: frame.subdata(in: offset..<end), at: time)
                time += 0.005
                offset = end
            }
            XCTAssertEqual(received.last, payload, "Scenario \(scenario)")
        }
    }

    func testMegabyteOfNoiseIsAbsorbedAndTheNextFrameStillArrives() {
        var rng = StressRandom(salt: 5)
        let parser = Packet(fragmentTimeout: 1)
        var received: [Data] = []
        parser.packetReceived = { received.append($0) }
        for chunk in 0..<4_300 { parser.processData(data: rng.bytes(244), at: 10 + Double(chunk) * 0.001) }
        let payload = Data([50, 0, 0, 0, 1, 1, 0])
        parser.processData(data: parser.preparePacket(data: payload), at: 20)
        XCTAssertEqual(received.last, payload)
    }

    // MARK: End-to-end telemetry under BLE loss

    /// One hour of the app's real polling cycle (realtime + setup replies every 2 s, as in
    /// BluetoothManager.vescLoop) packed into 20-byte BLE notifications, 1% of them lost.
    /// Every value that reaches the ride must be exactly what the controller sent, a lost
    /// notification may cost only the poll cycle it was in, and recorded energy stays close to truth.
    func testLossyBluetoothStreamNeverCorruptsValuesOrSpillsIntoTheNextPoll() throws {
        var rng = StressRandom(salt: 6)
        let parser = Packet()
        var decoded: [RealtimeTelemetry] = []
        parser.packetReceived = { payload in
            if case .realtime(let rt) = VescTelemetryDecoder.decode(payload) { decoded.append(rt) }
        }
        struct Sent { var temp: Int16; var current: Int32; var rpm: Int32; var voltage: Int16 }
        var sent: [Sent] = []
        var cleanCycles: Set<Int> = []
        let cycles = 1_800
        let pollInterval = 2.0
        for index in 0..<cycles {
            let progress = Double(index) / Double(cycles)
            let value = Sent(temp: Int16(300 + Int(progress * 250) + Int.random(in: -5...5, using: &rng)),
                             current: Int32.random(in: 0...6_000, using: &rng),
                             rpm: Int32.random(in: 0...6_000, using: &rng),
                             voltage: Int16(504 - Int(progress * 60)))
            sent.append(value)
            var realtime = VByteArray()
            realtime.vbAppendUInt8(50)
            realtime.vbAppendUInt32(0x8989)
            realtime.vbAppendInt16(value.temp)
            realtime.vbAppendInt32(value.current)
            realtime.vbAppendInt32(value.rpm)
            realtime.vbAppendInt16(value.voltage)
            realtime.vbAppendInt32(Int32(index)) // Wh carries the cycle index so every value can be traced.
            realtime.vbAppendUInt8(0)
            var setup = VByteArray()
            setup.vbAppendUInt8(51)
            setup.vbAppendUInt32((1 << 6) | (1 << 8))
            setup.vbAppendInt32(Int32.random(in: 0...12_000, using: &rng))
            setup.vbAppendInt16(Int16(900 - Int(progress * 700)))
            let burst = parser.preparePacket(data: realtime.data) + parser.preparePacket(data: setup.data)
            var clean = true
            var offset = 0
            var time = Double(index) * pollInterval
            while offset < burst.count {
                let end = min(burst.count, offset + 20)
                if rng.chance(0.01) { clean = false }
                else { parser.processData(data: burst.subdata(in: offset..<end), at: time) }
                time += 0.01
                offset = end
            }
            if clean { cleanCycles.insert(index) }
        }
        var indices: [Int] = []
        for rt in decoded {
            let index = Int((rt.wattHours! * 10000).rounded())
            guard sent.indices.contains(index) else { return XCTFail("Decoded a frame that was never sent") }
            let truth = sent[index]
            XCTAssertEqual(rt.controllerTemperature, Double(truth.temp) / 10)
            XCTAssertEqual(rt.inputCurrent, Double(truth.current) / 100)
            XCTAssertEqual(rt.rpm, Double(truth.rpm))
            XCTAssertEqual(rt.voltage, Double(truth.voltage) / 10)
            XCTAssertEqual(rt.faultCode, 0)
            if let previous = indices.last { XCTAssertGreaterThan(index, previous, "Frames must arrive once, in order") }
            indices.append(index)
        }
        let lossyCycles = cycles - cleanCycles.count
        print("Lossy BLE stream: \(lossyCycles) poll cycles lost a notification, \(indices.count)/\(cycles) realtime replies decoded")
        XCTAssertGreaterThan(lossyCycles, 0)
        XCTAssertTrue(cleanCycles.isSubset(of: Set(indices)), "A lost notification spilled into a later poll cycle")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try RideStore(directory: directory, writeData: { _, _ in }) // Integration only; persistence is tested below.
        try store.startRide(at: start)
        for index in indices {
            let truth = sent[index]
            try store.record(RideSample(timestamp: start.addingTimeInterval(Double(index) * pollInterval),
                                        batteryVoltage: Double(truth.voltage) / 10, inputCurrent: Double(truth.current) / 100,
                                        controllerTemperatureC: Double(truth.temp) / 10, motorTemperatureC: 0,
                                        batteryPercent: nil, speedMs: 6))
        }
        let ride = try XCTUnwrap(store.activeRide)
        let power = { (value: Sent) in Double(value.voltage) / 10 * Double(value.current) / 100 }
        var trueWattSeconds = 0.0
        for index in 1..<cycles { trueWattSeconds += (power(sent[index - 1]) + power(sent[index])) * pollInterval / 2 }
        let firstTime = Double(indices.first!) * pollInterval, lastTime = Double(indices.last!) * pollInterval
        let longestGap = zip(indices, indices.dropFirst()).map { Double($1 - $0) * pollInterval }.max() ?? 0
        if longestGap <= 10 {
            XCTAssertEqual(ride.observedSeconds, lastTime - firstTime, accuracy: 1e-6, "Gaps up to 10 s are bridged, not dropped")
            XCTAssertEqual(ride.distanceMeters, 6 * (lastTime - firstTime), accuracy: 1e-6)
        }
        XCTAssertEqual(ride.wattSeconds / trueWattSeconds, 1, accuracy: 0.05)
    }

    // MARK: Ride storage

    func testRideStoreSurvivesRandomOperationsWriteFailuresAndRestarts() throws {
        var rng = StressRandom(salt: 7)
        for scenario in 0..<60 {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            var failWrites = false
            let writer: (Data, URL) throws -> Void = { data, url in
                if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
                try data.write(to: url, options: .atomic)
            }
            var store = try RideStore(directory: directory, maxRetainedSamples: 25, writeData: writer)
            var clock = start
            for step in 0..<150 {
                failWrites = rng.chance(0.1)
                // Eighths of a second are exact in binary, so archive round trips compare exactly.
                clock += Double(Int.random(in: -8...40, using: &rng)) / 8
                let before = (store.activeRide, store.rides)
                let operation = Int.random(in: 0..<100, using: &rng)
                do {
                    switch operation {
                    case 0..<8: try store.startRide(at: clock)
                    case 8..<13: try store.endRide(at: clock)
                    case 13..<20: try store.connectionChanged(isConnected: rng.chance(0.5), at: clock)
                    case 20..<23:
                        let wasRecording = store.activeRide != nil
                        try store.record(RideSample(timestamp: clock, batteryVoltage: .nan, inputCurrent: 1,
                                                    controllerTemperatureC: 30, motorTemperatureC: 0, batteryPercent: nil, speedMs: nil))
                        XCTAssertFalse(wasRecording, "An invalid sample was accepted")
                    case 23..<25:
                        if let ride = store.rides.randomElement(using: &rng) { try store.deleteRide(id: ride.id) }
                    case 25..<28:
                        failWrites = false
                        let active = store.activeRide
                        store = try RideStore(directory: directory, maxRetainedSamples: 25, writeData: writer)
                        XCTAssertNil(store.activeRide)
                        if let active {
                            let recovered = store.rides.first { $0.id == active.id }
                            XCTAssertEqual(recovered?.interrupted, true)
                            XCTAssertEqual(recovered?.totalSampleCount, active.totalSampleCount)
                            XCTAssertEqual(recovered?.energyWh, active.energyWh)
                            XCTAssertEqual(recovered?.endedAt, active.updatedAt)
                        }
                    default:
                        try store.record(RideSample(timestamp: clock, batteryVoltage: Double.random(in: 40...51, using: &rng),
                                                    inputCurrent: Double.random(in: -5...80, using: &rng),
                                                    controllerTemperatureC: Double.random(in: 20...90, using: &rng), motorTemperatureC: 0,
                                                    batteryPercent: rng.chance(0.8) ? Double.random(in: 0...100, using: &rng) : nil,
                                                    speedMs: rng.chance(0.8) ? Double.random(in: 0...12, using: &rng) : nil))
                    }
                } catch {
                    XCTAssertTrue(error is RideStoreError || failWrites, "Scenario \(scenario) step \(step): unexpected \(error)")
                    XCTAssertEqual(store.activeRide, before.0, "A failed operation changed the active ride")
                    XCTAssertEqual(store.rides, before.1, "A failed operation changed history")
                }
                for ride in store.rides + [store.activeRide].compactMap({ $0 }) { assertConsistent(ride, maxSamples: 25) }
                for ride in store.rides { XCTAssertEqual(ride.endedAt, ride.updatedAt) }
            }
            failWrites = false
            let active = store.activeRide
            let reloaded = try RideStore(directory: directory, maxRetainedSamples: 25)
            XCTAssertEqual(Set(reloaded.rides.map(\.id)), Set(store.rides.map(\.id) + [active?.id].compactMap { $0 }))
            for ride in store.rides { XCTAssertEqual(reloaded.rides.first { $0.id == ride.id }, ride, "Scenario \(scenario)") }
        }
    }

    private func assertConsistent(_ ride: RideSession, maxSamples: Int) {
        XCTAssertLessThanOrEqual(ride.samples.count, maxSamples)
        XCTAssertGreaterThanOrEqual(ride.totalSampleCount, ride.samples.count)
        XCTAssertTrue(zip(ride.samples, ride.samples.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
        XCTAssertTrue(ride.samples.allSatisfy { $0.timestamp >= ride.startedAt && $0.timestamp <= ride.updatedAt })
        XCTAssertGreaterThanOrEqual(ride.energyWh, 0)
        XCTAssertGreaterThanOrEqual(ride.distanceMeters, 0)
        XCTAssertEqual(ride.energyWh * 3600, ride.wattSeconds, accuracy: 1e-6 * max(1, ride.wattSeconds))
        XCTAssertLessThanOrEqual(ride.observedSeconds, ride.updatedAt.timeIntervalSince(ride.startedAt) + 1e-9)
        // Physical bounds: averages over observed time cannot exceed the recorded peaks.
        XCTAssertLessThanOrEqual(ride.wattSeconds, ride.maxWatts * ride.observedSeconds + 1e-6)
        XCTAssertLessThanOrEqual(ride.distanceMeters, ride.maxSpeedMs * ride.observedSeconds + 1e-6)
    }

    // MARK: Arrival battery

    func testArrivalEstimateNeverReassuresWithoutAMeasuredDecline() {
        var rng = StressRandom(salt: 8)
        for _ in 0..<400 {
            var estimator = ArrivalBatteryEstimator()
            let kind = Int.random(in: 0..<4, using: &rng) // decline, flat, rising, noisy decline
            let rate = Double.random(in: 0.002...0.05, using: &rng)
            let speed = Double.random(in: 2...9, using: &rng)
            var percent = Double.random(in: 10...100, using: &rng)
            var distance = Double.random(in: 300...8000, using: &rng)
            var time = 0.0
            for _ in 0..<Int.random(in: 20...200, using: &rng) {
                let dt = Double.random(in: 0.5...2, using: &rng)
                time += dt
                switch kind {
                case 0: percent -= rate * dt
                case 1: break
                case 2: percent += rate * dt
                default: percent -= rate * dt + Double.random(in: -0.3...0.3, using: &rng)
                }
                percent = min(100, max(0, percent))
                distance = max(0, distance - speed * dt)
                estimator.observe(percent: percent, source: "VESC", at: start.addingTimeInterval(time),
                                  distanceMeters: distance, isTelemetryFresh: true)
                let reserve = Double.random(in: 0...50, using: &rng)
                guard let prediction = estimator.prediction(etaSeconds: distance / speed, reservePercent: reserve,
                                                            now: start.addingTimeInterval(time + Double.random(in: 0...3, using: &rng))) else { continue }
                XCTAssertTrue(kind == 0 || kind == 3, "Flat or rising battery produced a prediction")
                XCTAssertTrue(prediction.arrivalPercent.isFinite && prediction.secondsUntilEmpty.isFinite)
                XCTAssertLessThanOrEqual(prediction.arrivalPercent, percent + 1e-9, "Arrival cannot exceed the current battery")
                XCTAssertGreaterThan(prediction.depletionPercentPerSecond, 0)
                XCTAssertGreaterThanOrEqual(prediction.secondsUntilEmpty, 0)
                XCTAssertEqual(prediction.willExhaustBeforeArrival, prediction.arrivalPercent < 0)
                XCTAssertEqual(prediction.reserveShortfallPercent, max(0, reserve - prediction.arrivalPercent), accuracy: 1e-9)
                let summary = ArrivalBatterySummary(prediction: prediction, reservePercent: reserve)
                if prediction.arrivalPercent < 0 {
                    XCTAssertEqual(summary.level, .exhaustedBeforeArrival)
                    XCTAssertEqual(summary.glance, "Empty")
                } else {
                    XCTAssertEqual(summary.glance, "~\(Int(floor(min(100, prediction.arrivalPercent))))%")
                    XCTAssertEqual(summary.level, prediction.reserveShortfallPercent > 0 ? .belowReserve : .aboveReserve)
                }
            }
        }
    }

    func testSteadyDeclinePredictsTheExactLinearArrival() {
        var rng = StressRandom(salt: 9)
        for _ in 0..<300 {
            var estimator = ArrivalBatteryEstimator()
            let rate = Double.random(in: 0.01...0.05, using: &rng)
            let speed = Double.random(in: 3...9, using: &rng)
            let initial = Double.random(in: 60...100, using: &rng)
            let distance0 = Double.random(in: 2000...9000, using: &rng)
            for second in 0...90 {
                let percent = initial - rate * Double(second)
                let distance = distance0 - speed * Double(second)
                estimator.observe(percent: percent, source: "VESC", at: start.addingTimeInterval(Double(second)),
                                  distanceMeters: distance, isTelemetryFresh: true)
                let age = Double.random(in: 0...5, using: &rng)
                let eta = distance / speed
                let prediction = estimator.prediction(etaSeconds: eta, reservePercent: 20,
                                                      now: start.addingTimeInterval(Double(second) + age))
                if second < 60 { XCTAssertNil(prediction, "Needs 60 s of observations"); continue }
                guard let prediction else { return XCTFail("Clean linear decline produced no prediction at \(second) s") }
                XCTAssertEqual(prediction.depletionPercentPerSecond, rate, accuracy: 1e-9)
                XCTAssertEqual(prediction.arrivalPercent, percent - rate * (eta + age), accuracy: 1e-6)
            }
        }
    }

    // MARK: Display text

    func testDistanceAndDurationTextIsAlwaysConsistent() {
        var rng = StressRandom(salt: 10)
        for _ in 0..<30_000 {
            let meters: Double = [Double.random(in: 0...20_000, using: &rng), Double.random(in: 999...1001, using: &rng),
                                  Double.random(in: 9_990...10_010, using: &rng), -1, .nan, .infinity].randomElement(using: &rng)!
            let text = NavigationFormat.distance(meters)
            guard meters.isFinite, meters >= 0 else { XCTAssertEqual(text, "—"); continue }
            if text.hasSuffix(" km") {
                let value = Double(text.dropLast(3))!
                XCTAssertGreaterThanOrEqual(value, 1, text)
                XCTAssertEqual(value * 1000, meters, accuracy: value >= 10 ? 50 : 5, text)
                XCTAssertEqual(text.split(separator: ".").last!.count - 3, value >= 10 ? 1 : 2, "\(text) uses the wrong precision")
            } else {
                let value = Double(text.dropLast(2))!
                XCTAssertLessThan(value, 1000, "\(text) should be shown in km")
                XCTAssertEqual(value, meters, accuracy: 0.5)
            }

            let seconds: Double = [Double.random(in: 0...400_000, using: &rng), Double.random(in: 59...61, using: &rng),
                                   Double.random(in: 3_599...3_601, using: &rng), -1, .nan].randomElement(using: &rng)!
            let duration = NavigationFormat.duration(seconds)
            guard seconds.isFinite, seconds >= 0, seconds.rounded() < 360_000 else { XCTAssertEqual(duration, "—"); continue }
            if duration.contains("h") {
                let parts = duration.dropLast().split(separator: "h ")
                let hours = Int(parts[0])!, minutes = Int(parts[1])!
                XCTAssertLessThan(minutes, 60)
                XCTAssertEqual(Double(hours * 3600 + minutes * 60), seconds, accuracy: 60)
            } else {
                let parts = duration.split(separator: ":")
                let minutes = Int(parts[0])!, secs = Int(parts[1])!
                XCTAssertLessThan(secs, 60)
                XCTAssertLessThan(minutes, 60)
                XCTAssertEqual(Double(minutes * 60 + secs), seconds, accuracy: 0.5)
            }
        }
    }

    // MARK: BMS and complication

    func testCellSnapshotsAcceptOnlyCompleteMeasuredSets() {
        var rng = StressRandom(salt: 11)
        for _ in 0..<10_000 {
            let count = rng.chance(0.6) ? 12 : Int.random(in: 0...16, using: &rng)
            let cells: [Double] = (0..<count).map { _ in
                rng.chance(0.03) ? [Double.nan, .infinity, -0.01, 6.01].randomElement(using: &rng)! : Double.random(in: 0...6, using: &rng)
            }
            let measuredAt = rng.chance(0.02) ? Date(timeIntervalSince1970: .nan) : start
            let snapshot = BMSCellSnapshot(deviceID: UUID(), cellVoltages: cells, measuredAt: measuredAt)
            let valid = count == 12 && cells.allSatisfy { $0.isFinite && (0...6).contains($0) } && measuredAt.timeIntervalSince1970.isFinite
            XCTAssertEqual(snapshot != nil, valid)
            guard let snapshot else { continue }
            XCTAssertEqual(snapshot.minVoltage, cells.min())
            XCTAssertEqual(snapshot.maxVoltage, cells.max())
            XCTAssertEqual(snapshot.deltaMillivolts, (cells.max()! - cells.min()!) * 1000, accuracy: 1e-9)
            let age = Double.random(in: -20...30, using: &rng)
            XCTAssertEqual(snapshot.isFresh(at: start.addingTimeInterval(age)), age >= 0 && age < 10)
        }
        for _ in 0..<2_000 {
            let data = rng.bytes(Int.random(in: 0...3, using: &rng))
            let percent = BMSStandardValue.batteryPercent(data)
            XCTAssertEqual(percent != nil, data.count == 1 && data[data.startIndex] <= 100)
        }
    }

    func testComplicationNeverShowsStaleOrInvalidReadingsAsCurrent() throws {
        var rng = StressRandom(salt: 12)
        for _ in 0..<10_000 {
            var snapshot = TelemetrySnapshot()
            snapshot.speed = rng.chance(0.2) ? nil : Double.random(in: -10...1100, using: &rng)
            snapshot.speedUnit = ["mph", "kph", "ms", "knots", "furlongs"].randomElement(using: &rng)!
            snapshot.watts = rng.chance(0.02) ? .nan : Double.random(in: -100...500_000, using: &rng)
            snapshot.batteryPercent = rng.chance(0.2) ? nil : Double.random(in: -5...105, using: &rng)
            snapshot.batteryVoltage = Double.random(in: -1...210, using: &rng)
            snapshot.mosTempC = Double.random(in: -120...320, using: &rng)
            snapshot.faultCode = rng.chance(0.3) ? nil : UInt8.random(in: 0...40, using: &rng)
            snapshot.isConnected = rng.chance(0.8)
            snapshot.updatedAt = start
            let age = Double.random(in: -30...120, using: &rng)
            let now = start.addingTimeInterval(age)
            let fresh = snapshot.isFresh(at: now)
            XCTAssertEqual(fresh, snapshot.isValid && snapshot.isConnected && age >= 0 && age < 60)
            if !fresh { XCTAssertNil(snapshot.faultLabel(at: now), "A stale snapshot must not report fault status") }
            if snapshot.isValid {
                let decoded = try JSONDecoder().decode(TelemetrySnapshot.self, from: JSONEncoder().encode(snapshot))
                XCTAssertEqual(decoded.isFresh(at: now), fresh)
                XCTAssertEqual(decoded.faultLabel(at: now), snapshot.faultLabel(at: now))
            }
        }
    }

    // MARK: Request scheduling

    func testRequestQueueStaysBoundedUnderRandomTraffic() {
        var rng = StressRandom(salt: 13)
        let valid = [Data([50, 0, 0, 0x89, 0x89]), Data([50, 0, 0, 0x80, 0]), Data([51, 0, 0, 1, 0x40]), Data([128, 0x04, 0xFC])]
        var queue = VescRequestQueue()
        var latest: [UInt8: Data] = [:]
        for _ in 0..<50_000 {
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<4:
                let request = valid.randomElement(using: &rng)!
                let before = queue.count
                let inFlightSameCommand = queue.inFlight?.first == request.first
                if queue.enqueue(request) {
                    if !inFlightSameCommand { latest[request.first!] = request }
                } else {
                    XCTAssertEqual(before, 3, "A valid request was refused while there was room")
                }
            case 4:
                let request = rng.bytes(Int.random(in: 0...6, using: &rng))
                // Random bytes that happen to form a well-formed request are skipped, not queued.
                if !Self.isAllowed(request) {
                    let before = queue.count
                    XCTAssertFalse(queue.enqueue(request), "Malformed request queued")
                    XCTAssertEqual(queue.count, before)
                }
            case 5..<8:
                if let taken = queue.takeNext() {
                    XCTAssertEqual(taken, latest[taken.first!], "Queue must send the newest request for a command")
                }
            case 8: queue.complete()
            default: if rng.chance(0.05) { queue.reset() }
            }
            XCTAssertLessThanOrEqual(queue.count, 3)
            XCTAssertLessThanOrEqual(queue.pendingCount, queue.inFlight == nil ? 3 : 2)
        }
    }

    private static func isAllowed(_ request: Data) -> Bool {
        var probe = VescRequestQueue()
        return probe.enqueue(request)
    }
}
