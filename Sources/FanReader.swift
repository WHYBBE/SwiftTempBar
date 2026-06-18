import IOKit
import Foundation

final class FanReader {
    struct FanInfo {
        let current: Int
        let min: Int
        let max: Int
    }

    func readFans() -> [FanInfo] {
        guard let conn = openSMC() else { return [] }
        defer { IOServiceClose(conn) }

        guard let count = readUI8(conn, "FNum") else { return [] }
        var fans: [FanInfo] = []
        for i in 0..<min(Int(count), 32) {
            let current = readRPM(conn, "F\(i)Ac") ?? 0
            let minRPM = readRPM(conn, "F\(i)Mn") ?? 0
            let maxRPM = readRPM(conn, "F\(i)Mx") ?? 0
            if current > 0 || minRPM > 0 || maxRPM > 0 {
                fans.append(FanInfo(current: Int(current), min: Int(minRPM), max: Int(maxRPM)))
            }
        }
        return fans
    }

    private static let KERNEL_INDEX_SMC: UInt32 = 2
    private static let SMC_CMD_READ_KEYINFO: UInt8 = 9
    private static let SMC_CMD_READ_BYTES: UInt8 = 5
    private static let DATA_SIZE = 80

    private func openSMC() -> io_connect_t? {
        let matching = IOServiceMatching("AppleSMC")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let device = IOIteratorNext(iterator)
        guard device != 0 else { return nil }
        defer { IOObjectRelease(device) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(device, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        return conn
    }

    private func packKey(_ key: String) -> UInt32 {
        let bytes = Array(key.utf8)
        var result: UInt32 = 0
        for i in 0..<min(bytes.count, 4) {
            result |= UInt32(bytes[i]) << ((3 - i) * 8)
        }
        return result
    }

    private func unpackType(_ dataType: UInt32) -> String {
        String(format: "%c%c%c%c",
               UInt8((dataType >> 24) & 0xFF),
               UInt8((dataType >> 16) & 0xFF),
               UInt8((dataType >> 8) & 0xFF),
               UInt8(dataType & 0xFF))
            .trimmingCharacters(in: .whitespaces)
    }

    private func readKey(_ conn: io_connect_t, _ key: String) -> (String, [UInt8])? {
        let packed = packKey(key)
        let size = Self.DATA_SIZE

        var input = [UInt8](repeating: 0, count: size)
        var output = [UInt8](repeating: 0, count: size)

        input.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: packed, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: Self.SMC_CMD_READ_KEYINFO, toByteOffset: 42, as: UInt8.self)
        }

        var outputSize = size
        var r1: kern_return_t = 0
        input.withUnsafeBufferPointer { inp in
            output.withUnsafeMutableBufferPointer { out in
                r1 = IOConnectCallStructMethod(conn, Self.KERNEL_INDEX_SMC, inp.baseAddress, size, out.baseAddress, &outputSize)
            }
        }
        guard r1 == KERN_SUCCESS, output[40] == 0 else { return nil }

        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        output.withUnsafeBytes { buf in
            dataSize = buf.loadUnaligned(fromByteOffset: 28, as: UInt32.self)
            dataType = buf.loadUnaligned(fromByteOffset: 32, as: UInt32.self)
        }
        let typeStr = unpackType(dataType)
        let readSize = Int(min(dataSize, 32))

        input = [UInt8](repeating: 0, count: size)
        output = [UInt8](repeating: 0, count: size)

        input.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: packed, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: UInt32(readSize), toByteOffset: 28, as: UInt32.self)
            buf.storeBytes(of: Self.SMC_CMD_READ_BYTES, toByteOffset: 42, as: UInt8.self)
        }

        outputSize = size
        var r2: kern_return_t = 0
        input.withUnsafeBufferPointer { inp in
            output.withUnsafeMutableBufferPointer { out in
                r2 = IOConnectCallStructMethod(conn, Self.KERNEL_INDEX_SMC, inp.baseAddress, size, out.baseAddress, &outputSize)
            }
        }
        guard r2 == KERN_SUCCESS, output[40] == 0 else { return nil }

        let byteData = Array(output[48..<(48 + readSize)])
        return (typeStr, byteData)
    }

    private func readRPM(_ conn: io_connect_t, _ key: String) -> Double? {
        guard let (type, bytes) = readKey(conn, key) else { return nil }
        if type == "fpe2" && bytes.count >= 2 {
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0
        }
        if type == "flt" && bytes.count >= 4 {
            let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: raw))
        }
        return nil
    }

    private func readUI8(_ conn: io_connect_t, _ key: String) -> UInt8? {
        guard let (type, bytes) = readKey(conn, key), !bytes.isEmpty else { return nil }
        if type == "ui8" { return bytes[0] }
        return nil
    }
}
