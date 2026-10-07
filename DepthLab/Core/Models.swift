import CoreGraphics
import Foundation

/// Which depth sensor is being measured.
enum SensorMode: String, Codable, CaseIterable, Identifiable {
    case lidar
    case trueDepth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lidar: return "LiDAR (sau)"
        case .trueDepth: return "TrueDepth (trước)"
        }
    }

    var shortTitle: String {
        switch self {
        case .lidar: return "LiDAR"
        case .trueDepth: return "TrueDepth"
        }
    }

    /// How the raw sensor-orientation buffers are rotated for portrait display.
    var displayOrientation: DisplayOrientation {
        switch self {
        case .lidar: return .right
        case .trueDepth: return .leftMirrored
        }
    }
}

enum ObjectKind: String, Codable, CaseIterable, Identifiable {
    case emptySeat, infantDoll, backpack, darkFabric, flatPoster, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emptySeat: return "Ghế trống"
        case .infantDoll: return "Búp bê cỡ trẻ nhỏ"
        case .backpack: return "Balo"
        case .darkFabric: return "Vải tối"
        case .flatPoster: return "Áp phích phẳng"
        case .other: return "Khác"
        }
    }
}

enum Lighting: String, Codable, CaseIterable, Identifiable {
    case dark, indoor, shade, harshSun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Tối"
        case .indoor: return "Trong nhà"
        case .shade: return "Bóng râm"
        case .harshSun: return "Nắng gắt"
        }
    }
}

/// Pinhole intrinsics in pixels.
struct Intrinsics: Codable, Equatable {
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float

    func scaled(sx: Float, sy: Float) -> Intrinsics {
        Intrinsics(fx: fx * sx, fy: fy * sy, cx: cx * sx, cy: cy * sy)
    }
}

/// One depth map plus everything needed to analyse and save it. Row-major, sensor orientation.
struct DepthFrame {
    static let lowConfidence: UInt8 = 0
    static let mediumConfidence: UInt8 = 1
    static let highConfidence: UInt8 = 2

    let mode: SensorMode
    let width: Int
    let height: Int
    /// Metres; 0 means no measurement.
    let depth: [Float]
    /// 0 low, 1 medium, 2 high (ARKit levels). Meaningless where depth is 0.
    let confidence: [UInt8]
    /// True when the sensor gives no per-pixel confidence and the app derived it (TrueDepth).
    let confidenceIsSynthetic: Bool
    /// Intrinsics scaled to the depth-map resolution, if the sensor reported them.
    let intrinsics: Intrinsics?
    let imageWidth: Int
    let imageHeight: Int
    /// Camera picture for display; kept in memory unless the user opts in to saving it.
    let image: CGImage?
    let timestamp: TimeInterval
    /// Free-form sensor details (for example TrueDepth accuracy and quality).
    let sensorNote: String?

    @inline(__always) func index(x: Int, y: Int) -> Int { y * width + x }
}

/// Numbers shown live and stored with each sample.
struct DepthStats: Equatable {
    var center: Float?
    var minHigh: Float?
    var maxHigh: Float?
    /// 0...1 of all pixels with a depth value.
    var validFraction: Double
    /// 0...1 of all pixels that are valid and high confidence.
    var highFraction: Double
    var reliableRange: Float?

    static let empty = DepthStats(center: nil, minHigh: nil, maxHigh: nil,
                                  validFraction: 0, highFraction: 0, reliableRange: nil)
}

struct HistogramBin: Identifiable, Equatable {
    var id: Int { index }
    let index: Int
    /// Count of valid pixels in the band.
    var total: Int
    /// Count of high-confidence pixels in the band.
    var high: Int

    var lower: Float { Float(index) * DepthAnalysis.binWidth }
    var upper: Float { lower + DepthAnalysis.binWidth }
    var other: Int { total - high }
}

/// Orientation used to show sensor-orientation buffers in portrait.
enum DisplayOrientation {
    /// Rotated 90° clockwise (back camera).
    case right
    /// Transposed (front camera, mirrored selfie view).
    case leftMirrored

    /// Normalised display point (origin top-left of the portrait image) → normalised sensor point.
    func sensorPoint(fromDisplay p: CGPoint) -> CGPoint {
        switch self {
        case .right: return CGPoint(x: p.y, y: 1 - p.x)
        case .leftMirrored: return CGPoint(x: p.y, y: p.x)
        }
    }

    /// Inverse of `sensorPoint(fromDisplay:)`.
    func displayPoint(fromSensor p: CGPoint) -> CGPoint {
        switch self {
        case .right: return CGPoint(x: 1 - p.y, y: p.x)
        case .leftMirrored: return CGPoint(x: p.y, y: p.x)
        }
    }
}

/// One manual measurement paired with a tape-measure reference.
struct SampleRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var mode: SensorMode
    var deviceModel: String
    var measuredM: Double
    var groundTruthM: Double
    var objectKind: ObjectKind
    var lighting: Lighting
    var validPct: Double
    var highPct: Double
    var reliableRangeM: Double?
    var minHighM: Double?
    var maxHighM: Double?
    var depthWidth: Int
    var depthHeight: Int
    var fps: Double

    var absoluteErrorM: Double { ErrorMetrics.absolute(measured: measuredM, truth: groundTruthM) }
    var relativeErrorPct: Double? { ErrorMetrics.relativePercent(measured: measuredM, truth: groundTruthM) }
}

extension DepthFrame: @unchecked Sendable {}
