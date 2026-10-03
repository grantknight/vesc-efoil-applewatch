import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager(
        startBluetooth: !ProcessInfo.processInfo.arguments.contains("--demo")
    )
    @State private var showDemo = ProcessInfo.processInfo.arguments.contains("--demo")
    @State private var showHistory = false

    var body: some View {
        Group {
            if showDemo {
                DemoWatchView { showDemo = false }
            } else if bluetoothManager.state == .connected {
                Home(bluetoothManager: bluetoothManager, showDemo: $showDemo)
            } else {
                ConnectionScreen(bluetoothManager: bluetoothManager, showDemo: $showDemo, showHistory: $showHistory)
            }
        }
        .sheet(isPresented: $showHistory) { RideHistoryView(logger: SessionLogger.shared) }
        .onChange(of: showDemo) { _, enabled in bluetoothManager.setDemoMode(enabled) }
    }

}

private struct ConnectionScreen: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject private var logger = SessionLogger.shared
    @Binding var showDemo: Bool
    @Binding var showHistory: Bool

    var body: some View {
        NavigationStack {
                    List {
                        Section {
                            Label(connectionTitle, systemImage: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.cyan)
                            Text(connectionDetail).font(.caption).foregroundStyle(.secondary)
                            if bluetoothManager.state == .connecting { ProgressView() }
                            ForEach(bluetoothManager.peripherals, id: \.identifier) { peripheral in
                                Button(peripheral.name ?? "VESC device") {
                                    bluetoothManager.connectPeripheral(peripheral: peripheral)
                                }
                            }
                            if bluetoothManager.state != .off {
                                Button(bluetoothManager.state == .connecting ? "Cancel connection" : "Scan again") {
                                    bluetoothManager.restart(withNewDevice: bluetoothManager.state == .connecting)
                                }
                            }
                        }
                        Section("Your rides") {
                            if let error = logger.storageError {
                                Text(error).font(.caption2).foregroundStyle(.orange)
                                Button("Retry storage") { logger.retryLoad() }
                            }
                            if logger.isRecording {
                                Text("Ride recording · reconnecting").foregroundStyle(.orange).font(.caption)
                                Button("Save ride") { logger.endRide() }
                            }
                            Button("Ride history") { showHistory = true }
                            Button("Preview app") { showDemo = true }
                            Text("Preview uses sample data.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Foil Assist")
                }
    }

    private var connectionTitle: String {
        switch bluetoothManager.state {
        case .off: return "Bluetooth unavailable"
        case .start: return "Starting Bluetooth"
        case .connecting: return "Connecting to VESC"
        default: return "Find your VESC"
        }
    }

    private var connectionDetail: String {
        switch bluetoothManager.state {
        case .off: return "Enable Bluetooth and allow access in Watch Settings."
        case .connecting: return bluetoothManager.connectionMessage.isEmpty ? "Keep your Watch near the controller." : bluetoothManager.connectionMessage
        default: return "Power on the controller and select its Bluetooth device below."
        }
    }
}

struct Home: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject private var rtStats: VESCRtStats
    @ObservedObject private var logger = SessionLogger.shared
    @Binding var showDemo: Bool
    @State private var tabSelected = 0
    @State private var isSettingsPresented = false
    @State private var showHistory = false
    @State private var confirmSave = false
    @StateObject private var locationManager = LocationManager()
    @StateObject private var destinationManager = DestinationManager()

    init(bluetoothManager: BluetoothManager, showDemo: Binding<Bool>) {
        self.bluetoothManager = bluetoothManager
        _showDemo = showDemo
        _rtStats = ObservedObject(wrappedValue: bluetoothManager.vescRtStats)
    }

    private var speedUnit: GPSSpeedUnit { locationManager.getSpeedUnit() }
    private var displaySpeed: Double { locationManager.hasFreshSpeed ? locationManager.speed : 0 }
    private var travelSpeedMs: Double { locationManager.hasFreshSpeed ? locationManager.smoothedSpeedMs : 0 }

    var body: some View {
        TabView(selection: $tabSelected) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                DashboardView(
                    rtStats: rtStats, displaySpeed: displaySpeed, speedUnit: speedUnit,
                    speedAvailable: locationManager.hasFreshSpeed,
                    connectionMessage: bluetoothManager.connectionMessage,
                    isRecording: logger.isRecording, now: Date()
                )
            }.tag(0)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Controller").font(.headline).foregroundStyle(.cyan)
                        if !rtStats.isFresh(now: Date()) {
                            Label("Telemetry unavailable", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        detail("Battery", rtStats.isFresh(now: Date()) ? String(format: "%.1f V", rtStats.batteryVoltage) : "—")
                        detail("Input current", rtStats.isFresh(now: Date()) ? String(format: "%.1f A", rtStats.inputCurrent) : "—")
                        detail("Motor RPM", rtStats.isFresh(now: Date()) ? String(format: "%.0f", rtStats.rpm) : "—")
                        Text("GPS reports ground speed. Motor RPM is not travel speed.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 8)
                }
            }.tag(1)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your ride").font(.headline).foregroundStyle(.cyan)
                        if let ride = logger.activeRide {
                            Text("RECORDING").font(.caption2.bold()).foregroundStyle(.red)
                            detail("Duration", rideDuration(ride.duration))
                            detail("GPS distance", String(format: "%.2f km", ride.distanceMeters / 1000))
                            detail("Energy used", String(format: "%.1f Wh", ride.energyWh))
                            detail("Peak power", String(format: "%.0f W", ride.maxWatts))
                            Button("Save ride") { confirmSave = true }.tint(.cyan)
                            Text("Recording pauses telemetry during connection gaps.").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("Ready when you are.").font(.caption).foregroundStyle(.secondary)
                            Button("Start ride") { logger.startRide() }
                                .disabled(!rtStats.isFresh())
                                .tint(.cyan)
                            Text("Start after live telemetry arrives. Ride data saves on this Watch.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let error = logger.storageError {
                            Text(error).font(.caption2).foregroundStyle(.orange)
                            Button("Retry storage") { logger.retryLoad() }
                        }
                        Button("Ride history") { showHistory = true }
                    }.padding(.horizontal, 8)
                }
            }.tag(2)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                NavigationTabView(
                    locationManager: locationManager, destinationManager: destinationManager,
                    speedUnit: speedUnit, displaySpeed: displaySpeed,
                    travelSpeedMs: travelSpeedMs, smoothedEta: nil
                )
            }.tag(3)

            ScrollView {
                VStack(spacing: 10) {
                    Label("Foil Assist", systemImage: "water.waves").font(.headline).foregroundStyle(.cyan)
                    Button("Settings") { isSettingsPresented = true }
                    Button("Ride history") { showHistory = true }
                    Button("Preview app") { showDemo = true }
                    Text("Read-only telemetry. Configure your battery before riding.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 8)
            }.tag(4)
        }
        .tabViewStyle(.page)
        .sheet(isPresented: $showHistory) { RideHistoryView(logger: logger) }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(locationManager: locationManager, bluetoothManager: bluetoothManager, destinationManager: destinationManager)
        }
        .alert("Save this ride?", isPresented: $confirmSave) {
            Button("Save ride") { logger.endRide() }
            Button("Keep recording", role: .cancel) {}
        } message: { Text("Finish recording and keep this ride in history.") }
        .onAppear {
            if locationManager.isEnabled() { locationManager.start() }
            bluetoothManager.gpsSpeedProvider = { [weak locationManager] in
                guard let locationManager, locationManager.hasFreshSpeed else { return nil }
                return locationManager.smoothedSpeedMs
            }
        }
        .onDisappear {
            locationManager.stop()
            bluetoothManager.gpsSpeedProvider = nil
        }
        .onChange(of: locationManager.speed) { _, _ in
            bluetoothManager.publishTelemetrySnapshot(displaySpeed: displaySpeed, speedUnit: speedUnit)
        }
    }

    private func detail(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.caption)
    }
}

