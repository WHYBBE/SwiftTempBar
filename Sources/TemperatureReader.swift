import Foundation

final class TemperatureReader {
    func readTemperature(mode: DisplayMode) -> Double? {
        let sensors = Self.getThermalSensors()
        var hottest: Double?

        for sensor in sensors {
            guard sensor.value >= 0.0 && sensor.value < 110.0 else { continue }
            let match = switch mode {
            case .cpu: Self.isLikelyCPUName(sensor.name)
            case .gpu: Self.isLikelyGPUName(sensor.name)
            }
            if match, sensor.value > (hottest ?? 0) {
                hottest = sensor.value
            }
        }
        return hottest
    }
}

enum DisplayMode {
    case cpu
    case gpu

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        }
    }
}

private extension TemperatureReader {
    struct ThermalSensor {
        let name: String
        let value: Double
    }

    static func isLikelyCPUName(_ name: String) -> Bool {
        name.hasPrefix("PMU tdie") ||
        name.hasPrefix("PMU tdev") ||
        name.hasPrefix("pACC MTR Temp") ||
        name.hasPrefix("eACC MTR Temp") ||
        name.contains("CPU")
    }

    static func isLikelyGPUName(_ name: String) -> Bool {
        name.hasPrefix("GPU MTR Temp Sensor") ||
        name.contains("GPU") ||
        name.hasPrefix("PMU2 tdie") ||
        name.hasPrefix("PMU2 tdev")
    }
}

private enum HIDAPI {
    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    typealias CreateFunc = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    typealias SetMatchingFunc = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Int32
    typealias CopyServicesFunc = @convention(c) (UnsafeMutableRawPointer) -> CFArray?
    typealias CopyPropertyFunc = @convention(c) (UnsafeMutableRawPointer, CFString) -> Unmanaged<AnyObject>?
    typealias CopyEventFunc = @convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    typealias GetFloatValueFunc = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double

    static let create: CreateFunc? = load("IOHIDEventSystemClientCreate")
    static let setMatching: SetMatchingFunc? = load("IOHIDEventSystemClientSetMatching")
    static let copyServices: CopyServicesFunc? = load("IOHIDEventSystemClientCopyServices")
    static let copyProperty: CopyPropertyFunc? = load("IOHIDServiceClientCopyProperty")
    static let copyEvent: CopyEventFunc? = load("IOHIDServiceClientCopyEvent")
    static let getFloatValue: GetFloatValueFunc? = load("IOHIDEventGetFloatValue")

    private static func load<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}

private let kIOHIDEventTypeTemperature: Int64 = 15

private let thermalMatchingDict: CFDictionary = {
    var page: Int32 = 0xff00
    var usage: Int32 = 5
    let pageNum = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &page) as CFNumber
    let usageNum = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &usage) as CFNumber
    return [
        "PrimaryUsagePage" as CFString: pageNum,
        "PrimaryUsage" as CFString: usageNum
    ] as CFDictionary
}()

private func rawRelease(_ ptr: UnsafeMutableRawPointer) {
    Unmanaged<CFTypeRef>.fromOpaque(ptr).release()
}

private extension TemperatureReader {
    static func getThermalSensors() -> [ThermalSensor] {
        guard let create = HIDAPI.create,
              let setMatching = HIDAPI.setMatching,
              let copyServices = HIDAPI.copyServices,
              let copyProperty = HIDAPI.copyProperty,
              let copyEvent = HIDAPI.copyEvent,
              let getFloatValue = HIDAPI.getFloatValue
        else { return [] }

        guard let system = create(kCFAllocatorDefault) else { return [] }
        _ = setMatching(system, thermalMatchingDict)
        guard let services = copyServices(system) else { rawRelease(system); return [] }

        var sensors: [ThermalSensor] = []
        let count = CFArrayGetCount(services)
        let field = Int32(kIOHIDEventTypeTemperature << 16)
        for i in 0..<count {
            let ptr = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(services, i))
            let name: String
            if let ref = copyProperty(ptr!, "Product" as CFString) {
                name = ref.takeRetainedValue() as? String ?? "noname"
            } else {
                name = "noname"
            }
            var value: Double = 0
            if let event = copyEvent(ptr!, kIOHIDEventTypeTemperature, 0, 0) {
                value = getFloatValue(event, field)
                rawRelease(event)
            }
            sensors.append(ThermalSensor(name: name, value: value))
        }
        rawRelease(Unmanaged.passUnretained(services).toOpaque())
        rawRelease(system)
        return sensors
    }
}
