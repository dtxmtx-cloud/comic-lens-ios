import CoreGraphics
import Foundation
import FoundationModels

struct OCRSegment: Sendable {
    let index: Int
    let source: String
    /// Vision coordinates: normalized, origin at bottom-left.
    let box: CGRect
}

struct TranslationOverlay: Identifiable {
    let id: Int
    let source: String
    let japanese: String
    let box: CGRect
}

enum TranslationIssue: LocalizedError {
    case modelUnavailable
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Apple Intelligenceが利用できません。対応端末で設定を有効にし、モデルの準備完了後に再試行してください。"
        case .malformedResponse:
            return "翻訳結果の形式を読み取れませんでした。もう一度お試しください。"
        }
    }
}

enum TranslationLineParser {
    /// The model is asked for [[0]] 日本語 ... [[N]] 日本語; reject incomplete batches.
    static func parse(_ text: String, expected: Int) -> [String]? {
        let pattern = #"^\[\[(\d+)\]\]\s*(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        let value = text as NSString
        var result: [Int: String] = [:]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: value.length)) {
            guard match.numberOfRanges == 3,
                  let index = Int(value.substring(with: match.range(at: 1))),
                  index >= 0, index < expected,
                  result[index] == nil else { continue }
            let translated = value.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !translated.isEmpty { result[index] = translated }
        }
        guard result.count == expected else { return nil }
        return (0..<expected).compactMap { result[$0] }
    }
}

@MainActor
final class OnDeviceTranslator {
    func translate(_ segments: [OCRSegment]) async throws -> [String] {
        guard !segments.isEmpty else { return [] }

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable:
            throw TranslationIssue.modelUnavailable
        }

        let instructions = """
        The person's locale is ja_JP.
        Translate English comic-book dialogue into natural Japanese.
        Preserve names, continuity, speaker tone and meaning.
        The input is text from a visual OCR process. Correct only obvious OCR artifacts.
        Do not add narration or explanations. Never invent dialogue.
        You MUST respond in Japanese.
        Return exactly one line per numbered input, using this format:
        [[0]] 日本語
        [[1]] 日本語
        """

        // Process all dialogue groups without sending a long, easy-to-truncate
        // full-page response through the small on-device model at once.
        var result: [String] = []
        for start in stride(from: 0, to: segments.count, by: 5) {
            try Task.checkCancellation()
            let chunk = Array(segments[start..<min(start + 5, segments.count)])
            let lines = chunk.enumerated().map { offset, segment in
                "[[\(offset)]] \(segment.source.replacingOccurrences(of: "\n", with: " "))"
            }.joined(separator: "\n")
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: "Translate each numbered line.\n\(lines)")
            if let parsed = TranslationLineParser.parse(response.content, expected: chunk.count) {
                result.append(contentsOf: parsed)
                continue
            }

            // Fall back only for this chunk. Never silently drop a dialogue group
            // when the model returns a malformed numbered response.
            for segment in chunk {
                try Task.checkCancellation()
                let single = LanguageModelSession(instructions:
                    "The person's locale is ja_JP. Translate this English comic dialogue to natural Japanese. " +
                    "Return ONLY the Japanese translation. Do not add explanations.")
                let answer = try await single.respond(to: segment.source)
                let translation = answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translation.isEmpty else { throw TranslationIssue.malformedResponse }
                result.append(translation)
            }
        }
        return result
    }
}