import CoreVideo
import ImageIO
import XCTest
@testable import DepthLab

/// Builds a small frame from per-pixel depth/confidence for the pure-function tests.
private func makeFrame(width: Int, height: Int, depth: [Float], confidence: [UInt8]? = nil,
                       mode: SensorMode = .lidar, intrinsics: Intrinsics? = nil) -> DepthFrame {
    DepthFrame(mode: mode, width: width, height: height, depth: depth,
               confidence: confidence ?? [UInt8](repeating: 2, count: depth.count),
               confidenceIsSynthetic: false, intrinsics: intrinsics, imageWidth: 0, imageHeight: 0,
               image: nil, timestamp: 0, sensorNote: nil)
}

final class UnitConversionTests: XCTestCase {
    func testDisparityToMeters() {
        XCTAssertEqual(DepthUnits.meters(fromDisparity: 2), 0.5, accuracy: 1e-6)
        XCTAssertEqual(DepthUnits.meters(fromDisparity: 0.5), 2, accuracy: 1e-6)
    }

    func testInvalidValuesBecomeZero() {
        for v in [Float(0), -1, .nan, .infinity, -.infinity] {
            XCTAssertEqual(DepthUnits.meters(fromDisparity: v), 0)
            XCTAssertEqual(DepthUnits.sanitized(meters: v), 0)
            XCTAssertEqual(DepthUnits.millimetres(fromMeters: v), 0)
        }
        XCTAssertEqual(DepthUnits.sanitized(meters: 1.234), 1.234, accuracy: 1e-6)
    }

    func testMillimetresRoundAndClamp() {
        XCTAssertEqual(DepthUnits.millimetres(fromMeters: 1.5004), 1500)
        XCTAssertEqual(DepthUnits.millimetres(fromMeters: 1.5006), 1501)
        XCTAssertEqual(DepthUnits.millimetres(fromMeters: 100), UInt16.max)
    }
}

final class ErrorMetricsTests: XCTestCase {
    func testAbsoluteAndRelative() {
        XCTAssertEqual(ErrorMetrics.absolute(measured: 1.46, truth: 1.5), 0.04, accuracy: 1e-9)
        XCTAssertEqual(ErrorMetrics.absolute(measured: 1.54, truth: 1.5), 0.04, accuracy: 1e-9)
        XCTAssertEqual(ErrorMetrics.relativePercent(measured: 1.65, truth: 1.5)!, 10, accuracy: 1e-9)
        XCTAssertNil(ErrorMetrics.relativePercent(measured: 1, truth: 0))
    }

    func testInputParsingAcceptsCommaAndRejectsGarbage() {
        XCTAssertEqual(InputParsing.meters(from: "1,5"), 1.5)
        XCTAssertEqual(InputParsing.meters(from: " 2.25 "), 2.25)
        XCTAssertNil(InputParsing.meters(from: "abc"))
        XCTAssertNil(InputParsing.meters(from: "-1"))
        XCTAssertNil(InputParsing.meters(from: "0"))
        XCTAssertNil(InputParsing.meters(from: "500"))
    }
}

final class ReliableRangeTests: XCTestCase {
    func testHistogramBinsAndConfidenceSplit() {
        let bins = DepthAnalysis.histogram(depth: [0.1, 0.3, 0.3, 0, 7, 5.99], confidence: [2, 2, 1, 2, 2, 2])
        XCTAssertEqual(bins.count, 24)
        XCTAssertEqual(bins[0].total, 1)
        XCTAssertEqual(bins[1].total, 2)
        XCTAssertEqual(bins[1].high, 1)
        XCTAssertEqual(bins[23].total, 1) // 5.99 m; 7 m is outside the 0...6 m chart
        XCTAssertEqual(bins.map(\.total).reduce(0, +), 4)
    }

    private func bins(_ spec: [Int: (total: Int, high: Int)]) -> [HistogramBin] {
        (0..<DepthAnalysis.binCount).map { i in
            HistogramBin(index: i, total: spec[i]?.total ?? 0, high: spec[i]?.high ?? 0)
        }
    }

    func testFarthestQualifyingBandWins() {
        // Band 8 (2.00-2.25 m) is 40% high, band 12 (3.00-3.25 m) only 10%.
        let b = bins([4: (100, 90), 8: (100, 40), 12: (100, 10)])
        XCTAssertEqual(DepthAnalysis.reliableRange(bins: b, totalPixels: 1000, fraction: 0.3)!, 2.25, accuracy: 1e-6)
        XCTAssertEqual(DepthAnalysis.reliableRange(bins: b, totalPixels: 1000, fraction: 0.05)!, 3.25, accuracy: 1e-6)
    }

