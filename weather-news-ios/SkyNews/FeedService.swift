import Foundation
import Combine

private final class RSSParser: NSObject, XMLParserDelegate {
    private var articles: [NewsArticle] = []
    private let source: FeedSource
    private var insideEntry = false
    private var captureField: String?
    private var buffer = ""
    private var fields: [String: String] = [:]

    init(source: FeedSource) { self.source = source }

    static func parse(_ data: Data, source: FeedSource) -> [NewsArticle] {
        let receiver = RSSParser(source: source)
        let parser = XMLParser(data: data)
        parser.delegate = receiver
        parser.parse()
        return receiver.articles
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let key = name.lowercased()
        if key == "item" || key == "entry" {
            insideEntry = true
            fields.removeAll()
            return
        }
        guard insideEntry else { return }
        if key == "link", let href = attributes["href"], !href.isEmpty {
            fields["link"] = href
        }
        if ["title", "link", "guid", "id", "description", "summary",
            "content:encoded", "content", "pubdate", "published", "updated", "dc:date"].contains(key) {
            captureField = key
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureField != nil { buffer.append(string) }
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if captureField != nil { buffer.append(String(decoding: data, as: UTF8.self)) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        let key = name.lowercased()
        if insideEntry && captureField == key {
            let cleaned = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { fields[key] = cleaned }
            captureField = nil
        }
        if key == "item" || key == "entry" {
            insideEntry = false
            if let item = makeArticle() { articles.append(item) }
        }
    }

    private func makeArticle() -> NewsArticle? {
        guard let titleHTML = fields["title"],
              let linkText = fields["link"] ?? fields["guid"] ?? fields["id"],
              let url = URL(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let text = fields["content:encoded"] ?? fields["content"]
            ?? fields["description"] ?? fields["summary"] ?? ""
        let dateText = fields["pubdate"] ?? fields["published"] ?? fields["updated"]
            ?? fields["dc:date"] ?? ""
        return NewsArticle(
            id: url.absoluteString,
            title: Self.plainText(titleHTML),
            body: Self.plainText(text),
            url: url,
            source: source.name,
            publishedAt: Self.readDate(dateText) ?? Date(),
            textSource: (fields["content:encoded"] != nil || fields["content"] != nil) ? "rssFull" : "rssExcerpt"
        )
    }

    private static func readDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z",
                        "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func plainText(_ html: String) -> String {
        var value = html
        value = value.replacingOccurrences(of: "(?i)<(br|/p|/div|/li|/h[1-6])[^>]*>", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")
        ]
        for (entity, replacement) in entities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric HTML entities are decoded, including supplementary Unicode planes.
        let expression = try? NSRegularExpression(pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);")
        if let expression = expression {
            let matches = expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: value),
                      let numberRange = Range(match.range(at: 1), in: value) else { continue }
                let digits = String(value[numberRange])
                let scalarNumber = digits.lowercased().hasPrefix("x")
                    ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
                if let number = scalarNumber, let scalar = UnicodeScalar(number) {
                    value.replaceSubrange(range, with: String(scalar))
                }
            }
        }
        value = value.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class NewsStore: ObservableObject {
    @Published private(set) var articles: [NewsArticle] = []
    @Published private(set) var loading = false
    @Published private(set) var message: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: "feed.cached"),
           let cached = try? JSONDecoder().decode([NewsArticle].self, from: data) {
            articles = cached
        }
    }

    func refresh(_ sources: [FeedSource], fetchWebBodies: Bool = true) async {
        guard !loading else { return }
        let enabled = sources.filter(\.enabled)
        guard !enabled.isEmpty else {
            message = "設定からRSS配信元を有効にしてください。"
            return
        }
        loading = true
        defer { loading = false }
        let incoming: [NewsArticle] = await withTaskGroup(of: [NewsArticle].self) { group in
            for source in enabled {
                group.addTask {
                    guard let url = URL(string: source.address) else { return [] }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 20
                    request.setValue("SkyNewsFlow/0.1 RSS Reader", forHTTPHeaderField: "User-Agent")
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                        return RSSParser.parse(data, source: source)
                    } catch { return [] }
                }
            }
            var results: [NewsArticle] = []
            for await groupResult in group { results.append(contentsOf: groupResult) }
            return results
        }
        let unique = Dictionary(grouping: incoming, by: \.id).compactMap { $0.value.first }
        let sorted = unique.sorted { $0.publishedAt > $1.publishedAt }
        if !sorted.isEmpty {
            let oldWebBodies = Dictionary(
                uniqueKeysWithValues: articles.filter { $0.textSource == "web" }.map { ($0.id, $0) }
            )
            articles = Array(sorted.prefix(250)).map { item in
                guard let cached = oldWebBodies[item.id],
                      cached.body.count > item.body.count else { return item }
                return cached
            }
            message = nil
            persist()
            if fetchWebBodies { await enrichFromWeb(maxPages: 24) }
        } else {
            message = articles.isEmpty
                ? "記事を取得できませんでした。通信状況とRSSのURLを確認してください。"
                : "最新記事を取得できませんでした。保存済みの記事を表示しています。"
        }
    }

    private func enrichFromWeb(maxPages: Int) async {
        let candidates = Array(articles.filter {
            $0.textSource != "web" &&
            ($0.textSource != "rssFull" || $0.body.count < 900)
        }.prefix(maxPages))
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: (String, String?).self) { group in
            var iterator = candidates.makeIterator()
            for _ in 0..<min(3, candidates.count) {
                if let item = iterator.next() {
                    group.addTask {
                        (item.id, await ArticlePageExtractor.fetch(for: item))
                    }
                }
            }
            var extractedBodies: [String: String] = [:]
            for await (id, text) in group {
                if let text { extractedBodies[id] = text }
                if let nextItem = iterator.next() {
                    group.addTask {
                        (nextItem.id, await ArticlePageExtractor.fetch(for: nextItem))
                    }
                }
            }
            if !extractedBodies.isEmpty {
                var enriched = articles
                for index in enriched.indices {
                    if let body = extractedBodies[enriched[index].id] {
                        enriched[index].body = body
                        enriched[index].textSource = "web"
                    }
                }
                articles = enriched
            }
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(articles) {
            UserDefaults.standard.set(data, forKey: "feed.cached")
        }
    }

}