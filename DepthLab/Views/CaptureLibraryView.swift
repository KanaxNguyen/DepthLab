import SceneKit
import SwiftUI

struct CaptureLibraryView: View {
    @Environment(CaptureStore.self) private var store
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                if store.items.isEmpty {
                    Text("Chưa có mẫu chụp. Vào tab Đo và bấm Chụp mẫu.").foregroundStyle(.secondary)
                }
                ForEach(store.items) { item in
                    NavigationLink(value: item) { CaptureRow(item: item) }
                }
                .onDelete { offsets in offsets.map { store.items[$0] }.forEach(store.delete) }
            }
            .navigationTitle("Thư viện mẫu")
            .navigationDestination(for: CaptureItem.self) { CaptureDetailView(item: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label("Xoá tất cả", systemImage: "trash")
                    }
                    .disabled(store.items.isEmpty)
                }
            }
            .confirmationDialog("Xoá tất cả mẫu chụp?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Xoá tất cả", role: .destructive) { store.deleteAll() }
            }
            .onAppear { store.reload() }
        }
    }
}

extension CaptureItem: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private enum CaptureImage {
    static func load(_ url: URL, mode: SensorMode) -> UIImage? {
        guard let source = UIImage(contentsOfFile: url.path), let cg = source.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: mode.displayOrientation.uiOrientation)
    }
}

private struct CaptureRow: View {
    let item: CaptureItem
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() } else { Color.gray.opacity(0.3) }
            }
            .frame(width: 48, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.meta.mode.shortTitle) · giữa \(Format.meters(item.meta.centerM))").font(.headline)
                Text(item.meta.createdAt.formatted(date: .abbreviated, time: .standard)).font(.footnote)
                    .foregroundStyle(.secondary)
                if let truth = item.meta.groundTruthM {
                    Text("Khoảng cách thật \(Format.meters(truth))").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .task { thumbnail = CaptureImage.load(item.file("depth_heatmap.png"), mode: item.meta.mode) }
    }
}

private struct CaptureDetailView: View {
    let item: CaptureItem
    @Environment(CaptureStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var heatmap: UIImage?
    @State private var rgb: UIImage?
    @State private var showRGB = false
    @State private var points: [PLYPoint]?
    @State private var confirmDelete = false

    private var meta: CaptureMeta { item.meta }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if rgb != nil {
                    Picker("Ảnh", selection: $showRGB) {
                        Text("Heatmap").tag(false)
                        Text("Ảnh màu").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if let image = showRGB ? rgb : heatmap {
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(showRGB ? "Ảnh màu" : "Heatmap độ sâu")
                }
                metrics
                Text("Đám mây điểm 3D (kéo để xoay)").font(.headline)
                Group {
                    if let points, !points.isEmpty {
                        PointCloudView(points: points)
                    } else if points == nil, FileManager.default.fileExists(atPath: item.file("points.ply").path) {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Không có đám mây điểm (thiếu thông số camera).").foregroundStyle(.secondary)
                    }
                }
                .frame(height: 320)
                .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .navigationTitle(meta.mode.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(items: item.shareURLs) { Label("Chia sẻ", systemImage: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Xoá", systemImage: "trash") }
            }
        }
        .confirmationDialog("Xoá mẫu chụp này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá", role: .destructive) { store.delete(item); dismiss() }
        }
        .task {
            heatmap = CaptureImage.load(item.file("depth_heatmap.png"), mode: meta.mode)
            if item.hasRGB { rgb = CaptureImage.load(item.file("rgb.jpg"), mode: meta.mode) }
            let url = item.file("points.ply")
            points = await Task.detached { (try? String(contentsOf: url, encoding: .utf8)).flatMap(PLYWriter.parse) ?? [] }.value
        }
    }

    private var metrics: some View {
        VStack(spacing: 0) {
            row("Máy", "\(meta.device), iOS \(meta.systemVersion)")
            row("Kích thước depthMap", "\(meta.depthWidth) × \(meta.depthHeight)")
            row("Kích thước ảnh", meta.imageWidth > 0 ? "\(meta.imageWidth) × \(meta.imageHeight)" : "chưa có")
            row("FPS độ sâu", Format.fps(meta.fps))
            row("Điểm giữa", Format.meters(meta.centerM))
            row("Gần nhất / xa nhất (tin cậy cao)", "\(Format.meters(meta.minHighM)) / \(Format.meters(meta.maxHighM))")
            row("Điểm hợp lệ / tin cậy cao", String(format: "%.0f %% / %.0f %%", meta.validPct, meta.highPct))
            row("Độ xa tin cậy (quy ước app)", Format.meters(meta.reliableRangeM))
            row("Khoảng cách thật", meta.groundTruthM.map { Format.meters($0) } ?? "không nhập")
            row("Ánh sáng", meta.lighting?.title ?? "không nhập")
            row("Độ tin cậy", meta.confidenceIsSynthetic ? "suy ra từ chất lượng khung (cảm biến không có)" : "từ cảm biến")
            if let note = meta.sensorNote { row("Cảm biến", note) }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Orbitable SceneKit view of a coloured point cloud.
struct PointCloudView: UIViewRepresentable {
    let points: [PLYPoint]

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        let scene = SCNScene()
        let cloud = Self.node(for: points)
        scene.rootNode.addChildNode(cloud)

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 50
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 0.3)
        scene.rootNode.addChildNode(cameraNode)

        view.scene = scene
        view.pointOfView = cameraNode
        view.defaultCameraController.target = Self.centroid(of: points)
        view.defaultCameraController.interactionMode = .orbitTurntable
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private static func centroid(of points: [PLYPoint]) -> SCNVector3 {
        guard !points.isEmpty else { return SCNVector3Zero }
        let n = Float(points.count)
        return SCNVector3(points.reduce(0) { $0 + $1.x } / n, points.reduce(0) { $0 + $1.y } / n,
                          points.reduce(0) { $0 + $1.z } / n)
    }

    private static func node(for points: [PLYPoint]) -> SCNNode {
        let vertices = points.map { SCNVector3($0.x, $0.y, $0.z) }
        var colors = [Float]()
        colors.reserveCapacity(points.count * 4)
        for p in points { colors += [Float(p.r) / 255, Float(p.g) / 255, Float(p.b) / 255, 1] }
        let colorSource = SCNGeometrySource(
            data: colors.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color,
            vectorCount: points.count, usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 4)
        let element = SCNGeometryElement(indices: (0..<points.count).map { Int32($0) }, primitiveType: .point)
        element.pointSize = 3
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 5
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}
