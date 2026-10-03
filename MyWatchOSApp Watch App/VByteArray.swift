import Foundation

struct VByteArray {
    public var data: Data

    init() {
        self.data = Data()
    }

    init(data: Data) {
        self.data = data
    }

    private func roundDouble(_ x: Double) -> Double {
        x < 0.0 ? ceil(x - 0.5) : floor(x + 0.5)
    }

    mutating func vbAppendInt64(_ number: Int64) {
        let bytes = withUnsafeBytes(of: number.bigEndian) { Data($0) }
        data.append(bytes)
    }

    mutating func vbAppendUInt64(_ number: UInt64) {
        let bytes = withUnsafeBytes(of: number.bigEndian) { Data($0) }
        data.append(bytes)
    }

    mutating func vbAppendInt32(_ number: Int32) {
        let bytes = withUnsafeBytes(of: number.bigEndian) { Data($0) }
        data.append(bytes)
    }

    mutating func vbAppendUInt32(_ number: UInt32) {
        let bytes = withUnsafeBytes(of: number.bigEndian) { Data($0) }
        data.append(bytes)
    }

    mutating func vbAppendInt16(_ number: Int16) {
        let bytes = withUnsafeBytes(of: number.bigEndian) { Data($0) }
        data.append(bytes)
    }

    mutating func vbAppendUInt16(_ number: UInt16) {
        let bytes = withUnsafeBytes(of: number.bigEndian) { Data($0) }
        data.append(bytes)
        
        //data.append(UInt8(number >> 8))
        //data.append(UInt8(number & 0xFF))
        
    }

    mutating func vbAppendInt8(_ number: Int8) {
        data.append(UInt8(bitPattern: number))
    }

    mutating func vbAppendUInt8(_ number: UInt8) {
        data.append(number)
    }

    mutating func vbAppendDouble64(_ number: Double, scale: Double) {
        vbAppendInt64(Int64(roundDouble(number * scale)))
    }

    mutating func vbAppendDouble32(_ number: Double, scale: Double) {
        vbAppendInt32(Int32(roundDouble(number * scale)))
    }

    mutating func vbAppendDouble16(_ number: Double, scale: Double) {
        vbAppendInt16(Int16(roundDouble(number * scale)))
    }

    mutating func vbAppendDouble32Auto(_ number: Double) {
        // VESC auto floats use IEEE-754 single precision, with tiny values
        // flushed to zero. Using bitPattern also handles negative exponents.
        let narrowed = Float(number)
        let value: Float = abs(narrowed) < 1.5e-38 ? 0 : narrowed
        vbAppendUInt32(value.bitPattern)
    }

    mutating func vbAppendDouble64Auto(_ number: Double) {
        let n = Float(number)
        let err = Float(number - Double(n))
        vbAppendDouble32Auto(Double(n))
        vbAppendDouble32Auto(Double(err))
    }

    mutating func vbAppendString(_ str: String) {
        if let stringData = str.data(using: .utf8) {
            data.append(stringData)
            data.append(0)
        } else {
            data.append(0)
        }
    }

    mutating func vbPopFrontInt64() -> Int64 {
        guard data.count >= 8 else { return 0 }

        //print("data startIndex\(data.startIndex)")
        
        var res: Int64 = 0
            res |= Int64(data[data.startIndex]) << 56
            res |= Int64(data[data.startIndex + 1]) << 48
            res |= Int64(data[data.startIndex + 2]) << 40
            res |= Int64(data[data.startIndex + 3]) << 32
            res |= Int64(data[data.startIndex + 4]) << 24
            res |= Int64(data[data.startIndex + 5]) << 16
            res |= Int64(data[data.startIndex + 6]) << 8
            res |= Int64(data[data.startIndex + 7])
        
        data.removeFirst(8)
        return res
    }

