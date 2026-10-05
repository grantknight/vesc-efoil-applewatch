import Foundation
import Combine
import CoreBluetooth
import WidgetKit

var DEBUG = false
private enum VescCommand {
    static let getValuesSelective: UInt8 = 50
    static let getValuesSetupSelective: UInt8 = 51
    static let getStats: UInt8 = 128
}
enum btStateEnum { case off, start, scanning, scanningIdle, connecting, connected }
enum BluetoothError: Error { case timeout, connectTimeout, bluetoothNotAvailable }
extension Data {
    func hexEncodedString(upperCase: Bool = false) -> String {
        map { String(format: upperCase ? "%02hhX" : "%02hhx", $0) }.joined(separator: " ")
    }
}
extension Array where Element == UInt8 {
    func hexEncodedString() -> String { map { String(format: "%02hhX", $0) }.joined(separator: " ") }
}
extension ArraySlice where Element == UInt8 {
    func hexEncodedString() -> String { map { String(format: "%02hhX", $0) }.joined(separator: " ") }
}

/// Main-queue Bluetooth client that sends read-only telemetry queries.
final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var vescTimer: Timer?
    private var connectTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempt = 0
    private var vescTimerCounter: UInt = 0
    private var vesc: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var lastWidgetReload = Date.distantPast
    private var wasFresh = false
    private var connectedAt: Date?
    private let packet = Packet()
    private var requestQueue = VescRequestQueue()
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let writeUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let notifyUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    @Published var state = btStateEnum.start
    @Published var peripherals: [CBPeripheral] = []
    @Published var connectionMessage = ""
    @Published private(set) var lastTelemetryAt: Date?
    let vescRtStats = VESCRtStats()
    let vescStats = VESCStats()
    lazy var sessionLogger = SessionLogger.shared
    /// Returns fresh GPS speed in m/s. nil means unavailable, never propeller speed.
    var gpsSpeedProvider: (() -> Double?)?
    /// Display-unit GPS speed for the shared snapshot, resolved at publish time so a silent
    /// GPS stall cannot freeze an old speed under a fresh telemetry timestamp.
    var displaySpeedProvider: (() -> (speed: Double?, unit: GPSSpeedUnit))?
    var telemetryIsFresh: Bool { state == .connected && vescRtStats.isFresh() }
    /// Also excludes the saved controller while it is temporarily disconnected.
    var selectedPeripheralID: UUID? {
        vesc?.identifier ?? UserDefaults.standard.string(forKey: "VESC_UUID").flatMap { UUID(uuidString: $0) }
    }

    override convenience init() { self.init(startBluetooth: true) }
    init(startBluetooth: Bool) {
        super.init()
        packet.packetReceived = { [weak self] in self?.packetReceived(data: $0) }
        if startBluetooth { activateBluetooth() }
    }
    private func activateBluetooth() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: .main)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.vescLoop() }
        vescTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        var cached = TelemetrySnapshot.load()
        cached.isConnected = false
        cached.save()
        WidgetCenter.shared.reloadTimelines(ofKind: TelemetrySnapshot.widgetKind)
    }
    /// Demo mode suspends the real radio and preserves an active ride as a connection gap.
    func setDemoMode(_ enabled: Bool) {
        if !enabled { activateBluetooth(); return }
        guard centralManager != nil else { return }
        vescTimer?.invalidate()
        vescTimer = nil
        connectTimer?.invalidate()
        connectTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        centralManager.stopScan()
        centralManager.delegate = nil
        if let vesc { centralManager.cancelPeripheralConnection(vesc); vesc.delegate = nil }
        vesc = nil
        clearConnection()
        centralManager = nil
        state = .start
    }
    deinit {
        vescTimer?.invalidate()
        connectTimer?.invalidate()
        reconnectTimer?.invalidate()
    }
    func restart(withNewDevice: Bool = false) {
        guard centralManager != nil else { activateBluetooth(); return }
        if withNewDevice && sessionLogger.isRecording {
            sessionLogger.endRide()
            guard !sessionLogger.isRecording else {
                connectionMessage = "Save the active ride before changing controller"
                return
            }
        }
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        connectTimer?.invalidate()
        connectTimer = nil
        if withNewDevice {
            UserDefaults.standard.removeObject(forKey: "VESC_UUID")
        }
        let old = vesc
        vesc = nil
        if let old { centralManager.cancelPeripheralConnection(old) }
        clearConnection()
        peripherals.removeAll()
        reconnectAttempt = 0
        if centralManager.state == .poweredOn { startScanning() } else { state = .off }
    }
    /// Stops a pending connection attempt only. The saved controller and any active ride are
    /// kept, and no automatic retry runs until the user scans again.
    func cancelConnectionAttempt() {
        guard centralManager != nil else { return }
        connectTimer?.invalidate()
        connectTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempt = 0
        let old = vesc
        vesc = nil
        if let old { centralManager.cancelPeripheralConnection(old) }
        clearConnection()
        guard centralManager.state == .poweredOn else { state = .off; return }
        state = .scanningIdle
        connectionMessage = ""
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard centralManager === central else { return }
        guard central.state == .poweredOn else {
            connectTimer?.invalidate()
            reconnectTimer?.invalidate()
            vesc = nil
            clearConnection()
            state = .off
            connectionMessage = central.state == .unauthorized ? "Allow Bluetooth in Settings" : "Bluetooth unavailable"
            return
        }
        retrievePeripheral(withDeviceID: UserDefaults.standard.string(forKey: "VESC_UUID") ?? "")
    }
    func retrievePeripheral(withDeviceID deviceID: String) {
        guard centralManager != nil, centralManager.state == .poweredOn else { return }
        guard let uuid = UUID(uuidString: deviceID),
              let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first else { startScanning(); return }
        connectPeripheral(peripheral: peripheral)
    }
    func startScanning() {
        guard centralManager != nil, centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        state = .scanning
        connectionMessage = "Looking for VESC"
    }
    func stopScanning() {
        guard centralManager != nil else { return }
        centralManager.stopScan()
        state = .scanningIdle
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard centralManager === central else { return }
        if !peripherals.contains(where: { $0.identifier == peripheral.identifier }) { peripherals.append(peripheral) }
        if peripheral.identifier.uuidString == UserDefaults.standard.string(forKey: "VESC_UUID") { connectPeripheral(peripheral: peripheral) }
    }
    func connectPeripheral(peripheral: CBPeripheral) {
        guard centralManager != nil, centralManager.state == .poweredOn else { return }
        if sessionLogger.isRecording,
           let savedIdentifier = UserDefaults.standard.string(forKey: "VESC_UUID"),
           savedIdentifier != peripheral.identifier.uuidString {
            sessionLogger.endRide()
            guard !sessionLogger.isRecording else {
                connectionMessage = "Save the active ride before changing controller"
                return
            }
        }
        if vesc?.identifier == peripheral.identifier && (state == .connecting || state == .connected) { return }
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        connectTimer?.invalidate()
        let old = vesc
        vesc = nil
        if let old, old.identifier != peripheral.identifier { centralManager.cancelPeripheralConnection(old) }
        clearConnection()
        centralManager.stopScan()
        vesc = peripheral
        state = .connecting
        connectionMessage = "Connecting…"
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        connectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.failConnection("Connection timed out") }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard centralManager === central else { return }
        guard peripheral.identifier == vesc?.identifier, state == .connecting else { return }
        peripheral.discoverServices([serviceUUID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard centralManager === central else { return }
        guard peripheral.identifier == vesc?.identifier else { return }
        failConnection("Connection failed")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard centralManager === central else { return }
        guard peripheral.identifier == vesc?.identifier else { return }
        failConnection("Connection lost")
    }
    private func clearConnection() {
        writeCharacteristic = nil
        notifyCharacteristic = nil
        requestQueue.reset()
        packet.resetState()
        vescRtStats.resetStats()
        vescStats.resetStats()
        lastTelemetryAt = nil
        connectedAt = nil
        sessionLogger.connectionChanged(isConnected: false)
        wasFresh = false
        publishCurrentSnapshot(forceReload: true)
    }
    private func failConnection(_ message: String) {
        guard centralManager != nil else { return }
        connectTimer?.invalidate()
        connectTimer = nil
        let old = vesc
        vesc = nil
        if let old { centralManager.cancelPeripheralConnection(old) }
        clearConnection()
        guard centralManager.state == .poweredOn else { state = .off; return }
        state = .scanningIdle
        connectionMessage = message + ". Retrying…"
        reconnectAttempt = min(reconnectAttempt + 1, 5)
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: min(30, pow(2, Double(reconnectAttempt))), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.retrievePeripheral(withDeviceID: UserDefaults.standard.string(forKey: "VESC_UUID") ?? "")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == vesc?.identifier else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { failConnection("VESC UART service unavailable"); return }
        peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == vesc?.identifier else { return }
        guard error == nil, let characteristics = service.characteristics,
              let write = characteristics.first(where: { $0.uuid == writeUUID }),
              let notify = characteristics.first(where: { $0.uuid == notifyUUID }),
              (write.properties.contains(.writeWithoutResponse) || write.properties.contains(.write)),
              (notify.properties.contains(.notify) || notify.properties.contains(.indicate)) else { failConnection("VESC UART characteristics unavailable"); return }
        writeCharacteristic = write
        notifyCharacteristic = notify
        peripheral.setNotifyValue(true, for: notify)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == vesc?.identifier, characteristic.uuid == notifyUUID else { return }
        guard error == nil, characteristic.isNotifying, writeCharacteristic != nil else { failConnection("VESC notifications unavailable"); return }
        connectTimer?.invalidate()
        connectTimer = nil
        reconnectAttempt = 0
        packet.resetState()
        state = .connected
        connectedAt = Date()
        connectionMessage = "Waiting for telemetry"
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "VESC_UUID")
        vescRtStats.updateStats(isConnected: true)
        sessionLogger.connectionChanged(isConnected: true)
        vescLoop()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == vesc?.identifier, state == .connected,
              characteristic.uuid == notifyUUID, error == nil, let value = characteristic.value else { return }
        packet.processData(data: value)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == vesc?.identifier, state == .connected,
              characteristic.uuid == writeUUID else { return }
        if error != nil { failConnection("Telemetry request failed"); return }
        requestQueue.complete()
        drainRequests()
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral.identifier == vesc?.identifier, state == .connected else { return }
        drainRequests()
    }
    private func sendData(data: Data) {
        guard state == .connected, requestQueue.enqueue(data) else { return }
        drainRequests()
    }
    private func drainRequests() {
        guard state == .connected, let peripheral = vesc, peripheral.state == .connected,
              let characteristic = writeCharacteristic else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        while requestQueue.inFlight == nil {
            if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse { return }
            guard let request = requestQueue.takeNext() else { return }
            let framed = packet.preparePacket(data: request)
            guard !framed.isEmpty, framed.count <= peripheral.maximumWriteValueLength(for: type) else {
                failConnection("Bluetooth query exceeds write capacity")
                return
            }
            peripheral.writeValue(framed, for: characteristic, type: type)
            if type == .withResponse { return } // Next query is sent after didWriteValueFor acknowledgement.
            requestQueue.complete()
        }
    }
    func packetReceived(data: Data) {
        guard state == .connected, let update = VescTelemetryDecoder.decode(data) else { return }
        switch update {
        case .realtime(let values):
            // Never mix partial responses into an apparently complete live sample.
            guard values.isComplete else { return }
            if !telemetryIsFresh { sessionLogger.connectionChanged(isConnected: false) }
            vescRtStats.updateStats(batteryVoltage: values.voltage, inputCurrent: values.inputCurrent,
                mosTemperature: values.controllerTemperature, motorTemperature: values.motorTemperature,
                wattHours: values.wattHours, rpm: values.rpm)
            let receivedAt = Date()
            vescRtStats.updateFaultCode(values.faultCode, at: receivedAt)
            vescRtStats.markTelemetryReceived(at: receivedAt)
            // BatteryConfig supplies the confirmed 12S default when no cell count was saved.
            if !BatteryConfig.useVescBatteryLevel, let voltage = values.voltage {
                vescRtStats.updateBatteryPercent(BatteryConfig.percent(fromVoltage: voltage), source: .voltageEstimate)
            }
            lastTelemetryAt = receivedAt
            sessionLogger.connectionChanged(isConnected: true)
            wasFresh = true
            connectionMessage = ""
            sessionLogger.record(rt: vescRtStats, speedMs: gpsSpeedProvider?())
            publishCurrentSnapshot()
        case .setup(let values):
            vescRtStats.updateStats(vescSpeed: values.speedMs)
            if BatteryConfig.useVescBatteryLevel, let level = values.batteryLevel {
                vescRtStats.updateBatteryPercent(level * 100, source: .vesc)
            }
        case .statistics(let values):
            vescStats.updateStats(runTime: values.runTime, maxPower: values.maxPower,
                avgPower: values.avgPower, maxMosTemperature: values.maxControllerTemperature,
                avgMosTemperature: values.avgControllerTemperature, maxCurrent: values.maxCurrent,
                avgCurrent: values.avgCurrent)
        }
        objectWillChange.send()
    }
    private func publishCurrentSnapshot(forceReload: Bool = false) {
        var snapshot = TelemetrySnapshot()
        let display = displaySpeedProvider?()
        snapshot.speed = display?.speed
        snapshot.speedUnit = (display?.unit ?? .kph).rawValue
        snapshot.watts = vescRtStats.instantWatts
        snapshot.batteryPercent = vescRtStats.batteryPercentIsAvailable ? vescRtStats.batteryPercent : nil
        snapshot.batteryVoltage = vescRtStats.batteryVoltage
        snapshot.mosTempC = vescRtStats.mosTemperature
        snapshot.motorTempC = vescRtStats.motorTemperature // Legacy cache field; not displayed.
        snapshot.faultCode = vescRtStats.faultCode
        snapshot.isConnected = state == .connected
        snapshot.updatedAt = lastTelemetryAt ?? .distantPast
        snapshot.save()
        if forceReload || Date().timeIntervalSince(lastWidgetReload) >= 30 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: TelemetrySnapshot.widgetKind)
        }
    }
    func vescLoop() {
        let fresh = telemetryIsFresh
        if wasFresh != fresh {
            wasFresh = fresh
            if !fresh { sessionLogger.connectionChanged(isConnected: false) }
            publishCurrentSnapshot(forceReload: true)
            objectWillChange.send()
        }
        guard state == .connected else { return }
        if let last = lastTelemetryAt ?? connectedAt, Date().timeIntervalSince(last) > 15 {
            failConnection("Telemetry stopped")
            return
        }
        connectionMessage = fresh ? "" : "Waiting for fresh telemetry"
        vescTimerCounter &+= 1
        var vb = VByteArray()
        vb.vbAppendUInt8(VescCommand.getValuesSelective)
        let mask: UInt32 = (1 << 15) | (1 << 11) | (1 << 8) | (1 << 7) | (1 << 3) | (1 << 0)
        vb.vbAppendUInt32(mask)
        sendData(data: vb.data)
        vb = VByteArray()
        vb.vbAppendUInt8(VescCommand.getValuesSetupSelective)
        vb.vbAppendUInt32((1 << 6) | (1 << 8))
        sendData(data: vb.data)
        guard vescTimerCounter % 5 == 0 else { return }
        vb = VByteArray()
        vb.vbAppendUInt8(VescCommand.getStats)
        let statsMask: UInt16 = (1 << 10) | (1 << 7) | (1 << 6) | (1 << 5) | (1 << 4) | (1 << 3) | (1 << 2)
        vb.vbAppendUInt16(statsMask)
        sendData(data: vb.data)
    }
}
