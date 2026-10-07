import Charts
import SwiftUI

struct MeasureView: View {
    @State private var model = MeasureModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.opacityKey) private var opacity = AppSettings.defaultOpacity
    @AppStorage(AppSettings.heatmapMaxKey) private var heatmapMax = AppSettings.defaultHeatmapMax
    @AppStorage(AppSettings.smoothedKey) private var smoothed = false
    @AppStorage(AppSettings.filteringKey) private var filtering = false
    @State private var sampleSnapshot: MeasureSnapshot?
    @State private var captureSnapshot: MeasureSnapshot?

    private var snapshot: MeasureSnapshot? { model.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Cảm biến", selection: $model.mode) {
                        ForEach(SensorMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    cameraArea
                    LegendBar(maxMeters: heatmapMax)
                    HStack {
                        Image(systemName: "circle.lefthalf.filled").accessibilityHidden(true)
                        Slider(value: $opacity, in: 0...1)
                            .accessibilityLabel("Độ trong suốt lớp phủ độ sâu")
                            .accessibilityValue("\(Int(opacity * 100)) phần trăm")
                    }
                    reliableBanner
                    StatsGrid(stats: snapshot?.stats, fps: snapshot?.fps)
                    if let note = snapshot?.frame.sensorNote {
                        Text("Cảm biến: \(note)").font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    actionButtons
                    if let bins = snapshot?.bins {
                        HistogramChart(bins: bins, reliableRange: snapshot?.stats.reliableRange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("DepthLab")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { model.ensureRunning() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.ensureRunning() } else { model.stop() }
        }
        .onChange(of: model.mode) { model.touch = nil; model.start() }
        .onChange(of: smoothed) { model.start() }
        .onChange(of: filtering) { model.start() }
        .sheet(item: $sampleSnapshot) { SampleEntrySheet(snapshot: $0) }
        .sheet(item: $captureSnapshot) { CaptureSheet(snapshot: $0) }
    }

    @ViewBuilder private var cameraArea: some View {
        switch model.state {
        case .unsupported(let reason):
            StateMessage(symbol: "exclamationmark.triangle", title: "Không hỗ trợ", text: reason)
        case .denied:
            StateMessage(symbol: "camera.fill", title: "Chưa cấp quyền camera",
                         text: "Hãy bật quyền camera cho DepthLab trong Cài đặt của iPhone.", showSettings: true)
        case .failed(let message):
            StateMessage(symbol: "xmark.octagon", title: "Lỗi cảm biến", text: message)
        case .idle, .starting, .running:
            DepthCameraView(snapshot: snapshot, mode: model.mode, opacity: opacity,
                            touch: $model.touch, probe: model.probe,
                            isStarting: model.state != .running && snapshot == nil)
        }
    }

    private var reliableBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Độ xa tin cậy").font(.footnote).foregroundStyle(.secondary)
            Text(Format.meters(snapshot?.stats.reliableRange))
                .font(.title.weight(.semibold).monospacedDigit())
            Text("Quy ước của app: dải 0,25 m xa nhất có ≥ \(Int(AppSettings.reliableFraction * 100)) % điểm tin cậy cao. Không phải thông số của Apple.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button { sampleSnapshot = snapshot } label: {
                Label("Ghi mẫu", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(snapshot?.stats.center == nil)
            .accessibilityHint("Ghi khoảng cách đo cùng khoảng cách thật từ thước")

            Button { captureSnapshot = snapshot } label: {
                Label("Chụp mẫu", systemImage: "camera.aperture").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(snapshot == nil)
            .accessibilityHint("Lưu bản đồ độ sâu, độ tin cậy và đám mây điểm vào thư viện")
        }
        .controlSize(.large)
    }
}

struct StateMessage: View {
    let symbol: String
    let title: String
    let text: String
    var showSettings = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(text).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if showSettings {
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Camera picture with depth heatmap on top; tap to read the distance at a point.
struct DepthCameraView: View {
    let snapshot: MeasureSnapshot?
    let mode: SensorMode
    let opacity: Double
    @Binding var touch: CGPoint?
    let probe: (meters: Float, confidence: UInt8)?
    let isStarting: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let snapshot {
                    if let image = snapshot.frame.image {
                        Image(sensor: image, mode: mode).resizable().scaledToFill()
                    }
                    if let heat = snapshot.heatmap {
                        Image(sensor: heat, mode: mode).resizable().interpolation(.none).scaledToFill()
                            .opacity(opacity)
                    }
                } else if isStarting {
                    ProgressView("Đang khởi động cảm biến…").tint(.white).foregroundStyle(.white)
                }
                if let touch {
                    marker(at: touch, in: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                touch = CGPoint(x: min(max(tap.location.x / geo.size.width, 0), 1),
                                y: min(max(tap.location.y / geo.size.height, 0), 1))
            })
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ảnh camera với lớp phủ độ sâu. Khoảng cách điểm giữa \(Format.meters(snapshot?.stats.center))")
        .accessibilityHint("Chạm để đo khoảng cách tại một điểm")
        .accessibilityAction(named: "Đo tại điểm giữa") { touch = CGPoint(x: 0.5, y: 0.5) }
    }

    @ViewBuilder private func marker(at p: CGPoint, in size: CGSize) -> some View {
        let x = p.x * size.width, y = p.y * size.height
        Image(systemName: "plus.circle").font(.title2).foregroundStyle(.white)
            .shadow(color: .black, radius: 2).position(x: x, y: y)
        Text(probe.map { Format.meters($0.meters) } ?? "không có dữ liệu")
            .font(.footnote.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.75), in: Capsule())
            .foregroundStyle(.white)
            .position(x: min(max(x, 50), size.width - 50), y: y > 40 ? y - 28 : y + 28)
            .accessibilityHidden(true)
    }
}

struct LegendBar: View {
    let maxMeters: Double

    var body: some View {
        let stops = (0...10).map { i -> Color in
            let c = Colormap.depthColor(meters: Float(i), maxMeters: 10)
            return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
        }
        VStack(spacing: 2) {
            LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
                .frame(height: 14).clipShape(RoundedRectangle(cornerRadius: 4))
            GeometryReader { geo in
                ForEach(0...Int(maxMeters), id: \.self) { m in
                    Text(m == Int(maxMeters) ? "\(m) m" : "\(m)").font(.caption2.monospacedDigit())
                        .position(x: min(max(geo.size.width * CGFloat(Double(m) / maxMeters), 10), geo.size.width - 12), y: 8)
                }
            }
            .frame(height: 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thang màu độ sâu từ 0 đến \(Int(maxMeters)) mét, gần là đỏ, xa là xanh")
    }
}

struct StatsGrid: View {
    let stats: DepthStats?
    let fps: Double?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            cell("Điểm giữa", Format.meters(stats?.center))
            cell("FPS độ sâu thật", Format.fps(fps ?? 0))
            cell("Gần nhất (tin cậy cao)", Format.meters(stats?.minHigh))
            cell("Xa nhất (tin cậy cao)", Format.meters(stats?.maxHigh))
            cell("Điểm hợp lệ", stats.map { Format.percent($0.validFraction) } ?? "—")
            cell("Điểm tin cậy cao", stats.map { Format.percent($0.highFraction) } ?? "—")
        }
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Pixels per 0.25 m band, split by confidence, to show where the data runs dry.
struct HistogramChart: View {
    let bins: [HistogramBin]
    let reliableRange: Float?

    private struct Row: Identifiable {
        let id: String
        let x: Double
        let series: String
        let count: Int
    }

    private var rows: [Row] {
        bins.flatMap { bin -> [Row] in
            let mid = Double(bin.lower + DepthAnalysis.binWidth / 2)
            return [Row(id: "h\(bin.index)", x: mid, series: "Tin cậy cao", count: bin.high),
                    Row(id: "o\(bin.index)", x: mid, series: "Thấp/trung bình", count: bin.other)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Số điểm ảnh theo khoảng cách (mỗi cột 0,25 m)").font(.headline)
            Chart {
                ForEach(rows) { row in
                    BarMark(x: .value("Khoảng cách (m)", row.x), y: .value("Số điểm ảnh", row.count), width: .fixed(9))
                        .foregroundStyle(by: .value("Độ tin cậy", row.series))
                }
                if let reliableRange {
                    RuleMark(x: .value("Độ xa tin cậy", Double(reliableRange)))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .foregroundStyle(.primary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Độ xa tin cậy").font(.caption2)
                        }
                }
            }
            .chartForegroundStyleScale(["Tin cậy cao": Color.green, "Thấp/trung bình": Color.orange])
            .chartXScale(domain: 0...6)
            .chartXAxis { AxisMarks(values: .stride(by: 1)) }
            .chartXAxisLabel("Khoảng cách (m)")
            .chartYAxisLabel("Số điểm ảnh")
            .chartLegend(position: .bottom)
            .frame(height: 220)
            .accessibilityLabel("Biểu đồ số điểm ảnh theo khoảng cách")
            .accessibilityValue(summary)
        }
    }

    private var summary: String {
        guard let peak = bins.max(by: { $0.total < $1.total }), peak.total > 0 else { return "Chưa có dữ liệu" }
        return "Nhiều điểm nhất ở khoảng \(String(format: "%.2f", peak.lower)) đến \(String(format: "%.2f", peak.upper)) mét"
    }
}
