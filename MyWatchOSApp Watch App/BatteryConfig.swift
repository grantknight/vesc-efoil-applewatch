//
//  BatteryConfig.swift
//  MyWatchOSApp Watch App
//

import Foundation

enum BatteryConfig {
    private static let cellCountKey = "BATTERY_CELL_COUNT"
    private static let useVescLevelKey = "BATTERY_USE_VESC_LEVEL"
    private static let minVoltagePerCellKey = "BATTERY_MIN_V_PER_CELL"
    private static let maxVoltagePerCellKey = "BATTERY_MAX_V_PER_CELL"

    static var cellCount: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: cellCountKey)
            return stored > 0 ? stored : 14
        }
        set {
            UserDefaults.standard.set(max(1, min(24, newValue)), forKey: cellCountKey)
        }
    }

    /// When true, prefer COMM_GET_VALUES_SETUP_SELECTIVE battery_level from VESC.
    static var useVescBatteryLevel: Bool {
        get {
            if UserDefaults.standard.object(forKey: useVescLevelKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: useVescLevelKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: useVescLevelKey)
        }
    }

    static var minVoltagePerCell: Double {
        get {
            let v = UserDefaults.standard.double(forKey: minVoltagePerCellKey)
            return v > 0 ? v : 3.3
        }
        set {
            UserDefaults.standard.set(newValue, forKey: minVoltagePerCellKey)
        }
    }

    static var maxVoltagePerCell: Double {
        get {
            let v = UserDefaults.standard.double(forKey: maxVoltagePerCellKey)
            return v > 0 ? v : 4.2
        }
        set {
            UserDefaults.standard.set(newValue, forKey: maxVoltagePerCellKey)
        }
    }

    static func percent(fromVoltage voltage: Double) -> Double {
        guard voltage > 0, cellCount > 0 else { return 0 }
        let minV = minVoltagePerCell * Double(cellCount)
        let maxV = maxVoltagePerCell * Double(cellCount)
        guard maxV > minV else { return 0 }
        let fraction = (voltage - minV) / (maxV - minV)
        return min(100, max(0, fraction * 100))
    }
}
