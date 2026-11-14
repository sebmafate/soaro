import Foundation
import IOKit

/// Températures, ventilateurs et puissance. Best-effort : ces lectures reposent sur des interfaces
/// non documentées par Apple (capteurs HID, SMC) qui peuvent changer d'une version de macOS à l'autre.
/// Toute défaillance renvoie simplement « rien » et l'interface masque la section.
final class SensorSampler {
    private let hid = HIDTemperatureReader()
    private let smc = SMCReader()

    func sample() -> SensorStats? {
        let temps = hid?.read() ?? []
        let fans = smc?.fans() ?? []
        let power = smc?.readDouble("PSTR")

        var stats = SensorStats(
            cpu: Self.average(temps, matching: ["tdie", "cpu", "pacc", "eacc"]),
            gpu: Self.average(temps, matching: ["gpu"]),
            ssd: Self.average(temps, matching: ["nand", "ssd"]),
            battery: Self.average(temps, matching: ["gas gauge", "battery"]),
            all: temps.sorted { $0.name < $1.name },
            fans: fans,
            systemPower: power.flatMap { $0 > 0 && $0 < 500 ? $0 : nil }
        )
        // Pas de capteur GPU nommé : clés SMC usuelles des puces Apple.
        if stats.gpu == nil {
            for key in ["Tg0f", "Tg0j", "Tg0D", "Tg05", "Tg0P"] {
                if let t = smc?.readDouble(key), t > 0, t < 150 { stats.gpu = t; break }
            }
        }
        // Sur Intel et d'anciens Mac, certaines températures ne sont accessibles que via le SMC.
        if stats.cpu == nil, let t = smc?.readDouble("TC0P") ?? smc?.readDouble("TC0D"), t > 0 { stats.cpu = t }
        return stats.isEmpty ? nil : stats
    }

