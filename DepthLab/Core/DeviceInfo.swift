import Foundation
import UIKit

enum DeviceInfo {
    /// Hardware identifier such as "iPhone16,2".
    static var identifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static let names = [
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
    ]

    /// Friendly name when known, otherwise the raw identifier.
    static var model: String {
        #if targetEnvironment(simulator)
        return "Simulator (\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? identifier))"
        #else
        return names[identifier].map { "\($0) (\(identifier))" } ?? identifier
        #endif
    }

    static var systemVersion: String { UIDevice.current.systemVersion }
}
