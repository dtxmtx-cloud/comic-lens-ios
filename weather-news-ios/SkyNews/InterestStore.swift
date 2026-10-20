import Foundation
import Combine
import NaturalLanguage

@MainActor
final class InterestStore: ObservableObject {
    @Published private(set) var votes: [String: Int] = [:]
    @Published private(set) var weights: [String: Double] = [:]

    private struct Archive: Codable {
        let votes: [String: Int]
        let weights: [String: Double]
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: "feed.learning"),
              let archive = try? JSONDecoder().decode(Archive.self, from: data) else { return }
        votes = archive.votes
        weights = archive.weights
    }

    func vote(_ article: NewsArticle, liked: Bool) {
        let newValue = liked ? 1 : -1
        let previous = votes[article.id] ?? 0
        if previous == newValue { return }
        let delta = Double(newValue - previous)
        for term in Self.terms(for: article) {
            weights[term, default: 0] = max(-12, min(12, weights[term, default: 0] + delta))
        }
        weights["src:" + article.source, default: 0] += delta * 1.5
        votes[article.id] = newValue
        persist()
    }

    func reset() {
        votes.removeAll()
        weights.removeAll()
        persist()
    }

    func score(_ article: NewsArticle) -> Double {
        let tokens = Self.terms(for: article)
        let lexical = tokens.reduce(0.0) { sum, term in
            sum + (weights[term] ?? 0)
        } / Double(max(1, tokens.count))
        return lexical * 4 + (weights["src:" + article.source] ?? 0)
    }

    // 10 slots: preference N, latest 9-N, discovery 1.
    // Only articles not already scheduled are selected in each slot.
    func rank(_ articles: [NewsArticle], preferredPercent: Int) -> [NewsArticle] {
        let preferredSlots = max(0, min(9, preferredPercent / 10))
        let preference = articles.sorted {
            let a = score($0), b = score($1)
            return a == b ? $0.publishedAt > $1.publishedAt : a > b
        }
        let latest = articles.sorted { $0.publishedAt > $1.publishedAt }
        let discovery = articles.sorted {
            let a = abs(score($0)), b = abs(score($1))
            return a == b ? $0.publishedAt > $1.publishedAt : a < b
        }
        let schedule = Array(repeating: 0, count: preferredSlots)
            + Array(repeating: 1, count: 9 - preferredSlots) + [2]
        var visited = Set<String>()
        var result: [NewsArticle] = []
        let pools = [preference, latest, discovery]
        while result.count < articles.count {
            let before = result.count
            for slot in schedule {
                guard let item = pools[slot].first(where: { !visited.contains($0.id) }) else { continue }
                visited.insert(item.id)
                result.append(item)
            }
            if before == result.count { break }
        }
        return result
    }

    private static func terms(for article: NewsArticle) -> Set<String> {
        let combined = article.title + " " + String(article.body.prefix(600))
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = combined
        var words = Set<String>()
        tokenizer.enumerateTokens(in: combined.startIndex..<combined.endIndex) { range, _ in
            let part = String(combined[range]).lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if part.count >= 2 && part.count <= 32 { words.insert(part) }
            return words.count < 100
        }
        return words
    }

    private func persist() {
        let archive = Archive(votes: votes, weights: weights)
        if let data = try? JSONEncoder().encode(archive) {
            UserDefaults.standard.set(data, forKey: "feed.learning")
        }
    }
}