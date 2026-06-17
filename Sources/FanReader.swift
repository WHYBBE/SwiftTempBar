import IOKit

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
            let current = readFPE2(conn, "F\(i)Ac") ?? 0
            let minRPM = readFPE2(conn, "F\(i)Mn") ?? 0
            let maxRPM = readFPE2(conn, "F\(i)Mx") ?? 0
            if current > 0 || minRPM > 0 || maxRPM > 0 {
                fans.append(FanInfo(current: Int(current), min: Int(minRPM), max: Int(maxRPM)))
            }
        }
        return fans
    }

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct Vers {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyData {
        var key: UInt32 = 0
        var vers: Vers = .init()
        var pLimitData: PLimitData = .init()
        var keyInfo: KeyInfo = .init()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                    (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private static let KERNEL_INDEX_SMC: UInt32 = 2
    private static let SMC_CMD_READ_KEYINFO: UInt8 = 9
    private static let SMC_CMD_READ_BYTES: UInt8 = 5

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
    }

    private func readKey(_ conn: io_connect_t, _ key: String) -> (String, [UInt8])? {
        let packed = packKey(key)
        let size = MemoryLayout<SMCKeyData>.size

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = packed
        input.data8 = Self.SMC_CMD_READ_KEYINFO

        var outputSize = size
        let r1 = withUnsafePointer(to: &input) { inp in
            withUnsafeMutablePointer(to: &output) { out in
                IOConnectCallStructMethod(conn, Self.KERNEL_INDEX_SMC, inp, size, out, &outputSize)
            }
        }
        guard r1 == KERN_SUCCESS, output.result == 0 else { return nil }

        let dataSize = min(output.keyInfo.dataSize, 32)
        let dataType = unpackType(output.keyInfo.dataType)

        input = SMCKeyData()
        output = SMCKeyData()
        input.key = packed
        input.keyInfo.dataSize = dataSize
        input.data8 = Self.SMC_CMD_READ_BYTES

        outputSize = size
        let r2 = withUnsafePointer(to: &input) { inp in
            withUnsafeMutablePointer(to: &output) { out in
                IOConnectCallStructMethod(conn, Self.KERNEL_INDEX_SMC, inp, size, out, &outputSize)
            }
        }
        guard r2 == KERN_SUCCESS, output.result == 0 else { return nil }

        let byteData = withUnsafeBytes(of: output.bytes) { Array($0) }
        return (dataType, byteData)
    }

    private func readFPE2(_ conn: io_connect_t, _ key: String) -> Double? {
        guard let (type, bytes) = readKey(conn, key), bytes.count >= 2 else { return nil }
        if type != "fpe2" { return nil }
        let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        return Double(raw) / 4.0
    }

    private func readUI8(_ conn: io_connect_t, _ key: String) -> UInt8? {
        guard let (type, bytes) = readKey(conn, key), !bytes.isEmpty else { return nil }
        if type != "ui8" { return nil }
        return bytes[0]
    }
}
