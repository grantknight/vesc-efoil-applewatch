//
//  LocationManager.swift
//  MyWatchOSApp
//

import CoreLocation

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

    private let speedSmoothingAlpha: Double = 0.25
    private let headingSmoothingAlpha: Double = 0.22

    private static let gpsEnabledKey = "GPS_ENABLED"
    private static let speedUnitKey = "GPS_SPEEDUNIT"
    private static let gpsDefaultAppliedKey = "GPS_DEFAULTS_APPLIED"

    override init() {
        applyFirstLaunchDefaultsIfNeeded()

        if let stored = UserDefaults.standard.string(forKey: Self.speedUnitKey),
           let unit = GPSSpeedUnit(rawValue: stored) {
            speedUnit = unit
        }

        super.init()

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
    }

    func setSpeedUnit(_ unit: GPSSpeedUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: Self.speedUnitKey)
        speedUnit = unit
    }

    func getSpeedUnit() -> GPSSpeedUnit {
        speedUnit
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        var speedMs = max(location.speed, 0)
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
            self.speed = speedMs
            self.rawSpeedMs = rawMs
            self.smoothedSpeedMs = self.smoothedSpeedMs == 0
                ? rawMs
                : (self.smoothedSpeedMs * (1 - self.speedSmoothingAlpha)) + (rawMs * self.speedSmoothingAlpha)
            self.currentCoordinate = coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading
        let magneticHeading = newHeading.magneticHeading
        let resolved = trueHeading >= 0 ? trueHeading : magneticHeading
        guard resolved >= 0 else { return }
        DispatchQueue.main.async {
            self.headingDegrees = resolved
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
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isEnabled() {
                start()
            }
        case .denied, .restricted:
            speed = 0.0
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
