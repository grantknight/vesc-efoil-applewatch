import SwiftUI
import CoreLocation

struct DashboardView: View {
    @ObservedObject var rtStats: VESCRtStats
    let displaySpeed: Double
    let speedUnit: GPSSpeedUnit
    let speedAvailable: Bool
    let connectionMessage: String
    let isRecording: Bool
    let now: Date
    var usesSampleData = false
    var directionAngle: Double? = nil
    var directionReference = "Direction unavailable"
    var navigationDistance = "Destination —"
    var destinationETA = "ETA —"
    var arrivalBatterySummary = "Arrival battery —"
    var reserveWarning = false
    var onDestinationTap: () -> Void = {}

    private let sportColor = Color(red: 0.48, green: 0.96, blue: 0.69)
    private var fresh: Bool { usesSampleData ? rtStats.isConnected : rtStats.isFresh(now: now) }
    private var batteryAvailable: Bool { usesSampleData ? rtStats.batteryPercentSource == .demo : rtStats.batteryPercentIsAvailable }
    private var faultAvailable: Bool { fresh && (usesSampleData ? rtStats.faultCode != nil : rtStats.faultIsAvailable(now: now)) }
    private var activeFault: UInt8? { faultAvailable ? rtStats.faultCode.flatMap { $0 == 0 ? nil : $0 } : nil }
    private var status: String {
        if usesSampleData { return fresh ? "SAMPLE" : "SAMPLE GAP" }
        return fresh ? "LIVE" : (rtStats.isConnected ? "STALE DATA" : "RECONNECTING")
    }
    private var faultText: String {
        if let code = activeFault { return "ESC faults: \(code) · \(VescFaultCode.label(for: code))" }
        return faultAvailable ? "ESC faults: None" : "ESC faults: Unavailable"
    }

