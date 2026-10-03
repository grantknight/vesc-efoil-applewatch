import Foundation

/// Read-only query scheduling shared by the native BLE driver and portable tests.
/// One request per command, including the single in-flight write, bounds memory to three requests.
struct VescRequestQueue {
    private var pending: [Data] = []
    private(set) var inFlight: Data?
    var pendingCount: Int { pending.count }
    var count: Int { pending.count + (inFlight == nil ? 0 : 1) }

    @discardableResult mutating func enqueue(_ request: Data) -> Bool {
        guard Self.isValid(request), let command = request.first else { return false }
        if inFlight?.first == command { return true }
        if let index = pending.firstIndex(where: { $0.first == command }) {
            pending[index] = request
        } else {
            guard count < 3 else { return false }
            pending.append(request)
        }
        return true
    }

    /// The caller checks radio capacity before taking a request. Acknowledged writes hold this slot.
    mutating func takeNext() -> Data? {
        guard inFlight == nil, !pending.isEmpty else { return nil }
        let request = pending.removeFirst()
        inFlight = request
        return request
    }

    mutating func complete() { inFlight = nil }
    mutating func reset() { pending.removeAll(); inFlight = nil }

    private static func isValid(_ request: Data) -> Bool {
        guard let command = request.first else { return false }
        let allowedMask: UInt32
        let length: Int
        switch command {
        case 50:
            allowedMask = (1 << 11) | (1 << 8) | (1 << 7) | (1 << 3) | (1 << 1) | (1 << 0)
            length = 5
        case 51:
            allowedMask = (1 << 6) | (1 << 8)
            length = 5
        case 128:
            allowedMask = (1 << 10) | (1 << 7) | (1 << 6) | (1 << 5) | (1 << 4) | (1 << 3) | (1 << 2)
            length = 3
        default: return false
        }
        guard request.count == length else { return false }
        let mask = request.dropFirst().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return mask != 0 && mask & ~allowedMask == 0
    }
}
