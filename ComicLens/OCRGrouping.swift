import CoreGraphics
import Foundation

/// Vision-normalized coordinates, origin at the lower left.
struct OCRLine {
    let text: String
    let box: CGRect
}

struct OCRGroup {
    let text: String
    let box: CGRect
    let lineCount: Int
}

/// A conservative approximation of a comic dialogue block. It does not claim
/// to find actual speech-balloon contours; separate columns/panels stay apart.
enum OCRGrouping {
    private struct WorkingGroup {
        var lines: [OCRLine]
        var union: CGRect
        var last: CGRect
    }

    static func merge(_ input: [OCRLine]) -> [OCRGroup] {
        let ordered = input.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.box.width > 0 && $0.box.height > 0
        }.sorted(by: readingOrder)

        var groups: [WorkingGroup] = []
        for line in ordered {
            var choice: Int?
            var closest = CGFloat.greatestFiniteMagnitude
            for index in groups.indices {
                let group = groups[index]
                guard group.lines.count < 8,
                      canJoin(line.box, to: group.last, union: group.union) else { continue }
                // Prefer the closest vertically adjacent line in the same column.
                let distance = abs(group.last.minY - line.box.maxY)
                if distance < closest {
                    choice = index
                    closest = distance
                }
            }
            if let index = choice {
                groups[index].lines.append(line)
                groups[index].union = groups[index].union.union(line.box)
                groups[index].last = line.box
            } else {
                groups.append(WorkingGroup(lines: [line], union: line.box, last: line.box))
            }
        }

        return groups.sorted { readingOrder($0.union, $1.union) }.map { group in
            OCRGroup(text: group.lines.map(\.text).joined(separator: " "),
                     box: group.union, lineCount: group.lines.count)
        }
    }

    private static func canJoin(_ next: CGRect, to last: CGRect, union: CGRect) -> Bool {
        // Reject another bubble on the same horizontal reading row.
        let gap = last.minY - next.maxY
        let typicalHeight = max(last.height, next.height)
        guard gap >= -typicalHeight * 0.20,
              gap <= min(0.038, typicalHeight * 1.4) else { return false }

        let overlap = max(0, min(last.maxX, next.maxX) - max(last.minX, next.minX))
        let overlapFraction = overlap / max(0.0001, min(last.width, next.width))
        let aligned = abs(last.midX - next.midX) <= max(last.width, next.width) * 0.38
        guard overlapFraction >= 0.45 && aligned else { return false }

        // Avoid linking text from two visually separate panels into one block.
        let combined = union.union(next)
        return combined.height <= 0.20
    }

    private static func readingOrder(_ a: OCRLine, _ b: OCRLine) -> Bool {
        readingOrder(a.box, b.box)
    }

    private static func readingOrder(_ a: CGRect, _ b: CGRect) -> Bool {
        // A merged multiline block has a lower midpoint than a one-line bubble
        // in the same row. Compare their TOP edges instead so order is stable.
        if abs(a.maxY - b.maxY) > 0.012 {
            return a.maxY > b.maxY
        }
        return a.minX < b.minX
    }
}
