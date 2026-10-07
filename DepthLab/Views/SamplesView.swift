import Charts
import SwiftUI
import UniformTypeIdentifiers

/// CSV handed to the share sheet as a .csv file.
struct CSVDocument: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("depthlab-samples.csv")
    }
}

struct SamplesView: View {
    @Environment(SampleStore.self) private var store
    @State private var showRelative = false
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Đại lượng", selection: $showRelative) {
                        Text("Sai số tuyệt đối (m)").tag(false)
                        Text("Sai số tương đối (%)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    ForEach(SensorMode.allCases) { mode in
                        ErrorChart(mode: mode, samples: store.samples.filter { $0.mode == mode }, relative: showRelative)
                    }
                } header: { Text("Sai số theo khoảng cách thật") }

                Section("Mẫu đã ghi (\(store.samples.count))") {
                    if store.samples.isEmpty {
                        Text("Chưa có mẫu. Vào tab Đo và bấm Ghi mẫu.").foregroundStyle(.secondary)
                    }
                    ForEach(store.samples.reversed()) { SampleRow(sample: $0) }
                        .onDelete { offsets in
                            let reversed = Array(store.samples.reversed())
                            store.delete(ids: Set(offsets.map { reversed[$0].id }))
                        }
                }
            }
            .navigationTitle("Mẫu")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: CSVDocument(text: CSVExporter.csv(from: store.samples)),
                              preview: SharePreview("depthlab-samples.csv")) {
                        Label("Chia sẻ CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.samples.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label("Xoá tất cả", systemImage: "trash")
                    }
                    .disabled(store.samples.isEmpty)
                }
            }
            .confirmationDialog("Xoá tất cả mẫu đã ghi?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Xoá tất cả", role: .destructive) { store.deleteAll() }
            }
        }
    }
}

private struct SampleRow: View {
    let sample: SampleRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(sample.mode.shortTitle): đo \(Format.meters(sample.measuredM)) · thật \(Format.meters(sample.groundTruthM))")
                .font(.headline.monospacedDigit())
            Text("Sai số \(Format.meters(sample.absoluteErrorM))" + (sample.relativeErrorPct.map { String(format: " (%.1f %%)", $0) } ?? ""))
                .font(.subheadline.monospacedDigit())
            Text("Hợp lệ \(Int(sample.validPct.rounded())) % · tin cậy cao \(Int(sample.highPct.rounded())) % · xa tin cậy \(Format.meters(sample.reliableRangeM))")
                .font(.footnote).foregroundStyle(.secondary)
            Text("\(sample.objectKind.title) · \(sample.lighting.title) · \(sample.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorChart: View {
    let mode: SensorMode
    let samples: [SampleRecord]
    let relative: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.title).font(.headline)
            if samples.isEmpty {
                Text("Chưa có mẫu").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart(samples) { s in
                    PointMark(x: .value("Khoảng cách thật (m)", s.groundTruthM),
                              y: .value(relative ? "Sai số tương đối (%)" : "Sai số tuyệt đối (m)",
                                        relative ? (s.relativeErrorPct ?? 0) : s.absoluteErrorM))
                        .foregroundStyle(mode == .lidar ? Color.blue : Color.orange)
                }
                .chartXScale(domain: 0...6)
                .chartXAxisLabel("Khoảng cách thật (m)")
                .chartYAxisLabel(relative ? "Sai số tương đối (%)" : "Sai số tuyệt đối (m)")
                .frame(height: 170)
                .accessibilityLabel("Biểu đồ sai số \(mode.title), \(samples.count) mẫu")
            }
        }
        .padding(.vertical, 4)
    }
}
