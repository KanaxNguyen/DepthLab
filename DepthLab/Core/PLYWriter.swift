import Foundation

struct PLYPoint: Equatable {
    var x: Float, y: Float, z: Float
    var r: UInt8, g: UInt8, b: UInt8
}

/// ASCII PLY. Camera space: +X right, +Y up, camera looks down -Z (SceneKit / OpenGL style).
enum PLYWriter {
    static func points(from frame: DepthFrame, stride: Int, colorMaxMeters: Float) -> [PLYPoint] {
        guard let k = frame.intrinsics, stride > 0 else { return [] }
        var out: [PLYPoint] = []
        out.reserveCapacity(frame.depth.count / (stride * stride))
        for v in Swift.stride(from: 0, to: frame.height, by: stride) {
            for u in Swift.stride(from: 0, to: frame.width, by: stride) {
                let z = frame.depth[frame.index(x: u, y: v)]
                guard z > 0 else { continue }
                let c = Colormap.depthColor(meters: z, maxMeters: colorMaxMeters)
                out.append(PLYPoint(x: (Float(u) - k.cx) / k.fx * z, y: -(Float(v) - k.cy) / k.fy * z, z: -z,
                                    r: c.r, g: c.g, b: c.b))
            }
        }
        return out
    }

    static func ascii(_ points: [PLYPoint]) -> String {
        var s = "ply\nformat ascii 1.0\ncomment DepthLab point cloud, metres, camera space (+Y up, camera looks down -Z)\n"
        s += "element vertex \(points.count)\n"
        s += "property float x\nproperty float y\nproperty float z\n"
        s += "property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"
        for p in points {
            s += String(format: "%.4f %.4f %.4f %d %d %d\n", locale: Locale(identifier: "en_US_POSIX"),
                        p.x, p.y, p.z, Int(p.r), Int(p.g), Int(p.b))
        }
        return s
    }

    /// Reads back the ASCII format written above; nil when the header or a row is malformed.
    static func parse(_ text: String) -> [PLYPoint]? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        guard lines.next() == "ply" else { return nil }
        var count: Int?
        while let line = lines.next() {
            if line == "end_header" { break }
            if line.hasPrefix("element vertex ") { count = Int(line.dropFirst("element vertex ".count)) }
        }
        guard let count else { return nil }
        var out: [PLYPoint] = []
        out.reserveCapacity(count)
        while out.count < count, let line = lines.next() {
            let f = line.split(separator: " ")
            guard f.count == 6, let x = Float(f[0]), let y = Float(f[1]), let z = Float(f[2]),
                  let r = UInt8(f[3]), let g = UInt8(f[4]), let b = UInt8(f[5]) else { return nil }
            out.append(PLYPoint(x: x, y: y, z: z, r: r, g: g, b: b))
        }
        return out.count == count ? out : nil
    }
}