struct NavigationTabView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var destinationManager: DestinationManager
    let speedUnit: GPSSpeedUnit
    let displaySpeed: Double
    let travelSpeedMs: Double
    let smoothedEta: TimeInterval?

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            if destinationManager.destination == nil {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                    Text("No destination set")
                        .font(.caption)
                    DestinationPickerButton(destinationManager: destinationManager, currentCoordinate: locationManager.currentCoordinate)
                }
                .padding()
            } else {
                let freshCoordinate = locationManager.hasFreshLocation ? locationManager.currentCoordinate : nil
                let distance = destinationManager.distance(from: freshCoordinate)
                let eta = destinationManager.etaSeconds(distanceMeters: distance, speedMs: travelSpeedMs)
                let arrowAngle = destinationManager.arrowAngle(
                    current: freshCoordinate,
                    heading: locationManager.hasFreshHeading ? locationManager.smoothedHeadingDegrees : nil
                )

                VStack(spacing: 4) {
                    Text(destinationManager.destinationName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Image(systemName: arrowAngle == nil ? "location.slash" : "location.north.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.cyan)
                        .rotationEffect(.degrees(arrowAngle ?? 0))
                        .animation(.easeInOut(duration: 0.2), value: arrowAngle ?? 0)

                    Text(destinationManager.formattedDistance(distance))
                        .font(.caption)
                    Text(destinationManager.formattedETA(smoothedEta ?? eta))
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text(locationManager.hasFreshSpeed ? "GPS: \(String(format: "%.1f", displaySpeed)) \(speedUnit.rawValue)" : "GPS speed unavailable")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        DestinationPickerButton(destinationManager: destinationManager, currentCoordinate: locationManager.currentCoordinate)
                        Button("Clear") {
                            destinationManager.clearDestination()
                        }
                        .font(.caption2)
                    }
                    Text(arrowAngle == nil ? "Waiting for GPS / heading" : "Straight-line guidance")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
            }
        }
    }
}

