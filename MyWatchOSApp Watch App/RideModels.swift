import Foundation

/// A validated telemetry observation. Speeds are metres/second; power uses signed battery current.
struct RideSample: Codable, Equatable {
    var timestamp: Date
    var batteryVoltage: Double
    var inputCurrent: Double
    var controllerTemperatureC: Double
    var motorTemperatureC: Double
    var batteryPercent: Double?
    /// Fresh GPS ground speed only. Nil excludes this observation from distance integration.
    var speedMs: Double?

    var watts: Double { max(0, batteryVoltage * inputCurrent) }
    var isValid: Bool {
        let values = [timestamp.timeIntervalSince1970, batteryVoltage, inputCurrent,
                      controllerTemperatureC, motorTemperatureC, watts]
        return values.allSatisfy { $0.isFinite } && batteryVoltage > 0 && batteryVoltage <= 200
            && abs(inputCurrent) <= 2000 && (-100...300).contains(controllerTemperatureC)
            && (-100...300).contains(motorTemperatureC)
            && (batteryPercent.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && (speedMs.map { $0.isFinite && (0...100).contains($0) } ?? true)
    }
}

struct RideSession: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date?
    var interrupted: Bool = false
    var samples: [RideSample] = []
    var totalSampleCount: Int = 0
    var distanceMeters: Double = 0
    var energyWh: Double = 0
    var maxSpeedMs: Double = 0
    var maxWatts: Double = 0
    var maxMotorTemperatureC: Double = 0
    var maxControllerTemperatureC: Double = 0
    var startBatteryPercent: Double?
    var endBatteryPercent: Double?
    var disconnectionCount: Int = 0
    var observedSeconds: TimeInterval = 0
    var wattSeconds: Double = 0
    var updatedAt: Date

    var duration: TimeInterval { max(0, (endedAt ?? Date()).timeIntervalSince(startedAt)) }
    /// Time-weighted average over observed, contiguous telemetry only.
    var averageWatts: Double { observedSeconds > 0 ? wattSeconds / observedSeconds : 0 }
}
