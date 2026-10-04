import Foundation

struct NavigationCoordinate: Equatable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

enum NavigationEstimate {
    /// Decimal latitude, longitude. Accepts comma, semicolon or whitespace separators.
    static func parseCoordinate(_ text: String) -> NavigationCoordinate? {
        let parts = text.split { $0 == "," || $0 == ";" || $0.isWhitespace }
        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else { return nil }
        let coordinate = NavigationCoordinate(latitude: latitude, longitude: longitude)
        return coordinate.isValid ? coordinate : nil
    }

    /// Great-circle distance on a mean-radius spherical Earth; suitable for straight-line guidance.
    static func distanceMeters(from: NavigationCoordinate, to: NavigationCoordinate) -> Double? {
        guard from.isValid, to.isValid else { return nil }
        let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (to.longitude - from.longitude) * .pi / 180
        let a = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        return 6_371_008.8 * 2 * atan2(sqrt(min(1, max(0, a))), sqrt(max(0, 1 - a)))
    }

    static func bearingDegrees(from: NavigationCoordinate, to: NavigationCoordinate) -> Double? {
        guard from.isValid, to.isValid, let distance = distanceMeters(from: from, to: to), distance > 0.01 else { return nil }
        let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        // The initial course to an exactly antipodal point is not unique.
        guard abs(x) + abs(y) > 1e-12 else { return nil }
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func etaSeconds(distanceMeters: Double?, speedMs: Double?) -> TimeInterval? {
        guard let distanceMeters, let speedMs, distanceMeters.isFinite, distanceMeters >= 0,
              speedMs.isFinite, speedMs > 0.5, speedMs <= 100 else { return nil }
        let seconds = distanceMeters / speedMs
        return seconds.isFinite && seconds >= 0 && seconds < Double(Int.max) ? seconds : nil
    }
}

struct ArrivalBatteryPrediction: Equatable {
    /// Unclamped percentage. A negative value explicitly means projected exhaustion before arrival.
    var arrivalPercent: Double
    var reserveShortfallPercent: Double
    var willExhaustBeforeArrival: Bool
    var secondsUntilEmpty: TimeInterval
    var observedSpanSeconds: TimeInterval
    var depletionPercentPerSecond: Double
}

/// A measured-percentage trend, independent of pack capacity, motor RPM or ride recording.
/// Caller observes each fresh primary telemetry timestamp using fresh remaining GPS distance.
/// Destination changes must reset the estimator because distance progress is target-specific.
struct ArrivalBatteryEstimator {
    private struct Observation {
        var date: Date
        var percent: Double
        var remainingDistance: Double
    }
    private var observations: [Observation] = []
    private var source: String?
    private var inputIssue = "Gathering a steady consumption trend"
    private static let maximumGap: TimeInterval = 6
    private static let window: TimeInterval = 180
    var observationCount: Int { observations.count }

    mutating func reset() {
        observations.removeAll()
        source = nil
        inputIssue = "Gathering a steady consumption trend"
    }

    mutating func observe(percent: Double?, source newSource: String?, at date: Date,
                          distanceMeters: Double?, isTelemetryFresh: Bool) {
        guard isTelemetryFresh, let percent, percent.isFinite, (0...100).contains(percent),
              let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0,
              let newSource, !newSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              date.timeIntervalSince1970.isFinite, (0...7_258_118_400).contains(date.timeIntervalSince1970) else {
            reset()
            inputIssue = "Fresh battery and GPS observations are required"
            return
        }
        if let last = observations.last {
            let gap = date.timeIntervalSince(last.date)
            if gap < 0 {
                reset()
                inputIssue = "Observation time changed; gathering a new trend"
                return
            }
            if source != newSource || gap > Self.maximumGap { reset() }
            else if gap == 0 { return }
        }
        source = newSource
        observations.append(Observation(date: date, percent: percent, remainingDistance: distanceMeters))
        observations.removeAll { date.timeIntervalSince($0.date) > Self.window }
        if observations.count > 181 { observations.removeFirst(observations.count - 181) }
        inputIssue = "Gathering a steady consumption trend"
    }

    var unavailableReason: String {
        predictionUnavailableReason(etaSeconds: 1, now: Date()) ?? "Prediction available from recent measured consumption"
    }

    func prediction(etaSeconds: Double?, reservePercent: Double = 20, now: Date = Date()) -> ArrivalBatteryPrediction? {
        guard predictionUnavailableReason(etaSeconds: etaSeconds, reservePercent: reservePercent, now: now) == nil,
              let etaSeconds, let last = observations.last, let trend = trend() else { return nil }
        let sampleAge = now.timeIntervalSince(last.date)
        let arrival = last.percent - trend.rate * (etaSeconds + sampleAge)
        guard arrival.isFinite else { return nil }
        return ArrivalBatteryPrediction(arrivalPercent: arrival,
            reserveShortfallPercent: max(0, reservePercent - arrival),
            willExhaustBeforeArrival: arrival < 0,
            secondsUntilEmpty: max(0, last.percent / trend.rate - sampleAge),
            observedSpanSeconds: trend.span,
            depletionPercentPerSecond: trend.rate)
    }

    func predictionUnavailableReason(etaSeconds: Double?, reservePercent: Double = 20, now: Date = Date()) -> String? {
        guard let etaSeconds, etaSeconds.isFinite, etaSeconds >= 0,
              etaSeconds < Double(Int.max), reservePercent.isFinite, (0...100).contains(reservePercent) else {
            return "A valid straight-line ETA and reserve are required"
        }
        guard let first = observations.first, let last = observations.last else { return inputIssue }
        let age = now.timeIntervalSince(last.date)
        guard age.isFinite, age >= 0, age <= Self.maximumGap else { return "Battery trend is stale" }
        let span = last.date.timeIntervalSince(first.date)
        guard observations.count >= 8, span >= 60 else { return "Gathering at least 60 seconds of continuous observations" }
        guard first.remainingDistance - last.remainingDistance >= 50 else { return "Make steady progress toward the destination first" }
        guard first.percent - last.percent >= 0.5 else { return "Battery percentage is flat or rising" }
        guard let trend = trend(), trend.rate > 0, trend.rSquared >= 0.6 else { return "Consumption trend is too variable to predict" }
        let arrival = last.percent - trend.rate * (etaSeconds + age)
        guard arrival.isFinite, (last.percent / trend.rate).isFinite else { return "Consumption trend cannot support a finite prediction" }
        return nil
    }

    private func trend() -> (rate: Double, span: TimeInterval, rSquared: Double)? {
        guard let first = observations.first, let last = observations.last, observations.count >= 2 else { return nil }
        let count = Double(observations.count)
        let meanTime = observations.reduce(0) { $0 + $1.date.timeIntervalSince(first.date) } / count
        let meanPercent = observations.reduce(0) { $0 + $1.percent } / count
        var varianceTime = 0.0, variancePercent = 0.0, covariance = 0.0
        for observation in observations {
            let x = observation.date.timeIntervalSince(first.date) - meanTime
            let y = observation.percent - meanPercent
            varianceTime += x * x
            variancePercent += y * y
            covariance += x * y
        }
        guard varianceTime > 0, variancePercent > 0 else { return nil }
        let rate = -covariance / varianceTime
        let rSquared = covariance * covariance / (varianceTime * variancePercent)
        return rate.isFinite && rSquared.isFinite ? (rate, last.date.timeIntervalSince(first.date), rSquared) : nil
    }
}
