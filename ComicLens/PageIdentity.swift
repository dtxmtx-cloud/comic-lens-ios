import Foundation

/// Compares the visible English rather than volatile screenshot bytes.
/// No Kindle-specific DOM access, image extraction, or persistent book storage.
enum PageIdentity {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func matches(_ original: [String], _ current: [String]) -> Bool {
        guard !original.isEmpty, original.count == current.count else { return false }
        return zip(original, current).allSatisfy {
            normalize($0.0) == normalize($0.1)
        }
    }

    static func cacheKey(scope: String, lines: [String]) -> String {
        scope + "\u{001E}" + lines.map(normalize).joined(separator: "\u{001F}")
    }
}
