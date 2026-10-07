import Foundation
import Observation

/// Manual tape-measure samples, persisted as JSON in the app's Documents folder.
@Observable
final class SampleStore {
    private(set) var samples: [SampleRecord] = []
    private let fileURL: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        fileURL = directory.appendingPathComponent("samples.json")
        load()
    }

    func add(_ sample: SampleRecord) {
        samples.append(sample)
        save()
    }

    func delete(ids: Set<UUID>) {
        samples.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteAll() {
        samples = []
        save()
    }

    var observations: [SessionObservation] {
        samples.map {
            SessionObservation(mode: $0.mode, depthWidth: $0.depthWidth, depthHeight: $0.depthHeight, fps: $0.fps,
                        minHighM: $0.minHighM, maxHighM: $0.maxHighM, reliableRangeM: $0.reliableRangeM)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        samples = (try? decoder.decode([SampleRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(samples) { try? data.write(to: fileURL, options: .atomic) }
    }
}
