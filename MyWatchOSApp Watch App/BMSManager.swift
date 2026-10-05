import Foundation
import Combine
import CoreBluetooth

enum BMSConnectionState { case idle, scanning, connecting, linked, unavailable }
struct BMSDeviceDescriptor: Identifiable {
    let id: UUID
    let name: String
}

/// Independent second connection. Unknown vendor services are inspected by UUID only.
/// No write/notification subscription or cell-command guessing is performed.
final class BMSManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var state: BMSConnectionState = .idle
    @Published private(set) var devices: [BMSDeviceDescriptor] = []
    @Published private(set) var statusMessage = "Select your battery/BMS. Cell protocol unidentified."
    @Published private(set) var linkedDeviceName: String?
    @Published private(set) var manufacturer: String?
    @Published private(set) var model: String?
    @Published private(set) var standardBatteryPercent: Int?
    @Published private(set) var standardBatteryUpdatedAt: Date?
    @Published private(set) var cellSnapshot: BMSCellSnapshot? // Remains nil until an identified driver exists.
    @Published private(set) var discoveredServiceUUIDs: [String] = []
    @Published private(set) var discoveredCharacteristicUUIDs: [String] = []
    let expectedCellCount = 12

    private var central: CBCentralManager?
    private var selected: CBPeripheral?
    private var discovered: [UUID: CBPeripheral] = [:]
    private var excludedID: UUID?
    private var demoMode = false
    private var scanRequested = false
    private var scanTimer: Timer?
    private var connectionTimer: Timer?
    private var inspectionTimer: Timer?
    private var pollTimer: Timer?
    private var readTimer: Timer?
    // A lost link is retried a few times with backoff; a user disconnect or new choice cancels it.
    private var reconnectID: UUID?
    private var reconnectName: String?
    private var reconnectAttempt = 0
    private var reconnectTimer: Timer?
    private static let maxReconnectAttempts = 6
    private var readQueue: [CBCharacteristic] = []
    private var reading: CBCharacteristic?
    private var batteryCharacteristic: CBCharacteristic?
    private var servicesPending = Set<ObjectIdentifier>()
    private var inspectionActive = false
    private var seenStandardUUIDs = Set<CBUUID>()
    private let deviceInfo = CBUUID(string: "180A")
    private let batteryService = CBUUID(string: "180F")
    private let manufacturerUUID = CBUUID(string: "2A29")
    private let modelUUID = CBUUID(string: "2A24")
    private let batteryUUID = CBUUID(string: "2A19")

    override convenience init() { self.init(startBluetooth: true) }
    init(startBluetooth: Bool) {
        super.init()
        if startBluetooth { activate() }
    }
    private func activate() {
        guard !demoMode, central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }
    deinit {
        scanTimer?.invalidate(); connectionTimer?.invalidate(); inspectionTimer?.invalidate()
        pollTimer?.invalidate(); readTimer?.invalidate(); reconnectTimer?.invalidate()
    }

    func hasFreshStandardBatteryPercent(at date: Date = Date()) -> Bool {
        guard state == .linked, standardBatteryPercent != nil, let timestamp = standardBatteryUpdatedAt else { return false }
        let age = date.timeIntervalSince(timestamp)
        return age.isFinite && age >= 0 && age < 10
    }
    func excludePeripheral(_ id: UUID?) {
        excludedID = id
        if let id {
            discovered.removeValue(forKey: id)
            devices.removeAll { $0.id == id }
            if selected?.identifier == id || reconnectID == id {
                disconnect()
                statusMessage = "VESC excluded. Select a separate battery/BMS."
            }
        }
    }
    func setDemoMode(_ enabled: Bool) {
        guard demoMode != enabled else { return }
        demoMode = enabled
        if enabled {
            disconnect()
            // Retired-manager callbacks cannot mutate a future live session.
            central?.delegate = nil
            central = nil
            devices = []
            discovered = [:]
            statusMessage = "Demo only. Battery Bluetooth suspended."
        } else { statusMessage = "Select your battery/BMS. Cell protocol unidentified." }
    }
    func scan() {
        guard !demoMode else { return }
        guard selected == nil else {
            statusMessage = "Disconnect the battery/BMS before scanning again."
            return
        }
        cancelReconnect()
        scanRequested = true
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self, self.scanRequested else { return }
            self.disconnect()
            self.state = .unavailable
            self.statusMessage = "Bluetooth did not become available. Enable it and scan again."
        }
        activate()
        guard let central else { return }
        if central.state == .poweredOn { beginScan() }
        else { statusMessage = "Waiting for Bluetooth availability." }
    }
    private func beginScan() {
        guard !demoMode, let central, central.state == .poweredOn else { return }
        scanRequested = false
        scanTimer?.invalidate()
        devices = []; discovered = [:]
        state = .scanning
        statusMessage = "Scanning nearby BLE devices. Select your battery/BMS."
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self, self.state == .scanning else { return }
            self.central?.stopScan()
            self.state = .idle
            self.statusMessage = self.devices.isEmpty ? "No nearby devices found. Try scanning again." : "Scan complete. Select your battery/BMS."
        }
    }
    func connect(to id: UUID) {
        guard !demoMode else { return }
        guard id != excludedID else { statusMessage = "VESC excluded. Select a separate battery/BMS."; return }
        guard let central, central.state == .poweredOn, let peripheral = discovered[id] else {
            statusMessage = "Scan again before connecting the battery/BMS."
            return
        }
        guard selected == nil else {
            statusMessage = "Disconnect the current battery/BMS before choosing another device."
            return
        }
        cancelReconnect()
        central.stopScan(); scanTimer?.invalidate(); scanTimer = nil; scanRequested = false
        clearReadings()
        selected = peripheral
        peripheral.delegate = self
        linkedDeviceName = devices.first { $0.id == id }?.name ?? "Unnamed BLE device"
        state = .connecting
        statusMessage = "Connecting battery/BMS. Cell protocol unidentified."
        central.connect(peripheral, options: nil)
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self, weak peripheral] _ in
            guard let self, let peripheral, self.selected === peripheral, self.state == .connecting else { return }
            self.failConnection("Battery/BMS connection timed out.")
        }
    }
    /// User-initiated: also stops any automatic reconnection.
    func disconnect() {
        cancelReconnect()
        tearDown()
    }
    private func tearDown() {
        scanRequested = false
        central?.stopScan()
        scanTimer?.invalidate(); scanTimer = nil
        let old = selected
        selected = nil
        old?.delegate = nil
        if let old { central?.cancelPeripheralConnection(old) }
        // Retire the central so late connect/disconnect callbacks from an earlier
        // attempt cannot apply to a new attempt using the same peripheral UUID.
        central?.delegate = nil
        central = nil
        clearReadings()
        state = .idle
        statusMessage = "Battery/BMS disconnected. Cell readings unavailable."
    }
    private func clearReadings() {
        connectionTimer?.invalidate(); connectionTimer = nil
        inspectionTimer?.invalidate(); inspectionTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        readTimer?.invalidate(); readTimer = nil
        readQueue = []; reading = nil; batteryCharacteristic = nil; servicesPending = []
        inspectionActive = false; seenStandardUUIDs = []
        linkedDeviceName = nil; manufacturer = nil; model = nil
        standardBatteryPercent = nil; standardBatteryUpdatedAt = nil; cellSnapshot = nil
        discoveredServiceUUIDs = []; discoveredCharacteristicUUIDs = []
    }
    private func failConnection(_ message: String) { tearDown(); state = .unavailable; statusMessage = message }

    private func scheduleReconnect(_ id: UUID) {
        guard !demoMode, id != excludedID, reconnectAttempt < Self.maxReconnectAttempts else {
            cancelReconnect()
            return
        }
        reconnectID = id
        reconnectAttempt += 1
        let delay = min(30, 2 * pow(2, Double(reconnectAttempt - 1)))
        statusMessage = "Battery/BMS link lost. Reconnecting (attempt \(reconnectAttempt) of \(Self.maxReconnectAttempts)). VESC is unaffected."
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.reconnectTimer = nil
            self?.attemptReconnect()
        }
    }
    private func cancelReconnect() {
        reconnectTimer?.invalidate(); reconnectTimer = nil
        reconnectID = nil; reconnectName = nil; reconnectAttempt = 0
    }
    private func attemptReconnect() {
        guard let id = reconnectID, !demoMode, selected == nil, reconnectTimer == nil else { return }
        activate()
        // A newly created central continues from centralManagerDidUpdateState once powered on.
        guard let central, central.state == .poweredOn else { return }
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first, id != excludedID else {
            scheduleReconnect(id)
            return
        }
        selected = peripheral
        peripheral.delegate = self
        linkedDeviceName = reconnectName ?? "Battery/BMS"
        state = .connecting
        statusMessage = "Reconnecting battery/BMS. VESC is unaffected."
        central.connect(peripheral, options: nil)
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self, weak peripheral] _ in
            guard let self, let peripheral, self.selected === peripheral, self.state == .connecting else { return }
            let name = self.linkedDeviceName
            self.failConnection("Battery/BMS did not reconnect.")
            self.reconnectName = name
            self.scheduleReconnect(id)
        }
    }

    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        guard central === manager, !demoMode else { return }
        guard manager.state == .poweredOn else {
            let request = scanRequested || state == .scanning
            if manager.state == .unknown {
                scanRequested = request
                statusMessage = "Waiting for Bluetooth availability."
                return
            }
            disconnect()
            state = .unavailable
            statusMessage = manager.state == .unauthorized ? "Allow Bluetooth access in Settings." : "Battery Bluetooth unavailable."
            return
        }
        state = .idle
        if scanRequested { beginScan() }
        else if reconnectID != nil { attemptReconnect() }
    }
    func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === manager, !demoMode, state == .scanning, peripheral.identifier != excludedID,
              discovered[peripheral.identifier] != nil || discovered.count < 64 else { return }
        guard discovered[peripheral.identifier] == nil else { return }
        discovered[peripheral.identifier] = peripheral
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let raw = advertised ?? peripheral.name ?? "Unnamed BLE device"
        let name = String(raw.components(separatedBy: .controlCharacters).joined().prefix(80))
        devices.append(BMSDeviceDescriptor(id: peripheral.identifier, name: name.isEmpty ? "Unnamed BLE device" : name))
    }
    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === manager, !demoMode, selected === peripheral, state == .connecting,
              peripheral.identifier != excludedID else { return }
        connectionTimer?.invalidate(); connectionTimer = nil
        cancelReconnect()
        state = .linked
        inspectionActive = true
        statusMessage = "Linked. 12S cell protocol unidentified; no cell measurements."
        inspectionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self, weak peripheral] _ in
            guard let self, let peripheral, self.selected === peripheral, self.state == .linked else { return }
            self.servicesPending = []
            self.inspectionActive = false
            self.statusMessage = "Linked. Device inspection timed out; cell protocol unidentified."
        }
        peripheral.discoverServices(nil) // UUID diagnostics only; unknown values are never read.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.state == .linked, self.reading == nil, self.readQueue.isEmpty,
                  let characteristic = self.batteryCharacteristic else { return }
            self.readQueue = [characteristic]; self.drainReads()
        }
    }
    func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === manager, selected === peripheral, !demoMode else { return }
        let retrying = reconnectID == peripheral.identifier
        let name = linkedDeviceName
        failConnection("Battery/BMS connection failed. Retry after checking its phone app.")
        if retrying { reconnectName = name; scheduleReconnect(peripheral.identifier) }
    }
    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard central === manager, selected === peripheral, !demoMode else { return }
        let wasLinked = state == .linked || reconnectID == peripheral.identifier
        let name = linkedDeviceName
        failConnection("Battery/BMS link lost. VESC connection is independent.")
        if wasLinked { reconnectName = name; scheduleReconnect(peripheral.identifier) }
    }
    private func current(_ peripheral: CBPeripheral) -> Bool {
        !demoMode && state == .linked && selected === peripheral && peripheral.identifier != excludedID
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard current(peripheral), inspectionActive, servicesPending.isEmpty else { return }
        guard error == nil, let services = peripheral.services else {
            inspectionTimer?.invalidate(); inspectionTimer = nil
            inspectionActive = false
            statusMessage = "Linked. Services unavailable; cell protocol unidentified."
            return
        }
        let bounded = Array(services.prefix(32))
        discoveredServiceUUIDs = bounded.map { $0.uuid.uuidString }
        servicesPending = Set(bounded.map { ObjectIdentifier($0) })
        if bounded.isEmpty { inspectionTimer?.invalidate(); inspectionTimer = nil; inspectionActive = false }
        for service in bounded { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard current(peripheral), inspectionActive, servicesPending.remove(ObjectIdentifier(service)) != nil else { return }
        if error == nil {
            for characteristic in (service.characteristics ?? []).prefix(64) {
                if discoveredCharacteristicUUIDs.count < 64 {
                    discoveredCharacteristicUUIDs.append(service.uuid.uuidString + "/" + characteristic.uuid.uuidString)
                }
                let allowed = (service.uuid == deviceInfo && [manufacturerUUID, modelUUID].contains(characteristic.uuid))
                    || (service.uuid == batteryService && characteristic.uuid == batteryUUID)
                guard allowed, characteristic.properties.contains(.read), !seenStandardUUIDs.contains(characteristic.uuid), readQueue.count < 3,
                      reading?.uuid != characteristic.uuid, !readQueue.contains(where: { $0.uuid == characteristic.uuid }) else { continue }
                if characteristic.uuid == batteryUUID { batteryCharacteristic = characteristic }
                seenStandardUUIDs.insert(characteristic.uuid)
                readQueue.append(characteristic)
            }
            drainReads()
        }
        if servicesPending.isEmpty { inspectionTimer?.invalidate(); inspectionTimer = nil; inspectionActive = false }
    }
    private func drainReads() {
        guard let peripheral = selected, current(peripheral), reading == nil, !readQueue.isEmpty else { return }
        let next = readQueue.removeFirst()
        reading = next
        peripheral.readValue(for: next)
        readTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self, weak next] _ in
            guard let self, let next, self.reading === next else { return }
            // A timed-out ATT operation cannot be safely correlated with another read of this attribute.
            self.failConnection("Battery/BMS standard read timed out. Reconnect to inspect again.")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard current(peripheral), reading === characteristic else { return }
        readTimer?.invalidate(); readTimer = nil; reading = nil
        if error == nil, let data = characteristic.value {
            if characteristic.service?.uuid == deviceInfo && characteristic.uuid == manufacturerUUID {
                manufacturer = BMSStandardValue.deviceText(data)
            } else if characteristic.service?.uuid == deviceInfo && characteristic.uuid == modelUUID {
                model = BMSStandardValue.deviceText(data)
            } else if characteristic.service?.uuid == batteryService && characteristic.uuid == batteryUUID {
                standardBatteryPercent = BMSStandardValue.batteryPercent(data)
                standardBatteryUpdatedAt = standardBatteryPercent == nil ? nil : Date()
            }
        } else if characteristic.uuid == batteryUUID {
            standardBatteryPercent = nil; standardBatteryUpdatedAt = nil
        }
        drainReads()
    }
}
