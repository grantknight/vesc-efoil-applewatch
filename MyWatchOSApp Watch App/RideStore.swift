import Foundation

enum RideStoreError: LocalizedError {
    case alreadyRecording, noActiveRide, invalidSample, invalidTime, corruptArchive(String)
    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "A ride is already recording. Save it before starting another."
        case .noActiveRide: return "There is no active ride."
        case .invalidSample: return "Telemetry was invalid; the observation was not recorded."
        case .invalidTime: return "The ride time is out of order or outside the supported years 1970–2200."
        case .corruptArchive(let name): return "Ride archive \(name) could not be read. Existing files have been preserved."
        }
    }
}

/// Main-thread-owned store. Each update commits a complete, atomic checkpoint before changing memory.
/// An interruption can lose only an uncommitted observation, never the previous saved checkpoint.
final class RideStore {
    // Bound persisted dates before they reach date formatters or integer duration conversion.
    // This also catches corrupt, finite JSON numbers that Date itself will otherwise accept.
    private static let supportedEpochSeconds: ClosedRange<TimeInterval> = 0...7_258_118_400
    private struct Archive: Codable { var schemaVersion: Int = 1; var ride: RideSession }
    private let directory: URL
    private let writeData: (Data, URL) throws -> Void
    private let maxRetainedSamples: Int
    private let maximumIntegrationGap: TimeInterval
    private var previousSample: RideSample?
    private var connection: Bool?
    private(set) var activeRide: RideSession?
    private(set) var rides: [RideSession] = []

