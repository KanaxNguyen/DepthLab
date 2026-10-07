import AVFoundation
import CoreImage
import Foundation

enum SourceState: Equatable {
    case idle
    case starting
    case running
    case unsupported(String)
    case denied
    case failed(String)
}

/// A depth sensor. Callbacks arrive on the source's own serial queue, never on the main thread.
protocol DepthSource: AnyObject {
    /// Called at most ~15 times per second with a full frame and the measured depth FPS.
    var onFrame: ((DepthFrame, Double) -> Void)? { get set }
    var onState: ((SourceState) -> Void)? { get set }
    func start()
    func stop()
}

enum CameraAccess {
    /// Resolves to true when the user allows (or already allowed) camera use.
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

enum ImageConverter {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Camera picture shrunk to `maxWidth` for display; sensor orientation.
    static func cgImage(from buffer: CVPixelBuffer, maxWidth: CGFloat = 960) -> CGImage? {
        var image = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, maxWidth / image.extent.width)
        if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        return context.createCGImage(image, from: image.extent)
    }
}

/// Shared by both sources: depth FPS counting (only changed depth maps count) and frame throttling.
struct FrameTimer {
    private var meter = FPSMeter()
    private var gate = FrameGate(rate: 15)
    private var lastFingerprint: UInt64?

    /// Returns true when a full frame should be built and delivered.
    mutating func shouldDeliver(fingerprint: UInt64, at t: TimeInterval) -> Bool {
        if fingerprint != lastFingerprint {
            lastFingerprint = fingerprint
            meter.tick(at: t)
        }
        return gate.allow(at: t)
    }

    var fps: Double { meter.fps }
}