    /// Moyenne des capteurs dont le nom contient l'un des motifs, en ignorant les valeurs aberrantes.
    static func average(_ sensors: [TemperatureSensor], matching patterns: [String]) -> Double? {
        let values = sensors
            .filter { s in patterns.contains { s.name.lowercased().contains($0) } }
            .map(\.celsius)
            .filter { $0 > 0 && $0 < 150 }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Capteurs de température HID (Apple Silicon)

final class HIDTemperatureReader {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloatFn = @convention(c) (UnsafeRawPointer, Int32) -> Double

    private let client: UnsafeMutableRawPointer
    private let copyServices: CopyServicesFn
    private let copyProperty: CopyPropertyFn
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let services = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let property = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let event = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let float = dlsym(handle, "IOHIDEventGetFloatValue")
        else { return nil }

        guard let client = unsafeBitCast(create, to: CreateFn.self)(kCFAllocatorDefault) else { return nil }
        // Page d'usage 0xff00 / usage 5 = capteurs de température Apple
        let matching: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        _ = unsafeBitCast(setMatching, to: SetMatchingFn.self)(client, matching as CFDictionary)

        self.client = client
        self.copyServices = unsafeBitCast(services, to: CopyServicesFn.self)
        self.copyProperty = unsafeBitCast(property, to: CopyPropertyFn.self)
        self.copyEvent = unsafeBitCast(event, to: CopyEventFn.self)
        self.getFloat = unsafeBitCast(float, to: GetFloatFn.self)
    }

    deinit { Unmanaged<AnyObject>.fromOpaque(client).release() }

    func read() -> [TemperatureSensor] {
        guard let array = copyServices(client)?.takeRetainedValue() else { return [] }
        var result: [TemperatureSensor] = []
        for index in 0..<CFArrayGetCount(array) {
            guard let service = CFArrayGetValueAtIndex(array, index) else { continue }
            let name = (copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? "Capteur \(index)"
            guard let event = copyEvent(service, Self.temperatureEventType, 0, 0) else { continue }
            let celsius = getFloat(event, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(event).release()
            if celsius.isFinite, celsius > -50, celsius < 200 {
                result.append(TemperatureSensor(name: name, celsius: celsius))
            }
        }
        return result
    }
}

// MARK: - SMC (ventilateurs, puissance)

final class SMCReader {
    private var connection: io_connect_t = 0

    // Disposition de `SMCKeyData_t` (80 octets), manipulée par décalages pour éviter tout écart de padding.
    private enum Offset {
        static let key = 0, dataSize = 28, dataType = 32, dataAttributes = 36
        static let result = 40, status = 41, command = 42, bytes = 48
        static let size = 80
    }
    private enum Command: UInt8 { case readBytes = 5, getKeyInfo = 9 }

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    struct Value { var type: String; var bytes: [UInt8] }

    func read(_ key: String) -> Value? {
        guard key.utf8.count == 4 else { return nil }

        var input = [UInt8](repeating: 0, count: Offset.size)
        Self.store(UInt32(fourCC: key), in: &input, at: Offset.key)
        input[Offset.command] = Command.getKeyInfo.rawValue
        guard let info = call(input), info[Offset.result] == 0 else { return nil }

        let size = Int(Self.load(UInt32.self, from: info, at: Offset.dataSize))
        let type = Self.load(UInt32.self, from: info, at: Offset.dataType).fourCCString
        guard size > 0, size <= 32 else { return nil }

        var request = [UInt8](repeating: 0, count: Offset.size)
        Self.store(UInt32(fourCC: key), in: &request, at: Offset.key)
        Self.store(UInt32(size), in: &request, at: Offset.dataSize)
        request[Offset.command] = Command.readBytes.rawValue
        guard let output = call(request), output[Offset.result] == 0 else { return nil }
        return Value(type: type, bytes: Array(output[Offset.bytes..<(Offset.bytes + size)]))
    }

    func readDouble(_ key: String) -> Double? {
        read(key).flatMap { Self.decode($0) }
    }

    func fans() -> [FanInfo] {
        guard let count = readDouble("FNum"), count >= 1, count <= 8 else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let rpm = readDouble("F\(i)Ac") else { return nil }
            return FanInfo(index: i, rpm: rpm, minRPM: readDouble("F\(i)Mn"), maxRPM: readDouble("F\(i)Mx"))
        }
    }

    /// Décode les types SMC courants. Les flottants sont en ordre d'octets natif, les entiers en big-endian.
    static func decode(_ value: Value) -> Double? {
        let b = value.bytes
        switch value.type {
        case "flt ":
            guard b.count >= 4 else { return nil }
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            let f = Double(Float(bitPattern: bits))
            return f.isFinite ? f : nil
        case "ui8 ": return b.first.map(Double.init)
        case "ui16": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case "ui32": return b.count >= 4 ? Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])) : nil
        case "sp78": return b.count >= 2 ? Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 : nil
        case "fpe2": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4 : nil
        default: return nil
        }
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var input = input
        var output = [UInt8](repeating: 0, count: Offset.size)
        var outputSize = Offset.size
        let status = input.withUnsafeMutableBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection, 2, inPtr.baseAddress, Offset.size, outPtr.baseAddress, &outputSize)
            }
        }
        return status == KERN_SUCCESS ? output : nil
    }

    private static func store(_ value: UInt32, in buffer: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { for i in 0..<4 { buffer[offset + i] = $0[i] } }
    }

    private static func load<T: FixedWidthInteger>(_ type: T.Type, from buffer: [UInt8], at offset: Int) -> T {
        buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
}

private extension UInt32 {
    /// « FNum » → entier 32 bits big-endian, comme attendu par le SMC.
    init(fourCC: String) {
        self = fourCC.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    var fourCCString: String {
        String(decoding: [UInt8(self >> 24 & 0xff), UInt8(self >> 16 & 0xff), UInt8(self >> 8 & 0xff), UInt8(self & 0xff)], as: UTF8.self)
    }
}