    func testThresholdIsInclusive() {
        let b = bins([4: (100, 30)])
        XCTAssertEqual(DepthAnalysis.reliableRange(bins: b, totalPixels: 1000, fraction: 0.3)!, 1.25, accuracy: 1e-6)
        XCTAssertNil(DepthAnalysis.reliableRange(bins: b, totalPixels: 1000, fraction: 0.31))
    }

    func testTinyBandsAreIgnored() {
        // Band 20 has 3 pixels (< 0.5% of 10 000) and is all high; it must not extend the range.
        let b = bins([4: (500, 400), 20: (3, 3)])
        XCTAssertEqual(DepthAnalysis.reliableRange(bins: b, totalPixels: 10_000, fraction: 0.3)!, 1.25, accuracy: 1e-6)
    }

    func testNoDataGivesNil() {
        XCTAssertNil(DepthAnalysis.reliableRange(bins: bins([:]), totalPixels: 100, fraction: 0.3))
    }

    func testStatsOnSmallFrame() {
        // 4x2: left column invalid, rest valid; one low-confidence pixel.
        let depth: [Float] = [0, 1, 2, 3,
                              0, 1, 2, 3]
        let conf: [UInt8] = [0, 2, 2, 0,
                             0, 2, 2, 2]
        let stats = DepthAnalysis.stats(for: makeFrame(width: 4, height: 2, depth: depth, confidence: conf),
                                        reliableFraction: 0.3)
        XCTAssertEqual(stats.validFraction, 6.0 / 8.0, accuracy: 1e-9)
        XCTAssertEqual(stats.highFraction, 5.0 / 8.0, accuracy: 1e-9)
        XCTAssertEqual(stats.minHigh, 1)
        XCTAssertEqual(stats.maxHigh, 3)
        XCTAssertNotNil(stats.center)
        XCTAssertEqual(stats.reliableRange!, 3.25, accuracy: 1e-6) // 3 m band: 1 of 2 high
    }

    func testCenterIsMedianOfValidWindow() {
        var depth = [Float](repeating: 2, count: 25)
        depth[12] = 9 // centre outlier
        let f = makeFrame(width: 5, height: 5, depth: depth)
        XCTAssertEqual(DepthAnalysis.depth(in: f, atNormalized: CGPoint(x: 0.5, y: 0.5), radius: 1)!.meters, 2)
    }

    func testNoValidPixelsGivesNilNotZero() {
        let stats = DepthAnalysis.stats(for: makeFrame(width: 2, height: 2, depth: [0, 0, 0, 0]), reliableFraction: 0.3)
        XCTAssertNil(stats.center)
        XCTAssertNil(stats.minHigh)
        XCTAssertNil(stats.reliableRange)
        XCTAssertEqual(stats.validFraction, 0)
    }
}

final class CSVTests: XCTestCase {
    private func sample(object: ObjectKind = .infantDoll, device: String = "iPhone16,2") -> SampleRecord {
        SampleRecord(date: Date(timeIntervalSince1970: 0), mode: .lidar, deviceModel: device,
                     measuredM: 1.46, groundTruthM: 1.5, objectKind: object, lighting: .indoor,
                     validPct: 85.04, highPct: 60.2, reliableRangeM: 3, minHighM: 0.5, maxHighM: 4.1,
                     depthWidth: 256, depthHeight: 192, fps: 29.97)
    }

