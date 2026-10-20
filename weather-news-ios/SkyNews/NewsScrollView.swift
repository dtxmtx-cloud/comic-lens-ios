import SwiftUI
import UIKit

struct NewsScrollView: UIViewRepresentable {
    let articles: [NewsArticle]
    let pointsPerSecond: Double
    let textSize: Double
    let paused: Bool
    let onVisibleArticle: (String) -> Void

    func makeUIView(context: Context) -> ContinuouslyScrollingNews {
        ContinuouslyScrollingNews()
    }

    func updateUIView(_ view: ContinuouslyScrollingNews, context: Context) {
        view.speed = CGFloat(pointsPerSecond)
        view.manualPause = paused
        view.onVisibleArticle = onVisibleArticle
        view.render(articles, textSize: CGFloat(textSize))
    }
}

final class ContinuouslyScrollingNews: UIScrollView {
    var speed: CGFloat = 17
    var manualPause = false
    var onVisibleArticle: ((String) -> Void)?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var currentSignature = ""
    // A fixed-size rolling window prevents hundreds of full-body UILabels
    // from exhausting memory when publisher articles are long.
    private let windowCount = 4
    private var sourceArticles: [NewsArticle] = []
    private var nextArticleIndex = 0
    private var rows: [(String, UIView)] = []
    private var lastID: String?

    private let column: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.distribution = .fill
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .never
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -12),
            column.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -8),
            column.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor, constant: -24)
        ])
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit { displayLink?.invalidate() }

    func render(_ articles: [NewsArticle], textSize: CGFloat) {
        // Count + a short prefix is sufficient for detecting a body update,
        // without repeatedly hashing every byte of 250 lengthy news articles.
        let signature = articles.map {
            $0.id + ":" + String($0.body.count) + ":" +
            String($0.body.prefix(80).hashValue)
        }.joined(separator: "\n") + "|" + String(describing: textSize)
        guard signature != currentSignature else { return }
        currentSignature = signature
        sourceArticles = articles
        nextArticleIndex = 0
        rows.removeAll()
        lastID = nil
        for child in column.arrangedSubviews {
            column.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        guard !sourceArticles.isEmpty else { return }
        for _ in 0..<windowCount {
            appendNextArticle(textSize: textSize)
        }
        setContentOffset(.zero, animated: false)
        onVisibleArticle?(sourceArticles[0].id)
    }

    private var currentTextSize: CGFloat = 20

    private func appendNextArticle(textSize: CGFloat) {
        guard !sourceArticles.isEmpty else { return }
        currentTextSize = textSize
        let article = sourceArticles[nextArticleIndex]
        nextArticleIndex = (nextArticleIndex + 1) % sourceArticles.count
        let panel = makePanel(article, textSize: textSize)
        column.addArrangedSubview(panel)
        rows.append((article.id, panel))
    }

    private func recycleRows(at scrollY: inout CGFloat) {
        // Remove only rows completely above the viewport. Height is measured
        // before removal, then subtracted from content offset after relayout.
        for _ in 0..<windowCount {
            guard rows.count > 2, let first = rows.first else { return }
            let consumedHeight = first.1.bounds.height + column.spacing
            guard consumedHeight > 0, scrollY >= first.1.frame.maxY + column.spacing else { return }
            rows.removeFirst()
            column.removeArrangedSubview(first.1)
            first.1.removeFromSuperview()
            appendNextArticle(textSize: currentTextSize)
            scrollY = max(0, scrollY - consumedHeight)
            layoutIfNeeded()
            setContentOffset(CGPoint(x: 0, y: scrollY), animated: false)
        }
    }

    private func makePanel(_ article: NewsArticle, textSize: CGFloat) -> UIView {
        let panel = UIView()
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        panel.layer.cornerRadius = 17
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let source = UILabel()
        source.text = article.source + "  ·  " + (article.textSource == "web" ? "Web本文" : (article.textSource == "rssFull" ? "RSS本文" : "概要")) + "  ·  " +
            article.publishedAt.formatted(date: .abbreviated, time: .shortened)
        source.font = .systemFont(ofSize: max(11, textSize * 0.66), weight: .medium)
        source.textColor = UIColor.white.withAlphaComponent(0.80)
        source.numberOfLines = 2

        let heading = UILabel()
        heading.text = article.title
        heading.font = .systemFont(ofSize: textSize * 1.19, weight: .bold)
        heading.textColor = .white
        heading.numberOfLines = 0

        let summary = UILabel()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = textSize * 0.39
        let content = article.previewText
        summary.attributedText = NSAttributedString(string: content, attributes: [
            .font: UIFont.systemFont(ofSize: textSize, weight: .regular),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ])
        summary.numberOfLines = 0

        stack.addArrangedSubview(source)
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(summary)
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -24)
        ])
        return panel
    }

    @objc private func tick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        defer { lastTimestamp = timestamp }
        guard let previous = lastTimestamp else { return }
        guard !manualPause && !isDragging && !isDecelerating && window != nil else { return }
        guard !sourceArticles.isEmpty else { return }
        let elapsed = min(0.1, max(0, timestamp - previous))
        guard elapsed > 0 else { return }
        layoutIfNeeded()
        let maximum = max(0, contentSize.height - bounds.height)
        guard maximum > 0 else { return }
        var y = min(maximum, contentOffset.y + speed * CGFloat(elapsed))
        recycleRows(at: &y)
        setContentOffset(CGPoint(x: 0, y: y), animated: false)

        // The position refers to the current 4-row rolling window.
        if let index = rows.lastIndex(where: { $0.1.frame.minY <= y + 64 }) {
            let id = rows[index].0
            if lastID != id {
                lastID = id
                onVisibleArticle?(id)
            }
        }
    }
}