    var body: some View {
        GeometryReader { geometry in
            // Budget the entire viewport: the Watch clock, demo header and page dots
            // have already consumed space outside this geometry on the smallest Watch.
            let gap: CGFloat = 2
            let statusHeight: CGFloat = 9
            let faultHeight: CGFloat = 24
            let available = max(0, geometry.size.height - statusHeight - faultHeight - gap * 4)
            let heroHeight = available * 0.45
            let tileHeight = available * 0.275
            let valueSize = min(30, max(17, tileHeight * 0.80))
            // Speed is the hero reading: stay visibly larger than the four tiles at
            // every Watch size while leaving room for the GPS unit caption below it.
            let speedSize = min(40, max(17, min(heroHeight - 13, max(heroHeight * 0.62, valueSize + 5))))
            // Destination captions grow to 8pt only where the hero row can hold
            // them; the smallest Watch keeps the screenshot-verified 7pt budget.
            let captionSize: CGFloat = heroHeight >= 46 ? 8 : 7
            // The dial budgets its own height so a larger speed cannot push the
            // destination distance, ETA and arrival lines out of the hero row. The
            // floor stays below the caption budget even on degenerate geometries,
            // so the hero row never overflows onto the telemetry tiles.
            let needleSize = max(14, min(speedSize + 2, heroHeight - (captionSize * 2 + 6)))
            VStack(spacing: gap) {
                HStack {
                    Text("● \(status)").foregroundStyle(fresh ? sportColor : .orange)
                    Spacer()
                    if isRecording { Text("● REC").foregroundStyle(.red) }
                }.font(.system(size: 8, weight: .bold)).frame(height: statusHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Telemetry \(status.lowercased())\(isRecording ? ". Recording ride" : "")")
                HStack(spacing: 5) {
                    VStack(spacing: 1) {
                        Text(speedAvailable ? String(format: "%.1f", displaySpeed) : "—")
                            .font(.system(size: speedSize, weight: .bold, design: .rounded))
                            .foregroundStyle(sportColor).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                            .frame(height: speedSize + 2)
                        Text(speedAvailable ? "GPS · \(speedUnit.displayLabel)" : "GPS unavailable")
                            .font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(speedAvailable ? "GPS ground speed \(String(format: "%.1f", displaySpeed)) \(speedUnit.displayLabel)" : "GPS speed unavailable")
                    Button(action: onDestinationTap) {
                        VStack(spacing: 1) {
                            DestinationCompassNeedle(angle: directionAngle, color: sportColor)
                                .frame(width: needleSize, height: needleSize)
                            Text(navigationDistance + " · " + destinationETA)
                                .foregroundStyle(sportColor).font(.system(size: captionSize, weight: .semibold))
                            Text(arrivalBatterySummary)
                                .foregroundStyle(reserveWarning ? Color.orange : Color(white: 0.78))
                                .font(.system(size: captionSize, weight: reserveWarning ? .bold : .medium))
                        }.lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }.buttonStyle(.plain).accessibilityIdentifier("destination-arrow")
                        .accessibilityLabel("Destination setup. \(directionAngle == nil ? "Direction unavailable" : directionReference). \(navigationDistance). \(destinationETA). \(arrivalBatterySummary)")
                }.frame(height: heroHeight)
                HStack(spacing: 5) {
                    tile("POWER", value: fresh ? String(format: "%.0f", rtStats.instantWatts) : "—", unit: "W", size: valueSize, height: tileHeight)
                    tile("BATTERY", value: fresh && batteryAvailable ? String(format: "%.0f", rtStats.batteryPercent) : "—", unit: "%", size: valueSize, height: tileHeight,
                         accessibilityDetail: fresh && batteryAvailable ? "Estimated percentage. " + rtStats.batterySourceLabel : "Battery estimate unavailable")
                }
                HStack(spacing: 5) {
                    tile("ESC temperature", value: fresh ? String(format: "%.0f", rtStats.mosTemperature) : "—", unit: "°C", size: valueSize, height: tileHeight)
                    tile("VOLTAGE", value: fresh ? String(format: "%.1f", rtStats.batteryVoltage) : "—", unit: "V", size: valueSize, height: tileHeight)
                }
                Text(faultText).font(.system(size: 9, weight: .bold))
                    .foregroundStyle(activeFault != nil ? Color.red : (faultAvailable ? sportColor : Color.orange))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: faultHeight, maxHeight: faultHeight)
                    .background((activeFault != nil ? Color.red : (faultAvailable ? sportColor : Color.orange)).opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke((activeFault != nil ? Color.red : (faultAvailable ? sportColor : Color.orange)).opacity(0.65), lineWidth: 0.7))
                    .accessibilityIdentifier(activeFault != nil ? "esc-fault-warning" : "esc-fault-status")
            }.padding(.horizontal, 5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(.black)
        }
    }

    private func tile(_ label: String, value: String, unit: String, size: CGFloat, height: CGFloat, accessibilityDetail: String = "") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.system(size: min(13, max(10, size * 0.44)), weight: .semibold)).foregroundStyle(.white.opacity(0.9))
        }.lineLimit(1).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(sportColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(label) \(value) \(unit). \(accessibilityDetail)")
    }
}

/// A true direction is drawn only when the caller has a fresh heading/course and bearing.
/// The neutral face remains tappable when direction is unavailable. The filled face,
/// firmer ring/ticks and two-facet pointer mirror the approved Sport preview dial so
/// the arrow stays findable at a glance in bright outdoor light.
struct DestinationCompassNeedle: View {
    let angle: Double?
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.10))
            Circle().stroke(color.opacity(0.38), lineWidth: 0.8)
            DashboardCompassTicks().stroke(Color.white.opacity(0.5), lineWidth: 0.8)
            if let angle, angle.isFinite {
                ZStack {
                    DashboardNeedleHalf(pointsNorth: false).fill(color.opacity(0.35))
                    DashboardNeedleFacet(leading: true).fill(color)
                    DashboardNeedleFacet(leading: false).fill(Color.white.opacity(0.88))
                }.rotationEffect(.degrees(angle))
                Circle().fill(Color.white.opacity(0.95)).frame(width: 3, height: 3)
                    .overlay(Circle().stroke(Color.black, lineWidth: 0.7))
            } else {
                Text("—").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
        }.accessibilityHidden(true)
    }
}

