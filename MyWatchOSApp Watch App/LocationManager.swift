//
//  LocationManager.swift
//  MyWatchOSApp
//

import CoreLocation
import Combine

enum GPSSpeedUnit: String, CaseIterable, Identifiable {
    case kph
    case mph
    case ms
    case knots

    var id: GPSSpeedUnit { self }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var speedUnit: GPSSpeedUnit = .mph
    @Published var speed: Double = 0.0
    @Published var rawSpeedMs: Double = 0.0
    @Published var smoothedSpeedMs: Double = 0.0
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var headingDegrees: Double?
    @Published var smoothedHeadingDegrees: Double?
    @Published var isTracking: Bool = false
    @Published private(set) var lastLocationAt: Date?
    @Published private(set) var lastSpeedAt: Date?
    @Published private(set) var lastHeadingAt: Date?

    var hasFreshLocation: Bool {
        guard isEnabled(), isTracking, let lastLocationAt else { return false }
        return Date().timeIntervalSince(lastLocationAt) < 10
    }
    var hasFreshSpeed: Bool {
        guard hasFreshLocation, let lastSpeedAt else { return false }
        return Date().timeIntervalSince(lastSpeedAt) < 10
    }
    var hasFreshHeading: Bool {
        guard isTracking, let lastHeadingAt else { return false }
        return Date().timeIntervalSince(lastHeadingAt) < 10
    }

    private let speedSmoothingAlpha: Double = 0.25
    private let headingSmoothingAlpha: Double = 0.22

    private static let gpsEnabledKey = "GPS_ENABLED"
    private static let speedUnitKey = "GPS_SPEEDUNIT"
    private static let gpsDefaultAppliedKey = "GPS_DEFAULTS_APPLIED"

    override init() {
        super.init()
        applyFirstLaunchDefaultsIfNeeded()

        if let stored = UserDefaults.standard.string(forKey: Self.speedUnitKey),
           let unit = GPSSpeedUnit(rawValue: stored) {
            speedUnit = unit
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.headingFilter = 3
        locationManager.requestWhenInUseAuthorization()

        if isEnabled() {
            start()
        }
    }

    /// Efoil: GPS on by default, mph default speed unit.
    private func applyFirstLaunchDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.gpsDefaultAppliedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.gpsEnabledKey)
        UserDefaults.standard.set(GPSSpeedUnit.mph.rawValue, forKey: Self.speedUnitKey)
        UserDefaults.standard.set(true, forKey: Self.gpsDefaultAppliedKey)
    }

    func isEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: Self.gpsEnabledKey) == nil {
            return true
        }
        if let stored = UserDefaults.standard.object(forKey: Self.gpsEnabledKey) as? Bool {
            return stored
        }
        // Legacy installs stored "true" / "false" strings.
        return UserDefaults.standard.string(forKey: Self.gpsEnabledKey) == "true"
    }

    func toggleStatus(status: Bool) {
        UserDefaults.standard.set(status, forKey: Self.gpsEnabledKey)
        if status {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !isTracking else { return }
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        isTracking = true
    }

    func stop() {
        guard isTracking else { return }
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        speed = 0.0
        rawSpeedMs = 0.0
        smoothedSpeedMs = 0.0
        headingDegrees = nil
        smoothedHeadingDegrees = nil
        isTracking = false
        lastLocationAt = nil
        lastSpeedAt = nil
        lastHeadingAt = nil
    }

    func setSpeedUnit(_ unit: GPSSpeedUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: Self.speedUnitKey)
        speedUnit = unit
        speed = formatVescSpeed(rawSpeedMs, unit: unit)
    }

    func getSpeedUnit() -> GPSSpeedUnit {
        speedUnit
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isEnabled(), let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              abs(location.timestamp.timeIntervalSinceNow) < 10,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        var speedMs = location.speed.isFinite && location.speed >= 0 ? location.speed : 0
        let rawMs = speedMs
        let coordinate = location.coordinate

        switch speedUnit {
        case .ms:
            break
        case .kph:
            speedMs *= 3.6
        case .mph:
            speedMs *= 2.23694
        case .knots:
            speedMs *= 1.94384
        }

        DispatchQueue.main.async {
            guard self.isEnabled() else { return }
            self.isTracking = true
            self.speed = speedMs
            self.rawSpeedMs = rawMs
            self.smoothedSpeedMs = self.smoothedSpeedMs == 0
                ? rawMs
                : (self.smoothedSpeedMs * (1 - self.speedSmoothingAlpha)) + (rawMs * self.speedSmoothingAlpha)
            self.currentCoordinate = coordinate
            self.lastLocationAt = location.timestamp
            self.lastSpeedAt = location.speed >= 0 && location.speed.isFinite ? location.timestamp : nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading
        let magneticHeading = newHeading.magneticHeading
        let resolved = trueHeading >= 0 ? trueHeading : magneticHeading
        guard resolved >= 0 else { return }
        guard newHeading.headingAccuracy >= 0, abs(newHeading.timestamp.timeIntervalSinceNow) < 10 else { return }
        DispatchQueue.main.async {
            self.headingDegrees = resolved
            self.lastHeadingAt = newHeading.timestamp
            if let previous = self.smoothedHeadingDegrees {
                let delta = self.shortestAngleDelta(from: previous, to: resolved)
                self.smoothedHeadingDegrees = self.normalizeAngle(previous + (delta * self.headingSmoothingAlpha))
            } else {
                self.smoothedHeadingDegrees = resolved
            }
        }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if DEBUG { print("Location error: \(error.localizedDescription)") }
        DispatchQueue.main.async {
            self.isTracking = false
            self.speed = 0.0
            self.rawSpeedMs = 0.0
            self.smoothedSpeedMs = 0.0
            self.headingDegrees = nil
            self.smoothedHeadingDegrees = nil
            self.lastLocationAt = nil
            self.lastSpeedAt = nil
            self.lastHeadingAt = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isEnabled() {
                start()
            }
        case .denied, .restricted:
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
            speed = 0.0
            rawSpeedMs = 0.0
            smoothedSpeedMs = 0.0
            lastLocationAt = nil
            lastSpeedAt = nil
            lastHeadingAt = nil
            currentCoordinate = nil
            headingDegrees = nil
            smoothedHeadingDegrees = nil
            isTracking = false
        default:
            break
        }
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 360)
        if value < 0 {
            value += 360
        }
        return value
    }

    private func shortestAngleDelta(from: Double, to: Double) -> Double {
        var delta = normalizeAngle(to) - normalizeAngle(from)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return delta
    }
}
