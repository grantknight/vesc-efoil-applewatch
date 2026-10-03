//
//  VescStats.swift
//  MyWatchOSApp Watch App
//
//  Created by Gregory Dymarek on 10/08/2025.
//

import Foundation
import Combine

enum BatteryPercentSource { case unknown, vesc, voltageEstimate, demo }

final class VESCRtStats: ObservableObject {
    var batteryVoltage: Double = 0.0
    var inputCurrent: Double = 0.0
    var mosTemperature: Double = 0.0
    var motorTemperature: Double = 0.0
    var wattHours: Double = 0.0
    var rpm: Double = 0.0
    var batteryPercent: Double = 0.0
    private(set) var batteryPercentSource: BatteryPercentSource = .unknown
    private var batteryPercentTimestamp: Date = .distantPast
    var batteryPercentIsAvailable: Bool {
        let age = Date().timeIntervalSince(batteryPercentTimestamp)
        let selectedSource = batteryPercentSource == .demo ||
            (BatteryConfig.useVescBatteryLevel ? batteryPercentSource == .vesc : batteryPercentSource == .voltageEstimate)
        return selectedSource && age >= 0 && age <= 6
    }
    var batterySourceLabel: String {
        switch batteryPercentSource {
        case .vesc: return "VESC estimate"
        case .voltageEstimate: return "Voltage estimate"
        case .demo: return "Sample estimate"
        case .unknown: return "Battery % unavailable"
        }
    }
    func updateBatteryPercent(_ value: Double, source: BatteryPercentSource, at date: Date = .now) {
        guard value.isFinite else { return }
        batteryPercent = min(100, max(0, value))
        batteryPercentSource = source
        batteryPercentTimestamp = date
        objectWillChange.send()
    }
    /// Vehicle speed from VESC (m/s).
    var vescSpeed: Double = 0.0
    var isConnected: Bool = false

    private var lastUpdateTimestamp: Date = .distantPast
    private(set) var lastTelemetryTimestamp: Date = .distantPast

    func markTelemetryReceived(at date: Date = Date()) {
        lastTelemetryTimestamp = date
        objectWillChange.send()
    }

    func isFresh(now: Date = Date(), maxAge: TimeInterval = 6) -> Bool {
        let age = now.timeIntervalSince(lastTelemetryTimestamp)
        return isConnected && age >= 0 && age <= maxAge
    }

    var timeSinceLastUpdate: TimeInterval {
        Date().timeIntervalSince(lastUpdateTimestamp)
    }

    /// Instantaneous electrical power (W) from live voltage and current.
    var instantWatts: Double {
        max(0, batteryVoltage * inputCurrent)
    }

    func updateStats(
        batteryVoltage: Double? = nil,
        inputCurrent: Double? = nil,
        mosTemperature: Double? = nil,
        motorTemperature: Double? = nil,
        wattHours: Double? = nil,
        rpm: Double? = nil,
        batteryPercent: Double? = nil,
        vescSpeed: Double? = nil,
        isConnected: Bool? = nil
    ) {
        lastUpdateTimestamp = Date()

        if let batteryVoltage { self.batteryVoltage = batteryVoltage }
        if let inputCurrent { self.inputCurrent = inputCurrent }
        if let mosTemperature { self.mosTemperature = mosTemperature }
        if let motorTemperature { self.motorTemperature = motorTemperature }
        if let wattHours { self.wattHours = wattHours }
        if let rpm { self.rpm = rpm }
        if let batteryPercent { updateBatteryPercent(batteryPercent, source: .demo) }
        if let vescSpeed { self.vescSpeed = vescSpeed }
        if let isConnected { self.isConnected = isConnected }

        objectWillChange.send()
    }

    func resetStats() {
        batteryVoltage = 0.0
        inputCurrent = 0.0
        mosTemperature = 0.0
        motorTemperature = 0.0
        wattHours = 0.0
        rpm = 0.0
        batteryPercent = 0.0
        batteryPercentSource = .unknown
        batteryPercentTimestamp = .distantPast
        vescSpeed = 0.0
        isConnected = false
        lastUpdateTimestamp = .distantPast
        lastTelemetryTimestamp = .distantPast
        objectWillChange.send()
    }
}

final class VESCStats: ObservableObject {
    var runTime: Double = 0.0
    var maxPower: Double = 0.0
    var avgPower: Double = 0.0
    var maxMosTemperature: Double = 0.0
    var avgMosTemperature: Double = 0.0
    var maxCurrent: Double = 0.0
    var avgCurrent: Double = 0.0

    private var lastUpdateTimestamp: Date = .distantPast

    var timeSinceLastUpdate: TimeInterval {
        Date().timeIntervalSince(lastUpdateTimestamp)
    }

    func updateStats(
        runTime: Double? = nil,
        maxPower: Double? = nil,
        avgPower: Double? = nil,
        maxMosTemperature: Double? = nil,
        avgMosTemperature: Double? = nil,
        maxCurrent: Double? = nil,
        avgCurrent: Double? = nil
    ) {
        lastUpdateTimestamp = Date()

        if let runTime { self.runTime = runTime }
        if let maxPower { self.maxPower = maxPower }
        if let avgPower { self.avgPower = avgPower }
        if let maxMosTemperature { self.maxMosTemperature = maxMosTemperature }
        if let avgMosTemperature { self.avgMosTemperature = avgMosTemperature }
        if let maxCurrent { self.maxCurrent = maxCurrent }
        if let avgCurrent { self.avgCurrent = avgCurrent }

        objectWillChange.send()
    }

    func resetStats() {
        runTime = 0.0
        maxPower = 0.0
        avgPower = 0.0
        maxMosTemperature = 0.0
        avgMosTemperature = 0.0
        maxCurrent = 0.0
        avgCurrent = 0.0
        lastUpdateTimestamp = .distantPast
        objectWillChange.send()
    }
}

/// Converts VESC speed (m/s) to the user's preferred display unit.
func formatVescSpeed(_ speedMs: Double, unit: GPSSpeedUnit) -> Double {
    switch unit {
    case .ms:
        return speedMs
    case .kph:
        return speedMs * 3.6
    case .mph:
        return speedMs * 2.23694
    case .knots:
        return speedMs * 1.94384
    }
}
