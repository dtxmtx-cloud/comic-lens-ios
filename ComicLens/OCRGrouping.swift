import CoreGraphics
import Foundation

/// Vision coordinates, normalized to the visible snapshot (bottom-left origin).
struct OCRLine {
    let text: String
    let box: CGRect
}

/// A *candidate* classification, never a claim to have detected the real
/// speech-balloon contour. Decorative candidates remain available separately.
enum OCRBlockKind: String {
    case speech = "セリフ候補"
    case caption = "地の文候補"
    case decorative = "装飾・看板候補"
}

struct OCRGroup {
    let text: String
    let box: CGRect
    let lines: [OCRLine]
    let kind: OCRBlockKind
    var lineCount: Int { lines.count }
}

enum OCRGrouping {
    private struct Working {
        var lines: [OCRLine]
        var box: CGRect
        var bottomLine: OCRLine
    }

    static func merge(_ input: [OCRLine]) -> [OCRGroup] {
        let clean = input.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.box.width > 0 && $0.box.height > 0
        }
        guard !clean.isEmpty else { return [] }

        let heights = clean.map { $0.box.height }.sorted()
        let medianHeight = heights[heights.count / 2]

        // Vision can fragment a single printed row into two horizontal pieces.
        // Join only nearly touching pieces with aligned baselines, never whole
        // side-by-side balloons merely because they share a vertical level.
        let rows = joinRowFragments(clean.sorted(by: readingOrder), median: medianHeight)
        var blocks: [Working] = []
        for line in rows {
            var chosen: Int?
            var bestGap = CGFloat.greatestFiniteMagnitude
            for i in blocks.indices {
                guard blocks[i].lines.count < 14,
                      canJoinVertically(line, to: blocks[i], median: medianHeight) else {
                    continue
                }
                let gap = abs(blocks[i].bottomLine.box.minY - line.box.maxY)
                if gap < bestGap {
                    chosen = i
                    bestGap = gap
                }
            }
            if let chosen {
                blocks[chosen].lines.append(line)
                blocks[chosen].box = blocks[chosen].box.union(line.box)
                blocks[chosen].bottomLine = line
            } else {
                blocks.append(Working(lines: [line], box: line.box, bottomLine: line))
            }
        }

        return blocks.sorted { readingOrder($0.box, $1.box) }.map { block in
            let text = block.lines.map(\.text).joined(separator: " ")
            return OCRGroup(text: text, box: block.box, lines: block.lines,
                            kind: classify(text: text, lines: block.lines,
                                           median: medianHeight))
        }
    }

    private static func joinRowFragments(_ lines: [OCRLine], median: CGFloat) -> [OCRLine] {
        var result: [OCRLine] = []
        for line in lines {
            guard let index = result.indices.reversed().first(where: {
                canJoinSameRow(result[$0], line, median: median)
            }) else {
                result.append(line)
                continue
            }
            let left = result[index].box.minX <= line.box.minX ? result[index] : line
            let right = result[index].box.minX <= line.box.minX ? line : result[index]
            result[index] = OCRLine(text: left.text + " " + right.text,
                                    box: left.box.union(right.box))
        }
        return result.sorted(by: readingOrder)
    }

    private static func canJoinSameRow(_ lhs: OCRLine, _ rhs: OCRLine,
                                       median: CGFloat) -> Bool {
        let a = lhs.box, b = rhs.box
        let overlapY = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        let heightRatio = max(a.height, b.height) / max(0.0001, min(a.height, b.height))
        let gapX = max(a.minX, b.minX) - min(a.maxX, b.maxX)
        return overlapY / max(0.0001, min(a.height, b.height)) >= 0.72 &&
            heightRatio <= 1.4 &&
            gapX >= 0 &&
            gapX <= min(0.010, median * 0.75) &&
            a.union(b).width <= 0.60
    }

    private static func canJoinVertically(_ next: OCRLine, to block: Working,
                                          median: CGFloat) -> Bool {
        let a = block.bottomLine.box, b = next.box
        let gap = a.minY - b.maxY
        let lineHeight = max(a.height, b.height, median)
        let heightRatio = max(a.height, b.height) / max(0.0001, min(a.height, b.height))
        guard gap >= -min(a.height, b.height) * 0.16,
              gap <= min(0.018, lineHeight * 1.1),
              heightRatio <= 1.7 else { return false }

        let overlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        let fraction = overlap / max(0.0001, min(a.width, b.width))
        let leftAligned = abs(a.minX - b.minX) <= max(0.016, median * 1.6)
        let centerAligned = abs(a.midX - b.midX) <= max(a.width, b.width) * 0.28
        guard fraction >= 0.30 && (leftAligned || centerAligned) else { return false }

        // Different panels or vertically separated caption boxes must not
        // become one giant "dialogue" entry.
        let combined = block.box.union(b)
        return combined.height <= 0.19 && combined.width <= 0.58
    }

    private static func classify(text: String, lines: [OCRLine],
                                 median: CGFloat) -> OCRBlockKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let hasLowercase = letters.contains { CharacterSet.lowercaseLetters.contains($0) }
        let sentencePunctuation = trimmed.contains { ".!?…,:;\"'".contains($0) }

        // Short, isolated all-caps labels/logos such as "ARGUS" or
        // "ARKHAM ASYLUM" are reviewable, not silently translated as dialogue.
        // A dated heading with a period ("THREE MONTHS AGO.") is retained.
        if lines.count == 1 && words.count <= 2 && !hasLowercase &&
            !sentencePunctuation && letters.count >= 3 && letters.count <= 18 {
            return .decorative
        }

        // Approximation only; real speech/caption polygon detection is future work.
        // Left-aligned compact multi-line prose is often a square narration box.
        if lines.count >= 3 {
            let first = lines[0].box.minX
            let leftAligned = lines.filter {
                abs($0.box.minX - first) <= max(0.012, median * 1.25)
            }.count
            if leftAligned >= max(2, lines.count - 1) {
                return .caption
            }
        }
        return .speech
    }

    private static func readingOrder(_ a: OCRLine, _ b: OCRLine) -> Bool {
        readingOrder(a.box, b.box)
    }

    private static func readingOrder(_ a: CGRect, _ b: CGRect) -> Bool {
        if abs(a.maxY - b.maxY) > 0.008 { return a.maxY > b.maxY }
        return a.minX < b.minX
    }
}