    func testHeaderAndRow() {
        let lines = CSVExporter.csv(from: [sample()]).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], CSVExporter.header.joined(separator: ","))
        XCTAssertEqual(lines[1], "1970-01-01T00:00:00Z,lidar,iPhone16,2".replacingOccurrences(of: "iPhone16,2", with: "\"iPhone16,2\"")
            + ",infantDoll,indoor,1.4600,1.5000,0.0400,2.67,85.0,60.2,3.00,0.5000,4.1000,256,192,30.0")
        XCTAssertEqual(lines[1].split(separator: ",", omittingEmptySubsequences: false).count - 1, CSVExporter.header.count)
    }

    func testEscaping() {
        XCTAssertEqual(CSVExporter.escape("plain"), "plain")
        XCTAssertEqual(CSVExporter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExporter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testDecimalPointIsDotAndNilIsEmpty() {
        XCTAssertEqual(CSVExporter.number(1.5), "1.5000")
        XCTAssertEqual(CSVExporter.number(nil), "")
    }

    func testEmptyExportHasOnlyHeader() {
        XCTAssertEqual(CSVExporter.csv(from: []).split(separator: "\n").count, 1)
    }
}

final class PLYTests: XCTestCase {
    private let k = Intrinsics(fx: 100, fy: 100, cx: 1, cy: 1)

    func testBackProjection() {
        // 3x3 map, depth 2 m everywhere, principal point at pixel (1,1).
        let f = makeFrame(width: 3, height: 3, depth: [Float](repeating: 2, count: 9), intrinsics: k)
        let pts = PLYWriter.points(from: f, stride: 1, colorMaxMeters: 5)
        XCTAssertEqual(pts.count, 9)
        let center = pts[4]
        XCTAssertEqual(center.x, 0, accuracy: 1e-6)
        XCTAssertEqual(center.y, 0, accuracy: 1e-6)
        XCTAssertEqual(center.z, -2, accuracy: 1e-6)
        let topLeft = pts[0] // u=0 v=0: left of and above the axis
        XCTAssertEqual(topLeft.x, -0.02, accuracy: 1e-6)
        XCTAssertEqual(topLeft.y, 0.02, accuracy: 1e-6)
    }

    func testSkipsInvalidAndHonoursStride() {
        let f = makeFrame(width: 4, height: 4, depth: (0..<16).map { $0 == 0 ? 0 : 1 }, intrinsics: k)
        XCTAssertEqual(PLYWriter.points(from: f, stride: 1, colorMaxMeters: 5).count, 15)
        XCTAssertEqual(PLYWriter.points(from: f, stride: 2, colorMaxMeters: 5).count, 3) // (0,0) invalid
        XCTAssertTrue(PLYWriter.points(from: makeFrame(width: 2, height: 2, depth: [1, 1, 1, 1]), stride: 1, colorMaxMeters: 5).isEmpty)
    }

    func testAsciiHeaderAndRoundTrip() {
        let pts = [PLYPoint(x: 0.1, y: -0.2, z: -1.5, r: 255, g: 0, b: 10),
                   PLYPoint(x: 1, y: 2, z: -3, r: 1, g: 2, b: 3)]
        let text = PLYWriter.ascii(pts)
        XCTAssertTrue(text.hasPrefix("ply\nformat ascii 1.0\n"))
        XCTAssertTrue(text.contains("element vertex 2\n"))
        XCTAssertTrue(text.contains("end_header\n0.1000 -0.2000 -1.5000 255 0 10\n"))
        XCTAssertEqual(PLYWriter.parse(text), pts)
    }

    func testParseRejectsTruncatedFile() {
        let text = PLYWriter.ascii([PLYPoint(x: 0, y: 0, z: -1, r: 0, g: 0, b: 0)])
            .replacingOccurrences(of: "element vertex 1", with: "element vertex 2")
        XCTAssertNil(PLYWriter.parse(text))
        XCTAssertNil(PLYWriter.parse("not a ply"))
    }
}

final class ImageFileTests: XCTestCase {
    func testGray16PNGRoundTripKeepsMillimetres() throws {
        let mm: [UInt16] = [0, 500, 1500, 65535]
        let image = try XCTUnwrap(ImageFiles.gray16(millimetres: mm, width: 2, height: 2))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gray16-test.png")
        try ImageFiles.write(image, to: url, type: .png)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertEqual(props?[kCGImagePropertyDepth] as? Int, 16)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.bitsPerComponent, 16)
        let bytes = try XCTUnwrap(decoded.dataProvider?.data as Data?)
        // The decoder reports its own sample byte order; honour it.
        let littleEndian = decoded.bitmapInfo.contains(.byteOrder16Little)
        let values = (0..<4).map { i -> UInt16 in
            let a = UInt16(bytes[2 * i]), b = UInt16(bytes[2 * i + 1])
            return littleEndian ? b << 8 | a : a << 8 | b
        }
        XCTAssertEqual(values, mm)
    }

    func testConfidenceEncoding() {
        let f = makeFrame(width: 4, height: 1, depth: [0, 1, 1, 1], confidence: [2, 0, 1, 2])
        XCTAssertEqual(ImageFiles.confidenceGray(for: f), [0, 85, 170, 255])
    }
}

final class HeatmapAndGeometryTests: XCTestCase {
    func testNearIsWarmFarIsCool() {
        let near = Colormap.depthColor(meters: 0, maxMeters: 5)
        let far = Colormap.depthColor(meters: 4, maxMeters: 5)
        XCTAssertGreaterThan(near.r, near.b)
        XCTAssertGreaterThan(far.b, far.r)
        let beyond = Colormap.depthColor(meters: 99, maxMeters: 5)
        let atMax = Colormap.depthColor(meters: 5, maxMeters: 5)
        XCTAssertEqual(beyond.r, atMax.r) // clamped to the scale end
        XCTAssertEqual(beyond.b, atMax.b)
    }

