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
    var displayLabel: String {
        switch self { case .kph: return "km/h"; case .ms: return "m/s"; default: return rawValue }
    }
    var spokenLabel: String {
        switch self {
        case .kph: return "kilometres per hour"
        case .mph: return "miles per hour"
        case .ms: return "metres per second"
        case .knots: return "knots"
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var recordingObserver: AnyCancellable?
    @Published var speedUnit: GPSSpeedUnit = .kph
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
    @Published private(set) var courseDegrees: Double?
    @Published private(set) var lastCourseAt: Date?

    var hasFreshLocation: Bool {
        guard isEnabled(), isTracking, let lastLocationAt else { return false }
        return isRecent(lastLocationAt)
    }
    var hasFreshSpeed: Bool {
        guard hasFreshLocation, let lastSpeedAt else { return false }
        return isRecent(lastSpeedAt)
    }
    var hasFreshHeading: Bool {
        guard isTracking, let lastHeadingAt else { return false }
        return isRecent(lastHeadingAt)
    }
    var hasFreshCourse: Bool {
        guard hasFreshSpeed, rawSpeedMs > 0.5, courseDegrees != nil, let lastCourseAt else { return false }
        return isRecent(lastCourseAt)
    }
    var directionHeading: Double? {
        if hasFreshHeading { return smoothedHeadingDegrees }
        return hasFreshCourse ? courseDegrees : nil
    }
    var directionReference: String {
        if hasFreshHeading { return "Compass heading" }
        return hasFreshCourse ? "GPS course" : "Direction unavailable"
    }
    private func isRecent(_ date: Date) -> Bool {
        let age = Date().timeIntervalSince(date)
        return age.isFinite && age >= 0 && age <= 10
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
        // GPS may keep running with the wrist down only while a ride records (its workout
        // session keeps the app alive). Setting this without the declared background mode
        // would crash, so check first.
        if (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true {
            recordingObserver = SessionLogger.shared.$isRecording.removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] recording in self?.locationManager.allowsBackgroundLocationUpdates = recording }
        }
        locationManager.requestWhenInUseAuthorization()

        if isEnabled() {
            start()
        }
    }

    /// GPS and km/h are first-launch defaults; existing explicit preferences are retained.
    private func applyFirstLaunchDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.gpsDefaultAppliedKey) else { return }
        if UserDefaults.standard.object(forKey: Self.gpsEnabledKey) == nil { UserDefaults.standard.set(true, forKey: Self.gpsEnabledKey) }
        if UserDefaults.standard.object(forKey: Self.speedUnitKey) == nil { UserDefaults.standard.set(GPSSpeedUnit.kph.rawValue, forKey: Self.speedUnitKey) }
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
        guard isEnabled(), !isTracking else { return }
        isTracking = true
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }

    func stop() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        speed = 0.0
        rawSpeedMs = 0.0
        smoothedSpeedMs = 0.0
        currentCoordinate = nil
        headingDegrees = nil
        smoothedHeadingDegrees = nil
        lastLocationAt = nil
        lastSpeedAt = nil
        lastHeadingAt = nil
        courseDegrees = nil
        lastCourseAt = nil
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
        guard isEnabled(), isTracking, let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              isRecent(location.timestamp),
              CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        let validSpeed = location.speed.isFinite && (0...100).contains(location.speed)
        var speedMs = validSpeed ? location.speed : 0
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
            guard self.isEnabled(), self.isTracking else { return }
            self.speed = speedMs
            self.rawSpeedMs = rawMs
            self.smoothedSpeedMs = self.smoothedSpeedMs == 0
                ? rawMs
                : (self.smoothedSpeedMs * (1 - self.speedSmoothingAlpha)) + (rawMs * self.speedSmoothingAlpha)
            self.currentCoordinate = coordinate
            self.lastLocationAt = location.timestamp
            self.lastSpeedAt = validSpeed ? location.timestamp : nil
            if validSpeed, location.speed > 0.5, location.course.isFinite, (0..<360).contains(location.course),
               location.courseAccuracy.isFinite, location.courseAccuracy >= 0 {
                self.courseDegrees = location.course
                self.lastCourseAt = location.timestamp
            } else {
                self.courseDegrees = nil
                self.lastCourseAt = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isEnabled(), isTracking else { return }
        let trueHeading = newHeading.trueHeading
        let resolved = trueHeading
        // A compass disturbed by the motor or battery reports poor accuracy; ignoring it lets
        // the arrow fall back to GPS course instead of pointing confidently the wrong way.
        guard resolved.isFinite, (0..<360).contains(resolved), newHeading.headingAccuracy.isFinite,
              newHeading.headingAccuracy >= 0, newHeading.headingAccuracy <= 45,
              isRecent(newHeading.timestamp) else { return }
        DispatchQueue.main.async {
            guard self.isEnabled(), self.isTracking else { return }
            // After a heading gap, start from the new reading instead of easing the arrow
            // through a direction that is no longer current.
            let continuous = self.lastHeadingAt.map { newHeading.timestamp.timeIntervalSince($0) <= 10 } ?? false
            self.headingDegrees = resolved
            self.lastHeadingAt = newHeading.timestamp
            if continuous, let previous = self.smoothedHeadingDegrees {
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
            self.speed = 0.0
            self.rawSpeedMs = 0.0
            self.smoothedSpeedMs = 0.0
            self.headingDegrees = nil
            self.smoothedHeadingDegrees = nil
            self.lastLocationAt = nil
            self.lastSpeedAt = nil
            self.lastHeadingAt = nil
            self.courseDegrees = nil
            self.lastCourseAt = nil
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
            courseDegrees = nil
            lastCourseAt = nil
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
