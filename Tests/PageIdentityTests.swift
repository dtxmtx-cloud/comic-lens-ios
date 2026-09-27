import CoreGraphics
import Foundation

@main
struct PageIdentityTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description)
            checks += 1
        }

        let dialogue = ["We need to get out of here before sunrise!", "There's still time. Trust me!"]
        let same = ["  WE need to get out of here before sunrise!  ", "There's   still time. Trust me!"]
        let nextPage = ["Did you hear that? Something is moving behind us.", "Don't look back. Keep running!"]
        check(PageIdentity.matches(dialogue, same), "Stable text should survive pixel changes")
        check(!PageIdentity.matches(dialogue, nextPage), "Next page must invalidate cache")
        check(!PageIdentity.matches(dialogue, []), "Empty page is different")
        check(!PageIdentity.matches(dialogue, [dialogue[0]]), "Partial page is different")
        check(PageIdentity.cacheKey(scope: "demo", lines: dialogue) !=
              PageIdentity.cacheKey(scope: "kindle", lines: dialogue), "Do not mix book scopes")

        let lines: [OCRLine] = [
            OCRLine(text: "FIRST LINE", box: CGRect(x: 0.10, y: 0.89, width: 0.20, height: 0.025)),
            OCRLine(text: "RIGHT BUBBLE", box: CGRect(x: 0.65, y: 0.89, width: 0.22, height: 0.025)),
            OCRLine(text: "SECOND LINE", box: CGRect(x: 0.11, y: 0.85, width: 0.20, height: 0.025)),
            OCRLine(text: "LOWER PANEL", box: CGRect(x: 0.12, y: 0.37, width: 0.20, height: 0.025))
        ]
        let grouped = OCRGrouping.merge(lines)
        check(grouped.count == 3, "Join one balloon, not adjacent balloons")
        check(grouped[0].text == "FIRST LINE SECOND LINE", "Join stacked lines in reading order")
        check(grouped[0].lineCount == 2, "Retain lines in each group")
        check(grouped[1].text == "RIGHT BUBBLE", "Keep the right balloon separate")
        check(grouped[2].text == "LOWER PANEL", "Keep the lower panel separate")

        // Synthetic version of the user's screenshot: a large first caption,
        // separate boxes near one another, a side balloon and a decorative logo.
        let page = [
            OCRLine(text: "THREE MONTHS AGO.", box: CGRect(x: 0.08, y: 0.91, width: 0.24, height: 0.017)),
            OCRLine(text: "ARKHAM ASYLUM", box: CGRect(x: 0.17, y: 0.83, width: 0.19, height: 0.013)),
            OCRLine(text: "WAS REBUILT OF", box: CGRect(x: 0.17, y: 0.812, width: 0.20, height: 0.013)),
            OCRLine(text: "COURSE.", box: CGRect(x: 0.17, y: 0.794, width: 0.17, height: 0.013)),
            OCRLine(text: "THE GOVERNMENT STEPPED", box: CGRect(x: 0.32, y: 0.73, width: 0.24, height: 0.013)),
            OCRLine(text: "IN AND USING YOUR TAX", box: CGRect(x: 0.32, y: 0.712, width: 0.23, height: 0.013)),
            OCRLine(text: "DOLLARS, A.R.G.U.S.", box: CGRect(x: 0.32, y: 0.694, width: 0.23, height: 0.013)),
            OCRLine(text: "OF HOMELAND SECURITY", box: CGRect(x: 0.32, y: 0.676, width: 0.24, height: 0.013)),
            OCRLine(text: "OVERSAW RENOVATIONS.", box: CGRect(x: 0.32, y: 0.658, width: 0.23, height: 0.013)),
            OCRLine(text: "KEEP RUNNING!", box: CGRect(x: 0.68, y: 0.73, width: 0.15, height: 0.013)),
            OCRLine(text: "THE CITY", box: CGRect(x: 0.16, y: 0.50, width: 0.08, height: 0.013)),
            OCRLine(text: "IS SAFE.", box: CGRect(x: 0.245, y: 0.50, width: 0.10, height: 0.013)),
            OCRLine(text: "NO WAY!", box: CGRect(x: 0.39, y: 0.50, width: 0.13, height: 0.013)),
            OCRLine(text: "ARGUS", box: CGRect(x: 0.33, y: 0.19, width: 0.18, height: 0.035))
        ]
        let result = OCRGrouping.merge(page)
        let resultText = result.map(\.text)
        check(result.count == 7, "Retain seven independent text blocks, got \(resultText)")
        check(resultText[0] == "THREE MONTHS AGO.", "Do not merge a dated caption with the following box")
        check(resultText[1] == "ARKHAM ASYLUM WAS REBUILT OF COURSE.", "Join one three-line narration box")
        check(resultText[2].contains("OVERSAW RENOVATIONS."), "Keep long five-line narration together")
        check(resultText[3] == "KEEP RUNNING!", "Do not merge a right-hand balloon into a caption")
        check(resultText[4] == "THE CITY IS SAFE.", "Stitch a single printed row")
        check(resultText[5] == "NO WAY!", "Keep separate same-row balloon")
        check(result[6].kind == .decorative, "Classify isolated logo separately")
        check(result.reduce(0) { $0 + $1.lineCount } == page.count - 1,
              "Only the two row fragments became one OCR line")
        check(result.filter { $0.kind != .decorative }.count == 6,
              "Leave all prose available, separate only decorative candidates")

        let many = (0..<32).map {
            OCRLine(text: "LINE \($0)", box: CGRect(x: 0.1, y: 0.98 - CGFloat($0) * 0.027,
                                                     width: 0.15, height: 0.012))
        }
        let all = OCRGrouping.merge(many)
        check(all.reduce(0) { $0 + $1.lineCount } == 32, "Never silently drop OCR lines")
        check(OCRGrouping.merge([]).isEmpty, "Empty snapshot returns zero groups")
        print("Page identity and OCR grouping: PASS (\(checks) checks)")
    }
}
