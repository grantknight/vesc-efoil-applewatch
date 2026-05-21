//
//  BLuetoothManager.swift
//  MyWatchOSApp Watch App
//
//  Created by Gregory Dymarek on 09/07/2025.
//

import Foundation
import CoreBluetooth

var DEBUG = false

private enum VescCommand {
    static let getValuesSelective: UInt8 = 50
    static let getValuesSetupSelective: UInt8 = 51
    static let getStats: UInt8 = 128
}

enum btStateEnum {
    case off, start, scanning, scanningIdle, connecting, connected
}

enum BluetoothError: Error {
    case timeout
    case connectTimeout
    case bluetoothNotAvailable
}

extension Data {
    func hexEncodedString(upperCase: Bool = false) -> String {
        let format = upperCase ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined(separator: " ")
    }
}

extension Array where Element == UInt8 {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhX", $0) }.joined(separator: " ")
    }
}

extension ArraySlice where Element == UInt8 {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhX", $0) }.joined(separator: " ")
    }
}

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var vescTimer: Timer?
    private var vescTimerCounter: UInt = 0
    private var connectTimer: Timer?
    private let connectTimeoutInterval: TimeInterval = 15.0

    @Published var state = btStateEnum.start
    @Published var peripherals: [CBPeripheral] = []
    @Published var connectionMessage: String = ""

    private var vesc: CBPeripheral?
    private var char: CBCharacteristic?

    private let packet: Packet = Packet()
    let vescRtStats = VESCRtStats()
    let vescStats = VESCStats()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        packet.packetReceived = self.packetReceived

        vescTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.vescLoop()
        }
        if DEBUG {
            print("BluetoothManager INIT")
        }
    }

    func restart(withNewDevice: Bool = false) {
        if DEBUG { print("BluetoothManager RESET") }

        if withNewDevice {
            UserDefaults.standard.removeObject(forKey: "VESC_UUID")
        }

        if centralManager.isScanning {
            stopScanning()
        }

        if let vesc {
            centralManager.cancelPeripheralConnection(vesc)
        }
        vesc = nil
        char = nil

        vescRtStats.resetStats()
        vescStats.resetStats()
        connectionMessage = ""

        peripherals.removeAll()
        startScanning()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = .start
            retrievePeripheral(withDeviceID: UserDefaults.standard.string(forKey: "VESC_UUID") ?? "")
        case .poweredOff, .unauthorized, .unsupported:
            state = .off
        default:
            state = .off
        }
    }

    func retrievePeripheral(withDeviceID deviceID: String) {
        guard let uuid = UUID(uuidString: deviceID) else {
            startScanning()
            return
        }
        let retrieved = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = retrieved.first {
            connectionMessage = "Reconnecting..."
            connectPeripheral(peripheral: peripheral)
        } else {
            startScanning()
        }
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }

        let serviceUUIDs = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        centralManager.scanForPeripherals(withServices: [serviceUUIDs], options: nil)
        state = .scanning
        connectionMessage = ""
    }

    func stopScanning() {
        if !centralManager.isScanning {
            state = .scanningIdle
            return
        }
        centralManager.stopScan()
        state = .scanningIdle
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !peripherals.contains(peripheral) {
            peripherals.append(peripheral)
        }

        let savedPeripheral = UserDefaults.standard.string(forKey: "VESC_UUID")
        if peripheral.identifier.uuidString == savedPeripheral {
            stopScanning()
            connectPeripheral(peripheral: peripheral)
        }
    }

    func connectPeripheral(peripheral: CBPeripheral) {
        if centralManager.isScanning {
            stopScanning()
        }

        state = .connecting
        connectionMessage = "Connecting..."
        vesc = peripheral

        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ]
        centralManager.connect(peripheral, options: options)

        connectTimer = Timer.scheduledTimer(withTimeInterval: connectTimeoutInterval, repeats: false) { [weak self] _ in
            self?.handleConnectCompletion(.failure(BluetoothError.connectTimeout))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if DEBUG {
            print("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        }
        stopConnecting()
        state = .scanningIdle
        connectionMessage = "Connection failed"
        restart()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == vesc?.identifier else { return }
        if DEBUG {
            print("Disconnected: \(error?.localizedDescription ?? "no error")")
        }
        handleDisconnect()
    }

    private func handleConnectCompletion(_ result: Result<CBPeripheral, Error>) {
        switch result {
        case .success(let peripheral):
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "VESC_UUID")
            connectTimer?.invalidate()
            connectTimer = nil
            state = .connected
            connectionMessage = ""
            packet.resetState()
            vescRtStats.updateStats(isConnected: true)
            objectWillChange.send()
        case .failure:
            stopConnecting()
            connectionMessage = "Connection timed out"
            restart()
        }
    }

    private func handleDisconnect() {
        connectTimer?.invalidate()
        connectTimer = nil
        char = nil

        vescRtStats.resetStats()
        vescStats.resetStats()

        let savedUUID = UserDefaults.standard.string(forKey: "VESC_UUID") ?? ""
        if !savedUUID.isEmpty {
            state = .connecting
            connectionMessage = "Reconnecting..."
            if let peripheral = vesc {
                centralManager.connect(peripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
                ])
                connectTimer = Timer.scheduledTimer(withTimeInterval: connectTimeoutInterval, repeats: false) { [weak self] _ in
                    self?.handleConnectCompletion(.failure(BluetoothError.connectTimeout))
                }
            } else {
                retrievePeripheral(withDeviceID: savedUUID)
            }
        } else {
            vesc = nil
            state = .scanningIdle
            connectionMessage = "Disconnected"
            startScanning()
        }
        objectWillChange.send()
    }

    private func stopConnecting() {
        if let vesc {
            centralManager.cancelPeripheralConnection(vesc)
        }
        connectTimer?.invalidate()
        connectTimer = nil
        vesc = nil
        char = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            if DEBUG { print("didDiscoverServices error: \(error.localizedDescription)") }
            state = .start
            return
        }
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let writeCharUuid = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

        if let error {
            if DEBUG { print("Characteristic discovery error: \(error.localizedDescription)") }
            state = .start
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            peripheral.setNotifyValue(true, for: characteristic)
            if characteristic.uuid == writeCharUuid {
                char = characteristic
                handleConnectCompletion(.success(peripheral))
                vescLoop()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            if DEBUG { print("didUpdateValueFor error: \(error.localizedDescription)") }
            return
        }
        packet.processData(data: characteristic.value ?? Data())
    }

    func sendData(data: Data) {
        guard let vesc else { return }

        switch vesc.state {
        case .disconnected:
            handleDisconnect()
            return
        case .connected:
            break
        default:
            return
        }

        guard let char else { return }

        let packetData = packet.preparePacket(data: data)
        vesc.writeValue(packetData, for: char, type: .withoutResponse)
    }

    func packetReceived(data: Data) {
        var vb = VByteArray(data: data)
        let id = vb.vbPopFrontUInt8()

        if id == VescCommand.getValuesSelective {
            parseValuesSelective(&vb)
        } else if id == VescCommand.getValuesSetupSelective {
            parseValuesSetupSelective(&vb)
        } else if id == VescCommand.getStats {
            parseStats(&vb)
        }

        objectWillChange.send()
    }

    private func parseValuesSelective(_ vb: inout VByteArray) {
        let mask = vb.vbPopFrontUInt32()

        if mask & (1 << 0) != 0 {
            vescRtStats.updateStats(mosTemperature: vb.vbPopFrontDouble16(scale: 10.0))
        }
        if mask & (1 << 3) != 0 {
            vescRtStats.updateStats(inputCurrent: vb.vbPopFrontDouble32(scale: 100.0))
        }
        if mask & (1 << 7) != 0 {
            vescRtStats.updateStats(rpm: vb.vbPopFrontDouble32(scale: 1.0))
        }
        if mask & (1 << 8) != 0 {
            vescRtStats.updateStats(batteryVoltage: vb.vbPopFrontDouble16(scale: 10.0))
        }
        if mask & (1 << 11) != 0 {
            vescRtStats.updateStats(wattHours: vb.vbPopFrontDouble32(scale: 10000.0))
        }
    }

    private func parseValuesSetupSelective(_ vb: inout VByteArray) {
        let mask = vb.vbPopFrontUInt32()

        if mask & (1 << 6) != 0 {
            vescRtStats.updateStats(vescSpeed: vb.vbPopFrontDouble32(scale: 1000.0))
        }
        if mask & (1 << 8) != 0 {
            let level = vb.vbPopFrontDouble16(scale: 1000.0)
            vescRtStats.updateStats(batteryPercent: level * 100.0)
        }
    }

    private func parseStats(_ vb: inout VByteArray) {
        // Response echoes mask as uint32 per VESC firmware.
        let mask = vb.vbPopFrontUInt32()

        if mask & (1 << 2) != 0 {
            vescStats.updateStats(avgPower: vb.vbPopFrontDouble32Auto())
        }
        if mask & (1 << 3) != 0 {
            vescStats.updateStats(maxPower: vb.vbPopFrontDouble32Auto())
        }
        if mask & (1 << 4) != 0 {
            vescStats.updateStats(avgCurrent: vb.vbPopFrontDouble32Auto())
        }
        if mask & (1 << 5) != 0 {
            vescStats.updateStats(maxCurrent: vb.vbPopFrontDouble32Auto())
        }
        if mask & (1 << 6) != 0 {
            vescStats.updateStats(avgMosTemperature: vb.vbPopFrontDouble32Auto())
        }
        if mask & (1 << 7) != 0 {
            vescStats.updateStats(maxMosTemperature: vb.vbPopFrontDouble32Auto())
        }
        if mask & (1 << 10) != 0 {
            vescStats.updateStats(runTime: vb.vbPopFrontDouble32Auto())
        }
    }

    func vescLoop() {
        guard char != nil else { return }

        vescTimerCounter += 1

        var vb = VByteArray()
        vb.vbAppendUInt8(VescCommand.getValuesSelective)
        var mask: UInt32 = 0
        mask |= UInt32(1) << 11
        mask |= UInt32(1) << 8
        mask |= UInt32(1) << 7
        mask |= UInt32(1) << 3
        mask |= UInt32(1) << 0
        vb.vbAppendUInt32(mask)
        sendData(data: vb.data)

        vb = VByteArray()
        vb.vbAppendUInt8(VescCommand.getValuesSetupSelective)
        var setupMask: UInt32 = 0
        setupMask |= UInt32(1) << 6  // speed (m/s)
        setupMask |= UInt32(1) << 8  // battery level (0–1)
        vb.vbAppendUInt32(setupMask)
        sendData(data: vb.data)

        if vescTimerCounter % 5 != 0 { return }

        vb = VByteArray()
        vb.vbAppendUInt8(VescCommand.getStats)
        // Request mask is uint16 per VESC firmware; response echoes uint32.
        var statsMask: UInt16 = 0
        statsMask |= UInt16(1) << 10
        statsMask |= UInt16(1) << 7
        statsMask |= UInt16(1) << 6
        statsMask |= UInt16(1) << 5
        statsMask |= UInt16(1) << 4
        statsMask |= UInt16(1) << 3
        statsMask |= UInt16(1) << 2
        vb.vbAppendUInt16(statsMask)
        sendData(data: vb.data)
    }
}
