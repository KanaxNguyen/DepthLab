import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { SpecsView() } label: { Label("Thông số đo được", systemImage: "gauge.with.dots.needle.33percent") }
                NavigationLink { SettingsView() } label: { Label("Cài đặt", systemImage: "gearshape") }
                NavigationLink { AboutView() } label: { Label("Giới thiệu", systemImage: "info.circle") }
            }
            .navigationTitle("Thêm")
        }
    }
}

/// Sensor comparison filled only from recorded samples and captures.
struct SpecsView: View {
    @Environment(SampleStore.self) private var samples
    @Environment(CaptureStore.self) private var captures

    var body: some View {
        let observations = samples.observations + captures.observations
        List {
            Section {
                Text("Mọi số dưới đây lấy từ các mẫu và mẫu chụp đã ghi trên máy này. Ô chưa có dữ liệu ghi \"chưa đo\".")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(SensorMode.allCases) { mode in
                let specs = SpecsSummary.make(from: observations, mode: mode)
                Section(mode.title) {
                    row("Số phiên đã ghi", "\(specs.sessions)")
                    row("Độ phân giải depthMap", specs.resolution)
                    row("FPS thật (trung vị)", specs.fpsMedian.map { Format.fps($0) })
                    row("FPS thật (cao nhất)", specs.fpsMax.map { Format.fps($0) })
                    row("Khoảng cách nhỏ nhất quan sát được", specs.minObservedM.map { Format.meters($0) })
                    row("Khoảng cách lớn nhất quan sát được", specs.maxObservedM.map { Format.meters($0) })
                    row("Độ xa tin cậy lớn nhất (quy ước app)", specs.bestReliableRangeM.map { Format.meters($0) })
                }
            }
        }
        .navigationTitle("Thông số đo được")
    }

    private func row(_ title: String, _ value: String?) -> some View {
        LabeledContent(title) {
            Text(value ?? "chưa đo").foregroundStyle(value == nil ? .secondary : .primary).monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @AppStorage(AppSettings.reliableFractionKey) private var fraction = AppSettings.defaultReliableFraction
    @AppStorage(AppSettings.heatmapMaxKey) private var heatmapMax = AppSettings.defaultHeatmapMax
    @AppStorage(AppSettings.hideLowKey) private var hideLow = false
    @AppStorage(AppSettings.smoothedKey) private var smoothed = false
    @AppStorage(AppSettings.filteringKey) private var filtering = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("Ngưỡng: \(Int((fraction * 100).rounded())) % điểm tin cậy cao")
                    Slider(value: $fraction, in: 0.1...0.9, step: 0.05)
                        .accessibilityLabel("Ngưỡng độ xa tin cậy")
                        .accessibilityValue("\(Int((fraction * 100).rounded())) phần trăm")
                }
            } header: { Text("Độ xa tin cậy") } footer: {
                Text("Quy ước của app, không phải thông số của Apple: chia độ sâu thành các dải 0,25 m (0 đến 6 m). Độ xa tin cậy là mép xa của dải xa nhất có ít nhất ngưỡng này số điểm là tin cậy cao. Dải có dưới 0,5 % tổng số điểm bị bỏ qua để tránh nhiễu.")
            }
            Section("Heatmap") {
                Stepper("Thang màu tối đa: \(Int(heatmapMax)) m", value: $heatmapMax, in: 1...8, step: 1)
                    .frame(minHeight: 44)
                Toggle("Chỉ hiện điểm tin cậy cao", isOn: $hideLow).frame(minHeight: 44)
            }
            Section {
                Toggle("Thử smoothedSceneDepth", isOn: $smoothed).frame(minHeight: 44)
            } header: { Text("LiDAR") } footer: {
                Text("Mặc định dùng sceneDepth. Đổi tuỳ chọn sẽ khởi động lại phiên đo.")
            }
            Section {
                Toggle("Bật lọc của hệ thống", isOn: $filtering).frame(minHeight: 44)
            } header: { Text("TrueDepth") } footer: {
                Text("Mặc định tắt để xem dữ liệu thô. Khi bật, hệ thống nội suy lấp lỗ nên số điểm hợp lệ sẽ cao hơn thực tế. TrueDepth không có độ tin cậy từng điểm: app coi điểm hợp lệ là tin cậy cao khi chất lượng khung là high, và trung bình nếu là low.")
            }
        }
        .navigationTitle("Cài đặt")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                Text("DepthLab là công cụ đo thực nghiệm, không phải sản phẩm. Kết quả chỉ là số liệu thực nghiệm trên một máy (\(DeviceInfo.model)), không phải thông số của Apple.")
            }
            Section("Mục đích") {
                Text("Đo LiDAR (camera sau) và TrueDepth (camera trước) nhìn xa tới đâu, còn đáng tin tới đâu, để đánh giá việc gắn iPhone gần gương chiếu hậu nhìn xuống ghế sau (khoảng 1,5 đến 2 m).")
            }
            Section("Quyền riêng tư") {
                Text("Không dùng mạng, không tài khoản, không gửi dữ liệu ra ngoài máy. Ảnh màu không được lưu trừ khi bạn bật công tắc khi chụp mẫu. Chỉ thử với búp bê hoặc vật thay thế, không thử với trẻ thật hay thú thật.")
            }
            Section("Phiên bản") {
                LabeledContent("Bản", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Máy", value: DeviceInfo.model)
                LabeledContent("iOS", value: DeviceInfo.systemVersion)
            }
        }
        .navigationTitle("Giới thiệu")
    }
}
