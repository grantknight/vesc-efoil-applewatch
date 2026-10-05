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

/// Compact, glanceable navigation strings shared by the dashboard and navigation page.
/// Unavailable inputs always produce a dash, never a reassuring zero.
enum NavigationFormat {
    static func distance(_ meters: Double?) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "—" }
        // Tiers follow the rounded value, so 999.6 m reads "1.00 km" (not "1000 m") and
        // 9,996 m reads "10.0 km" (not "10.00 km").
        // Round explicitly (half away from zero) so the preview's Math.round gives identical text.
        if meters >= 9_995 { return String(format: "%.1f km", (meters / 100).rounded() / 10) }
        let wholeMeters = meters.rounded()
        if wholeMeters >= 1000 { return String(format: "%.2f km", (meters / 10).rounded() / 100) }
        return String(format: "%.0f m", wholeMeters)
    }

    /// Minutes and seconds under an hour ("3:05"), hours and minutes above ("1h 05m").
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let rounded = seconds.rounded()
        guard rounded < 360_000 else { return "—" } // 100 hours: no meaningful foil ETA
        let total = Int(rounded)
        if total >= 3600 { return "\(total / 3600)h " + String(format: "%02dm", total % 3600 / 60) }
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

/// How the projected arrival battery relates to the user's reserve.
enum ArrivalBatteryLevel: Equatable {
    case unavailable, aboveReserve, belowReserve, exhaustedBeforeArrival
}

/// One interpretation of a prediction for every surface, so the dashboard, navigation page,
/// browser preview and spoken labels cannot disagree. Percentages round down and shortfalls
/// round up, so the display never looks better than the estimate.
struct ArrivalBatterySummary: Equatable {
    let level: ArrivalBatteryLevel
    /// Dashboard value beside the arrival flag: "~64%", "~2%", "Empty" or "—".
    let glance: String
    /// Navigation page sentence.
    let detail: String
    /// VoiceOver sentence with spoken units.
    let spoken: String

    init(prediction: ArrivalBatteryPrediction?, reservePercent: Double) {
        let reserve = reservePercent.isFinite ? Int(min(100, max(0, reservePercent)).rounded()) : 0
        guard let prediction, prediction.arrivalPercent.isFinite else {
            level = .unavailable
            glance = "—"
            detail = "Arrival battery unavailable"
            spoken = "Arrival battery estimate unavailable"
            return
        }
        if prediction.willExhaustBeforeArrival || prediction.arrivalPercent < 0 {
            level = .exhaustedBeforeArrival
            glance = "Empty"
            detail = "Battery runs out before arrival"
            spoken = "Battery projected to run out before arrival"
            return
        }
        let arrival = Int(floor(min(100, prediction.arrivalPercent)))
        if prediction.reserveShortfallPercent > 0 {
            let shortfall = Int(ceil(prediction.reserveShortfallPercent))
            level = .belowReserve
            glance = "~\(arrival)%"
            detail = "Arrival ~\(arrival)% · \(shortfall)% under \(reserve)% reserve"
            spoken = "Estimated battery at arrival about \(arrival) percent, \(shortfall) percent below the \(reserve) percent reserve"
        } else {
            level = .aboveReserve
            glance = "~\(arrival)%"
            detail = "Arrival ~\(arrival)% · reserve \(reserve)%"
            spoken = "Estimated battery at arrival about \(arrival) percent, above the \(reserve) percent reserve"
        }
    }
}
