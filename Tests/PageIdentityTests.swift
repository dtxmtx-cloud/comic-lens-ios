import Foundation

@main
struct PageIdentityTests {
    static func main() {
        let dialogue = ["We need to get out of here before sunrise!", "There's still time. Trust me!"]
        let same = ["  WE need to get out of here before sunrise!  ", "There's   still time. Trust me!"]
        let nextPage = ["Did you hear that? Something is moving behind us.", "Don't look back. Keep running!"]

        precondition(PageIdentity.matches(dialogue, same),
                     "Stable dialogue must survive screenshot changes.")
        precondition(!PageIdentity.matches(dialogue, nextPage),
                     "Actual next-page dialogue must invalidate the old translation.")
        precondition(!PageIdentity.matches(dialogue, []))
        precondition(!PageIdentity.matches(dialogue, [dialogue[0]]))
        precondition(PageIdentity.cacheKey(scope: "demo", lines: dialogue) !=
                     PageIdentity.cacheKey(scope: "kindle", lines: dialogue))
        // Two OCR rows inside one balloon should get one translation block.
        let lines: [OCRLine] = [
            OCRLine(text: "FIRST LINE", box: CGRect(x: 0.10, y: 0.89, width: 0.20, height: 0.025)),
            OCRLine(text: "RIGHT BUBBLE", box: CGRect(x: 0.65, y: 0.89, width: 0.22, height: 0.025)),
            OCRLine(text: "SECOND LINE", box: CGRect(x: 0.11, y: 0.85, width: 0.20, height: 0.025)),
            OCRLine(text: "LOWER PANEL", box: CGRect(x: 0.12, y: 0.37, width: 0.20, height: 0.025))
        ]
        let grouped = OCRGrouping.merge(lines)
        precondition(grouped.count == 3, "Join one balloon; keep nearby separate balloons/panels.")
        precondition(grouped[0].text == "FIRST LINE SECOND LINE")
        precondition(grouped[0].lineCount == 2)
        precondition(grouped[1].text == "RIGHT BUBBLE")
        precondition(grouped[2].text == "LOWER PANEL")

        // The previous prefix(16) discarded lower-page dialogue.
        let moreThanSixteen = (0..<32).map {
            OCRLine(text: "LINE \($0)", box: CGRect(x: 0.1, y: 0.98 - CGFloat($0) * 0.027,
                                                     width: 0.15, height: 0.012))
        }
        let all = OCRGrouping.merge(moreThanSixteen)
        precondition(all.reduce(0) { $0 + $1.lineCount } == 32, "No OCR lines may be silently lost.")
        print("Page identity and OCR grouping regression tests: PASS (10 checks)")
    }
}
