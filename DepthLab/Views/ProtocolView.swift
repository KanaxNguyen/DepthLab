import SwiftUI

struct ProtocolView: View {
    @Environment(ProtocolStore.self) private var store
    @Environment(SampleStore.self) private var samples
    @State private var mode: SensorMode = .lidar

    private var doneCount: Int {
        ProtocolStore.distances.reduce(0) { acc, d in
            acc + Lighting.allCases.filter { store.isDone(mode, d, $0) }.count
        }
    }

    private var total: Int { ProtocolStore.distances.count * Lighting.allCases.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Cảm biến", selection: $mode) {
                        ForEach(SensorMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ProgressView(value: Double(doneCount), total: Double(total)) {
                        Text("Đã đo xong \(doneCount)/\(total) ô")
                    }
                }
                Section("Cách thử") {
                    Text("1. Cố định iPhone trên giá đỡ, cảm biến hướng vào vật cần đo.")
                    Text("2. Đặt búp bê cỡ trẻ nhỏ hoặc vật thay thế đúng mốc; đo thước từ cảm biến tới vật.")
                    Text("3. Chờ số đo ổn định vài giây, bấm Ghi mẫu rồi nhập khoảng cách thật, loại vật, ánh sáng.")
                    Text("4. Lặp lại cho cả 4 điều kiện ánh sáng, rồi tick ô đã xong.")
                    Text("Chỉ dùng búp bê hoặc vật thay thế, không dùng trẻ thật hay thú thật.").bold()
                }
                .font(.subheadline)

                ForEach(ProtocolStore.distances, id: \.self) { distance in
                    Section("Mốc \(distance.formatted(.number.precision(.fractionLength(0...1)))) m") {
                        ForEach(Lighting.allCases) { lighting in
                            row(distance, lighting)
                        }
                    }
                }
            }
            .navigationTitle("Quy trình thử")
        }
    }

    private func row(_ distance: Double, _ lighting: Lighting) -> some View {
        let done = store.isDone(mode, distance, lighting)
        let count = ProtocolStore.sampleCount(in: samples.samples, mode, distance, lighting)
        return Button { store.toggle(mode, distance, lighting) } label: {
            HStack {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
                Text(lighting.title).foregroundStyle(.primary)
                Spacer()
                Text("\(count) mẫu").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("\(lighting.title), mốc \(distance) mét, \(mode.shortTitle)")
        .accessibilityValue(done ? "đã đo xong, \(count) mẫu" : "chưa đo, \(count) mẫu")
        .accessibilityHint("Chạm đúp để đổi trạng thái")
    }
}
