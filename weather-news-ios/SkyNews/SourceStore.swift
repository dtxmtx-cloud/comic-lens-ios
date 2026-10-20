import Foundation
import Combine

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var sources: [FeedSource]

    init() {
        if let data = UserDefaults.standard.data(forKey: "rss.sources"),
           let stored = try? JSONDecoder().decode([FeedSource].self, from: data) {
            sources = stored
        } else {
            sources = FeedSource.defaults
        }
    }

    func setEnabled(_ sourceID: UUID, _ value: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].enabled = value
        persist()
    }

    func add(name: String, address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              !sources.contains(where: { $0.address == trimmed }) else { return false }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sources.append(FeedSource(name: title.isEmpty ? (url.host ?? "RSS") : title, address: trimmed))
        persist()
        return true
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { sources.remove(at: index) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(data, forKey: "rss.sources")
        }
    }
}