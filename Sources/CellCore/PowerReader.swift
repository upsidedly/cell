import Foundation
import IOKit

/// Reads battery properties in-process. No registry property or CF object
/// crosses the actor boundary; callers receive only an immutable sample.
public actor PowerReader {
    public init() {}

    public func sample() throws -> PowerSample {
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard battery != IO_OBJECT_NULL else {
            throw PowerReadError.batteryUnavailable
        }
        defer { IOObjectRelease(battery) }

        var properties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(battery, &properties, kCFAllocatorDefault, 0)
        let retainedProperties = properties?.takeRetainedValue()
        guard status == KERN_SUCCESS else {
            throw PowerReadError.registryReadFailed(status)
        }
        guard let properties = retainedProperties,
              let values = properties as NSDictionary as? [String: Any] else {
            throw PowerReadError.invalidProperty("AppleSmartBattery")
        }
        return try PowerSample.decode(values, sampledAt: Date())
    }
}
