import CoreGraphics
import Foundation
import Observation
import os
import UIKit

/// Everything the measure screen shows for one delivered frame.
struct MeasureSnapshot: Identifiable {
    let id = UUID()
    let frame: DepthFrame
    let stats: DepthStats
    let bins: [HistogramBin]
    let heatmap: CGImage?
    let fps: Double
}

/// Owns the active sensor and turns its frames into UI state. Sensor code stays in Capture/.
@MainActor
@Observable
final class MeasureModel {
    var mode: SensorMode = .lidar
    private(set) var state: SourceState = .idle
    private(set) var snapshot: MeasureSnapshot?
    /// Tapped point, normalised in the displayed portrait image.
    var touch: CGPoint?

    private var source: DepthSource?
    private var generation = 0
    private var lastLog = Date.distantPast
    private static let log = Logger(subsystem: "vn.cabinsentinel.depthlab", category: "depth")

    /// Starts the sensor unless one is already starting or running.
    func ensureRunning() {
        if source != nil, state == .starting || state == .running { return }
        start()
    }

    /// Always restarts, for mode or setting changes.
    func start() {
        stop()
        generation += 1
        let token = generation
        let source: DepthSource = mode == .lidar
            ? LiDARSource(smoothed: AppSettings.useSmoothed)
            : TrueDepthSource(filtering: AppSettings.trueDepthFiltering)
        source.onState = { [weak self] s in
            DispatchQueue.main.async { self?.apply(state: s, token: token) }
        }
        source.onFrame = { [weak self] frame, fps in
            let snap = Self.process(frame, fps: fps)
            DispatchQueue.main.async { self?.apply(snapshot: snap, token: token) }
        }
        self.source = source
        state = .starting
        snapshot = nil
        UIApplication.shared.isIdleTimerDisabled = true
        source.start()
    }

    func stop() {
        generation += 1
        source?.stop()
        source = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if state == .running || state == .starting { state = .idle }
    }

    /// Distance and confidence at the tapped point, if any.
    var probe: (meters: Float, confidence: UInt8)? {
        guard let touch, let frame = snapshot?.frame else { return nil }
        let p = mode.displayOrientation.sensorPoint(fromDisplay: touch)
        return DepthAnalysis.depth(in: frame, atNormalized: p, radius: 1)
    }

    private func apply(state s: SourceState, token: Int) {
        guard token == generation else { return }
        state = s
        #if DEBUG
        print("[depthlab] state=\(s)")
        #endif
        Self.log.info("state=\(String(describing: s), privacy: .public)")
    }

    private func apply(snapshot snap: MeasureSnapshot, token: Int) {
        guard token == generation else { return }
        snapshot = snap
        // Local diagnostic line (viewable with Console/devicectl), at most every 2 s.
        if Date().timeIntervalSince(lastLog) >= 2 {
            lastLog = Date()
            let f = snap.frame, s = snap.stats
            #if DEBUG
            print("[depthlab] \(f.mode.rawValue) depth=\(f.width)x\(f.height) image=\(f.imageWidth)x\(f.imageHeight) fps=\(String(format: "%.1f", snap.fps)) valid=\(String(format: "%.2f", s.validFraction)) high=\(String(format: "%.2f", s.highFraction)) center=\(s.center ?? -1) min=\(s.minHigh ?? -1) max=\(s.maxHigh ?? -1) reliable=\(s.reliableRange ?? -1) note=\(f.sensorNote ?? "")")
            #endif
            Self.log.info("\(f.mode.rawValue, privacy: .public) depth=\(f.width)x\(f.height) image=\(f.imageWidth)x\(f.imageHeight) fps=\(snap.fps, format: .fixed(precision: 1)) valid=\(s.validFraction, format: .fixed(precision: 2)) high=\(s.highFraction, format: .fixed(precision: 2)) center=\(s.center ?? -1, format: .fixed(precision: 2)) min=\(s.minHigh ?? -1, format: .fixed(precision: 2)) max=\(s.maxHigh ?? -1, format: .fixed(precision: 2)) reliable=\(s.reliableRange ?? -1, format: .fixed(precision: 2)) note=\(f.sensorNote ?? "", privacy: .public)")
        }
    }

    private nonisolated static func process(_ frame: DepthFrame, fps: Double) -> MeasureSnapshot {
        let stats = DepthAnalysis.stats(for: frame, reliableFraction: AppSettings.reliableFraction)
        return MeasureSnapshot(
            frame: frame, stats: stats,
            bins: DepthAnalysis.histogram(depth: frame.depth, confidence: frame.confidence),
            heatmap: HeatmapRenderer.image(for: frame, maxMeters: AppSettings.heatmapMax,
                                           hideLowConfidence: AppSettings.hideLow),
            fps: fps)
    }
}
