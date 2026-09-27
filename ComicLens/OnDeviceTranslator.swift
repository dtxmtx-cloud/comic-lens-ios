import CoreGraphics
import Foundation
import FoundationModels
import Translation

struct OCRSegment: Sendable {
    let index: Int
    let source: String
    /// Vision coordinates: normalized, origin at bottom-left.
    let box: CGRect
    let kind: OCRBlockKind
    let lines: [OCRLine]

    init(index: Int, source: String, box: CGRect, kind: OCRBlockKind = .speech,
         lines: [OCRLine] = []) {
        self.index = index
        self.source = source
        self.box = box
        self.kind = kind
        self.lines = lines
    }
}

/// The complete ordered reading list, including a segment whose translation
/// could not be produced. Its number is always the reader marker number.
struct TranslationEntry: Identifiable {
    let id: Int
    let source: String
    let japanese: String?
    let box: CGRect
    let kind: OCRBlockKind
    let lines: [OCRLine]
}

struct TranslationOverlay: Identifiable {
    let id: Int
    let source: String
    let japanese: String
    let box: CGRect
    let kind: OCRBlockKind
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

struct PageTranslationResult {
    /// Nil preserves the visible original when both local engines cannot translate.
    let texts: [String?]
    let aiCount: Int
    let systemCount: Int
    let originalCount: Int
    let languagePackNeeded: Bool
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

    /// Best-effort transformation of individual, user-visible dialogue blocks.
    /// Apple Intelligence errors must never discard translations from other blocks.
    /// The dedicated system Translation framework is a separate translation engine,
    /// not a modification to Foundation Models guardrail settings.
    func translatePage(_ segments: [OCRSegment]) async -> PageTranslationResult {
        guard !segments.isEmpty else {
            return PageTranslationResult(texts: [], aiCount: 0, systemCount: 0,
                                         originalCount: 0, languagePackNeeded: false)
        }

        let en = Locale.Language(identifier: "en")
        let ja = Locale.Language(identifier: "ja")
        let languageStatus = await LanguageAvailability(preferredStrategy: .lowLatency)
            .status(from: en, to: ja)
        let systemSession: TranslationSession?
        switch languageStatus {
        case .installed:
            systemSession = TranslationSession(installedSource: en, target: ja,
                                               preferredStrategy: .lowLatency)
        case .supported, .unsupported:
            systemSession = nil
        @unknown default:
            systemSession = nil
        }

        var results = [String?](repeating: nil, count: segments.count)
        var aiCount = 0
        var systemCount = 0

        // Sending a whole comic page into a single generative prompt previously
        // caused one rejected segment to blank the entire page.
        for (position, segment) in segments.enumerated() {
            if Task.isCancelled { break }
            if case .available = SystemLanguageModel.default.availability {
                do {
                    let session = LanguageModelSession(instructions: """
                        The user's locale is ja_JP. Translate the provided English
                        comic dialogue into natural Japanese. Preserve its original
                        meaning and names. Do not invent text or add explanations.
                        Return only the Japanese translation.
                        """)
                    let response = try await session.respond(to: segment.source)
                    let value = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        results[position] = value
                        aiCount += 1
                        continue
                    }
                } catch {
                    // Report partial completion and preserve the original if the
                    // next, dedicated translation engine is unavailable too.
                }
            }
            if let systemSession {
                do {
                    let response = try await systemSession.translate(segment.source)
                    let value = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        results[position] = value
                        systemCount += 1
                    }
                } catch {
                    // Keep the visible original. Never invent a translated sentence.
                }
            }
        }
        let originalCount = results.filter { $0 == nil }.count
        return PageTranslationResult(texts: results, aiCount: aiCount,
                                     systemCount: systemCount, originalCount: originalCount,
                                     languagePackNeeded: languageStatus == .supported)
    }
}