struct DestinationPickerButton: View {
    @ObservedObject var destinationManager: DestinationManager
    let currentCoordinate: CLLocationCoordinate2D?
    @State private var showPicker = false

    var body: some View {
        Button(destinationManager.destination == nil ? "Set destination" : "Edit destination") {
            showPicker = true
        }
        .font(.caption2)
        .sheet(isPresented: $showPicker) {
            DestinationPickerView(
                destinationManager: destinationManager,
                currentCoordinate: currentCoordinate
            )
        }
    }
}

private struct MapDestinationPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct DestinationPickerView: View {
    @ObservedObject var destinationManager: DestinationManager
    let currentCoordinate: CLLocationCoordinate2D?

    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion

    init(destinationManager: DestinationManager, currentCoordinate: CLLocationCoordinate2D?) {
        self.destinationManager = destinationManager
        self.currentCoordinate = currentCoordinate

        let base = destinationManager.destination ?? currentCoordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        _region = State(initialValue: MKCoordinateRegion(
            center: base,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }

    private var annotationItems: [MapDestinationPin] {
        guard let destination = destinationManager.destination else { return [] }
        return [MapDestinationPin(coordinate: destination)]
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Pan map, pin center")
                .font(.caption2)

            Map(
                coordinateRegion: $region,
                interactionModes: [.pan, .zoom],
                annotationItems: annotationItems
            ) { item in
                MapMarker(coordinate: item.coordinate, tint: .red)
            }
            .overlay(alignment: .center) {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Button("Set pin at center") {
                destinationManager.setDestination(region.center)
                dismiss()
            }
            .font(.caption)

            if let destination = destinationManager.destination {
                Text(String(format: "%.4f, %.4f", destination.latitude, destination.longitude))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button("Cancel") {
                dismiss()
            }
            .font(.caption2)
        }
        .padding()
        .onAppear {
            if let destination = destinationManager.destination {
                region.center = destination
            } else if let currentCoordinate {
                region.center = currentCoordinate
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var destinationManager: DestinationManager

    @Environment(\.dismiss) private var dismiss
    @State private var showConfirmation = false
    @State private var cellCount = BatteryConfig.cellCount
    @State private var useVescBattery = BatteryConfig.useVescBatteryLevel
    @State private var showDestinationPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("GPS") {
                    Toggle("Enable GPS", isOn: Binding(
                        get: { locationManager.isEnabled() },
                        set: { locationManager.toggleStatus(status: $0) }
                    ))
                    Picker("Speed units", selection: Binding(
                        get: { locationManager.getSpeedUnit() },
                        set: { locationManager.setSpeedUnit($0) }
                    )) {
                        ForEach(GPSSpeedUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                }

                Section("Destination") {
                    if let destination = destinationManager.destination {
                        Text(String(format: "%.4f, %.4f", destination.latitude, destination.longitude))
                            .font(.caption2)
                    } else {
                        Text("No destination set")
                            .font(.caption2)
                    }

                    Button(destinationManager.destination == nil ? "Set destination" : "Edit destination") {
                        showDestinationPicker = true
                    }

                    if destinationManager.destination != nil {
                        Button("Clear destination", role: .destructive) {
                            destinationManager.clearDestination()
                        }
                    }
                }

                Section("Battery") {
                    Text("Battery % is an estimate. Configure this for your pack.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Toggle("Use VESC battery %", isOn: $useVescBattery)
                        .onChange(of: useVescBattery) { _, v in
                            BatteryConfig.useVescBatteryLevel = v
                        }
                    Stepper("Cells: \(cellCount)S", value: $cellCount, in: 6...24)
                        .onChange(of: cellCount) { _, v in
                            BatteryConfig.cellCount = v
                        }
                    Button("Apply \(cellCount)S pack") {
                        BatteryConfig.cellCount = cellCount
                    }
                    Text("Voltage curve: \(String(format: "%.1f", BatteryConfig.minVoltagePerCell))–\(String(format: "%.1f", BatteryConfig.maxVoltagePerCell)) V/cell when VESC % is off")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Button("Reset pairing") {
                    showConfirmation = true
                }
                .foregroundColor(.red)

                Button("Done") {
                    dismiss()
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showDestinationPicker) {
                DestinationPickerView(
                    destinationManager: destinationManager,
                    currentCoordinate: locationManager.currentCoordinate
                )
            }
            .alert("Reset pairing?", isPresented: $showConfirmation) {
                Button("Reset", role: .destructive) {
                    dismiss()
                    bluetoothManager.restart(withNewDevice: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears saved VESC and returns to device list.")
            }
            .onAppear {
                cellCount = BatteryConfig.cellCount
                useVescBattery = BatteryConfig.useVescBatteryLevel
            }
        }
    }
}

#Preview {
    ContentView()
}
