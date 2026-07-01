#if canImport(UIKit)
import UIKit

/// Precise hardware identifier (e.g. "iPhone14,5"), the closest iOS equivalent to ClientPython's
/// `platform.machine()` used as `device_type` in the RFC 8628 authorization request.
func deviceHardwareIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
}

/// Mirrors ClientPython's `platform.platform()` used as `device_os`.
@MainActor
func deviceOSDescription() -> String {
    "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
}
#endif
