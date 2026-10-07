import ARKit
import Foundation

/// Back-camera LiDAR depth through ARKit scene depth.
final class LiDARSource: NSObject, @unchecked Sendable, DepthSource, ARSessionDelegate {
    var onFrame: ((DepthFrame, Double) -> Void)?
    var onState: ((SourceState) -> Void)?

    private let session = ARSession()
    private let queue = DispatchQueue(label: "depthlab.lidar")
    private let smoothed: Bool
    private var timer = FrameTimer()

    init(smoothed: Bool) {
        self.smoothed = smoothed
        super.init()
        session.delegate = self
        session.delegateQueue = queue
    }

    /// Nil when this device can run scene depth; otherwise a Vietnamese reason.
    static var unsupportedReason: String? {
        #if targetEnvironment(simulator)
        return "Simulator không có LiDAR. Hãy chạy trên iPhone Pro hoặc iPad Pro có LiDAR."
        #else
        guard ARWorldTrackingConfiguration.isSupported else { return "Máy này không hỗ trợ ARKit." }
        let semantics: ARConfiguration.FrameSemantics = [.sceneDepth]
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(semantics) else {
            return "Máy này không hỗ trợ sceneDepth (không có LiDAR)."
        }
        return nil
        #endif
    }

    func start() {
        if let reason = Self.unsupportedReason {
            onState?(.unsupported(reason))
            return
        }
        onState?(.starting)
        Task {
            guard await CameraAccess.request() else {
                onState?(.denied)
                return
            }
            let config = ARWorldTrackingConfiguration()
            config.frameSemantics = smoothed ? [.smoothedSceneDepth] : [.sceneDepth]
            if smoothed, !ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                onState?(.unsupported("Máy này không hỗ trợ smoothedSceneDepth."))
                return
            }
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
            onState?(.running)
        }
    }

    func stop() {
        session.pause()
        onFrame = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let depthData = smoothed ? frame.smoothedSceneDepth : frame.sceneDepth else { return }
        let depthMap = depthData.depthMap
        let fingerprint = PixelBufferReader.fingerprint(of: depthMap)
        guard timer.shouldDeliver(fingerprint: fingerprint, at: frame.timestamp) else { return }

        let w = CVPixelBufferGetWidth(depthMap), h = CVPixelBufferGetHeight(depthMap)
        let imageW = CVPixelBufferGetWidth(frame.capturedImage), imageH = CVPixelBufferGetHeight(frame.capturedImage)
        var confidence = [UInt8](repeating: 0, count: w * h)
        if let map = depthData.confidenceMap { confidence = PixelBufferReader.bytes(from: map) }

        // ARKit intrinsics refer to the full camera image; scale them to the depth map.
        let k = frame.camera.intrinsics
        let intrinsics = Intrinsics(fx: k.columns.0.x, fy: k.columns.1.y, cx: k.columns.2.x, cy: k.columns.2.y)
            .scaled(sx: Float(w) / Float(imageW), sy: Float(h) / Float(imageH))

        let depth = PixelBufferReader.floats(from: depthMap).map(DepthUnits.sanitized(meters:))
        let out = DepthFrame(
            mode: .lidar, width: w, height: h, depth: depth, confidence: confidence,
            confidenceIsSynthetic: false, intrinsics: intrinsics,
            imageWidth: imageW, imageHeight: imageH,
            image: ImageConverter.cgImage(from: frame.capturedImage),
            timestamp: frame.timestamp,
            sensorNote: smoothed ? "smoothedSceneDepth" : "sceneDepth")
        onFrame?(out, timer.fps)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onState?(.failed(error.localizedDescription))
    }

    func sessionWasInterrupted(_ session: ARSession) {
        onState?(.failed("Phiên AR bị gián đoạn."))
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        onState?(.running)
    }
}
