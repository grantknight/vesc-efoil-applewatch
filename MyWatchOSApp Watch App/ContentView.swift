import SwiftUI
import MapKit
import CoreLocation

private var requestsDemo: Bool {
    ProcessInfo.processInfo.arguments.contains { ["--demo", "--demo-navigation", "--demo-fault", "--demo-destination", "--demo-bms", "--demo-bms-unavailable"].contains($0) }
}

private enum HomeSheet: String, Identifiable {
    case settings, history, destination, bms
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager(
        startBluetooth: !requestsDemo
    )
    @StateObject private var bmsManager = BMSManager(startBluetooth: false)
    @State private var showDemo = requestsDemo
    @State private var showHistory = false
    @State private var hasEnteredHome = false

    var body: some View {
        Group {
            if showDemo {
                DemoWatchView { showDemo = false }
            } else if bluetoothManager.state == .connected || hasEnteredHome {
                Home(bluetoothManager: bluetoothManager, bmsManager: bmsManager, showDemo: $showDemo, showConnection: {
                    bluetoothManager.restart()
                    if bluetoothManager.state != .connected { hasEnteredHome = false }
                })
            } else {
                ConnectionScreen(bluetoothManager: bluetoothManager, bmsManager: bmsManager, showDemo: $showDemo, showHistory: $showHistory)
            }
        }
        .sheet(isPresented: $showHistory) { RideHistoryView(logger: SessionLogger.shared) }
        .onAppear {
            bmsManager.setDemoMode(showDemo)
            bmsManager.excludePeripheral(bluetoothManager.selectedPeripheralID)
        }
        .onChange(of: showDemo) { _, enabled in
            bluetoothManager.setDemoMode(enabled)
            bmsManager.setDemoMode(enabled)
        }
        .onChange(of: bluetoothManager.selectedPeripheralID) { _, identifier in bmsManager.excludePeripheral(identifier) }
        .onChange(of: bluetoothManager.state == .connected) { _, connected in
            if connected { hasEnteredHome = true }
        }
    }

}