    init(directory: URL, maxRetainedSamples: Int = 1800, maximumIntegrationGap: TimeInterval = 10,
         writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        self.directory = directory
        self.maxRetainedSamples = max(1, maxRetainedSamples)
        self.maximumIntegrationGap = max(0, maximumIntegrationGap)
        self.writeData = writeData
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var loaded: [RideSession] = []
        for url in urls {
            let archive: Archive
            do { archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url)) }
            catch { throw RideStoreError.corruptArchive(url.lastPathComponent) }
            guard archive.schemaVersion == 1, Self.isValidArchive(archive.ride),
                  url.deletingPathExtension().lastPathComponent == archive.ride.id.uuidString,
                  !loaded.contains(where: { $0.id == archive.ride.id }) else {
                throw RideStoreError.corruptArchive(url.lastPathComponent)
            }
            loaded.append(archive.ride)
        }
        // Only after every file validates do we perform recovery, preserving bad/unknown archives.
        for var ride in loaded {
            if ride.endedAt == nil {
                ride.endedAt = ride.updatedAt
                ride.interrupted = true
                try persist(ride)
            }
            rides.append(ride)
        }
        sortHistory()
    }

    @discardableResult func startRide(at date: Date = Date()) throws -> RideSession {
        guard activeRide == nil else { throw RideStoreError.alreadyRecording }
        guard Self.isSupportedDate(date) else { throw RideStoreError.invalidTime }
        let ride = RideSession(startedAt: date, updatedAt: date)
        try persist(ride)
        activeRide = ride
        previousSample = nil
        connection = nil
        return ride
    }

    @discardableResult func endRide(at date: Date = Date()) throws -> RideSession {
        guard var ride = activeRide else { throw RideStoreError.noActiveRide }
        guard Self.isSupportedDate(date), date >= ride.updatedAt else { throw RideStoreError.invalidTime }
        ride.endedAt = date
        ride.updatedAt = date
        try persist(ride)
        rides.insert(ride, at: 0)
        sortHistory()
        activeRide = nil
        previousSample = nil
        connection = nil
        return ride
    }

    func record(_ sample: RideSample) throws {
        guard var ride = activeRide else { return }
        guard sample.isValid else { throw RideStoreError.invalidSample }
        guard Self.isSupportedDate(sample.timestamp), sample.timestamp >= ride.updatedAt else { throw RideStoreError.invalidTime }
        guard connection != false else { return }
        // Duplicate timestamps never double-count observations or integrate elapsed time.
        if sample.timestamp == ride.samples.last?.timestamp { return }
        if let previousSample {
            let dt = sample.timestamp.timeIntervalSince(previousSample.timestamp)
            if dt > 0 && dt <= maximumIntegrationGap {
                let joules = (previousSample.watts + sample.watts) * 0.5 * dt
                ride.wattSeconds += joules
                ride.energyWh += joules / 3600
                if let previousSpeed = previousSample.speedMs, let speed = sample.speedMs {
                    ride.distanceMeters += (previousSpeed + speed) * 0.5 * dt
                }
                ride.observedSeconds += dt
            }
        }
        ride.samples.append(sample)
        if ride.samples.count > maxRetainedSamples {
            ride.samples.removeFirst(ride.samples.count - maxRetainedSamples)
        }
        ride.totalSampleCount += 1
        ride.maxSpeedMs = max(ride.maxSpeedMs, sample.speedMs ?? 0)
        ride.maxWatts = max(ride.maxWatts, sample.watts)
        ride.maxMotorTemperatureC = ride.totalSampleCount == 1 ? sample.motorTemperatureC : max(ride.maxMotorTemperatureC, sample.motorTemperatureC)
        ride.maxControllerTemperatureC = ride.totalSampleCount == 1 ? sample.controllerTemperatureC : max(ride.maxControllerTemperatureC, sample.controllerTemperatureC)
        if ride.startBatteryPercent == nil { ride.startBatteryPercent = sample.batteryPercent }
        ride.endBatteryPercent = sample.batteryPercent
        ride.updatedAt = sample.timestamp
        try persist(ride)
        activeRide = ride
        previousSample = sample
        connection = true
    }

    func connectionChanged(isConnected: Bool, at date: Date = Date()) throws {
        // Drop integration baseline immediately, including when persistence fails.
        if !isConnected { previousSample = nil }
        guard Self.isSupportedDate(date) else { throw RideStoreError.invalidTime }
        guard var ride = activeRide else { connection = isConnected; return }
        if !isConnected && connection != false {
            ride.disconnectionCount += 1
            guard Self.isSupportedDate(date), date >= ride.updatedAt else { throw RideStoreError.invalidTime }
            ride.updatedAt = date
            try persist(ride)
            activeRide = ride
        }
        connection = isConnected
    }

    func deleteRide(id: UUID) throws {
        guard rides.contains(where: { $0.id == id }) else { return }
        try FileManager.default.removeItem(at: fileURL(id))
        rides.removeAll { $0.id == id }
    }

    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    private func persist(_ ride: RideSession) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try writeData(encoder.encode(Archive(ride: ride)), fileURL(ride.id))
    }
    private func sortHistory() { rides.sort { $0.startedAt > $1.startedAt } }
    private static func isSupportedDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && supportedEpochSeconds.contains(date.timeIntervalSince1970)
    }
    private static func isValidArchive(_ ride: RideSession) -> Bool {
        let metrics = [ride.startedAt.timeIntervalSince1970, ride.updatedAt.timeIntervalSince1970,
                       ride.distanceMeters, ride.energyWh, ride.maxSpeedMs, ride.maxWatts,
                       ride.maxMotorTemperatureC, ride.maxControllerTemperatureC,
                       ride.observedSeconds, ride.wattSeconds]
        let orderedSamples = zip(ride.samples, ride.samples.dropFirst()).allSatisfy { pair in pair.0.timestamp < pair.1.timestamp }
        return metrics.allSatisfy { $0.isFinite }
            && isSupportedDate(ride.startedAt) && isSupportedDate(ride.updatedAt)
            && ride.updatedAt >= ride.startedAt
            && (ride.endedAt.map { isSupportedDate($0) && $0 == ride.updatedAt } ?? true)
            && ride.totalSampleCount >= ride.samples.count && ride.disconnectionCount >= 0
            && ride.distanceMeters >= 0 && ride.energyWh >= 0 && ride.observedSeconds >= 0
            && ride.wattSeconds >= 0 && orderedSamples
            && ride.samples.allSatisfy { $0.isValid && isSupportedDate($0.timestamp) && $0.timestamp >= ride.startedAt && $0.timestamp <= ride.updatedAt }
            && [ride.startBatteryPercent, ride.endBatteryPercent].compactMap { $0 }.allSatisfy { $0.isFinite && (0...100).contains($0) }
    }
}
