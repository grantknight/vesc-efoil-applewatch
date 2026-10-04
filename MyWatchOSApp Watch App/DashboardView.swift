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
    var navigationSummary = "Tap arrow to choose destination"
    var reserveSummary = "Reserve 20% · estimate unavailable"
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

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 190
            VStack(spacing: compact ? 2 : 4) {
                HStack {
                    Text("● \(status)").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(fresh ? sportColor : .orange)
                    Spacer()
                    if isRecording { Text("● REC").font(.system(size: 9, weight: .bold)).foregroundStyle(.red) }
                }
                if let code = activeFault {
                    Text("ESC FAULT \(code) · \(VescFaultCode.label(for: code))")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(3).background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityIdentifier("esc-fault-warning")
                }
                Text(speedAvailable ? String(format: "%.1f", displaySpeed) : "—")
                    .font(.system(size: min(geometry.size.height * (activeFault == nil ? 0.25 : 0.20), 49), weight: .bold, design: .rounded))
                    .foregroundStyle(sportColor).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel(speedAvailable ? "GPS ground speed \(String(format: "%.1f", displaySpeed)) \(speedUnit.displayLabel)" : "GPS speed unavailable")
                HStack(spacing: 6) {
                    Text(speedAvailable ? "GPS · \(speedUnit.displayLabel)" : "GPS unavailable")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Button(action: onDestinationTap) {
                        VStack(spacing: 0) {
                        Image(systemName: directionAngle == nil ? "location.circle" : "location.north.fill")
                            .font(.system(size: 16, weight: .bold))
                            .rotationEffect(.degrees(directionAngle ?? 0))
                            .foregroundStyle(sportColor)
                        Text(directionAngle == nil ? "SET" : (directionReference == "GPS course" ? "COURSE" : "COMPASS"))
                            .font(.system(size: 6, weight: .bold)).foregroundStyle(.secondary)
                        }.frame(width: 38, height: 29)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Destination setup")
                        .accessibilityIdentifier("destination-arrow")
                }
                HStack(spacing: 6) {
                    tile("POWER", value: fresh ? String(format: "%.0f", rtStats.instantWatts) : "—", unit: "W", compact: compact)
                    tile("BATTERY", value: fresh && batteryAvailable ? String(format: "%.0f", rtStats.batteryPercent) : "—", unit: "% est.", compact: compact)
                }
                HStack(spacing: 5) {
                    Text(fresh ? String(format: "ESC %.0f°C", rtStats.mosTemperature) : "ESC —")
                        .foregroundStyle(.white)
                    Text(faultAvailable ? (rtStats.faultCode == 0 ? "· No fault" : "· Fault") : "· Fault status —")
                        .foregroundStyle(faultAvailable && rtStats.faultCode == 0 ? Color.secondary : .orange)
                }.font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                Text(fresh ? String(format: "%.1f V", rtStats.batteryVoltage) + " · " + rtStats.batterySourceLabel : "Waiting for fresh telemetry")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                VStack(spacing: 1) {
                    Text(navigationSummary).foregroundStyle(sportColor)
                    Text(reserveSummary).foregroundStyle(reserveWarning ? Color.orange : Color.secondary)
                }.font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }.padding(.horizontal, 6).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
        }
    }

    private func tile(_ label: String, value: String, unit: String, compact: Bool) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: compact ? 21 : 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 8)).foregroundStyle(.secondary)
            }.lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity).padding(.vertical, compact ? 3 : 5)
            .background(sportColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(label) \(value) \(unit)")
    }
}

/// Synthetic samples never enter SessionLogger or the shared complication store.
struct DemoWatchView: View {
    let onExit: () -> Void
    @StateObject private var stats = VESCRtStats()
    @StateObject private var destinationManager = DestinationManager(persists: false)
    @State private var tab = ProcessInfo.processInfo.arguments.contains("--demo-navigation") ? 2 : 0
    @State private var simulateGap = false
    @State private var simulateFault = ProcessInfo.processInfo.arguments.contains("--demo-fault")
    @State private var showDestination = ProcessInfo.processInfo.arguments.contains("--demo-destination")
    private let sampleCoordinate = CLLocationCoordinate2D(latitude: 37.775, longitude: -122.4194)
    @State private var sampleEstimator = ArrivalBatteryEstimator()
    @State private var fixtureTime = Date()
    @State private var pointsInitialized = false
    private var lowBatteryFixture: Bool { ProcessInfo.processInfo.arguments.contains("--demo-navigation") }
    private var samplePrediction: ArrivalBatteryPrediction? {
        guard !simulateGap else { return nil }
        return sampleEstimator.prediction(etaSeconds: 180, reservePercent: destinationManager.reservePercent, now: fixtureTime)
    }
    private var sampleReserveSummary: String {
        guard let prediction = samplePrediction else { return "Arrival estimate unavailable" }
        if prediction.willExhaustBeforeArrival { return "Battery may run out before arrival" }
        if prediction.reserveShortfallPercent > 0 { return String(format: "Reserve short by %.0f%% · est.", ceil(prediction.reserveShortfallPercent)) }
        return String(format: "Arrival ~%.0f%% · reserve %.0f%%", prediction.arrivalPercent, destinationManager.reservePercent)
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
                              navigationSummary: destinationManager.destinationName + " · 920 m · 03:00",
                              reserveSummary: sampleReserveSummary,
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
                    }.font(.caption).padding(.horizontal, 8)
                }.tag(1)
                NavigationSummaryView(destinationManager: destinationManager, currentCoordinate: sampleCoordinate,
                    heading: 0, eta: 180, prediction: samplePrediction,
                    unavailableReason: "Sample connection gap", directionReference: "GPS course", usesSampleData: true).tag(2)
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
