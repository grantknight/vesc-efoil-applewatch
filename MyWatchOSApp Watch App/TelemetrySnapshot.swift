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
        return isConnected && age >= 0 && age < Self.staleInterval
    }
    static func load() -> Self {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return snapshot
    }
    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
