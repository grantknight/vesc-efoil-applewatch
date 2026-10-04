import Foundation

/// A complete measured series-group set, never inferred from pack voltage or percentage.
/// Construction is independent of the live BLE manager so demo data cannot enter its state.
struct BMSCellSnapshot: Equatable {
    let deviceID: UUID
    let cellVoltages: [Double]
    let measuredAt: Date
    var cellCount: Int { cellVoltages.count }
    var minVoltage: Double { cellVoltages.min()! }
    var maxVoltage: Double { cellVoltages.max()! }
    var deltaMillivolts: Double { (maxVoltage - minVoltage) * 1000 }

    init?(deviceID: UUID, cellVoltages: [Double], measuredAt: Date, expectedCellCount: Int = 12) {
        guard (1...50).contains(expectedCellCount), cellVoltages.count == expectedCellCount,
              // Preserve reported critically low cells. A future identified wire
              // driver must reject its own unavailable/sentinel values before construction.
              cellVoltages.allSatisfy({ $0.isFinite && (0...6.0).contains($0) }),
              measuredAt.timeIntervalSince1970.isFinite else { return nil }
        self.deviceID = deviceID
        self.cellVoltages = cellVoltages
        self.measuredAt = measuredAt
    }

    func isFresh(at date: Date = Date(), maxAge: TimeInterval = 10) -> Bool {
        let age = date.timeIntervalSince(measuredAt)
        return date.timeIntervalSince1970.isFinite && maxAge.isFinite && maxAge > 0
            && age.isFinite && age >= 0 && age < maxAge
    }
}

/// Bluetooth SIG standard data only; it identifies a device, not a cell protocol.
enum BMSStandardValue {
    static func batteryPercent(_ data: Data) -> Int? {
        guard data.count == 1, let byte = data.first, byte <= 100 else { return nil }
        return Int(byte)
    }

    static func deviceText(_ data: Data) -> String? {
        guard !data.isEmpty, data.count <= 128, let value = String(data: data, encoding: .utf8),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