    func testRGBAInvalidPixelsAndLowConfidence() {
        let f = makeFrame(width: 3, height: 1, depth: [0, 1, 1], confidence: [2, 2, 0])
        let overlay = HeatmapRenderer.rgba(for: f, maxMeters: 5, hideLowConfidence: true, opaqueBackground: false)
        XCTAssertEqual(overlay[3], 0)   // invalid → transparent
        XCTAssertEqual(overlay[7], 255) // valid + high → opaque
        XCTAssertEqual(overlay[11], 0)  // low confidence hidden
        let saved = HeatmapRenderer.rgba(for: f, maxMeters: 5, hideLowConfidence: false, opaqueBackground: true)
        XCTAssertEqual(saved[3], 255)   // invalid → opaque black
        XCTAssertEqual(saved[0], 0)
        XCTAssertEqual(saved[11], 255)
    }

    func testOrientationMappingIsInvertible() {
        for o in [DisplayOrientation.right, .leftMirrored] {
            for p in [CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0, y: 1), CGPoint(x: 0.5, y: 0.5)] {
                let back = o.displayPoint(fromSensor: o.sensorPoint(fromDisplay: p))
                XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
                XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
            }
        }
    }

    func testRightRotationCorners() {
        // Rotated 90° clockwise: top-left of the portrait image is the sensor's bottom-left.
        let p = DisplayOrientation.right.sensorPoint(fromDisplay: CGPoint(x: 0, y: 0))
        XCTAssertEqual(p.x, 0, accuracy: 1e-9)
        XCTAssertEqual(p.y, 1, accuracy: 1e-9)
        // Top-right of the portrait image is the sensor's top-left.
        let q = DisplayOrientation.right.sensorPoint(fromDisplay: CGPoint(x: 1, y: 0))
        XCTAssertEqual(q.x, 0, accuracy: 1e-9)
        XCTAssertEqual(q.y, 0, accuracy: 1e-9)
    }

    func testIntrinsicsScaling() {
        let k = Intrinsics(fx: 1000, fy: 1100, cx: 960, cy: 720).scaled(sx: 0.5, sy: 0.25)
        XCTAssertEqual(k, Intrinsics(fx: 500, fy: 275, cx: 480, cy: 180))
    }
}

final class MeterAndSpecsTests: XCTestCase {
    func testFPSMeter() {
        var m = FPSMeter(window: 2)
        XCTAssertEqual(m.fps, 0)
        for i in 0..<31 { m.tick(at: Double(i) / 30) } // 30 intervals over 1 s
        XCTAssertEqual(m.fps, 30, accuracy: 1e-6)
        m.tick(at: 100)
        XCTAssertEqual(m.fps, 0) // old ticks fell out of the window
    }

    func testFrameGateLimitsRate() {
        var g = FrameGate(rate: 10)
        let allowed = (0..<100).filter { g.allow(at: Double($0) / 100) }.count // 1 s at 100 Hz
        XCTAssertEqual(allowed, 10)
    }

    func testSpecsAreEmptyUntilMeasured() {
        let s = SpecsSummary.make(from: [], mode: .lidar)
        XCTAssertEqual(s.sessions, 0)
        XCTAssertNil(s.resolution)
        XCTAssertNil(s.fpsMedian)
        XCTAssertNil(s.minObservedM)
        XCTAssertNil(s.maxObservedM)
        XCTAssertNil(s.bestReliableRangeM)
    }

    func testSpecsAggregatePerSensor() {
        let obs = [
            SessionObservation(mode: .lidar, depthWidth: 256, depthHeight: 192, fps: 30, minHighM: 0.4, maxHighM: 3.1, reliableRangeM: 2.5),
            SessionObservation(mode: .lidar, depthWidth: 256, depthHeight: 192, fps: 10, minHighM: 0.3, maxHighM: 4.8, reliableRangeM: nil),
            SessionObservation(mode: .trueDepth, depthWidth: 640, depthHeight: 480, fps: 25, minHighM: 0.2, maxHighM: 1.0, reliableRangeM: 1.0),
        ]
        let l = SpecsSummary.make(from: obs, mode: .lidar)
        XCTAssertEqual(l.sessions, 2)
        XCTAssertEqual(l.resolution, "256 × 192")
        XCTAssertEqual(l.fpsMedian, 20)
        XCTAssertEqual(l.fpsMax, 30)
        XCTAssertEqual(l.minObservedM, 0.3)
        XCTAssertEqual(l.maxObservedM, 4.8)
        XCTAssertEqual(l.bestReliableRangeM, 2.5)
        XCTAssertEqual(SpecsSummary.make(from: obs, mode: .trueDepth).resolution, "640 × 480")
    }
}

