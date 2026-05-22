//
//  DestinationManager.swift
//  MyWatchOSApp Watch App
//

import Foundation
import CoreLocation

private struct StoredDestination: Codable {
    let latitude: Double
    let longitude: Double
    let name: String
}

final class DestinationManager: ObservableObject {
    @Published var destination: CLLocationCoordinate2D?
    @Published var destinationName: String = "Pinned destination"

    private let storageKey = "NAV_DESTINATION"
    private var smoothedEtaSecondsValue: TimeInterval?

    init() {
        load()
    }

    func setDestination(_ coordinate: CLLocationCoordinate2D, name: String = "Pinned destination") {
        destination = coordinate
        destinationName = name
        smoothedEtaSecondsValue = nil
        save()
    }

    func clearDestination() {
        destination = nil
        smoothedEtaSecondsValue = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func distance(from current: CLLocationCoordinate2D?) -> CLLocationDistance? {
        guard let current, let destination else { return nil }
        let from = CLLocation(latitude: current.latitude, longitude: current.longitude)
        let to = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return from.distance(from: to)
    }

    /// Bearing from current point to destination in degrees, normalized 0...360.
    func bearingToDestination(from current: CLLocationCoordinate2D?) -> Double? {
        guard let current, let destination else { return nil }
        let lat1 = current.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let dLon = (destination.longitude - current.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return normalizeDegrees(bearing)
    }

    /// Arrow rotation where 0 means straight ahead relative to user's heading.
    func arrowAngle(current: CLLocationCoordinate2D?, heading: Double?) -> Double? {
        guard let bearing = bearingToDestination(from: current), let heading else { return nil }
        return normalizeSignedDegrees(bearing - heading)
    }

    func etaSeconds(distanceMeters: Double?, speedMs: Double) -> TimeInterval? {
        guard let distanceMeters, distanceMeters > 1, speedMs > 0.5 else { return nil }
        return distanceMeters / speedMs
    }

    func smoothedETA(distanceMeters: Double?, speedMs: Double) -> TimeInterval? {
        guard let eta = etaSeconds(distanceMeters: distanceMeters, speedMs: speedMs) else {
            smoothedEtaSecondsValue = nil
            return nil
        }

        if let previous = smoothedEtaSecondsValue {
            smoothedEtaSecondsValue = (previous * 0.75) + (eta * 0.25)
        } else {
            smoothedEtaSecondsValue = eta
        }

        return smoothedEtaSecondsValue
    }

    func formattedETA(_ etaSeconds: TimeInterval?) -> String {
        guard let etaSeconds else { return "ETA: --" }
        let total = Int(etaSeconds.rounded())
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "ETA: %dh %02dm", hours, mins)
        }
        return String(format: "ETA: %02d:%02d", mins, secs)
    }

    func formattedDistance(_ meters: Double?) -> String {
        guard let meters else { return "Distance: --" }
        if meters >= 1000 {
            return String(format: "Distance: %.2f km", meters / 1000)
        }
        return String(format: "Distance: %.0f m", meters)
    }

    private func save() {
        guard let destination else { return }
        let stored = StoredDestination(
            latitude: destination.latitude,
            longitude: destination.longitude,
            name: destinationName
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(StoredDestination.self, from: data) else {
            return
        }
        destination = CLLocationCoordinate2D(latitude: stored.latitude, longitude: stored.longitude)
        destinationName = stored.name
    }

    private func normalizeDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }

    private func normalizeSignedDegrees(_ degrees: Double) -> Double {
        var value = normalizeDegrees(degrees)
        if value > 180 {
            value -= 360
        }
        return value
    }
}