private struct ConnectionScreen: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var bmsManager: BMSManager
    @ObservedObject private var logger = SessionLogger.shared
    @Binding var showDemo: Bool
    @Binding var showHistory: Bool
    @State private var showBMS = false

    var body: some View {
        NavigationStack {
                    List {
                        Section("Connect VESC") {
                            Label(connectionTitle, systemImage: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.cyan)
                            Text(connectionDetail).font(.caption).foregroundStyle(.secondary)
                            if bluetoothManager.state == .connecting { ProgressView() }
                            ForEach(bluetoothManager.peripherals, id: \.identifier) { peripheral in
                                Button(peripheral.name ?? "VESC device") {
                                    bmsManager.excludePeripheral(peripheral.identifier)
                                    bluetoothManager.connectPeripheral(peripheral: peripheral)
                                }
                            }
                            if bluetoothManager.state != .off {
                                Button(bluetoothManager.state == .connecting ? "Cancel connection" : "Scan again") {
                                    bluetoothManager.restart(withNewDevice: bluetoothManager.state == .connecting)
                                }
                            }
                        }
                        Section("Battery BMS") {
                            Button("Connect battery BMS") {
                                bmsManager.excludePeripheral(bluetoothManager.selectedPeripheralID)
                                showBMS = true
                            }
                            Text("Separate read-only 12S battery connection.").font(.caption2).foregroundStyle(.secondary)
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
                }.sheet(isPresented: $showBMS) {
                    BMSConnectionView(manager: bmsManager, excludedVESC: bluetoothManager.selectedPeripheralID)
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
    @ObservedObject var bmsManager: BMSManager
    @ObservedObject private var rtStats: VESCRtStats
    @ObservedObject private var logger = SessionLogger.shared
    @Binding var showDemo: Bool
    let showConnection: () -> Void
    @State private var tabSelected = 0
    @State private var sheet: HomeSheet?
    @State private var confirmSave = false
    @State private var arrivalEstimator = ArrivalBatteryEstimator()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var destinationManager = DestinationManager()

    init(bluetoothManager: BluetoothManager, bmsManager: BMSManager, showDemo: Binding<Bool>, showConnection: @escaping () -> Void) {
        self.bluetoothManager = bluetoothManager
        self.bmsManager = bmsManager
        _showDemo = showDemo
        self.showConnection = showConnection
        _rtStats = ObservedObject(wrappedValue: bluetoothManager.vescRtStats)
    }

    private var speedUnit: GPSSpeedUnit { locationManager.getSpeedUnit() }
    private var displaySpeed: Double { locationManager.hasFreshSpeed ? locationManager.speed : 0 }
    private var travelSpeedMs: Double { locationManager.hasFreshSpeed ? locationManager.smoothedSpeedMs : 0 }
    private var freshCoordinate: CLLocationCoordinate2D? { locationManager.hasFreshLocation ? locationManager.currentCoordinate : nil }
    private var remainingDistance: Double? { destinationManager.distance(from: freshCoordinate) }
    private var eta: TimeInterval? { NavigationEstimate.etaSeconds(distanceMeters: remainingDistance, speedMs: locationManager.hasFreshSpeed ? travelSpeedMs : nil) }
    private var prediction: ArrivalBatteryPrediction? {
        guard rtStats.isFresh(), rtStats.batteryPercentIsAvailable, locationManager.hasFreshSpeed else { return nil }
        return arrivalEstimator.prediction(etaSeconds: eta, reservePercent: destinationManager.reservePercent)
    }
    private var estimateReason: String {
        guard rtStats.isFresh(), rtStats.batteryPercentIsAvailable, locationManager.hasFreshSpeed else { return "Fresh battery and GPS observations are required" }
        return arrivalEstimator.predictionUnavailableReason(etaSeconds: eta, reservePercent: destinationManager.reservePercent) ?? "Measured consumption estimate"
    }
    private var dashboardArrival: String {
        if let prediction {
            if prediction.willExhaustBeforeArrival { return "Runs out before arrival" }
            if prediction.reserveShortfallPercent > 0 { return String(format: "Arrival ~%.0f%% · short %.0f%%", floor(max(0, prediction.arrivalPercent)), ceil(prediction.reserveShortfallPercent)) }
            return String(format: "Arrival ~%.0f%%", floor(max(0, prediction.arrivalPercent)))
        }
        return "Arrival battery —"
    }

    var body: some View {
        TabView(selection: $tabSelected) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                DashboardView(
                    rtStats: rtStats, displaySpeed: displaySpeed, speedUnit: speedUnit,
                    speedAvailable: locationManager.hasFreshSpeed,
                    connectionMessage: bluetoothManager.connectionMessage,
                    isRecording: logger.isRecording, now: Date(),
                    directionAngle: destinationManager.arrowAngle(current: freshCoordinate, heading: locationManager.directionHeading),
                    directionReference: locationManager.directionReference,
                    navigationDistance: destinationManager.formattedDistance(remainingDistance).replacingOccurrences(of: "Distance: ", with: ""),
                    destinationETA: destinationManager.formattedETA(eta).replacingOccurrences(of: "ETA: ", with: ""),
                    arrivalBatterySummary: dashboardArrival,
                    reserveWarning: (prediction?.reserveShortfallPercent ?? 0) > 0,
                    onDestinationTap: { sheet = .destination }
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
                        Text("Battery estimate: " + rtStats.batterySourceLabel).font(.caption2).foregroundStyle(.secondary)
                        detail("Input current", rtStats.isFresh(now: Date()) ? String(format: "%.1f A", rtStats.inputCurrent) : "—")
                        detail("ESC temperature", rtStats.isFresh() ? String(format: "%.0f°C", rtStats.mosTemperature) : "—")
                        Text(rtStats.faultLabel ?? "Fault status unavailable")
                            .font(.caption).foregroundStyle(rtStats.faultCode == 0 && rtStats.faultIsAvailable() ? Color.secondary : Color.orange)
                        Text("GPS reports ground speed, not speed through water.")
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
                        Button("Ride history") { sheet = .history }
                    }.padding(.horizontal, 8)
                }
            }.tag(2)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                NavigationSummaryView(destinationManager: destinationManager, currentCoordinate: freshCoordinate,
                    heading: locationManager.directionHeading,
                    eta: eta, prediction: prediction, unavailableReason: estimateReason,
                    directionReference: locationManager.directionReference)
            }.tag(3)

            ScrollView {
                VStack(spacing: 10) {
                    Label("Foil Assist", systemImage: "water.waves").font(.headline).foregroundStyle(.cyan)
                    Button("Settings") { sheet = .settings }
                    Button("Connect VESC", action: showConnection)
                    Button("Connect battery BMS") {
                        bmsManager.excludePeripheral(bluetoothManager.selectedPeripheralID)
                        sheet = .bms
                    }
                    Button("Ride history") { sheet = .history }
                    Button("Preview app") { showDemo = true }
                    Text("Read-only telemetry. Configure your battery before riding.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 8)
            }.tag(4)
        }
        .tabViewStyle(.page)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .history: RideHistoryView(logger: logger)
            case .settings: SettingsView(locationManager: locationManager, bluetoothManager: bluetoothManager, bmsManager: bmsManager, destinationManager: destinationManager, onConnection: showConnection)
            case .destination: DestinationPickerView(destinationManager: destinationManager, currentCoordinate: freshCoordinate)
            case .bms: BMSConnectionView(manager: bmsManager, excludedVESC: bluetoothManager.selectedPeripheralID)
            }
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
            bluetoothManager.displaySpeedProvider = { [weak locationManager] in
                guard let locationManager else { return (nil, .mph) }
                return (locationManager.hasFreshSpeed ? locationManager.speed : nil, locationManager.speedUnit)
            }
        }
        .onDisappear {
            locationManager.stop()
            bluetoothManager.gpsSpeedProvider = nil
            bluetoothManager.displaySpeedProvider = nil
        }
        .onChange(of: rtStats.lastTelemetryTimestamp) { _, timestamp in
            arrivalEstimator.observe(percent: rtStats.batteryPercentIsAvailable ? rtStats.batteryPercent : nil,
                source: rtStats.batteryPercentIsAvailable ? batteryTrendSource : nil,
                at: timestamp, distanceMeters: locationManager.hasFreshSpeed ? remainingDistance : nil,
                isTelemetryFresh: rtStats.isFresh())
        }
        .onChange(of: destinationManager.destination?.latitude) { _, _ in arrivalEstimator.reset() }
        .onChange(of: destinationManager.destination?.longitude) { _, _ in arrivalEstimator.reset() }
        .onChange(of: destinationManager.destinationKind) { _, _ in arrivalEstimator.reset() }
        .onChange(of: batteryTrendSource) { _, _ in arrivalEstimator.reset() }
    }

    private func detail(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.caption)
    }

    private var batteryTrendSource: String {
        var identity = String(describing: rtStats.batteryPercentSource)
        if rtStats.batteryPercentSource == .voltageEstimate {
            identity += "-\(BatteryConfig.cellCount)-\(BatteryConfig.minVoltagePerCell)-\(BatteryConfig.maxVoltagePerCell)"
        }
        return identity
    }
}

