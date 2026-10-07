import Foundation

enum CSVExporter {
    static let header = [
        "date", "mode", "device", "object", "lighting",
        "measured_m", "truth_m", "abs_error_m", "rel_error_pct",
        "valid_pct", "high_conf_pct", "reliable_range_m", "min_high_m", "max_high_m",
        "depth_w", "depth_h", "fps",
    ]

    static func escape(_ field: String) -> String {
        guard field.contains(where: { ",\"\n\r".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Fixed decimals with a dot separator regardless of device locale; empty for nil.
    static func number(_ v: Double?, decimals: Int = 4) -> String {
        guard let v else { return "" }
        return String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    static func csv(from samples: [SampleRecord]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = [header.joined(separator: ",")]
        for s in samples {
            let fields: [String] = [
                iso.string(from: s.date), s.mode.rawValue, s.deviceModel, s.objectKind.rawValue, s.lighting.rawValue,
                number(s.measuredM), number(s.groundTruthM), number(s.absoluteErrorM), number(s.relativeErrorPct, decimals: 2),
                number(s.validPct, decimals: 1), number(s.highPct, decimals: 1),
                number(s.reliableRangeM, decimals: 2), number(s.minHighM), number(s.maxHighM),
                String(s.depthWidth), String(s.depthHeight), number(s.fps, decimals: 1),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
