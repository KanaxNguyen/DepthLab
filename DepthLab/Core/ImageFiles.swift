import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageFiles {
    struct WriteError: Error { let message: String }

    /// 16-bit grayscale depth in millimetres (0 = no data), sensor orientation.
    static func gray16(millimetres: [UInt16], width: Int, height: Int) -> CGImage? {
        var data = Data(count: millimetres.count * 2)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for (i, v) in millimetres.enumerated() { // big endian, as PNG stores it
                p[2 * i] = UInt8(v >> 8)
                p[2 * i + 1] = UInt8(v & 0xff)
            }
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 16,
                       bytesPerRow: width * 2, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func gray8(_ values: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(values) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// invalid → 0, low → 85, medium → 170, high → 255.
    static func confidenceGray(for frame: DepthFrame) -> [UInt8] {
        zip(frame.depth, frame.confidence).map { depth, conf in
            guard depth > 0 else { return 0 }
            switch conf {
            case DepthFrame.highConfidence...: return 255
            case DepthFrame.mediumConfidence: return 170
            default: return 85
            }
        }
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double? = nil) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw WriteError(message: "Không tạo được \(url.lastPathComponent)")
        }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw WriteError(message: "Không ghi được \(url.lastPathComponent)")
        }
    }
}
