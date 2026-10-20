import Foundation
import SwiftSoup

/// Best-effort article extraction for publicly accessible HTML.
/// Never runs scripts, logs in, bypasses a paywall, or downloads non-HTML files.
enum ArticlePageExtractor {
    static func fetch(for article: NewsArticle) async -> String? {
        guard article.url.scheme?.lowercased() == "https",
              let host = article.url.host, !host.isEmpty else { return nil }
        var request = URLRequest(url: article.url)
        request.timeoutInterval = 15
        request.setValue("text/html,application/xhtml+xml;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("SkyNewsFlow/0.2 (personal RSS reader)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  response.url?.scheme?.lowercased() == "https",
                  data.count <= 3_000_000 else { return nil }
            let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard contentType.contains("text/html") || contentType.contains("application/xhtml+xml") else {
                return nil
            }
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .shiftJIS)
                ?? String(decoding: data, as: UTF8.self)
            return extract(from: html, existingText: article.body)
        } catch {
            return nil
        }
    }

    /// Pure parser: can be regression-tested with fixture HTML without network access.
    static func extract(from html: String, existingText: String = "") -> String? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        var candidates: [String] = []

        for selector in [
            "[itemprop=articleBody]",
            "article",
            "[class*=article-body]",
            "[class*=articleBody]",
            "[class*=article_content]",
            "[class*=article-content]",
            "[class*=entry-content]",
            "[class*=post-content]",
            "[class*=story-body]",
            "[id*=article-body]",
            "[id*=articleBody]",
            "main",
            "[role=main]"
        ] {
            guard let elements = try? document.select(selector) else { continue }
            for element in elements.array().prefix(6) {
                let cloned = element
                if let noisy = try? cloned.select(
                    "script, style, nav, footer, header, aside, form, button, iframe, " +
                    ".related, .recommend, .recommended, .share, .social, " +
                    ".advertisement, .ad, .breadcrumb, .comments, [aria-hidden=true]"
                ) {
                    for node in noisy.array() { try? node.remove() }
                }
                var parts: [String] = []
                if let blocks = try? cloned.select("p,h2,h3,blockquote") {
                    for block in blocks.array().prefix(160) {
                        guard let text = try? block.text() else { continue }
                        let trimmed = normalized(text)
                        if trimmed.count >= 12 && parts.last != trimmed {
                            parts.append(trimmed)
                        }
                    }
                }
                let paragraphs = parts.joined(separator: "\n\n")
                let best = paragraphs.count >= 120
                    ? paragraphs : normalized((try? cloned.text()) ?? "")
                if best.count >= 150 && best.count <= 80_000 {
                    candidates.append(best)
                }
            }
        }

        // JSON-LD articleBody is another common form of publisher-provided text.
        if let scripts = try? document.select("script[type=application/ld+json]") {
            for script in scripts.array().prefix(16) {
                guard let raw = try? script.data(),
                      let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) else { continue }
                for text in jsonArticleBodies(json) where text.count >= 150 && text.count <= 80_000 {
                    candidates.append(text)
                }
            }
        }

        guard let best = candidates.max(by: { $0.count < $1.count }) else { return nil }

        // Do not replace an RSS excerpt with shorter navigation / boilerplate.
        let minLength = max(150, Int(Double(existingText.count) * 1.15))
        guard best.count >= minLength else { return nil }
        return best
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func jsonArticleBodies(_ object: Any) -> [String] {
        if let values = object as? [Any] {
            return values.flatMap(jsonArticleBodies)
        }
        guard let dictionary = object as? [String: Any] else { return [] }
        var matches: [String] = []
        if let body = dictionary["articleBody"] as? String {
            matches.append(normalized(body))
        }
        if let graph = dictionary["@graph"] {
            matches.append(contentsOf: jsonArticleBodies(graph))
        }
        return matches
    }
}