//
//  ContentView.swift
//  MyWatchOSApp Watch App
//

import SwiftUI
import MapKit
import CoreLocation

func secondsToHoursMinutesSeconds(_ seconds: Int) -> (Int, Int, Int) {
    (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
}

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some View {
        switch bluetoothManager.state {
        case .start:
            Hello()
        case .scanning, .scanningIdle:
            Scan(bluetoothManager: bluetoothManager)
        case .connecting:
            Connect(bluetoothManager: bluetoothManager)
        case .off:
            BTOff()
        default:
            Home(bluetoothManager: bluetoothManager)
        }
    }
}

struct Hello: View {
    var body: some View {
        Text("Initializing...")
    }
}

struct BTOff: View {
    var body: some View {
        ZStack {
            Color.red.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 24))
                    .symbolEffect(.pulse, options: .repeating)

                Text("Bluetooth Error")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.red)

                Text("App has no access to Bluetooth!")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Scan: View {
    @ObservedObject var bluetoothManager: BluetoothManager

    var body: some View {
        VStack {
            Text("Device list")
            Spacer()
            List {
                ForEach(bluetoothManager.peripherals, id: \.identifier) { peripheral in
                    if let name = peripheral.name {
                        Button {
                            bluetoothManager.connectPeripheral(peripheral: peripheral)
                        } label: {
                            Text(name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray)
                                .cornerRadius(10)
                        }
                    }
                }

                if bluetoothManager.state == .scanning {
                    ProgressView()
                }

                Button {
                    bluetoothManager.stopScanning()
                } label: {
                    Text("STOP")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }

                Button {
                    bluetoothManager.restart()
                } label: {
                    Text("REFRESH")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct Connect: View {
    @ObservedObject var bluetoothManager: BluetoothManager

    var body: some View {
        VStack(spacing: 8) {
            Text(bluetoothManager.connectionMessage.isEmpty ? "Connecting..." : bluetoothManager.connectionMessage)
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(2.0, anchor: .center)
            Button("Cancel...") {
                bluetoothManager.restart(withNewDevice: true)
            }
        }
    }
}

struct Home: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject private var rtStats: VESCRtStats
    @ObservedObject private var sessionStats: VESCStats

    @State private var crownOffset: Double = 0
    @State private var tabSelected = 0
    @State private var crownCounter: Double = 0
    @State private var isSettingsPresented = false
    @State private var smoothedEta: TimeInterval?

    @StateObject private var locationManager = LocationManager()
    @StateObject private var destinationManager = DestinationManager()

    private let tabCount = 5

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        _rtStats = ObservedObject(wrappedValue: bluetoothManager.vescRtStats)
        _sessionStats = ObservedObject(wrappedValue: bluetoothManager.vescStats)
    }

    private var speedUnit: GPSSpeedUnit {
        locationManager.getSpeedUnit()
    }

    private var vescSpeedDisplay: Double {
        formatVescSpeed(rtStats.vescSpeed, unit: speedUnit)
    }

    /// Prefer the higher of VESC wheel speed and GPS when GPS is enabled.
    private var displaySpeed: Double {
        guard locationManager.isEnabled() else { return vescSpeedDisplay }
        return max(vescSpeedDisplay, locationManager.speed)
    }

    private var travelSpeedMs: Double {
        let gpsSpeed = locationManager.isEnabled() ? locationManager.smoothedSpeedMs : 0
        return max(rtStats.vescSpeed, gpsSpeed)
    }

    private var destinationDistance: Double? {
        destinationManager.distance(from: locationManager.currentCoordinate)
    }

    private var destinationETA: TimeInterval? {
        smoothedEta
    }

    private var dashboardArrowAngle: Double? {
        guard destinationManager.destination != nil else { return nil }
        return destinationManager.arrowAngle(
            current: locationManager.currentCoordinate,
            heading: locationManager.smoothedHeadingDegrees
        )
    }

    private var dashboardDistanceText: String? {
        guard destinationManager.destination != nil else { return nil }
        return destinationManager.formattedDistance(destinationDistance)
    }

    private var dashboardEtaText: String? {
        guard destinationManager.destination != nil else { return nil }
        return destinationManager.formattedETA(destinationETA)
    }

    private func refreshSmoothedEta() {
        smoothedEta = destinationManager.smoothedETA(
            distanceMeters: destinationDistance,
            speedMs: travelSpeedMs
        )
    }

    var body: some View {
        TabView(selection: $tabSelected) {
            DashboardView(
                rtStats: rtStats,
                displaySpeed: displaySpeed,
                speedUnit: speedUnit,
                connectionMessage: bluetoothManager.connectionMessage,
                destinationArrowAngle: dashboardArrowAngle,
                destinationDistanceText: dashboardDistanceText,
                destinationEtaText: dashboardEtaText
            )
            .tag(0)

            ZStack {
                Color.blue.opacity(0.1)
                    .ignoresSafeArea()

                VStack(spacing: 3) {
                    Image(systemName: "waveform")
                        .foregroundColor(.red)
                        .font(.system(size: 18))

                    Text("Speed: \(String(format: "%.1f", displaySpeed)) \(speedUnit.rawValue)")
                    Text("Power: \(String(format: "%.0f", rtStats.instantWatts)) W")
                    Text("Battery: \(String(format: "%.0f", rtStats.batteryPercent))% · \(String(format: "%.1f", rtStats.batteryVoltage)) V")
                    Text("MOS: \(String(format: "%.1f", rtStats.mosTemperature))°  Motor: \(String(format: "%.1f", rtStats.motorTemperature))°")
                    Text("RPM: \(String(format: "%.0f", rtStats.rpm))  A: \(String(format: "%.1f", rtStats.inputCurrent))")
                    Text(destinationManager.formattedDistance(destinationDistance))
                    Text(destinationManager.formattedETA(destinationETA))

                    let lag = rtStats.timeSinceLastUpdate
                    Text(lag < 3600 ? "Lag: \(String(format: "%.0f", lag))s" : "Lag: —")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .padding()
            }
            .tag(1)

            ZStack {
                Color.purple.opacity(0.1)
                    .ignoresSafeArea()

                VStack(spacing: 3) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 18))

                    let (h, m, s) = secondsToHoursMinutesSeconds(Int(sessionStats.runTime))
                    Text("Run: \(String(format: "%02d", h)):\(String(format: "%02d", m)):\(String(format: "%02d", s))")
                    Text("Power avg/max: \(String(format: "%.0f", sessionStats.avgPower))/\(String(format: "%.0f", sessionStats.maxPower)) W")
                    Text("Current avg/max: \(String(format: "%.1f", sessionStats.avgCurrent))/\(String(format: "%.1f", sessionStats.maxCurrent)) A")
                    Text("MOS avg/max: \(String(format: "%.1f", sessionStats.avgMosTemperature))/\(String(format: "%.1f", sessionStats.maxMosTemperature))°")
                    Text("Wh: \(String(format: "%.1f", rtStats.wattHours))")
                }
                .font(.caption)
                .padding()
            }
            .tag(2)

            NavigationTabView(
                locationManager: locationManager,
                destinationManager: destinationManager,
                speedUnit: speedUnit,
                displaySpeed: displaySpeed,
                travelSpeedMs: travelSpeedMs,
                smoothedEta: destinationETA
            )
            .tag(3)

            ZStack {
                Color.green.opacity(0.1)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    Text(rtStats.isConnected ? "VESC connected" : "Not connected")
                        .font(.caption)
                    Button("Settings") {
                        isSettingsPresented = true
                    }
                    .font(.caption)
                }
            }
            .tag(4)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                locationManager: locationManager,
                bluetoothManager: bluetoothManager,
                destinationManager: destinationManager
            )
        }
        .tabViewStyle(.page)
        .focusable()
        .digitalCrownRotation(
            detent: $crownOffset,
            from: 0,
            through: 1,
            by: 0.01,
            sensitivity: .medium,
            isContinuous: true,
            onChange: { crownEvent in
                crownCounter += crownEvent.velocity
                if crownCounter > 10 {
                    crownCounter = 10
                    if tabSelected < tabCount - 1 {
                        tabSelected += 1
                    }
                }
                if crownCounter < 0 {
                    crownCounter = 0
                    if tabSelected > 0 {
                        tabSelected -= 1
                    }
                }
            }
        )
        .onChange(of: locationManager.speed) { _, _ in
            bluetoothManager.publishTelemetrySnapshot(
                displaySpeed: displaySpeed,
                speedUnit: speedUnit
            )
            refreshSmoothedEta()
        }
        .onChange(of: locationManager.currentCoordinate?.latitude ?? 0) { _, _ in
            bluetoothManager.publishTelemetrySnapshot(
                displaySpeed: displaySpeed,
                speedUnit: speedUnit
            )
            refreshSmoothedEta()
        }
        .onChange(of: locationManager.currentCoordinate?.longitude ?? 0) { _, _ in
            refreshSmoothedEta()
        }
        .onChange(of: rtStats.vescSpeed) { _, _ in
            refreshSmoothedEta()
        }
        .onChange(of: locationManager.smoothedSpeedMs) { _, _ in
            refreshSmoothedEta()
        }
        .onChange(of: destinationManager.destination?.latitude ?? 0) { _, _ in
            refreshSmoothedEta()
        }
        .onChange(of: destinationManager.destination?.longitude ?? 0) { _, _ in
            refreshSmoothedEta()
        }
        .onAppear {
            refreshSmoothedEta()
        }
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
                let distance = destinationManager.distance(from: locationManager.currentCoordinate)
                let eta = destinationManager.etaSeconds(distanceMeters: distance, speedMs: travelSpeedMs)
                let arrowAngle = destinationManager.arrowAngle(
                    current: locationManager.currentCoordinate,
                    heading: locationManager.smoothedHeadingDegrees
                ) ?? 0

                VStack(spacing: 4) {
                    Text(destinationManager.destinationName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Image(systemName: "location.north.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.cyan)
                        .rotationEffect(.degrees(arrowAngle))
                        .animation(.easeInOut(duration: 0.2), value: arrowAngle)

                    Text(destinationManager.formattedDistance(distance))
                        .font(.caption)
                    Text(destinationManager.formattedETA(smoothedEta ?? eta))
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text("Speed: \(String(format: "%.1f", displaySpeed)) \(speedUnit.rawValue)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        DestinationPickerButton(destinationManager: destinationManager, currentCoordinate: locationManager.currentCoordinate)
                        Button("Clear") {
                            destinationManager.clearDestination()
                        }
                        .font(.caption2)
                    }
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
                    Toggle("Use VESC battery %", isOn: $useVescBattery)
                        .onChange(of: useVescBattery) { _, v in
                            BatteryConfig.useVescBatteryLevel = v
                        }
                    Stepper("Cells: \(cellCount)S", value: $cellCount, in: 6...24)
                        .onChange(of: cellCount) { _, v in
                            BatteryConfig.cellCount = v
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
