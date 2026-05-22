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
    @Published var isTracking: Bool = false

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
        isTracking = true
    }

    func stop() {
        guard isTracking else { return }
        locationManager.stopUpdatingLocation()
        speed = 0.0
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
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if DEBUG { print("Location error: \(error.localizedDescription)") }
        DispatchQueue.main.async {
            self.isTracking = false
            self.speed = 0.0
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
}
