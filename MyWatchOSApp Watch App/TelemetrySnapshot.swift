//
//  TelemetrySnapshot.swift
//  MyWatchOSApp Watch App
//
//  Persists latest telemetry for in-app dashboard and future WidgetKit complications.
//

import Foundation

struct TelemetrySnapshot: Codable {
    var speed: Double = 0
    var speedUnit: String = "mph"
    var watts: Double = 0
    var batteryPercent: Double = 0
    var batteryVoltage: Double = 0
    var mosTempC: Double = 0
    var motorTempC: Double = 0
    var isConnected: Bool = false
    var updatedAt: Date = .distantPast

    private static let storageKey = "TELEMETRY_SNAPSHOT"

    static func load() -> TelemetrySnapshot {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(TelemetrySnapshot.self, from: data) else {
            return TelemetrySnapshot()
        }
        return snapshot
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

enum TelemetryPublisher {
    static func publish(
        rt: VESCRtStats,
        speed: Double,
        speedUnit: GPSSpeedUnit,
        isConnected: Bool
    ) {
        var snapshot = TelemetrySnapshot()
        snapshot.speed = speed
        snapshot.speedUnit = speedUnit.rawValue
        snapshot.watts = rt.instantWatts
        snapshot.batteryPercent = rt.batteryPercent
        snapshot.batteryVoltage = rt.batteryVoltage
        snapshot.mosTempC = rt.mosTemperature
        snapshot.motorTempC = rt.motorTemperature
        snapshot.isConnected = isConnected
        snapshot.updatedAt = Date()
        snapshot.save()
    }
}
