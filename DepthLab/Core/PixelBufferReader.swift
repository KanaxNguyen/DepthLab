import CoreVideo
import Foundation

/// Copies CVPixelBuffer planes into Swift arrays, honouring row padding.
enum PixelBufferReader {
    static func floats(from buffer: CVPixelBuffer) -> [Float] {
        read(buffer, as: Float.self, zero: 0)
    }

    static func bytes(from buffer: CVPixelBuffer) -> [UInt8] {
        read(buffer, as: UInt8.self, zero: 0)
    }

    private static func read<T>(_ buffer: CVPixelBuffer, as: T.Type, zero: T) -> [T] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [T](repeating: zero, count: w * h) }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var out = [T](repeating: zero, count: w * h)
        for y in 0..<h {
            let row = (base + y * rowBytes).assumingMemoryBound(to: T.self)
            for x in 0..<w { out[y * w + x] = row[x] }
        }
        return out
    }

    /// Cheap hash of 64 sampled pixels; equal values mean the sensor repeated the same depth map.
    static func fingerprint(of buffer: CVPixelBuffer) -> UInt64 {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer), w > 0, h > 0 else { return 0 }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var hash: UInt64 = 0xcbf29ce484222325
        for i in 0..<64 {
            let x = (i * 37 + 5) % w, y = (i * 53 + 11) % h
            let bits = (base + y * rowBytes).assumingMemoryBound(to: UInt32.self)[x]
            hash = (hash ^ UInt64(bits)) &* 0x100000001b3
        }
        return hash
    }
}
