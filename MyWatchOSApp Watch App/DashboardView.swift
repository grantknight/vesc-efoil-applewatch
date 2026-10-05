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
    var hasDestination = true
    var navigationDistance = "—"
    var destinationETA = "—"
    var arrival = ArrivalBatterySummary(prediction: nil, reservePercent: 20)
    var onDestinationTap: () -> Void = {}

    /// Always-On (wrist down) throttles redraws to about once a minute, so a frame must not
    /// keep claiming LIVE for values that can no longer be re-checked every second.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    private let sportColor = SportPalette.accent
    private var fresh: Bool { usesSampleData ? rtStats.isConnected : rtStats.isFresh(now: now) }
    private var wristDown: Bool { isLuminanceReduced && !usesSampleData }
    private var batteryAvailable: Bool { usesSampleData ? rtStats.batteryPercentSource == .demo : rtStats.batteryPercentIsAvailable }
    private var faultAvailable: Bool { fresh && (usesSampleData ? rtStats.faultCode != nil : rtStats.faultIsAvailable(now: now)) }
    private var activeFault: UInt8? { faultAvailable ? rtStats.faultCode.flatMap { $0 == 0 ? nil : $0 } : nil }
    private var status: String {
        if usesSampleData { return fresh ? "SAMPLE" : "SAMPLE GAP" }
        if wristDown { return "WRIST DOWN" }
        return fresh ? "LIVE" : (rtStats.isConnected ? "STALE DATA" : "RECONNECTING")
    }
    private var faultText: String {
        if let code = activeFault { return "ESC faults: \(code) · \(VescFaultCode.label(for: code))" }
        // A wrist-down frame can be a minute old, so it never shows a green all-clear.
        if wristDown { return "ESC faults: raise wrist to check" }
        return faultAvailable ? "ESC faults: None" : "ESC faults: Unavailable"
    }
    private var faultColor: Color { activeFault != nil ? SportPalette.fault : (faultAvailable && !wristDown ? sportColor : SportPalette.caution) }
    private var arrivalColor: Color {
        switch arrival.level {
        case .exhaustedBeforeArrival: return SportPalette.fault
        case .belowReserve: return SportPalette.caution
        case .aboveReserve: return SportPalette.secondaryText
        case .unavailable: return SportPalette.mutedText
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Budget the whole viewport. Speed is the hero reading and must stay larger than
            // the four tiles; the dial sits beside its three destination lines so neither the
            // arrow nor the text has to shrink to fit under the other on a 40 mm Watch.
            let gap: CGFloat = 3
            let statusHeight: CGFloat = 12
            let faultHeight: CGFloat = 24
            let available = max(0, geometry.size.height - statusHeight - faultHeight - gap * 3)
            let heroHeight = available * 0.46
            let tileHeight = available * 0.27
            let valueSize = min(32, max(17, tileHeight * 0.80))
            let speedSize = min(44, max(valueSize + 2, heroHeight - 17))
            let columnWidth = max(0, (geometry.size.width - 10 - 6) / 2)
            let dialSize = max(14, min(heroHeight, columnWidth * 0.48))
            let captionSize = min(13, heroHeight / 3.6, max(9.5, heroHeight * 0.25))
            VStack(spacing: gap) {
                HStack {
                    Text("● \(status)").foregroundStyle(fresh && !wristDown ? sportColor : SportPalette.caution)
                    Spacer()
                    if isRecording { Text("● REC").foregroundStyle(SportPalette.fault) }
                }.font(.system(size: 10, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(height: statusHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Telemetry \(status.lowercased())\(isRecording ? ". Recording ride" : "")")
                HStack(spacing: 6) {
                    VStack(spacing: 1) {
                        Text(speedAvailable ? String(format: "%.1f", displaySpeed) : "—")
                            .font(.system(size: speedSize, weight: .bold, design: .rounded))
                            .foregroundStyle(wristDown ? SportPalette.secondaryText : sportColor).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            .frame(height: speedSize + 2)
                        Text(speedAvailable ? "GPS \(speedUnit.displayLabel)" : "GPS unavailable")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(SportPalette.secondaryText)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(speedAvailable ? "GPS ground speed \(String(format: "%.1f", displaySpeed)) \(speedUnit.spokenLabel)" : "GPS speed unavailable")
                    Button(action: onDestinationTap) {
                        HStack(spacing: 4) {
                            DestinationCompassNeedle(angle: directionAngle, color: sportColor)
                                .frame(width: dialSize, height: dialSize)
                            VStack(alignment: .leading, spacing: 0) {
                                if hasDestination {
                                    Text(navigationDistance).foregroundStyle(wristDown ? SportPalette.secondaryText : sportColor)
                                    Text(destinationETA).foregroundStyle(wristDown ? SportPalette.secondaryText : SportPalette.primaryText)
                                    (Text(Image(systemName: "flag.checkered")).font(.system(size: captionSize * 0.8))
                                        + Text(" " + arrival.glance))
                                        .foregroundStyle(arrivalColor)
                                } else {
                                    Text("Set").foregroundStyle(sportColor)
                                    Text("point").foregroundStyle(sportColor)
                                }
                            }.font(.system(size: captionSize, weight: .semibold, design: .rounded)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("destination-arrow")
                        .accessibilityLabel(destinationAccessibilityLabel)
                }.frame(height: heroHeight)
                HStack(spacing: 6) {
                    tile("Power", value: tileValue(String(format: "%.0f", rtStats.instantWatts)), unit: "W", spokenUnit: "watts", size: valueSize, height: tileHeight)
                    tile("Battery", value: tileValue(batteryAvailable ? String(format: "%.0f", rtStats.batteryPercent) : nil), unit: "%", spokenUnit: "percent", size: valueSize, height: tileHeight,
                         accessibilityDetail: fresh && batteryAvailable ? "Estimated percentage. " + rtStats.batterySourceLabel : "Battery estimate unavailable")
                }
                HStack(spacing: 6) {
                    tile("ESC temperature", value: tileValue(String(format: "%.0f", rtStats.mosTemperature)), unit: "°C", spokenUnit: "degrees Celsius", size: valueSize, height: tileHeight)
                    tile("Pack voltage", value: tileValue(String(format: "%.1f", rtStats.batteryVoltage)), unit: "V", spokenUnit: "volts", size: valueSize, height: tileHeight)
                }
                Text(faultText).font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(faultColor)
                    .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: faultHeight, maxHeight: faultHeight)
                    .background(faultColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(faultColor.opacity(0.7), lineWidth: 1))
                    .accessibilityIdentifier(activeFault != nil ? "esc-fault-warning" : "esc-fault-status")
            }.padding(.horizontal, 5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(.black)
        }
    }

    private var destinationAccessibilityLabel: String {
        guard hasDestination else { return "Destination setup. No destination set" }
        let direction = directionAngle == nil ? "Direction unavailable" : directionReference
        return "Destination setup. \(direction). Distance \(navigationDistance). Time to arrival \(destinationETA). \(arrival.spoken)"
    }

    /// Stale values are never shown as current; wrist-down frames keep the value but grey it.
    private func tileValue(_ value: String?) -> String { fresh ? (value ?? "—") : "—" }

    private func tile(_ label: String, value: String, unit: String, spokenUnit: String, size: CGFloat, height: CGFloat, accessibilityDetail: String = "") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(wristDown ? SportPalette.secondaryText : SportPalette.primaryText)
            Text(unit).font(.system(size: min(15, max(10, size * 0.48)), weight: .semibold)).foregroundStyle(SportPalette.unitText)
        }.lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(sportColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(sportColor.opacity(0.22), lineWidth: 0.75))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value == "—" ? "\(label) unavailable. \(accessibilityDetail)" : "\(label) \(value) \(spokenUnit). \(accessibilityDetail)")
    }
}

/// Shared Sport colours. Text colours are chosen for contrast on pure black in daylight.
enum SportPalette {
    static let accent = Color(red: 0.48, green: 0.96, blue: 0.69)
    static let caution = Color(red: 1.0, green: 0.70, blue: 0.30)
    static let fault = Color(red: 1.0, green: 0.36, blue: 0.38)
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.80)
    static let unitText = Color(white: 0.86)
    static let mutedText = Color(white: 0.62)
}

/// A true direction is drawn only when the caller has a fresh heading/course and bearing.
/// The arrow is relative to the wearer's heading, so the top index marks "ahead". The neutral
/// face stays tappable when direction is unavailable.
struct DestinationCompassNeedle: View {
    let angle: Double?
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let line = max(1, size * 0.035)
            ZStack {
                Circle().fill(color.opacity(0.12))
                if let angle, angle.isFinite {
                    Circle().stroke(color.opacity(0.55), lineWidth: line)
                    DashboardCompassTicks().stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    DashboardAheadIndex().fill(Color.white)
                    ZStack {
                        DashboardNeedleTail().fill(color.opacity(0.35))
                        DashboardNeedleFacet(leading: true).fill(color)
                        DashboardNeedleFacet(leading: false).fill(Color(red: 0.80, green: 1.0, blue: 0.88))
                    }.rotationEffect(.degrees(angle))
                    Circle().fill(Color.white).frame(width: max(3, size * 0.12), height: max(3, size * 0.12))
                        .overlay(Circle().stroke(Color.black, lineWidth: max(0.7, size * 0.025)))
                } else {
                    Circle().stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: line, dash: [max(2, size * 0.07), max(2, size * 0.06)]))
                    Text("—").font(.system(size: max(9, size * 0.32), weight: .bold)).foregroundStyle(SportPalette.mutedText)
                }
            }.frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityHidden(true)
    }
}