    mutating func vbPopFrontUInt64() -> UInt64 {
        guard data.count >= 8 else { return 0 }

        //print("data startIndex\(data.startIndex)")
        
        var res: UInt64 = 0
            res |= UInt64(data[data.startIndex]) << 56
            res |= UInt64(data[data.startIndex + 1]) << 48
            res |= UInt64(data[data.startIndex + 2]) << 40
            res |= UInt64(data[data.startIndex + 3]) << 32
            res |= UInt64(data[data.startIndex + 4]) << 24
            res |= UInt64(data[data.startIndex + 5]) << 16
            res |= UInt64(data[data.startIndex + 6]) << 8
            res |= UInt64(data[data.startIndex + 7])
        
        data.removeFirst(8)
        return res
    }

    mutating func vbPopFrontInt32() -> Int32 {
        guard data.count >= 4 else { return 0 }
        
        //print("data startIndex\(data.startIndex)")
        
        var res: Int32 = 0
        res |= Int32(data[data.startIndex]) << 24
        res |= Int32(data[data.startIndex + 1]) << 16
        res |= Int32(data[data.startIndex + 2]) << 8
        res |= Int32(data[data.startIndex + 3])
        
        data.removeFirst(4)
        return res
    }

    mutating func vbPopFrontUInt32() -> UInt32 {
        
        guard data.count >= 4 else { return 0 }
        
        //print("data startIndex\(data.startIndex)")
        
        var res: UInt32 = 0
        res |= UInt32(data[data.startIndex]) << 24
        res |= UInt32(data[data.startIndex + 1]) << 16
        res |= UInt32(data[data.startIndex + 2]) << 8
        res |= UInt32(data[data.startIndex + 3])

        data.removeFirst(4)
        return res
    }

    mutating func vbPopFrontInt16() -> Int16 {
        guard data.count >= 2 else { return 0 }
        
        //print("data startIndex\(data.startIndex)")
        
        let res = Int16(data[data.startIndex]) << 8 |
                  Int16(data[data.startIndex+1])
        
        data.removeFirst(2)
        return res
    }

    mutating func vbPopFrontUInt16() -> UInt16 {
        guard data.count >= 2 else { return 0 }

        //print("data startIndex\(data.startIndex)")
        
        let res = UInt16(data[data.startIndex]) << 8 |
                  UInt16(data[data.startIndex+1])
        
        data.removeFirst(2)
        return res
    }

    mutating func vbPopFrontInt8() -> Int8 {
        guard !data.isEmpty else { return 0 }
        let value = Int8(bitPattern: data.removeFirst())
        return value
    }

    mutating func vbPopFrontUInt8() -> UInt8 {
        guard !data.isEmpty else { return 0 }
        let value = data.removeFirst()
        return value
    }

    mutating func vbPopFrontDouble64(scale: Double) -> Double {
        Double(vbPopFrontInt64()) / scale
    }

    mutating func vbPopFrontDouble32(scale: Double) -> Double {
        Double(vbPopFrontInt32()) / scale
    }

    mutating func vbPopFrontDouble16(scale: Double) -> Double {
        Double(vbPopFrontInt16()) / scale
    }

    mutating func vbPopFrontDouble32Auto() -> Double {
        // Match util/buffer.c, including its special exponent-zero significand rule.
        // Normal numbers match IEEE Float; subnormal wire patterns do not.
        let bits = vbPopFrontUInt32()
        let exponent = Int((bits >> 23) & 0xff)
        let mantissa = bits & 0x7fffff
        guard exponent != 0 || mantissa != 0 else {
            return bits & 0x80000000 != 0 ? -Double.zero : Double.zero
        }
        let significand = Float(Double(mantissa) / 16_777_216 + 0.5)
        let magnitude = Float(Double(significand) * pow(2, Double(exponent - 126)))
        return Double(bits & 0x80000000 != 0 ? -magnitude : magnitude)
    }

    mutating func vbPopFrontDouble64Auto() -> Double {
        let n = vbPopFrontDouble32Auto()
        let err = vbPopFrontDouble32Auto()
        return n + err
    }

    mutating func vbPopFrontString() -> String {
        guard !data.isEmpty else { return "" }
        guard let nullIndex = data.firstIndex(of: 0) else { return "" }
        let length = data.distance(from: data.startIndex, to: nullIndex)
        let stringData = data.prefix(length)
        data.removeFirst(length + 1)
        return String(data: stringData, encoding: .utf8) ?? ""
    }
}