struct NavigationSummaryView: View {
    @ObservedObject var destinationManager: DestinationManager
    let currentCoordinate: CLLocationCoordinate2D?
    let heading: Double?
    let eta: TimeInterval?
    let prediction: ArrivalBatteryPrediction?
    let unavailableReason: String
    var directionReference = "Direction unavailable"
    var usesSampleData = false
    @State private var showEditor = false

    var body: some View {
            ScrollView {
                VStack(spacing: 4) {
                    Text(destinationManager.destination == nil ? "Choose destination" : destinationManager.destinationName)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.mint).lineLimit(1).minimumScaleFactor(0.8)
                    let angle = destinationManager.arrowAngle(current: currentCoordinate, heading: heading)
                    HStack(spacing: 7) {
                        Button { showEditor = true } label: {
                            DestinationCompassNeedle(angle: angle, color: .mint)
                                .frame(width: 28, height: 28)
                        }.buttonStyle(.plain).accessibilityLabel("Destination setup")
                        Text(angle == nil ? "Direction unavailable" : directionReference)
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(height: 28)
                    Text(destinationManager.formattedDistance(destinationManager.distance(from: currentCoordinate)).replacingOccurrences(of: "Distance: ", with: "") + " · " + destinationManager.formattedETA(eta))
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    if let prediction {
                        Text(String(format: "Arrival ~%.0f%% · reserve %.0f%%", floor(max(0, prediction.arrivalPercent)), destinationManager.reservePercent))
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(prediction.reserveShortfallPercent > 0 ? Color.orange : Color.mint)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if prediction.willExhaustBeforeArrival {
                            Text("Battery may run out before arrival").font(.system(size: 9, weight: .bold)).foregroundStyle(.red).lineLimit(2)
                        }
                        if prediction.reserveShortfallPercent > 0 {
                            Text(String(format: "Reserve short by %.0f%%", ceil(prediction.reserveShortfallPercent)))
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                        }
                    } else {
                        Text("Arrival battery unavailable").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                        Text(String(format: "Reserve %.0f%%", destinationManager.reservePercent)).font(.system(size: 10))
                    }
                    Button("Destination setup") { showEditor = true }.font(.caption).tint(.mint).padding(.top, 4)
                    if let prediction {
                        Text("Battery time ~" + durationText(prediction.secondsUntilEmpty)).font(.caption)
                        if prediction.depletionPercentPerSecond.isFinite, prediction.depletionPercentPerSecond > 0 {
                            let untilReserve = max(0, prediction.secondsUntilEmpty - destinationManager.reservePercent / prediction.depletionPercentPerSecond)
                            Text("To reserve ~" + durationText(untilReserve)).font(.caption2)
                        }
                        Text("Estimated time to empty from recent consumption.").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(unavailableReason).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("Straight-line guidance only. Battery estimates assume recent consumption continues; wind, current and assist use can change the result.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.multilineTextAlignment(.center).padding(.horizontal, 8)
            }
                .sheet(isPresented: $showEditor) {
                    DestinationPickerView(destinationManager: destinationManager, currentCoordinate: currentCoordinate, usesSampleData: usesSampleData)
                }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        destinationManager.formattedETA(max(0, seconds)).replacingOccurrences(of: "ETA: ", with: "")
    }
}

struct DestinationPickerView: View {
    @ObservedObject var destinationManager: DestinationManager
    let currentCoordinate: CLLocationCoordinate2D?
    var usesSampleData = false
    @Environment(\.dismiss) private var dismiss
    @State private var pointKind: DestinationKind = .finish
    @State private var pointName = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var feedback = ""
    @State private var confirmClearLaunch = false

    private var manualCoordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let coordinate = NavigationCoordinate(latitude: lat, longitude: lon)
        guard coordinate.isValid else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        NavigationStack {
            Form {
                if usesSampleData { Text("DEMO · SAMPLE POINTS").font(.caption2.bold()).foregroundStyle(.orange) }
                Section("Launch / beach") {
                    Text(destinationManager.launchCoordinate == nil ? "No launch saved" : destinationManager.launchName)
                        .font(.caption)
                    Button(usesSampleData ? "Mark sample launch" : "Mark launch from GPS") {
                        guard let currentCoordinate else { return }
                        destinationManager.saveLaunchPoint(currentCoordinate)
                        feedback = "Launch saved. Current target preserved."
                    }.disabled(currentCoordinate == nil).accessibilityIdentifier("mark-launch")
                    if currentCoordinate == nil { Text("A fresh GPS fix is required.").font(.caption2).foregroundStyle(.secondary) }
                    Button("Return to launch") {
                        destinationManager.selectReturnToLaunch()
                        dismiss()
                    }.disabled(destinationManager.launchCoordinate == nil).accessibilityIdentifier("return-launch")
                    if destinationManager.launchCoordinate != nil {
                        Button("Remove saved launch", role: .destructive) { confirmClearLaunch = true }
                    }
                }
                Section("Finish") {
                    if destinationManager.finishCoordinate != nil {
                        Button("Go to \(destinationManager.finishName)") { destinationManager.selectFinish(); dismiss() }
                        Button("Clear finish", role: .destructive) { destinationManager.clearDestination() }
                    }
                }
                Section("Add a named point") {
                    Picker("Point type", selection: $pointKind) {
                        ForEach(DestinationKind.allCases) { kind in Text(kind.title).tag(kind) }
                    }
                    TextField("Name", text: $pointName).accessibilityIdentifier("destination-name")
                    TextField("Latitude", text: $latitude).accessibilityIdentifier("destination-latitude")
                    TextField("Longitude", text: $longitude).accessibilityIdentifier("destination-longitude")
                    Text("Decimal degrees: latitude −90…90, longitude −180…180. Use a period for decimals.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Save coordinates") {
                        guard let manualCoordinate else { feedback = "Enter valid decimal latitude and longitude."; return }
                        save(manualCoordinate)
                    }.disabled(manualCoordinate == nil).accessibilityIdentifier("save-coordinates")
                    NavigationLink("Choose on map") {
                        MapPointPickerView(destinationManager: destinationManager, currentCoordinate: currentCoordinate,
                            pointKind: pointKind, pointName: pointName)
                    }.accessibilityIdentifier("choose-map")
                }
                Section("Battery reserve") {
                    Stepper(String(format: "Reserve %.0f%%", destinationManager.reservePercent),
                        value: $destinationManager.reservePercent, in: 0...100, step: 5)
                    Text("Default 20%. Arrival battery needs a steady measured depletion trend while approaching the selected point.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !feedback.isEmpty { Text(feedback).font(.caption).foregroundStyle(.mint).accessibilityIdentifier("destination-feedback") }
                Button("Done") { dismiss() }
            }.navigationTitle("Destination")
                .alert("Remove launch point?", isPresented: $confirmClearLaunch) {
                    Button("Remove", role: .destructive) { destinationManager.clearLaunchPoint() }
                    Button("Keep", role: .cancel) {}
                } message: { Text("The saved finish is preserved.") }
        }
    }

    private func save(_ coordinate: CLLocationCoordinate2D) {
        if pointKind == .launch {
            destinationManager.saveLaunchPoint(coordinate, name: pointName.isEmpty ? "Launch / beach" : pointName)
            feedback = "Launch saved independently of finish."
        } else {
            destinationManager.setDestination(coordinate, name: pointName.isEmpty ? "Finish" : pointName)
            feedback = "Finish selected. Launch stays saved."
        }
    }
}

private struct MapPointPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
}

private struct MapPointPickerView: View {
    @ObservedObject var destinationManager: DestinationManager
    let currentCoordinate: CLLocationCoordinate2D?
    let pointKind: DestinationKind
    let pointName: String
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion

    init(destinationManager: DestinationManager, currentCoordinate: CLLocationCoordinate2D?, pointKind: DestinationKind, pointName: String) {
        self.destinationManager = destinationManager
        self.currentCoordinate = currentCoordinate
        self.pointKind = pointKind
        self.pointName = pointName
        let existing = pointKind == .launch ? destinationManager.launchCoordinate : destinationManager.finishCoordinate
        let center = existing ?? currentCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        _region = State(initialValue: MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
    }

    private var pins: [MapPointPin] {
        var points: [MapPointPin] = []
        if let coordinate = destinationManager.launchCoordinate { points.append(MapPointPin(id: "launch", coordinate: coordinate)) }
        if let coordinate = destinationManager.finishCoordinate { points.append(MapPointPin(id: "finish", coordinate: coordinate)) }
        return points
    }

    var body: some View {
        VStack(spacing: 5) {
            Text("Pan / zoom; pin the center").font(.caption2)
            Map(coordinateRegion: $region, interactionModes: [.pan, .zoom], annotationItems: pins) { point in
                MapMarker(coordinate: point.coordinate, tint: point.id == "launch" ? .orange : .mint)
            }
            .overlay { Image(systemName: "plus").foregroundStyle(.white).padding(5).background(.black.opacity(0.5), in: Circle()).allowsHitTesting(false) }
            Text(String(format: "%.5f, %.5f", region.center.latitude, region.center.longitude)).font(.caption2).monospacedDigit()
            Button("Save \(pointKind.title) here") {
                guard region.center.latitude.isFinite, region.center.longitude.isFinite, CLLocationCoordinate2DIsValid(region.center) else { return }
                if pointKind == .launch { destinationManager.saveLaunchPoint(region.center, name: pointName.isEmpty ? "Launch / beach" : pointName) }
                else { destinationManager.setDestination(region.center, name: pointName.isEmpty ? "Finish" : pointName) }
                dismiss()
            }.font(.caption).tint(.mint).accessibilityIdentifier("save-map-center")
        }.navigationTitle("Place a pin")
    }
}

struct SettingsView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var bmsManager: BMSManager
    @ObservedObject var destinationManager: DestinationManager
    var onConnection: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showConfirmation = false
    @State private var cellCount = BatteryConfig.cellCount
    @State private var useVescBattery = BatteryConfig.useVescBatteryLevel
    @State private var showDestinationPicker = false
    @State private var showBMS = false

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
                            Text(unit.displayLabel).tag(unit)
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

                    if destinationManager.finishCoordinate != nil {
                        Button("Clear finish", role: .destructive) {
                            destinationManager.clearDestination()
                        }
                    }
                }

                Section("Battery") {
                    Button("Connect battery BMS") {
                        bmsManager.excludePeripheral(bluetoothManager.selectedPeripheralID)
                        showBMS = true
                    }
                    Text("The 12S BMS cells are separate from this VESC percentage setup.").font(.caption2).foregroundStyle(.secondary)
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
                    currentCoordinate: locationManager.hasFreshLocation ? locationManager.currentCoordinate : nil
                )
            }
            .sheet(isPresented: $showBMS) {
                BMSConnectionView(manager: bmsManager, excludedVESC: bluetoothManager.selectedPeripheralID)
            }
            .alert("Reset pairing?", isPresented: $showConfirmation) {
                Button("Reset", role: .destructive) {
                    dismiss()
                    bluetoothManager.restart(withNewDevice: true)
                    if bluetoothManager.state != .connected { onConnection() }
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
