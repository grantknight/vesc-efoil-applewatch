import Foundation
import XCTest
@testable import VESCCore

final class ProtocolTests: XCTestCase {
    // CRC-CCITT XMODEM reference implementation, independent of Packet's table.
    private func crc(_ data: Data) -> UInt16 {
        var value: UInt16 = 0
        for byte in data {
            value ^= UInt16(byte) << 8
            for _ in 0..<8 { value = value & 0x8000 != 0 ? (value << 1) ^ 0x1021 : value << 1 }
        }
        return value
    }
    func testGoldenXmodemCRC() {
        let payload = Data("123456789".utf8)
        XCTAssertEqual(crc(payload), 0x31c3)
        XCTAssertEqual(Packet().preparePacket(data: payload), Data([2, 9] + Array(payload) + [0x31, 0xc3, 3]))
    }
    func testFramingBoundariesAndEmpty() {
        for length in [1, 254, 255, 256, 1024, 10_000] {
            let payload = Data(repeating: 0x55, count: length)
            let frame = Packet().preparePacket(data: payload)
            XCTAssertEqual(frame.first, length <= 255 ? 2 : 3)
            let parser = Packet()
            var received: [Data] = []
            parser.packetReceived = { received.append($0) }
            parser.processData(data: frame)
            XCTAssertEqual(received, [payload])
        }
        XCTAssertTrue(Packet().preparePacket(data: Data()).isEmpty)
        XCTAssertTrue(Packet().preparePacket(data: Data(count: 10_001)).isEmpty)
    }
    func testBadCRCAndStopRejectedAndNextFrameRecovered() {
        let payload = Data([50, 0, 0, 0, 1, 1, 0])
        let valid = Packet().preparePacket(data: payload)
        for index in [valid.count - 2, valid.count - 1] {
            var invalid = valid
            invalid[index] ^= 0xff
            let parser = Packet()
            var received: [Data] = []
            parser.packetReceived = { received.append($0) }
            parser.processData(data: invalid + valid)
            XCTAssertEqual(received, [payload])
        }
    }
    func testResetDropsPartialFrame() {
        let parser = Packet()
        let valid = parser.preparePacket(data: Data([50, 0, 0, 0, 1, 1, 0]))
        var received: [Data] = []
        parser.packetReceived = { received.append($0) }
        parser.processData(data: valid.prefix(4))
        parser.resetState()
        parser.processData(data: valid)
        XCTAssertEqual(received.count, 1)
    }
    func testSignedIntegersAndConsumedString() {
        var bytes = VByteArray()
        bytes.vbAppendInt64(Int64.min)
        bytes.vbAppendInt32(-1234567)
        bytes.vbAppendInt16(-3210)
        bytes.vbAppendString("foil ✓")
        bytes.vbAppendUInt8(42)
        XCTAssertEqual(bytes.vbPopFrontInt64(), Int64.min)
        XCTAssertEqual(bytes.vbPopFrontInt32(), -1234567)
        XCTAssertEqual(bytes.vbPopFrontInt16(), -3210)
        XCTAssertEqual(bytes.vbPopFrontString(), "foil ✓")
        XCTAssertEqual(bytes.vbPopFrontUInt8(), 42)
        XCTAssertTrue(bytes.data.isEmpty)
    }
    func testAutoFloatGoldenBytesAndFiniteValidation() {
        for (value, bits) in [(1.0, UInt32(0x3f800000)), (-0.25, UInt32(0xbe800000)), (1024.0, UInt32(0x44800000))] {
            var bytes = VByteArray()
            bytes.vbAppendDouble32Auto(value)
            XCTAssertEqual(bytes.vbPopFrontUInt32(), bits)
            bytes.vbAppendUInt32(bits)
            XCTAssertEqual(bytes.vbPopFrontDouble32Auto(), value)
        }
        let nanStats = Data([128, 0, 0, 0, 4, 0x7f, 0xc0, 0, 0])
        XCTAssertNil(VescTelemetryDecoder.decode(nanStats))
    }
    func testFirmwareAutoFloatSpecialExponentAndFlushRules() {
        // Golden wire expectations derive from upstream buffer_get_float32_auto:
        // exponent zero + nonzero mantissa is normalized with exponent -126.
        var bytes = VByteArray(data: Data([0, 0, 0, 1]))
        XCTAssertEqual(bytes.vbPopFrontDouble32Auto(), Double(Float(0.5 + 1.0 / 16_777_216) * pow(Float(2), -126)))
        bytes = VByteArray(data: Data([0x80, 0, 0, 1]))
        XCTAssertLessThan(bytes.vbPopFrontDouble32Auto(), -5e-39)
        bytes = VByteArray(data: Data([0x7f, 0xff, 0xff, 0xff]))
        XCTAssertFalse(bytes.vbPopFrontDouble32Auto().isFinite)
        bytes = VByteArray()
        bytes.vbAppendDouble32Auto(1e-39)
        bytes.vbAppendDouble32Auto(-1e-39)
        XCTAssertEqual(bytes.data, Data(repeating: 0, count: 8))
        bytes.vbAppendDouble32Auto(0)
        XCTAssertEqual(bytes.vbPopFrontDouble32Auto(), 0)
    }
    func testStaleBogusLengthHeaderCannotWedgeNextTelemetryPacket() {
        let parser = Packet(fragmentTimeout: 1)
        let payload = Data([50, 0, 0, 0, 1, 1, 0])
        var received: [Data] = []
        parser.packetReceived = { received.append($0) }
        parser.processData(data: Data([3, 0x27, 0x10]), at: 10)
        parser.processData(data: parser.preparePacket(data: payload), at: 12)
        XCTAssertEqual(received, [payload])
    }
    func testFragmentsWithinTimeoutSurviveButStaleFragmentsAreDiscarded() {
        let parser = Packet(fragmentTimeout: 1)
        let payload = Data([50, 0, 0, 0, 1, 1, 0])
        let frame = parser.preparePacket(data: payload)
        var received: [Data] = []
        parser.packetReceived = { received.append($0) }
        parser.processData(data: frame.prefix(4), at: 10)
        parser.processData(data: frame.dropFirst(4), at: 10.5)
        XCTAssertEqual(received, [payload])
        parser.processData(data: frame.prefix(4), at: 11)
        parser.processData(data: frame, at: 13)
        XCTAssertEqual(received, [payload, payload])
    }
    func testSelectiveGoldenRealtimeAndTruncation() {
        // Independent firmware vector: mask=0x8989, ESC35C, 12.34A,
        // 4500 RPM, 52.0V, 1.0Wh, no fault; no motor sensor or serializer.
        let payload = Data([50, 0, 0, 0x89, 0x89, 1, 0x5e,
                            0, 0, 4, 0xd2, 0, 0, 0x11, 0x94, 2, 8, 0, 0, 0x27, 0x10, 0])
        guard case .realtime(let rt) = VescTelemetryDecoder.decode(payload) else { return XCTFail("Valid live vector rejected") }
        XCTAssertTrue(rt.isComplete)
        XCTAssertEqual(rt.controllerTemperature, 35)
        XCTAssertNil(rt.motorTemperature)
        XCTAssertEqual(rt.faultCode, 0)
        XCTAssertEqual(rt.inputCurrent, 12.34)
        XCTAssertEqual(rt.rpm, 4500)
        XCTAssertEqual(rt.voltage, 52)
        XCTAssertEqual(rt.wattHours, 1)
        for length in 0..<payload.count { XCTAssertNil(VescTelemetryDecoder.decode(payload.prefix(length))) }
        XCTAssertNil(VescTelemetryDecoder.decode(payload + Data([0])))
        XCTAssertNil(VescTelemetryDecoder.decode(Data([50, 0, 0, 0, 4, 0, 0, 0, 0]))) // unrequested bit
    }
    func testFaultByteWidthAndUnknownCodesRemainDistinctFromNoFault() {
        for code in [UInt8(0), 5, 6, 33, 255] {
            let reply = Data([50, 0, 0, 0x80, 0, code]) // Bit15, exactly one byte.
            guard case .realtime(let rt) = VescTelemetryDecoder.decode(reply) else { return XCTFail("Fault reply") }
            XCTAssertEqual(rt.faultCode, code)
            XCTAssertFalse(rt.isComplete, "A fault-only response cannot make old power readings live")
            XCTAssertNil(VescTelemetryDecoder.decode(reply.dropLast()))
            XCTAssertNil(VescTelemetryDecoder.decode(reply + Data([0])))
            let primary = Data([50, 0, 0, 0x89, 0x89, 1, 0x5e,
                                0, 0, 4, 0xd2, 0, 0, 0x11, 0x94, 2, 8, 0, 0, 0x27, 0x10, code])
            guard case .realtime(let complete) = VescTelemetryDecoder.decode(primary) else { return XCTFail("Primary fault reply") }
            XCTAssertTrue(complete.isComplete, "Unknown fault codes must still surface in a validated live sample")
            XCTAssertEqual(complete.faultCode, code)
        }
    }
    func testLegacyPrimaryWithoutFaultIsNotACompleteCurrentSample() {
        let reply = Data([50, 0, 0, 9, 0x8b, 1, 0x5e, 1, 0x90,
                          0, 0, 4, 0xd2, 0, 0, 0x11, 0x94, 2, 8, 0, 0, 0x27, 0x10])
        guard case .realtime(let rt) = VescTelemetryDecoder.decode(reply) else { return XCTFail("Legacy vector") }
        XCTAssertEqual(rt.motorTemperature, 40, "Optional legacy decoding retained")
        XCTAssertNil(rt.faultCode)
        XCTAssertFalse(rt.isComplete, "Absent fault status must not become no fault")
    }
    func testSetupAndStatsGolden() {
        guard case .setup(let setup) = VescTelemetryDecoder.decode(Data([51, 0, 0, 1, 0x40, 0, 0, 0x13, 0x88, 3, 0x20])) else { return XCTFail("Setup vector") }
        XCTAssertEqual(setup.speedMs, 5)
        XCTAssertEqual(setup.batteryLevel, 0.8)
        XCTAssertNil(VescTelemetryDecoder.decode(Data([51, 0, 0, 1, 0, 0x7f, 0xff])))
        guard case .statistics(let stats) = VescTelemetryDecoder.decode(Data([128, 0, 0, 0, 4, 0x44, 0x80, 0, 0])) else { return XCTFail("Stats vector") }
        XCTAssertEqual(stats.avgPower, 1024)
    }
    func testInvalidVoltageIsRejectedBeforeItCanBecomeLiveTelemetry() {
        // Bit 8 only: supplied zero/negative battery voltage is not valid live data.
        XCTAssertNil(VescTelemetryDecoder.decode(Data([50, 0, 0, 1, 0, 0, 0])))
        XCTAssertNil(VescTelemetryDecoder.decode(Data([50, 0, 0, 1, 0, 0xff, 0xff])))
        guard case .realtime(let valid) = VescTelemetryDecoder.decode(Data([50, 0, 0, 1, 0, 2, 8])) else {
            return XCTFail("52V voltage reply rejected")
        }
        XCTAssertEqual(valid.voltage, 52)
        XCTAssertFalse(valid.isComplete)
    }
    func testThreeThousandFragmentationCases() {
        var seed = UInt64(ProcessInfo.processInfo.environment["TEST_SEED"] ?? "101") ?? 101
        func random() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed }
        for index in 0..<3000 {
            let length = Int(random() % 1000) + 1
            let payload = Data((0..<length).map { _ in UInt8(truncatingIfNeeded: random() >> 24) })
            let parser = Packet()
            let frame = parser.preparePacket(data: payload)
            let header = length <= 255 ? 2 : 3
            XCTAssertEqual(frame[frame.count - 3], UInt8(crc(payload) >> 8))
            XCTAssertEqual(frame[frame.count - 2], UInt8(truncatingIfNeeded: crc(payload)))
            XCTAssertEqual(frame.count, length + header + 3)
            var received: [Data] = []
            parser.packetReceived = { received.append($0) }
            var offset = 0
            while offset < frame.count {
                let end = min(frame.count, offset + Int(random() % 47) + 1)
                parser.processData(data: frame.subdata(in: offset..<end))
                offset = end
            }
            XCTAssertEqual(received, [payload], "Seed case \(index)")
        }
    }
}
