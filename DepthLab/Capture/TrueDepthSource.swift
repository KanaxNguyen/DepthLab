import AVFoundation
import Foundation

/// Front-camera TrueDepth depth, synchronised with video through AVCaptureDataOutputSynchronizer.
final class TrueDepthSource: NSObject, @unchecked Sendable, DepthSource, AVCaptureDataOutputSynchronizerDelegate {
    var onFrame: ((DepthFrame, Double) -> Void)?
    var onState: ((SourceState) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "depthlab.truedepth.session")
    private let dataQueue = DispatchQueue(label: "depthlab.truedepth.data")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let filtering: Bool
    private var timer = FrameTimer()

    init(filtering: Bool) {
        self.filtering = filtering
        super.init()
    }

    static var unsupportedReason: String? {
        #if targetEnvironment(simulator)
        return "Simulator không có TrueDepth. Hãy chạy trên iPhone có Face ID."
        #else
        guard AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil else {
            return "Máy này không có camera TrueDepth."
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
            sessionQueue.async { [self] in
                if let error = configure() {
                    onState?(.failed(error))
                    return
                }
                session.startRunning()
                onState?(.running)
            }
        }
    }

    func stop() {
        onFrame = nil
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Returns an error message, or nil on success.
    private func configure() -> String? {
        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return "Không mở được camera TrueDepth."
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        guard session.canAddInput(input) else { return "Không thêm được đầu vào camera." }
        session.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        depthOutput.isFilteringEnabled = filtering
        depthOutput.alwaysDiscardsLateDepthData = true
        guard session.canAddOutput(videoOutput), session.canAddOutput(depthOutput) else {
            return "Không thêm được đầu ra video/độ sâu."
        }
        session.addOutput(videoOutput)
        session.addOutput(depthOutput)
        depthOutput.connection(with: .depthData)?.isEnabled = true

        // Video format closest to 1280 px wide that can also deliver depth; the largest depth format for it.
        let candidates = device.formats.filter { !$0.supportedDepthDataFormats.isEmpty }
        guard let format = candidates.min(by: { Self.distance($0) < Self.distance($1) }),
              let depthFormat = format.supportedDepthDataFormats.max(by: { Self.pixels($0) < Self.pixels($1) }) else {
            return "Không có định dạng video hỗ trợ độ sâu."
        }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeDepthDataFormat = depthFormat
            device.unlockForConfiguration()
        } catch {
            return "Không đặt được định dạng camera: \(error.localizedDescription)"
        }

        let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        sync.setDelegate(self, queue: dataQueue)
        synchronizer = sync
        return nil
    }

    private static func pixels(_ f: AVCaptureDevice.Format) -> Int {
        let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        return Int(d.width) * Int(d.height)
    }

    private static func distance(_ f: AVCaptureDevice.Format) -> Int {
        abs(Int(CMVideoFormatDescriptionGetDimensions(f.formatDescription).width) - 1280)
    }

    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput collection: AVCaptureSynchronizedDataCollection) {
        guard let syncedDepth = collection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
              !syncedDepth.depthDataWasDropped else { return }

        // Work in Float32 so the buffer layout is known; keep disparity as disparity until converted below.
        let source = syncedDepth.depthData
        let type = source.depthDataType
        let isDisparity = type == kCVPixelFormatType_DisparityFloat16 || type == kCVPixelFormatType_DisparityFloat32
        let target = isDisparity ? kCVPixelFormatType_DisparityFloat32 : kCVPixelFormatType_DepthFloat32
        let data = type == target ? source : source.converting(toDepthDataType: target)
        let map = data.depthDataMap

        let fingerprint = PixelBufferReader.fingerprint(of: map)
        guard timer.shouldDeliver(fingerprint: fingerprint, at: CMTimeGetSeconds(syncedDepth.timestamp)) else { return }

        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map)
        let raw = PixelBufferReader.floats(from: map)
        let depth = isDisparity ? raw.map(DepthUnits.meters(fromDisparity:)) : raw.map(DepthUnits.sanitized(meters:))

        // TrueDepth has no per-pixel confidence: valid pixels inherit the frame-level quality.
        let frameLevel: UInt8 = data.depthDataQuality == .high ? DepthFrame.highConfidence : DepthFrame.mediumConfidence
        let confidence = depth.map { $0 > 0 ? frameLevel : DepthFrame.lowConfidence }

        var imageSize = (w: 0, h: 0)
        var cgImage: CGImage?
        if let video = collection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
           !video.sampleBufferWasDropped, let buffer = CMSampleBufferGetImageBuffer(video.sampleBuffer) {
            imageSize = (CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer))
            cgImage = ImageConverter.cgImage(from: buffer)
        }

        var intrinsics: Intrinsics?
        if let cal = data.cameraCalibrationData {
            let k = cal.intrinsicMatrix, ref = cal.intrinsicMatrixReferenceDimensions
            if ref.width > 0, ref.height > 0 {
                intrinsics = Intrinsics(fx: k.columns.0.x, fy: k.columns.1.y, cx: k.columns.2.x, cy: k.columns.2.y)
                    .scaled(sx: Float(w) / Float(ref.width), sy: Float(h) / Float(ref.height))
                if imageSize.w == 0 { imageSize = (Int(ref.width), Int(ref.height)) }
            }
        }

        let accuracy = data.depthDataAccuracy == .absolute ? "absolute" : "relative"
        let note = "native=\(Self.name(of: type)), accuracy=\(accuracy), quality=\(data.depthDataQuality == .high ? "high" : "low"), "
            + "filtered=\(data.isDepthDataFiltered)"
        let out = DepthFrame(
            mode: .trueDepth, width: w, height: h, depth: depth, confidence: confidence,
            confidenceIsSynthetic: true, intrinsics: intrinsics,
            imageWidth: imageSize.w, imageHeight: imageSize.h, image: cgImage,
            timestamp: CMTimeGetSeconds(syncedDepth.timestamp), sensorNote: note)
        onFrame?(out, timer.fps)
    }

    private static func name(of type: OSType) -> String {
        switch type {
        case kCVPixelFormatType_DisparityFloat16: return "DisparityFloat16"
        case kCVPixelFormatType_DisparityFloat32: return "DisparityFloat32"
        case kCVPixelFormatType_DepthFloat16: return "DepthFloat16"
        case kCVPixelFormatType_DepthFloat32: return "DepthFloat32"
        default: return "format-\(type)"
        }
    }
}
