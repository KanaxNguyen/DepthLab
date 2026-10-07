import SwiftUI
import UIKit

enum Format {
    static func meters(_ v: Float?) -> String { v.map { String(format: "%.2f m", $0) } ?? "—" }
    static func meters(_ v: Double?) -> String { v.map { String(format: "%.2f m", $0) } ?? "—" }
    static func percent(_ fraction: Double) -> String { String(format: "%.0f %%", fraction * 100) }
    static func fps(_ v: Double) -> String { v > 0 ? String(format: "%.1f", v) : "—" }
}

extension DisplayOrientation {
    var uiOrientation: UIImage.Orientation {
        switch self {
        case .right: return .right
        case .leftMirrored: return .leftMirrored
        }
    }
}

extension Image {
    /// Sensor-orientation image rotated for portrait display.
    init(sensor image: CGImage, mode: SensorMode) {
        self.init(uiImage: UIImage(cgImage: image, scale: 1, orientation: mode.displayOrientation.uiOrientation))
    }
}
