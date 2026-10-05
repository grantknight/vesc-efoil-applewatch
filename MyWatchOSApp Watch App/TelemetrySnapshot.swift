import Foundation

/// Shared between the watch app and WidgetKit extension, with no app-only dependencies.
struct TelemetrySnapshot: Codable {
    static let appGroup = "group.com.grantknight.vescfoil"
    static let widgetKind = "FoilingTelemetryWidget"
    // Complications show explicitly cached readings; foreground live freshness is 6 seconds.
    static let staleInterval: TimeInterval = 60
    var speed: Double?
    var speedUnit = "mph"
    var watts: Double = 0
    var batteryPercent: Double?
    var batteryVoltage: Double = 0
    var mosTempC: Double = 0
    var motorTempC: Double = 0 // Legacy field; never presented as a live motor sensor.
    /// nil means fault status was not supplied (including snapshots from earlier app versions).
    var faultCode: UInt8?
    func faultLabel(at date: Date = Date()) -> String? {
        guard isFresh(at: date), let faultCode else { return nil }
        return VescFaultCode.label(for: faultCode)
    }
    var isConnected = false
    /// Time of the validated primary telemetry sample, never a view refresh time.
    var updatedAt: Date = .distantPast
    private static let storageKey = "TELEMETRY_SNAPSHOT_V2"

    func isFresh(at date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince(updatedAt)
        return isValid && isConnected && age >= 0 && age < Self.staleInterval
    }
    var isValid: Bool {
        [watts, batteryVoltage, mosTempC, motorTempC, updatedAt.timeIntervalSince1970].allSatisfy { $0.isFinite }
            && (0...400_000).contains(watts) && (0...200).contains(batteryVoltage)
            && (-100...300).contains(mosTempC) && (-100...300).contains(motorTempC)
            && (batteryPercent.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && (speed.map { $0.isFinite && $0 >= 0 && $0 <= 1000 } ?? true)
            && ["mph", "kph", "ms", "knots"].contains(speedUnit)
    }
    static func load() -> Self {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data), snapshot.isValid else { return Self() }
        return snapshot
    }
    func save() {
        guard isValid, let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Numeric ordering follows upstream VESC firmware datatypes.h mc_fault_code.
/// Unknown firmware additions remain numeric and cannot be mistaken for FAULT_CODE_NONE.
enum VescFaultCode {
    private static let labels = [
            "No fault", "Over voltage", "Under voltage", "Driver fault", "Absolute over current",
            "ESC over temperature", "Motor over temperature", "Gate driver over voltage",
            "Gate driver under voltage", "MCU under voltage", "Watchdog reset", "Encoder SPI",
            "Encoder sin/cos amplitude low", "Encoder sin/cos amplitude high", "Flash corruption",
            "Current sensor 1 offset", "Current sensor 2 offset", "Current sensor 3 offset",
            "Unbalanced currents", "Brake fault", "Resolver tracking lost", "Resolver signal degraded",
            "Resolver signal lost", "App config flash corruption", "Motor config flash corruption",
            "Encoder magnet missing", "Encoder magnet too strong", "Phase filter fault", "Encoder fault",
            "Low voltage output fault", "Encoder slip", "Over speed", "Under speed", "Absolute over speed"
    ]
    static func label(for code: UInt8) -> String {
        return Int(code) < labels.count ? labels[Int(code)] : "Unknown fault (\(code))"
    }
}
