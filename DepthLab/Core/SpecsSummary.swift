import Foundation

/// What one recorded session says about a sensor; the only input of the "measured specs" table.
struct SessionObservation: Equatable {
    var mode: SensorMode
    var depthWidth: Int
    var depthHeight: Int
    var fps: Double
    var minHighM: Double?
    var maxHighM: Double?
    var reliableRangeM: Double?
}

struct SensorSpecs: Equatable {
    var mode: SensorMode
    var sessions = 0
    var resolution: String?
    var fpsMedian: Double?
    var fpsMax: Double?
    var minObservedM: Double?
    var maxObservedM: Double?
    var bestReliableRangeM: Double?
}

enum SpecsSummary {
    /// Only fills what the observations contain; everything else stays nil ("chưa đo").
    static func make(from observations: [SessionObservation], mode: SensorMode) -> SensorSpecs {
        let obs = observations.filter { $0.mode == mode }
        var specs = SensorSpecs(mode: mode, sessions: obs.count)
        if let last = obs.last(where: { $0.depthWidth > 0 && $0.depthHeight > 0 }) {
            specs.resolution = "\(last.depthWidth) × \(last.depthHeight)"
        }
        let fps = obs.map(\.fps).filter { $0 > 0 }.sorted()
        if !fps.isEmpty {
            specs.fpsMax = fps.last
            specs.fpsMedian = fps.count % 2 == 1 ? fps[fps.count / 2] : (fps[fps.count / 2 - 1] + fps[fps.count / 2]) / 2
        }
        specs.minObservedM = obs.compactMap(\.minHighM).min()
        specs.maxObservedM = obs.compactMap(\.maxHighM).max()
        specs.bestReliableRangeM = obs.compactMap(\.reliableRangeM).max()
        return specs
    }
}
