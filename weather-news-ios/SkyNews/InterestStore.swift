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
        // Publish weights once. Writing into a @Published dictionary for
        // every token used to trigger dozens of full UI updates per vote.
        var nextWeights = weights
        for term in Self.terms(for: article) {
            nextWeights[term, default: 0] = max(-12, min(12, nextWeights[term, default: 0] + delta))
        }
        nextWeights["src:" + article.source, default: 0] += delta * 1.5
        weights = nextWeights
        var nextVotes = votes
        nextVotes[article.id] = newValue
        votes = nextVotes
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

    // Score each article ONCE, then sort cached numeric scores. The previous
    // comparator ran NaturalLanguage tokenizer thousands of times per sort,
    // blocking the UI whenever the parent view refreshed.
    func rank(_ articles: [NewsArticle], preferredPercent: Int) -> [NewsArticle] {
        guard !articles.isEmpty else { return [] }
        let preferredSlots = max(0, min(9, preferredPercent / 10))
        var scores: [String: Double] = [:]
        scores.reserveCapacity(articles.count)
        for article in articles {
            scores[article.id] = score(article)
        }
        let preference = articles.sorted {
            let a = scores[$0.id] ?? 0
            let b = scores[$1.id] ?? 0
            return a == b ? $0.publishedAt > $1.publishedAt : a > b
        }
        let latest = articles.sorted { $0.publishedAt > $1.publishedAt }
        let discovery = articles.sorted {
            let a = abs(scores[$0.id] ?? 0)
            let b = abs(scores[$1.id] ?? 0)
            return a == b ? $0.publishedAt > $1.publishedAt : a < b
        }
        let schedule = Array(repeating: 0, count: preferredSlots)
            + Array(repeating: 1, count: 9 - preferredSlots) + [2]
        var visited = Set<String>()
        var result: [NewsArticle] = []
        result.reserveCapacity(articles.count)
        let pools = [preference, latest, discovery]
        // Keep pool cursors rather than scanning all articles for each slot.
        var indices = [0, 0, 0]
        while result.count < articles.count {
            let before = result.count
            for slot in schedule {
                while indices[slot] < pools[slot].count,
                      visited.contains(pools[slot][indices[slot]].id) {
                    indices[slot] += 1
                }
                if indices[slot] < pools[slot].count {
                    let item = pools[slot][indices[slot]]
                    indices[slot] += 1
                    if visited.insert(item.id).inserted {
                        result.append(item)
                    }
                }
            }
            if result.count == before { break }
        }
        return result
    }

    private static func terms(for article: NewsArticle) -> Set<String> {
        let combined = String(article.title.prefix(320))
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