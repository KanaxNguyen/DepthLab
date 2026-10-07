import CoreGraphics
import Foundation

enum Colormap {
    /// Google "Turbo" polynomial approximation; t in 0...1 → RGB 0...255.
    static func turbo(_ t: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        let x = min(max(t, 0), 1)
        let r = 0.13572138 + x * (4.61539260 + x * (-42.66032258 + x * (132.13108234 + x * (-152.94239396 + x * 59.28637943))))
        let g = 0.09140261 + x * (2.19418839 + x * (4.84296658 + x * (-14.18503333 + x * (4.27729857 + x * 2.82956604))))
        let b = 0.10667330 + x * (12.64194608 + x * (-60.58204836 + x * (110.36276771 + x * (-89.90310912 + x * 27.34824973))))
        func byte(_ v: Float) -> UInt8 { UInt8(min(max(v, 0), 1) * 255) }
        return (byte(r), byte(g), byte(b))
    }

    /// Near is warm, far is cool.
    static func depthColor(meters: Float, maxMeters: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        turbo(1 - min(max(meters / maxMeters, 0), 1))
    }
}

enum HeatmapRenderer {
    /// RGBA8 (premultiplied, opaque where valid). Invalid pixels are transparent, or opaque black.
    static func rgba(for frame: DepthFrame, maxMeters: Float, hideLowConfidence: Bool,
                     opaqueBackground: Bool) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: frame.width * frame.height * 4)
        for i in 0..<frame.depth.count {
            let d = frame.depth[i]
            let hidden = d <= 0 || (hideLowConfidence && frame.confidence[i] < DepthFrame.highConfidence)
            let o = i * 4
            if hidden {
                if opaqueBackground { out[o + 3] = 255 }
                continue
            }
            let c = Colormap.depthColor(meters: d, maxMeters: maxMeters)
            out[o] = c.r; out[o + 1] = c.g; out[o + 2] = c.b; out[o + 3] = 255
        }
        return out
    }

    static func cgImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard rgba.count == width * height * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func image(for frame: DepthFrame, maxMeters: Float, hideLowConfidence: Bool,
                      opaqueBackground: Bool = false) -> CGImage? {
        cgImage(rgba: rgba(for: frame, maxMeters: maxMeters, hideLowConfidence: hideLowConfidence,
                           opaqueBackground: opaqueBackground),
                width: frame.width, height: frame.height)
    }
}