private struct DashboardNeedleHalf: Shape {
    let pointsNorth: Bool

    func path(in rect: CGRect) -> Path {
        let tipY = pointsNorth ? rect.minY + rect.height * 0.08 : rect.maxY - rect.height * 0.08
        let baseY = pointsNorth ? rect.midY + rect.height * 0.04 : rect.midY - rect.height * 0.04
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: tipY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.12, y: baseY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.12, y: baseY))
        path.closeSubpath()
        return path
    }
}

/// One side of the forward pointer, split along its axis so the two facets can
/// carry different brightness like the preview needle.
private struct DashboardNeedleFacet: Shape {
    let leading: Bool

    func path(in rect: CGRect) -> Path {
        let tipY = rect.minY + rect.height * 0.08
        let baseY = rect.midY + rect.height * 0.04
        let baseX = leading ? rect.midX - rect.width * 0.12 : rect.midX + rect.width * 0.12
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: tipY))
        path.addLine(to: CGPoint(x: baseX, y: baseY))
        path.addLine(to: CGPoint(x: rect.midX, y: baseY))
        path.closeSubpath()
        return path
    }
}

private struct DashboardCompassTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.09))
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.09))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.09, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.09, y: rect.midY))
        return path
    }
}

/// Synthetic samples never enter SessionLogger or the shared complication store.
struct DemoWatchView: View {
    let onExit: () -> Void
    @StateObject private var stats = VESCRtStats()
    @StateObject private var destinationManager = DestinationManager(persists: false)
    @State private var tab = ProcessInfo.processInfo.arguments.contains { ["--demo-bms", "--demo-bms-unavailable"].contains($0) } ? 4 : (ProcessInfo.processInfo.arguments.contains("--demo-navigation") ? 2 : 0)
    @State private var simulateGap = false
    @State private var simulateFault = ProcessInfo.processInfo.arguments.contains("--demo-fault")
    @State private var showDestination = ProcessInfo.processInfo.arguments.contains("--demo-destination")
    private let sampleCoordinate = CLLocationCoordinate2D(latitude: 37.775, longitude: -122.4194)
    @State private var sampleEstimator = ArrivalBatteryEstimator()
    @State private var fixtureTime = Date()
    @State private var pointsInitialized = false
    private var lowBatteryFixture: Bool { ProcessInfo.processInfo.arguments.contains("--demo-navigation") }
    private var sampleDistance: Double? { destinationManager.distance(from: sampleCoordinate) }
    private var sampleETA: Double? { NavigationEstimate.etaSeconds(distanceMeters: sampleDistance, speedMs: 18.4 / 3.6) }
    private var isFixtureTarget: Bool {
        destinationManager.destinationKind == .finish
            && destinationManager.destination?.latitude == 37.7825
            && destinationManager.destination?.longitude == -122.415
    }
    private var samplePrediction: ArrivalBatteryPrediction? {
        guard !simulateGap, isFixtureTarget else { return nil }
        return sampleEstimator.prediction(etaSeconds: sampleETA, reservePercent: destinationManager.reservePercent, now: fixtureTime)
    }
    private var sampleArrivalSummary: String {
        guard let prediction = samplePrediction else { return "Arrival battery —" }
        if prediction.willExhaustBeforeArrival { return "Runs out before arrival" }
        if prediction.reserveShortfallPercent > 0 { return String(format: "Arrival ~%.0f%% · short %.0f%%", floor(max(0, prediction.arrivalPercent)), ceil(prediction.reserveShortfallPercent)) }
        return String(format: "Arrival ~%.0f%%", floor(max(0, prediction.arrivalPercent)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DEMO · SAMPLE DATA").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                Spacer()
                Button(action: onExit) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Exit demo")
            }.padding(.horizontal, 8)
            TabView(selection: $tab) {
                DashboardView(rtStats: stats, displaySpeed: 18.4, speedUnit: .kph,
                              speedAvailable: true, connectionMessage: "", isRecording: true,
                              now: Date(), usesSampleData: true,
                              directionAngle: destinationManager.arrowAngle(current: sampleCoordinate, heading: 0), directionReference: "GPS course",
                              navigationDistance: destinationManager.formattedDistance(sampleDistance).replacingOccurrences(of: "Distance: ", with: ""),
                              destinationETA: destinationManager.formattedETA(sampleETA).replacingOccurrences(of: "ETA: ", with: ""),
                              arrivalBatterySummary: sampleArrivalSummary,
                              reserveWarning: (samplePrediction?.reserveShortfallPercent ?? 0) > 0,
                              onDestinationTap: { showDestination = true }).tag(0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Sample ride").font(.headline).foregroundStyle(.cyan)
                        Text("Duration  24:16")
                        Text("GPS distance  5.82 km")
                        Text("Energy  128.4 Wh")
                        Text("Peak power  1,840 W")
                        Text("Synthetic session. Nothing is saved.").font(.caption2).foregroundStyle(.secondary)
                        Button(simulateGap ? "Restore sample connection" : "Simulate disconnect") {
                            simulateGap.toggle(); loadSample()
                        }
                        Button(simulateFault ? "Clear sample ESC fault" : "Simulate ESC fault") {
                            simulateFault.toggle(); loadSample()
                        }
                        Button("Sample 12S BMS cells") { tab = 4 }
                    }.font(.caption).padding(.horizontal, 8)
                }.tag(1)
                NavigationSummaryView(destinationManager: destinationManager, currentCoordinate: sampleCoordinate,
                    heading: 0, eta: sampleETA, prediction: samplePrediction,
                    unavailableReason: simulateGap ? "Sample connection gap" : "No consumption trend for this sample target", directionReference: "GPS course", usesSampleData: true).tag(2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sample history").font(.headline).foregroundStyle(.cyan)
                        Text("Morning ride · 24 min")
                        Text("5.82 km · 128 Wh")
                        Divider()
                        Text("Evening ride · 18 min")
                        Text("4.12 km · 92 Wh")
                        Text("These examples are not saved rides.").font(.caption2).foregroundStyle(.secondary)
                        Button("Exit demo", action: onExit)
                    }.font(.caption).padding(.horizontal, 8)
                }.tag(3)
                BMSDemoView(unavailable: ProcessInfo.processInfo.arguments.contains("--demo-bms-unavailable")).tag(4)
            }.tabViewStyle(.page)
        }.onAppear(perform: loadSample)
            .sheet(isPresented: $showDestination) {
                DestinationPickerView(destinationManager: destinationManager, currentCoordinate: sampleCoordinate, usesSampleData: true)
            }
    }

    private func loadSample() {
        stats.updateStats(batteryVoltage: 46.8, inputCurrent: 18.2, mosTemperature: 42,
                          wattHours: 128.4, rpm: 3450,
                          batteryPercent: lowBatteryFixture ? 14 : 76, isConnected: !simulateGap)
        stats.updateFaultCode(simulateFault ? 1 : 0)
        fixtureTime = Date()
        sampleEstimator.reset()
        // Fixed simulation clock makes fixture screenshots deterministic without inventing live packets.
        for step in 0...45 {
            let percent = (lowBatteryFixture ? 20.0 : 82.0) - Double(step) * (6.0 / 45.0)
            sampleEstimator.observe(percent: percent, source: "synthetic fixture", at: fixtureTime.addingTimeInterval(Double(step * 2 - 90)),
                distanceMeters: 1400 - Double(step) * (480.0 / 45.0), isTelemetryFresh: true)
        }
        if !pointsInitialized {
            pointsInitialized = true
            destinationManager.setDestination(CLLocationCoordinate2D(latitude: 37.7825, longitude: -122.415), name: "Finish")
            destinationManager.saveLaunchPoint(CLLocationCoordinate2D(latitude: 37.77, longitude: -122.423), name: "Launch beach")
        }
    }
}
