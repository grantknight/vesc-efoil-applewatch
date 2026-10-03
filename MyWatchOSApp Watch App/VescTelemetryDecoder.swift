import Foundation

/// Only the requested protocol fields are supported. A truncated, unknown or
/// non-finite reply is rejected as a whole; it must never become a live zero.
enum VescTelemetryUpdate {
    case realtime(RealtimeTelemetry)
    case setup(SetupTelemetry)
    case statistics(SessionTelemetry)
}

struct RealtimeTelemetry {
    var controllerTemperature: Double?
    var motorTemperature: Double?
    var inputCurrent: Double?
    var rpm: Double?
    var voltage: Double?
    var wattHours: Double?
    var isComplete: Bool {
        controllerTemperature != nil && motorTemperature != nil && inputCurrent != nil
            && rpm != nil && voltage != nil && wattHours != nil
    }
}

struct SetupTelemetry {
    var speedMs: Double?
    var batteryLevel: Double?
}

struct SessionTelemetry {
    var avgPower: Double?
    var maxPower: Double?
    var avgCurrent: Double?
    var maxCurrent: Double?
    var avgControllerTemperature: Double?
    var maxControllerTemperature: Double?
    var runTime: Double?
}

enum VescTelemetryDecoder {
    static func decode(_ data: Data) -> VescTelemetryUpdate? {
        guard data.count >= 5 else { return nil }
        var bytes = VByteArray(data: data)
        let command = bytes.vbPopFrontUInt8()
        let mask = bytes.vbPopFrontUInt32()
        let widths: [Int: Int]
        switch command {
        case 50: widths = [0: 2, 1: 2, 3: 4, 7: 4, 8: 2, 11: 4]
        case 51: widths = [6: 4, 8: 2]
        case 128: widths = [2: 4, 3: 4, 4: 4, 5: 4, 6: 4, 7: 4, 10: 4]
        default: return nil
        }
        let allowed = widths.keys.reduce(UInt32(0)) { $0 | (UInt32(1) << $1) }
        guard mask != 0, mask & ~allowed == 0 else { return nil }
        let expected = widths.reduce(0) { $0 + ((mask & (UInt32(1) << $1.key)) != 0 ? $1.value : 0) }
        guard bytes.data.count == expected else { return nil }
        func has(_ bit: Int) -> Bool { mask & (UInt32(1) << bit) != 0 }
        func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
            value.map { $0.isFinite && range.contains($0) } ?? true
        }
        switch command {
        case 50:
            var rt = RealtimeTelemetry()
            if has(0) { rt.controllerTemperature = bytes.vbPopFrontDouble16(scale: 10) }
            if has(1) { rt.motorTemperature = bytes.vbPopFrontDouble16(scale: 10) }
            if has(3) { rt.inputCurrent = bytes.vbPopFrontDouble32(scale: 100) }
            if has(7) { rt.rpm = bytes.vbPopFrontDouble32(scale: 1) }
            if has(8) { rt.voltage = bytes.vbPopFrontDouble16(scale: 10) }
            if has(11) { rt.wattHours = bytes.vbPopFrontDouble32(scale: 10000) }
            guard valid(rt.controllerTemperature, in: -100...250), valid(rt.motorTemperature, in: -100...250),
                  valid(rt.inputCurrent, in: -2000...2000), valid(rt.rpm, in: -1_000_000...1_000_000),
                  valid(rt.voltage, in: Double.leastNonzeroMagnitude...200), valid(rt.wattHours, in: -1_000_000...1_000_000) else { return nil }
            return .realtime(rt)
        case 51:
            var setup = SetupTelemetry()
            if has(6) { setup.speedMs = bytes.vbPopFrontDouble32(scale: 1000) }
            if has(8) { setup.batteryLevel = bytes.vbPopFrontDouble16(scale: 1000) }
            guard valid(setup.speedMs, in: -200...200), valid(setup.batteryLevel, in: 0...1) else { return nil }
            return .setup(setup)
        default:
            var stats = SessionTelemetry()
            if has(2) { stats.avgPower = bytes.vbPopFrontDouble32Auto() }
            if has(3) { stats.maxPower = bytes.vbPopFrontDouble32Auto() }
            if has(4) { stats.avgCurrent = bytes.vbPopFrontDouble32Auto() }
            if has(5) { stats.maxCurrent = bytes.vbPopFrontDouble32Auto() }
            if has(6) { stats.avgControllerTemperature = bytes.vbPopFrontDouble32Auto() }
            if has(7) { stats.maxControllerTemperature = bytes.vbPopFrontDouble32Auto() }
            if has(10) { stats.runTime = bytes.vbPopFrontDouble32Auto() }
            guard valid(stats.avgPower, in: -1_000_000...1_000_000), valid(stats.maxPower, in: -1_000_000...1_000_000),
                  valid(stats.avgCurrent, in: -2000...2000), valid(stats.maxCurrent, in: -2000...2000),
                  valid(stats.avgControllerTemperature, in: -100...250), valid(stats.maxControllerTemperature, in: -100...250),
                  valid(stats.runTime, in: 0...100_000_000) else { return nil }
            return .statistics(stats)
        }
    }
}
