import Foundation
import Observation

/// Ticks for the test protocol: sensor × distance × lighting.
@Observable
final class ProtocolStore {
    static let distances: [Double] = [0.5, 1, 1.5, 2, 3, 4, 5]
    private static let defaultsKey = "protocolDone"

    private(set) var done: Set<String>

    init() {
        done = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    static func key(_ mode: SensorMode, _ distance: Double, _ lighting: Lighting) -> String {
        "\(mode.rawValue)|\(distance)|\(lighting.rawValue)"
    }

    func isDone(_ mode: SensorMode, _ distance: Double, _ lighting: Lighting) -> Bool {
        done.contains(Self.key(mode, distance, lighting))
    }

    func toggle(_ mode: SensorMode, _ distance: Double, _ lighting: Lighting) {
        let k = Self.key(mode, distance, lighting)
        if done.contains(k) { done.remove(k) } else { done.insert(k) }
        UserDefaults.standard.set(Array(done), forKey: Self.defaultsKey)
    }

    /// Samples whose true distance is within 0.1 m of the milestone and lighting matches.
    static func sampleCount(in samples: [SampleRecord], _ mode: SensorMode, _ distance: Double, _ lighting: Lighting) -> Int {
        samples.filter {
            $0.mode == mode && $0.lighting == lighting && abs($0.groundTruthM - distance) <= 0.1
        }.count
    }
}