final class PixelBufferTests: XCTestCase {
    private func buffer(width: Int, height: Int, format: OSType) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        // Odd width forces row padding in most allocators.
        CVPixelBufferCreate(nil, width, height, format, [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary, &pb)
        return try XCTUnwrap(pb)
    }

    func testFloatReadHonoursRowPadding() throws {
        let pb = try buffer(width: 5, height: 3, format: kCVPixelFormatType_OneComponent32Float)
        CVPixelBufferLockBaseAddress(pb, [])
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        XCTAssertGreaterThan(rowBytes, 5 * 4)
        let base = CVPixelBufferGetBaseAddress(pb)!
        for y in 0..<3 { for x in 0..<5 {
            (base + y * rowBytes).assumingMemoryBound(to: Float.self)[x] = Float(y * 10 + x)
        } }
        CVPixelBufferUnlockBaseAddress(pb, [])
        XCTAssertEqual(PixelBufferReader.floats(from: pb), (0..<3).flatMap { y in (0..<5).map { Float(y * 10 + $0) } })
    }

    func testFingerprintChangesWithContent() throws {
        let pb = try buffer(width: 16, height: 16, format: kCVPixelFormatType_OneComponent32Float)
        CVPixelBufferLockBaseAddress(pb, [])
        memset(CVPixelBufferGetBaseAddress(pb)!, 0, CVPixelBufferGetBytesPerRow(pb) * 16)
        CVPixelBufferUnlockBaseAddress(pb, [])
        let a = PixelBufferReader.fingerprint(of: pb)
        XCTAssertEqual(a, PixelBufferReader.fingerprint(of: pb))
        CVPixelBufferLockBaseAddress(pb, [])
        memset(CVPixelBufferGetBaseAddress(pb)!, 0x3f, CVPixelBufferGetBytesPerRow(pb) * 16)
        CVPixelBufferUnlockBaseAddress(pb, [])
        XCTAssertNotEqual(a, PixelBufferReader.fingerprint(of: pb))
    }
}

final class StoreTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testSampleStorePersists() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let record = SampleRecord(date: Date(timeIntervalSince1970: 100), mode: .trueDepth, deviceModel: "x",
                                  measuredM: 1, groundTruthM: 1.1, objectKind: .backpack, lighting: .dark,
                                  validPct: 50, highPct: 40, reliableRangeM: nil, minHighM: nil, maxHighM: nil,
                                  depthWidth: 640, depthHeight: 480, fps: 20)
        SampleStore(directory: dir).add(record)
        let reloaded = SampleStore(directory: dir)
        XCTAssertEqual(reloaded.samples, [record])
        reloaded.deleteAll()
        XCTAssertTrue(SampleStore(directory: dir).samples.isEmpty)
    }

    func testCaptureWritesAllFilesAndRGBOnlyWhenAsked() throws {
        AppSettings.register()
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let k = Intrinsics(fx: 10, fy: 10, cx: 2, cy: 2)
        let f = makeFrame(width: 4, height: 4, depth: [Float](repeating: 1.5, count: 16), intrinsics: k)
        let stats = DepthAnalysis.stats(for: f, reliableFraction: 0.3)

        let plain = try CaptureStore.write(frame: f, stats: stats, fps: 30, groundTruthM: 1.5, lighting: .indoor,
                                           saveRGB: false, root: root, now: Date(timeIntervalSince1970: 0))
        let names = Set(plain.shareURLs.map(\.lastPathComponent))
        XCTAssertEqual(names, ["depth.png", "depth_heatmap.png", "confidence.png", "points.ply", "meta.json"])
        XCTAssertFalse(plain.hasRGB)

        let meta = try JSONDecoder.iso.decode(CaptureMeta.self, from: Data(contentsOf: plain.file("meta.json")))
        XCTAssertEqual(meta.depthWidth, 4)
        XCTAssertEqual(meta.groundTruthM, 1.5)
        XCTAssertFalse(meta.rgbSaved)
        XCTAssertEqual(PLYWriter.parse(try String(contentsOf: plain.file("points.ply")))?.count, 16 / 1)

        // Same second again must not overwrite the first capture.
        let second = try CaptureStore.write(frame: f, stats: stats, fps: 30, groundTruthM: nil, lighting: nil,
                                            saveRGB: true, root: root, now: Date(timeIntervalSince1970: 0))
        XCTAssertNotEqual(second.directory, plain.directory)
        XCTAssertFalse(second.hasRGB) // saveRGB requested but this frame carries no image
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
