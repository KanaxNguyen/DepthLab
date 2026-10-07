import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers

/// Saved with every capture as meta.json.
struct CaptureMeta: Codable, Equatable {
    var createdAt: Date
    var mode: SensorMode
    var device: String
    var systemVersion: String
    var depthWidth: Int
    var depthHeight: Int
    var imageWidth: Int
    var imageHeight: Int
    var intrinsicsAtDepthResolution: Intrinsics?
    var fps: Double
    var centerM: Double?
    var minHighM: Double?
    var maxHighM: Double?
    var validPct: Double
    var highPct: Double
    var reliableRangeM: Double?
    var groundTruthM: Double?
    var lighting: Lighting?
    var rgbSaved: Bool
    var confidenceIsSynthetic: Bool
    var sensorNote: String?
    var orientation = "sensor (landscape buffer, not rotated for portrait)"
    var confidenceEncoding = "PNG 8-bit: 0 = no depth, 85 = low, 170 = medium, 255 = high"
    var depthEncoding = "PNG 16-bit grayscale, millimetres, 0 = no depth"
}

struct CaptureItem: Identifiable, Equatable {
    var id: String { directory.lastPathComponent }
    let directory: URL
    let meta: CaptureMeta

    func file(_ name: String) -> URL { directory.appendingPathComponent(name) }
    var hasRGB: Bool { FileManager.default.fileExists(atPath: file("rgb.jpg").path) }
    var shareURLs: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Capture folders under Documents/Captures, newest first.
@Observable
final class CaptureStore {
    private(set) var items: [CaptureItem] = []
    private let root: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        root = directory.appendingPathComponent("Captures", isDirectory: true)
        reload()
    }

    var observations: [SessionObservation] {
        items.reversed().map {
            SessionObservation(mode: $0.meta.mode, depthWidth: $0.meta.depthWidth, depthHeight: $0.meta.depthHeight,
                        fps: $0.meta.fps, minHighM: $0.meta.minHighM, maxHighM: $0.meta.maxHighM,
                        reliableRangeM: $0.meta.reliableRangeM)
        }
    }

    func reload() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        items = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
                  let meta = try? decoder.decode(CaptureMeta.self, from: data) else { return nil }
            return CaptureItem(directory: dir, meta: meta)
        }.sorted { $0.meta.createdAt > $1.meta.createdAt }
    }

    /// Writes a capture folder off the main thread. RGB is written only when `saveRGB` is true.
    @discardableResult
    func save(frame: DepthFrame, stats: DepthStats, fps: Double, groundTruthM: Double?, lighting: Lighting?,
              saveRGB: Bool) async throws -> CaptureItem {
        let root = root
        let item = try await Task.detached {
            try Self.write(frame: frame, stats: stats, fps: fps, groundTruthM: groundTruthM, lighting: lighting,
                           saveRGB: saveRGB, root: root, now: Date())
        }.value
        items.insert(item, at: 0)
        return item
    }

    nonisolated static func write(frame: DepthFrame, stats: DepthStats, fps: Double, groundTruthM: Double?,
                                  lighting: Lighting?, saveRGB: Bool, root: URL, now: Date) throws -> CaptureItem {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        var name = "\(stamp.string(from: now))-\(frame.mode.rawValue)"
        var dir = root.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: dir.path) {
            name = "\(stamp.string(from: now))-\(frame.mode.rawValue)-\(n)"
            dir = root.appendingPathComponent(name, isDirectory: true)
            n += 1
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let w = frame.width, h = frame.height
        let mm = frame.depth.map(DepthUnits.millimetres(fromMeters:))
        guard let depthPNG = ImageFiles.gray16(millimetres: mm, width: w, height: h),
              let confPNG = ImageFiles.gray8(ImageFiles.confidenceGray(for: frame), width: w, height: h),
              let heat = HeatmapRenderer.image(for: frame, maxMeters: AppSettings.heatmapMax, hideLowConfidence: false,
                                               opaqueBackground: true) else {
            throw ImageFiles.WriteError(message: "Không dựng được ảnh độ sâu")
        }
        try ImageFiles.write(depthPNG, to: dir.appendingPathComponent("depth.png"), type: .png)
        try ImageFiles.write(heat, to: dir.appendingPathComponent("depth_heatmap.png"), type: .png)
        try ImageFiles.write(confPNG, to: dir.appendingPathComponent("confidence.png"), type: .png)

        // Back-projecting needs intrinsics; the TrueDepth cloud is subsampled to keep the file small.
        let stride = frame.mode == .lidar ? 1 : 2
        let points = PLYWriter.points(from: frame, stride: stride, colorMaxMeters: AppSettings.heatmapMax)
        if !points.isEmpty {
            try PLYWriter.ascii(points).write(to: dir.appendingPathComponent("points.ply"), atomically: true, encoding: .utf8)
        }

        var rgbSaved = false
        if saveRGB, let image = frame.image {
            try ImageFiles.write(image, to: dir.appendingPathComponent("rgb.jpg"), type: .jpeg, quality: 0.9)
            rgbSaved = true
        }

        let meta = CaptureMeta(
            createdAt: now, mode: frame.mode, device: DeviceInfo.model, systemVersion: DeviceInfo.systemVersion,
            depthWidth: w, depthHeight: h, imageWidth: frame.imageWidth, imageHeight: frame.imageHeight,
            intrinsicsAtDepthResolution: frame.intrinsics, fps: fps,
            centerM: stats.center.map(Double.init), minHighM: stats.minHigh.map(Double.init),
            maxHighM: stats.maxHigh.map(Double.init),
            validPct: stats.validFraction * 100, highPct: stats.highFraction * 100,
            reliableRangeM: stats.reliableRange.map(Double.init),
            groundTruthM: groundTruthM, lighting: lighting, rgbSaved: rgbSaved,
            confidenceIsSynthetic: frame.confidenceIsSynthetic, sensorNote: frame.sensorNote)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meta).write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        return CaptureItem(directory: dir, meta: meta)
    }

    func delete(_ item: CaptureItem) {
        try? FileManager.default.removeItem(at: item.directory)
        items.removeAll { $0.id == item.id }
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: root)
        items = []
    }
}
