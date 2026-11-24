import SwiftUI
import UIKit

// The categories are based on headline keywords. An article is never placed
// under an unrelated category merely to fill an empty lane.
private enum HeadlineTopic: Int, CaseIterable {
    case breaking, economy, science, games, entertainment, sports, general

    var title: String {
        switch self {
        case .breaking: return "速報"
        case .economy: return "経済"
        case .science: return "科学"
        case .games: return "ゲーム"
        case .entertainment: return "エンタメ"
        case .sports: return "スポーツ"
        case .general: return "新着"
        }
    }

    var accent: Color {
        switch self {
        case .breaking: return Color(red: 1, green: 0.73, blue: 0.73)
        case .economy: return Color(red: 0.69, green: 0.85, blue: 1)
        case .science: return Color(red: 0.73, green: 0.97, blue: 0.86)
        case .games: return Color(red: 0.83, green: 0.77, blue: 1)
        case .entertainment: return Color(red: 1, green: 0.90, blue: 0.73)
        case .sports: return Color(red: 0.74, green: 0.97, blue: 1)
        case .general: return .white
        }
    }

    static func classify(_ title: String) -> HeadlineTopic {
        let value = title.lowercased()
        func matches(_ words: [String]) -> Bool {
            words.contains { value.contains($0) }
        }
        if matches(["速報", "緊急", "地震", "津波", "警報", "避難", "台風", "災害"]) {
            return .breaking
        }
        if matches(["サッカー", "野球", "スポーツ", "五輪", "オリンピック", "大リーグ", "mlb",
                    "選手権", "日本代表", "バスケット", "ゴルフ", "テニス", "相撲", "競技"]) {
            return .sports
        }
        if matches(["株価", "日経平均", "円相場", "為替", "物価", "金利", "景気", "経済",
                    "金融", "企業決算", "決算発表", "投資", "賃金", "市場", "東証"]) {
            return .economy
        }
        if matches(["ゲーム", "rpg", "playstation", "switch", "ニンテンドー", "任天堂",
                    "ps5", "steam", "ゲーミング"]) {
            return .games
        }
        if matches(["アニメ", "映画", "ドラマ", "漫画", "マンガ", "音楽", "芸能",
                    "アイドル", "声優", "エンタメ", "配信番組"]) {
            return .entertainment
        }
        if matches(["研究", "科学", "宇宙", "天文学", "実験", "論文", "人工知能",
                    "ai", "ロボット", "化学", "生物", "量子", "発見", "技術"]) {
            return .science
        }
        return .general
    }
}

private struct HeadlineLaneData: Identifiable {
    let id: Int
    let title: String
    let tint: Color
    let articles: [NewsArticle]
}

/// A compact, semi-transparent LED-style headline board.  The original
/// lock-screen clock, weather gauges and muted sky remain untouched.
struct HeadlineTickerBoard: View {
    let articles: [NewsArticle]
    let laneCount: Int
    let speed: Double
    let fontSize: Double
    let paused: Bool
    let openArticle: (NewsArticle) -> Void
    let vote: (NewsArticle, Bool) -> Void

    private var lanes: [HeadlineLaneData] {
        let count = max(2, min(6, laneCount))
        var groups = HeadlineTopic.allCases.compactMap { topic -> (HeadlineTopic, [NewsArticle])? in
            let items = articles.filter { HeadlineTopic.classify($0.title) == topic }
            return items.isEmpty ? nil : (topic, items)
        }
        // Split populated buckets if the sources cover fewer than N topics;
        // keep each category honest and each lane supplied with real headlines.
        while groups.count < count {
            guard let i = groups.indices
                .filter({ groups[$0].1.count >= 2 })
                .max(by: { groups[$0].1.count < groups[$1].1.count })
            else { break }
            let original = groups[i]
            let left = original.1.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
            let right = original.1.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? nil : $0.element }
            groups[i] = (original.0, left)
            groups.insert((original.0, right), at: i + 1)
        }
        // With very few total articles, repeat real lanes rather than showing
        // labels with fabricated or unrelated text.
        if !groups.isEmpty {
            let base = groups
            var n = 0
            while groups.count < count {
                groups.append(base[n % base.count])
                n += 1
            }
        }
        return Array(groups.prefix(count)).enumerated().map { position, group in
            HeadlineLaneData(
                id: position,
                title: group.0.title,
                tint: group.0.accent,
                articles: group.1
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let visibleLanes = lanes
            let available = geometry.size.height
            let lineHeight = max(40, min(58, (available - CGFloat(visibleLanes.count - 1) * 10) /
                                           CGFloat(max(1, visibleLanes.count))))
            VStack(spacing: 0) {
                Spacer(minLength: 4)
                VStack(spacing: 10) {
                    ForEach(visibleLanes) { lane in
                        HStack(spacing: 0) {
                            Capsule()
                                .fill(lane.tint.opacity(0.87))
                                .frame(width: 3.5)
                                .padding(.vertical, 9)
                            Text(lane.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: 74, alignment: .leading)
                                .padding(.leading, 9)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.72))
                                .padding(.trailing, 6)
                            HeadlineMarquee(
                                articles: lane.articles,
                                speed: speed * (1 + Double(lane.id % 3) * 0.08),
                                fontSize: fontSize,
                                paused: paused,
                                openArticle: openArticle,
                                vote: vote
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(height: lineHeight)
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.7)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                }
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 13)
    }
}

private struct HeadlineMarquee: UIViewRepresentable {
    let articles: [NewsArticle]
    let speed: Double
    let fontSize: Double
    let paused: Bool
    let openArticle: (NewsArticle) -> Void
    let vote: (NewsArticle, Bool) -> Void

