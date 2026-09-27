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
        print("PageIdentity regression tests: PASS (5 checks)")
    }
}
