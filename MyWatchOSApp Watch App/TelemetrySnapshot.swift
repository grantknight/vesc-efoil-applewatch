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
    var motorTempC: Double = 0
    var isConnected = false
    /// Time of the validated primary telemetry sample, never a view refresh time.
    var updatedAt: Date = .distantPast
    private static let storageKey = "TELEMETRY_SNAPSHOT_V2"

    func isFresh(at date: Date = .now) -> Bool {
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
