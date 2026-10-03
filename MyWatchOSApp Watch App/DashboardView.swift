import SwiftUI

/// Critical glance sized for the smallest supported Watch.
struct DashboardView: View {
    @ObservedObject var rtStats: VESCRtStats
    let displaySpeed: Double
    let speedUnit: GPSSpeedUnit
    let speedAvailable: Bool
    let connectionMessage: String
    let isRecording: Bool
    let now: Date
    private var fresh: Bool { rtStats.isFresh(now: now) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(fresh ? Color.cyan : Color.orange).frame(width: 5, height: 5)
                    Text(fresh ? "LIVE" : (rtStats.isConnected ? "STALE DATA" : "RECONNECTING"))
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(fresh ? Color.cyan : Color.orange)
                    Spacer()
                    if isRecording {
                        Label("REC", systemImage: "record.circle.fill")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                    }
                }.accessibilityElement(children: .combine)
                Text(speedAvailable ? String(format: "%.1f", displaySpeed) : "—")
                    .font(.system(size: min(geometry.size.height * 0.23, 48), weight: .bold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityLabel(speedAvailable ? "GPS speed \(String(format: "%.1f", displaySpeed)) \(speedUnit.rawValue)" : "GPS speed unavailable")
                Text(speedAvailable ? "GPS · \(speedUnit.rawValue)" : "GPS unavailable")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    metric("POWER", value: fresh ? String(format: "%.0f", rtStats.instantWatts) : "—", unit: "W")
                    metric("BATTERY", value: fresh && rtStats.batteryPercentIsAvailable ? String(format: "%.0f", rtStats.batteryPercent) : "—", unit: "% est.")
                }.padding(.top, 2)
                HStack(spacing: 8) {
                    metric("CTRL", value: fresh ? String(format: "%.0f", rtStats.mosTemperature) : "—", unit: "°C")
                    metric("MOTOR", value: fresh ? String(format: "%.0f", rtStats.motorTemperature) : "—", unit: "°C")
                }
                Text(fresh ? String(format: "%.1f V", rtStats.batteryVoltage) : "Waiting for fresh telemetry")
                    .font(.system(size: 10)).foregroundStyle(fresh ? Color.secondary : Color.orange)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }.padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
        }
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
            }.lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title) \(value) \(unit)")
    }
}

/// Synthetic samples never enter SessionLogger or the shared complication store.
struct DemoWatchView: View {
    let onExit: () -> Void
    @StateObject private var stats = VESCRtStats()
    @State private var tab = 0
    @State private var simulateGap = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DEMO · SAMPLE DATA").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                Spacer()
                Button(action: onExit) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Exit demo")
            }.padding(.horizontal, 8)
            TabView(selection: $tab) {
                TimelineView(.periodic(from: .now, by: 2)) { timeline in
                    DashboardView(rtStats: stats, displaySpeed: 18.4, speedUnit: .kph,
                                  speedAvailable: true, connectionMessage: "", isRecording: true, now: timeline.date)
                        .onChange(of: timeline.date) { _, _ in loadSample() }
                }.tag(0)
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
                    }.font(.caption).padding(.horizontal, 8)
                }.tag(1)
                ScrollView {
                    VStack(spacing: 7) {
                        Text("Sample destination").font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "location.north.fill").font(.system(size: 42)).rotationEffect(.degrees(35)).foregroundStyle(.cyan)
                        Text("850 m").font(.title3.bold())
                        Text("Est. arrival 02:46").font(.caption)
                        Text("Straight-line guidance only.").font(.caption2).foregroundStyle(.secondary)
                    }
                }.tag(2)
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
    }

    private func loadSample() {
        stats.updateStats(batteryVoltage: 46.8, inputCurrent: 18.2, mosTemperature: 42,
                          motorTemperature: 48, wattHours: 128.4, rpm: 3450,
                          batteryPercent: 76, isConnected: !simulateGap)
        if !simulateGap { stats.markTelemetryReceived() }
    }
}