/// Short dim tail opposite the pointer, so the forward end is unambiguous at a glance.
private struct DashboardNeedleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.13, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.13, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// One side of the forward pointer; two facets with different brightness read as a solid
/// arrow in glare without relying on fine detail.
private struct DashboardNeedleFacet: Shape {
    let leading: Bool

    func path(in rect: CGRect) -> Path {
        let tipY = rect.minY + rect.height * 0.10
        let baseY = rect.midY + rect.height * 0.06
        let baseX = leading ? rect.midX - rect.width * 0.15 : rect.midX + rect.width * 0.15
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: tipY))
        path.addLine(to: CGPoint(x: baseX, y: baseY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Fixed "ahead" marker at twelve o'clock: the needle points relative to this mark.
private struct DashboardAheadIndex: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.13))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.07, y: rect.minY - rect.height * 0.01))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.07, y: rect.minY - rect.height * 0.01))
        path.closeSubpath()
        return path
    }
}

/// East, south and west ticks; north is the filled "ahead" index.
private struct DashboardCompassTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
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
    private var sampleArrival: ArrivalBatterySummary {
        ArrivalBatterySummary(prediction: samplePrediction, reservePercent: destinationManager.reservePercent)
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
                              hasDestination: destinationManager.destination != nil,
                              navigationDistance: NavigationFormat.distance(sampleDistance),
                              destinationETA: NavigationFormat.duration(sampleETA),
                              arrival: sampleArrival,
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