    func makeUIView(context: Context) -> HeadlineMarqueeUIView {
        HeadlineMarqueeUIView()
    }

    func updateUIView(_ view: HeadlineMarqueeUIView, context: Context) {
        view.speed = CGFloat(speed)
        view.isPaused = paused
        view.onOpen = openArticle
        view.onVote = vote
        view.setArticles(articles, fontSize: CGFloat(fontSize))
    }
}

private final class HeadlineButton: UIButton {
    var article: NewsArticle?
}

/// One small, reusable pair of headline buttons per lane. Previous builds
/// generated up to 48 buttons per lane, each with a context menu interaction,
/// then moved two enormous subview trees 30 times per second.
///
/// With this implementation six lanes = 12 buttons, at 12 frames per second.
private final class HeadlineMarqueeUIView: UIView, UIContextMenuInteractionDelegate {
    var speed: CGFloat = 42
    var isPaused = false
    var onOpen: ((NewsArticle) -> Void)?
    var onVote: ((NewsArticle, Bool) -> Void)?

    private let first = HeadlineButton(type: .custom)
    private let second = HeadlineButton(type: .custom)
    private var articles: [NewsArticle] = []
    private var nextIndex = 0
    private var fontSize: CGFloat = 19
    private var signature = ""
    private var lastSize = CGSize.zero
    private let gap: CGFloat = 18
    private var lastTimestamp: CFTimeInterval?
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
        for button in [first, second] {
            button.setTitleColor(UIColor.white.withAlphaComponent(0.97), for: .normal)
            button.titleLabel?.lineBreakMode = .byClipping
            button.titleLabel?.numberOfLines = 1
            button.contentHorizontalAlignment = .left
            button.addTarget(self, action: #selector(openHeadline(_:)), for: .touchUpInside)
            button.addInteraction(UIContextMenuInteraction(delegate: self))
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // The display link retains its target. Explicitly invalidating on detach
    // is essential to avoid a permanent view + CADisplayLink retain cycle.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = nil
        } else if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFramesPerSecond = 12
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    func setArticles(_ updated: [NewsArticle], fontSize size: CGFloat) {
        // Titles are short, so comparing this signature is inexpensive.
        let newSignature = updated.map { $0.id + "|" + $0.title }.joined(separator: "\n")
            + "|" + String(describing: size)
        guard newSignature != signature else { return }
        signature = newSignature
        articles = updated
        fontSize = size
        nextIndex = 0
        lastSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        nextIndex = 0
        let w1 = loadNext(into: first)
        let w2 = loadNext(into: second)
        first.frame = CGRect(x: 0, y: 0, width: w1, height: bounds.height)
        second.frame = CGRect(x: w1 + gap, y: 0, width: w2, height: bounds.height)
    }

    @discardableResult
    private func loadNext(into button: HeadlineButton) -> CGFloat {
        guard !articles.isEmpty else {
            button.article = nil
            button.setTitle(nil, for: .normal)
            return 0
        }
        let article = articles[nextIndex % articles.count]
        nextIndex = (nextIndex + 1) % articles.count
        button.article = article
        let title = String(article.title.prefix(160)) + "    ·    "
        button.setTitle(title, for: .normal)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        button.titleLabel?.font = font
        button.accessibilityLabel = article.title + "、" + article.source
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        return min(1800, max(140, textWidth + 8))
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let previous = lastTimestamp, window != nil, !isPaused,
              !articles.isEmpty, bounds.width > 0 else { return }

        let travel = max(0, speed) * CGFloat(min(0.12, max(0, link.timestamp - previous)))
        guard travel > 0 else { return }

        first.frame.origin.x -= travel
        second.frame.origin.x -= travel

        if first.frame.maxX < 0 {
            let nextX = second.frame.maxX + gap
            let nextWidth = loadNext(into: first)
            first.frame = CGRect(x: nextX, y: 0, width: nextWidth, height: bounds.height)
        }
        if second.frame.maxX < 0 {
            let nextX = first.frame.maxX + gap
            let nextWidth = loadNext(into: second)
            second.frame = CGRect(x: nextX, y: 0, width: nextWidth, height: bounds.height)
        }
    }

    @objc private func openHeadline(_ sender: HeadlineButton) {
        guard let article = sender.article else { return }
        onOpen?(article)
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let article = (interaction.view as? HeadlineButton)?.article else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let read = UIAction(title: "元記事を開く",
                                image: UIImage(systemName: "arrow.up.right.square")) { _ in
                self?.onOpen?(article)
            }
            let like = UIAction(title: "興味あり",
                                image: UIImage(systemName: "hand.thumbsup")) { _ in
                self?.onVote?(article, true)
            }
            let dislike = UIAction(title: "興味なし",
                                   image: UIImage(systemName: "hand.thumbsdown")) { _ in
                self?.onVote?(article, false)
            }
            return UIMenu(children: [read, like, dislike])
        }
    }
}