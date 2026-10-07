import Foundation

/// UserDefaults keys (also used by @AppStorage in the views) and their defaults.
enum AppSettings {
    static let reliableFractionKey = "reliableFraction"
    static let heatmapMaxKey = "heatmapMaxMeters"
    static let smoothedKey = "useSmoothedDepth"
    static let filteringKey = "trueDepthFiltering"
    static let hideLowKey = "hideLowConfidence"
    static let opacityKey = "overlayOpacity"

    static let defaultReliableFraction = 0.30
    static let defaultHeatmapMax = 5.0
    static let defaultOpacity = 0.6

    static func register() {
        UserDefaults.standard.register(defaults: [
            reliableFractionKey: defaultReliableFraction,
            heatmapMaxKey: defaultHeatmapMax,
            opacityKey: defaultOpacity,
        ])
    }

    static var reliableFraction: Double { UserDefaults.standard.double(forKey: reliableFractionKey) }
    static var heatmapMax: Float { Float(UserDefaults.standard.double(forKey: heatmapMaxKey)) }
    static var useSmoothed: Bool { UserDefaults.standard.bool(forKey: smoothedKey) }
    static var trueDepthFiltering: Bool { UserDefaults.standard.bool(forKey: filteringKey) }
    static var hideLow: Bool { UserDefaults.standard.bool(forKey: hideLowKey) }
}
