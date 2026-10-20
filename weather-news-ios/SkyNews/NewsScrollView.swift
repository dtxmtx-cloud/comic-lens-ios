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
    private var firstCycle: UIStackView?
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

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit { displayLink?.invalidate() }

    func render(_ articles: [NewsArticle], textSize: CGFloat) {
        let signature = articles.map(\.id).joined(separator: "\n") + "|" + String(textSize)
        guard signature != currentSignature else { return }
        currentSignature = signature
        rows.removeAll()
        firstCycle = nil
        for child in column.arrangedSubviews {
            column.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        guard !articles.isEmpty else { return }
        for repeatIndex in 0..<2 {
            let group = UIStackView()
            group.axis = .vertical
            group.alignment = .fill
            group.distribution = .fill
            group.spacing = 14
            for article in articles {
                let panel = makePanel(article, textSize: textSize)
                group.addArrangedSubview(panel)
                if repeatIndex == 0 { rows.append((article.id, panel)) }
            }
            column.addArrangedSubview(group)
            if repeatIndex == 0 { firstCycle = group }
        }
        setContentOffset(.zero, animated: false)
        lastID = nil
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
        source.text = article.source + "  ·  " +
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
        if manualPause || isDragging || isDecelerating || window == nil { return }
        let elapsed = min(0.1, max(0, timestamp - previous))
        guard elapsed > 0 else { return }
        layoutIfNeeded()
        let cycle = (firstCycle?.bounds.height ?? 0) + column.spacing
        let maximum = contentSize.height - bounds.height
        guard cycle > 0, maximum > 0 else { return }
        var y = contentOffset.y + speed * CGFloat(elapsed)
        if y >= cycle { y -= cycle }
        if y > maximum { y = 0 }
        setContentOffset(CGPoint(x: 0, y: max(0, y)), animated: false)
        let cyclePosition = y.truncatingRemainder(dividingBy: cycle)
        if let index = rows.lastIndex(where: { $0.1.frame.minY <= cyclePosition + 60 }) {
            let id = rows[index].0
            if lastID != id {
                lastID = id
                onVisibleArticle?(id)
            }
        }
    }
}