import Foundation

/// Unit conversion for raw sensor values.
enum DepthUnits {
    /// Disparity (1/m) → metres. Zero, negative, NaN and infinite values mean "no measurement".
    static func meters(fromDisparity d: Float) -> Float {
        (d.isFinite && d > 0) ? 1 / d : 0
    }

    /// Passes finite positive metres through, everything else becomes 0.
    static func sanitized(meters v: Float) -> Float {
        (v.isFinite && v > 0) ? v : 0
    }

    /// Metres → 16-bit millimetres, clamped; 0 stays 0.
    static func millimetres(fromMeters m: Float) -> UInt16 {
        guard m.isFinite, m > 0 else { return 0 }
        return UInt16(min((m * 1000).rounded(), Float(UInt16.max)))
    }
}

enum ErrorMetrics {
    static func absolute(measured: Double, truth: Double) -> Double {
        abs(measured - truth)
    }

    /// Relative error in percent of the true distance; nil when the truth is not positive.
    static func relativePercent(measured: Double, truth: Double) -> Double? {
        truth > 0 ? abs(measured - truth) / truth * 100 : nil
    }
}

/// Parses a distance typed by the user; accepts both "1,5" and "1.5".
enum InputParsing {
    static func meters(from text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned), v.isFinite, v > 0, v <= 50 else { return nil }
        return v
    }
}

enum DepthAnalysis {
    static let binWidth: Float = 0.25
    static let binCount = 24 // 0 ... 6 m
    /// A distance band needs at least this share of all pixels to count towards the reliable range.
    static let minBandFraction = 0.005

    static func histogram(depth: [Float], confidence: [UInt8]) -> [HistogramBin] {
        var bins = (0..<binCount).map { HistogramBin(index: $0, total: 0, high: 0) }
        for i in 0..<depth.count {
            let d = depth[i]
            guard d > 0 else { continue }
            let b = Int(d / binWidth)
            guard b < binCount else { continue }
            bins[b].total += 1
            if confidence[i] >= DepthFrame.highConfidence { bins[b].high += 1 }
        }
        return bins
    }

    /// App convention (not an Apple figure): upper edge of the farthest 0.25 m band in which
    /// at least `fraction` of the band's pixels are high confidence, ignoring bands holding
    /// fewer than `minBandFraction` of all pixels.
    static func reliableRange(bins: [HistogramBin], totalPixels: Int, fraction: Double) -> Float? {
        let minPixels = max(1, Int((minBandFraction * Double(totalPixels)).rounded(.up)))
        for bin in bins.reversed() where bin.total >= minPixels {
            if Double(bin.high) / Double(bin.total) >= fraction { return bin.upper }
        }
        return nil
    }

    static func stats(for frame: DepthFrame, reliableFraction: Double) -> DepthStats {
        let total = frame.depth.count
        guard total > 0 else { return .empty }
        var valid = 0, high = 0
        var minHigh = Float.greatestFiniteMagnitude, maxHigh: Float = 0
        for i in 0..<total {
            let d = frame.depth[i]
            guard d > 0 else { continue }
            valid += 1
            if frame.confidence[i] >= DepthFrame.highConfidence {
                high += 1
                minHigh = min(minHigh, d)
                maxHigh = max(maxHigh, d)
            }
        }
        let bins = histogram(depth: frame.depth, confidence: frame.confidence)
        return DepthStats(
            center: depth(in: frame, atNormalized: CGPoint(x: 0.5, y: 0.5), radius: 2)?.meters,
            minHigh: high > 0 ? minHigh : nil,
            maxHigh: high > 0 ? maxHigh : nil,
            validFraction: Double(valid) / Double(total),
            highFraction: Double(high) / Double(total),
            reliableRange: reliableRange(bins: bins, totalPixels: total, fraction: reliableFraction))
    }

    /// Median of valid depths in a (2r+1)² window around a normalised sensor point.
    static func depth(in frame: DepthFrame, atNormalized p: CGPoint, radius: Int)
        -> (meters: Float, confidence: UInt8)? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let cx = min(max(Int(p.x * CGFloat(frame.width)), 0), frame.width - 1)
        let cy = min(max(Int(p.y * CGFloat(frame.height)), 0), frame.height - 1)
        var values: [(Float, UInt8)] = []
        for y in max(0, cy - radius)...min(frame.height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(frame.width - 1, cx + radius) {
                let i = frame.index(x: x, y: y)
                if frame.depth[i] > 0 { values.append((frame.depth[i], frame.confidence[i])) }
            }
        }
        guard !values.isEmpty else { return nil }
        values.sort { $0.0 < $1.0 }
        let mid = values[values.count / 2]
        return (mid.0, mid.1)
    }
}

/// Frames per second over a sliding window of timestamps.
struct FPSMeter {
    private var times: [TimeInterval] = []
    private let window: TimeInterval

    init(window: TimeInterval = 2) { self.window = window }

    mutating func tick(at t: TimeInterval) {
        times.append(t)
        while let first = times.first, t - first > window { times.removeFirst() }
    }

    var fps: Double {
        guard times.count >= 2, let first = times.first, let last = times.last, last > first else { return 0 }
        return Double(times.count - 1) / (last - first)
    }
}

/// Lets a frame through at most `rate` times per second.
struct FrameGate {
    private var last: TimeInterval = -.infinity
    private let interval: TimeInterval

    init(rate: Double) { interval = 1 / rate }

    mutating func allow(at t: TimeInterval) -> Bool {
        guard t - last >= interval else { return false }
        last = t
        return true
    }
}
