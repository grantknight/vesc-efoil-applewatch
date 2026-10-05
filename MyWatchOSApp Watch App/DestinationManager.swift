//
//  DestinationManager.swift
//  MyWatchOSApp Watch App
//

import Foundation
import Combine
import CoreLocation

private struct StoredDestination: Codable {
    let latitude: Double
    let longitude: Double
    let name: String
}

enum DestinationKind: String, CaseIterable, Identifiable {
    case finish, launch
    var id: String { rawValue }
    var title: String { self == .launch ? "Launch / beach" : "Finish" }
}

final class DestinationManager: ObservableObject {
    @Published private(set) var finishCoordinate: CLLocationCoordinate2D?
    @Published private(set) var finishName = "Finish"
    @Published private(set) var launchCoordinate: CLLocationCoordinate2D?
    @Published private(set) var launchName = "Launch / beach"
    @Published private(set) var destinationKind: DestinationKind = .finish
    @Published var reservePercent: Double = 20 {
        didSet {
            guard reservePercent.isFinite, (0...100).contains(reservePercent) else { reservePercent = oldValue; return }
            if persists { UserDefaults.standard.set(reservePercent, forKey: "NAV_RESERVE_PERCENT") }
        }
    }
    var destination: CLLocationCoordinate2D? { destinationKind == .launch ? launchCoordinate : finishCoordinate }
    var destinationName: String { destinationKind == .launch ? launchName : finishName }

    private let storageKey = "NAV_DESTINATION"
    private let launchStorageKey = "NAV_LAUNCH"
    private let persists: Bool

    init(persists: Bool = true) {
        self.persists = persists
        if persists { load() }
    }

    func setDestination(_ coordinate: CLLocationCoordinate2D, name: String = "Pinned destination") {
        guard Self.validCoordinate(coordinate) else { return }
        finishCoordinate = coordinate
        finishName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Finish" : name
        destinationKind = .finish
        save()
    }

    func clearDestination() {
        finishCoordinate = nil
        if persists { UserDefaults.standard.removeObject(forKey: storageKey); saveSelection() }
    }

    func saveLaunchPoint(_ coordinate: CLLocationCoordinate2D, name: String = "Launch / beach") {
        guard Self.validCoordinate(coordinate) else { return }
        launchCoordinate = coordinate
        launchName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Launch / beach" : name
        savePoint(coordinate, name: launchName, key: launchStorageKey)
    }

    func selectReturnToLaunch() {
        guard launchCoordinate != nil else { return }
        destinationKind = .launch
        saveSelection()
    }

    func selectFinish() {
        guard finishCoordinate != nil else { return }
        destinationKind = .finish
        saveSelection()
    }

    func clearLaunchPoint() {
        launchCoordinate = nil
        if destinationKind == .launch { destinationKind = .finish }
        if persists { UserDefaults.standard.removeObject(forKey: launchStorageKey); saveSelection() }
    }

    func distance(from current: CLLocationCoordinate2D?) -> CLLocationDistance? {
        guard let current, let destination,
              Self.validCoordinate(current), Self.validCoordinate(destination) else { return nil }
        return NavigationEstimate.distanceMeters(from: Self.navigationCoordinate(current), to: Self.navigationCoordinate(destination))
    }

    /// Bearing from current point to destination in degrees, normalized 0...360.
    func bearingToDestination(from current: CLLocationCoordinate2D?) -> Double? {
        guard let current, let destination,
              Self.validCoordinate(current), Self.validCoordinate(destination) else { return nil }
        return NavigationEstimate.bearingDegrees(from: Self.navigationCoordinate(current), to: Self.navigationCoordinate(destination))
    }

    /// Arrow rotation where 0 means straight ahead relative to user's heading.
    func arrowAngle(current: CLLocationCoordinate2D?, heading: Double?) -> Double? {
        guard let bearing = bearingToDestination(from: current), let heading, heading.isFinite else { return nil }
        return normalizeSignedDegrees(bearing - heading)
    }

    func etaSeconds(distanceMeters: Double?, speedMs: Double) -> TimeInterval? {
        NavigationEstimate.etaSeconds(distanceMeters: distanceMeters, speedMs: speedMs)
    }

    func formattedETA(_ etaSeconds: TimeInterval?) -> String {
        guard let etaSeconds, etaSeconds.isFinite, etaSeconds >= 0 else { return "ETA: --" }
        let rounded = etaSeconds.rounded()
        guard rounded < Double(Int.max) else { return "ETA: --" }
        let total = Int(rounded)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "ETA: \(hours)h " + String(format: "%02dm", mins)
        }
        return String(format: "ETA: %02d:%02d", mins, secs)
    }

    func formattedDistance(_ meters: Double?) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "Distance: --" }
        if meters >= 1000 {
            return String(format: "Distance: %.2f km", meters / 1000)
        }
        return String(format: "Distance: %.0f m", meters)
    }

    private func save() {
        guard let finishCoordinate else { return }
        savePoint(finishCoordinate, name: finishName, key: storageKey)
        saveSelection()
    }

    private func savePoint(_ coordinate: CLLocationCoordinate2D, name: String, key: String) {
        guard persists, Self.validCoordinate(coordinate) else { return }
        let stored = StoredDestination(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func saveSelection() {
        if persists { UserDefaults.standard.set(destinationKind.rawValue, forKey: "NAV_TARGET_KIND") }
    }

    private func load() {
        if let point = loadPoint(key: storageKey) { finishCoordinate = point.0; finishName = point.1 }
        if let point = loadPoint(key: launchStorageKey) { launchCoordinate = point.0; launchName = point.1 }
        if let kind = UserDefaults.standard.string(forKey: "NAV_TARGET_KIND").flatMap(DestinationKind.init(rawValue:)),
           kind != .launch || launchCoordinate != nil { destinationKind = kind }
        if let value = UserDefaults.standard.object(forKey: "NAV_RESERVE_PERCENT") as? Double,
           value.isFinite, (0...100).contains(value) { reservePercent = value }
    }

    private func loadPoint(key: String) -> (CLLocationCoordinate2D, String)? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredDestination.self, from: data) else {
            return nil
        }
        let coordinate = CLLocationCoordinate2D(latitude: stored.latitude, longitude: stored.longitude)
        guard Self.validCoordinate(coordinate) else { return nil }
        return (coordinate, stored.name)
    }

    private static func validCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        navigationCoordinate(coordinate).isValid
    }

    private static func navigationCoordinate(_ coordinate: CLLocationCoordinate2D) -> NavigationCoordinate {
        NavigationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
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
