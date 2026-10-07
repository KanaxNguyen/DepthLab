import SwiftUI

/// "Ghi mẫu": pairs the frozen measurement with a tape-measure distance.
struct SampleEntrySheet: View {
    let snapshot: MeasureSnapshot
    @Environment(SampleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var truthText = ""
    @State private var kind: ObjectKind = .emptySeat
    @State private var lighting: Lighting = .indoor

    private var truth: Double? { InputParsing.meters(from: truthText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Số đo của app") {
                    LabeledContent("Chế độ", value: snapshot.frame.mode.title)
                    LabeledContent("Khoảng cách đo (điểm giữa)", value: Format.meters(snapshot.stats.center))
                    LabeledContent("Điểm hợp lệ", value: Format.percent(snapshot.stats.validFraction))
                    LabeledContent("Điểm tin cậy cao", value: Format.percent(snapshot.stats.highFraction))
                    LabeledContent("Độ xa tin cậy", value: Format.meters(snapshot.stats.reliableRange))
                }
                Section("Nhập từ thước") {
                    TextField("Khoảng cách thật (m)", text: $truthText)
                        .keyboardType(.decimalPad)
                        .frame(minHeight: 44)
                    Picker("Loại vật", selection: $kind) {
                        ForEach(ObjectKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Ánh sáng", selection: $lighting) {
                        ForEach(Lighting.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Text("Chỉ dùng búp bê hoặc vật thay thế để thử. Không dùng trẻ thật hay thú thật.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ghi mẫu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }.disabled(truth == nil)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard let truth, let measured = snapshot.stats.center else { return }
        let s = snapshot.stats
        store.add(SampleRecord(
            date: Date(), mode: snapshot.frame.mode, deviceModel: DeviceInfo.model,
            measuredM: Double(measured), groundTruthM: truth, objectKind: kind, lighting: lighting,
            validPct: s.validFraction * 100, highPct: s.highFraction * 100,
            reliableRangeM: s.reliableRange.map(Double.init),
            minHighM: s.minHigh.map(Double.init), maxHighM: s.maxHigh.map(Double.init),
            depthWidth: snapshot.frame.width, depthHeight: snapshot.frame.height, fps: snapshot.fps))
        dismiss()
    }
}

/// "Chụp mẫu": saves depth, confidence, point cloud and meta (RGB only if opted in).
struct CaptureSheet: View {
    let snapshot: MeasureSnapshot
    @Environment(CaptureStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var truthText = ""
    @State private var lighting: Lighting = .indoor
    @State private var saveRGB = false
    @State private var confirmRGB = false
    @State private var saving = false
    @State private var saved: CaptureItem?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Mẫu chụp") {
                    LabeledContent("Chế độ", value: snapshot.frame.mode.title)
                    LabeledContent("Điểm giữa", value: Format.meters(snapshot.stats.center))
                    TextField("Khoảng cách thật (m), tuỳ chọn", text: $truthText)
                        .keyboardType(.decimalPad).frame(minHeight: 44)
                    Picker("Ánh sáng", selection: $lighting) {
                        ForEach(Lighting.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle("Lưu ảnh màu (có thể chứa khuôn mặt)", isOn: Binding(
                        get: { saveRGB },
                        set: { on in if on { confirmRGB = true } else { saveRGB = false } }))
                        .frame(minHeight: 44)
                } footer: {
                    Text("Mặc định tắt. Chỉ bật với búp bê hoặc vật thay thế, không dùng người thật.")
                }
                Section {
                    if let saved {
                        Label("Đã lưu \(saved.id)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        ShareLink(items: saved.shareURLs) { Label("Chia sẻ các tệp", systemImage: "square.and.arrow.up") }
                            .frame(minHeight: 44)
                    } else {
                        Button { Task { await save() } } label: {
                            if saving { ProgressView() } else { Label("Lưu mẫu chụp", systemImage: "square.and.arrow.down") }
                        }
                        .disabled(saving).frame(minHeight: 44)
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Chụp mẫu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(saved == nil ? "Huỷ" : "Xong") { dismiss() } } }
            .alert("Bật lưu ảnh màu?", isPresented: $confirmRGB) {
                Button("Bật, chỉ với búp bê/vật thay thế") { saveRGB = true }
                Button("Không", role: .cancel) {}
            } message: {
                Text("Ảnh màu có thể chứa khuôn mặt và sẽ được lưu vào máy. Chỉ dùng với búp bê hoặc vật thay thế, không dùng người thật. Camera trước thường hướng vào mặt người.")
            }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            saved = try await store.save(frame: snapshot.frame, stats: snapshot.stats, fps: snapshot.fps,
                                         groundTruthM: InputParsing.meters(from: truthText), lighting: lighting,
                                         saveRGB: saveRGB)
        } catch {
            errorMessage = (error as? ImageFiles.WriteError)?.message ?? error.localizedDescription
        }
    }
}
