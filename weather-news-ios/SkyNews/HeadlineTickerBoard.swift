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

/// Reuses only two short ticker strips (a rolling row of titles) instead of
/// rendering all feed articles or allocating a huge Core Animation animation.
private final class HeadlineMarqueeUIView: UIView, UIContextMenuInteractionDelegate {
    var speed: CGFloat = 45
    var isPaused = false
    var onOpen: ((NewsArticle) -> Void)?
    var onVote: ((NewsArticle, Bool) -> Void)?

    private let first = UIView()
    private let second = UIView()
    private var articles: [NewsArticle] = []
    private var fontSize: CGFloat = 20
    private var signature = ""
    private var builtWidth: CGFloat = 0
    private var builtHeight: CGFloat = 0
    private var cycleWidth: CGFloat = 0
    private var position: CGFloat = 0
    private var lastTimestamp: CFTimeInterval?
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        first.isUserInteractionEnabled = true
        second.isUserInteractionEnabled = true
        addSubview(first)
        addSubview(second)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit { displayLink?.invalidate() }

    func setArticles(_ value: [NewsArticle], fontSize: CGFloat) {
        let newSignature = value.map { $0.id + ":" + $0.title }.joined(separator: "\n")
            + "|" + String(describing: fontSize)
        guard signature != newSignature else { return }
        signature = newSignature
        articles = value
        self.fontSize = fontSize
        builtWidth = 0
        builtHeight = 0
        position = 0
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 && bounds.height > 0 else { return }
        if builtWidth != bounds.width || builtHeight != bounds.height {
            rebuild()
        }
        moveStrips()
    }

    private func rebuild() {
        builtWidth = bounds.width
        builtHeight = bounds.height
        for strip in [first, second] {
            strip.subviews.forEach { $0.removeFromSuperview() }
        }
        guard !articles.isEmpty else { cycleWidth = 0; return }

        // A modest track repeats a handful of titles; wider screens still
        // always have text to display, even when the RSS feed contains one item.
        let targetWidth = max(bounds.width * 1.5, 950)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium)
        ]
        var x: CGFloat = 0
        var index = 0
        while x < targetWidth && index < 24 {
            let article = articles[index % articles.count]
            let caption = article.title + "     ·     "
            let width = max(90, ceil((caption as NSString).size(withAttributes: attrs).width) + 8)
            for strip in [first, second] {
                let button = HeadlineButton(type: .custom)
                button.article = article
                button.setTitle(caption, for: .normal)
                button.setTitleColor(.white.withAlphaComponent(0.97), for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .medium)
                button.titleLabel?.lineBreakMode = .byClipping
                button.contentHorizontalAlignment = .left
                button.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
                button.accessibilityLabel = article.title + "、" + article.source
                button.addTarget(self, action: #selector(openHeadline(_:)), for: .touchUpInside)
                button.addInteraction(UIContextMenuInteraction(delegate: self))
                strip.addSubview(button)
            }
            x += width
            index += 1
        }
        cycleWidth = max(1, x)
        first.frame = CGRect(x: 0, y: 0, width: cycleWidth, height: bounds.height)
        second.frame = CGRect(x: cycleWidth, y: 0, width: cycleWidth, height: bounds.height)
        position = 0
    }

    private func moveStrips() {
        guard cycleWidth > 0 else { return }
        first.frame.origin.x = -position
        second.frame.origin.x = cycleWidth - position
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let before = lastTimestamp, window != nil, !isPaused, cycleWidth > 0 else { return }
        let delta = CGFloat(min(0.1, max(0, link.timestamp - before)))
        position += max(0, speed) * delta
        if position >= cycleWidth {
            position.formTruncatingRemainder(dividingBy: cycleWidth)
        }
        moveStrips()
    }

    @objc private func openHeadline(_ sender: HeadlineButton) {
        guard let article = sender.article else { return }
        onOpen?(article)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let article = (interaction.view as? HeadlineButton)?.article else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let read = UIAction(title: "元記事を開く", image: UIImage(systemName: "arrow.up.right.square")) { _ in
                self?.onOpen?(article)
            }
            let like = UIAction(title: "興味あり", image: UIImage(systemName: "hand.thumbsup")) { _ in
                self?.onVote?(article, true)
            }
            let dislike = UIAction(title: "興味なし", image: UIImage(systemName: "hand.thumbsdown")) { _ in
                self?.onVote?(article, false)
            }
            return UIMenu(children: [read, like, dislike])
        }
    }
}