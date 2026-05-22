//
//  ContentView.swift
//  MyWatchOSApp Watch App
//

import SwiftUI

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

    @StateObject private var locationManager = LocationManager()

    private let tabCount = 4

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        _rtStats = ObservedObject(wrappedValue: bluetoothManager.vescRtStats)
        _sessionStats = ObservedObject(wrappedValue: bluetoothManager.vescStats)
    }

    private var speedUnit: GPSSpeedUnit {
        locationManager.getSpeedUnit()
    }

    private var vescSpeed: Double {
        formatVescSpeed(rtStats.vescSpeed, unit: speedUnit)
    }

    /// Prefer the higher of VESC wheel speed and GPS when GPS is enabled.
    private var displaySpeed: Double {
        guard locationManager.isEnabled() else { return vescSpeed }
        return max(vescSpeed, locationManager.speed)
    }

    var body: some View {
        TabView(selection: $tabSelected) {
            DashboardView(
                rtStats: rtStats,
                displaySpeed: displaySpeed,
                speedUnit: speedUnit,
                connectionMessage: bluetoothManager.connectionMessage
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
            .tag(3)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(locationManager: locationManager, bluetoothManager: bluetoothManager)
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
        .onChange(of: rtStats.timeSinceLastUpdate) { _, _ in
            bluetoothManager.publishTelemetrySnapshot(
                displaySpeed: displaySpeed,
                speedUnit: speedUnit
            )
        }
        .onChange(of: locationManager.speed) { _, _ in
            bluetoothManager.publishTelemetrySnapshot(
                displaySpeed: displaySpeed,
                speedUnit: speedUnit
            )
        }
    }
}

struct SettingsView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var bluetoothManager: BluetoothManager

    @Environment(\.dismiss) private var dismiss
    @State private var showConfirmation = false
    @State private var cellCount = BatteryConfig.cellCount
    @State private var useVescBattery = BatteryConfig.useVescBatteryLevel

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
