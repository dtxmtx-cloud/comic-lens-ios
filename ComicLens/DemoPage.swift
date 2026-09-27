import Foundation

enum DemoPage {
    /// Original sample text only. No copyrighted comic image or login data is included.
    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
      <style>
        *{box-sizing:border-box}body{margin:0;background:#172139;color:#fff;font-family:-apple-system,sans-serif}
        header{padding:14px;background:#111827;display:flex;align-items:center;justify-content:space-between}
        button{border:0;background:#f9d35d;color:#182338;padding:10px 15px;border-radius:18px;font-weight:700}
        main{padding:18px 14px;min-height:90vh;background:linear-gradient(145deg,#5c2c71,#162c57 62%,#13233e)}
        .panel{background:linear-gradient(145deg,#e76d5b,#efb95b);border:5px solid #111827;border-radius:9px;min-height:250px;margin-bottom:16px;position:relative;padding:19px}
        .panel:nth-child(2){background:linear-gradient(110deg,#2c7581,#233a75)}
        .bubble{background:white;color:#152133;border:3px solid #152133;border-radius:40% 44% 40% 35%;padding:19px 14px;max-width:86%;font-size:20px;font-weight:750;line-height:1.25;box-shadow:0 4px 0 #101928}
        .bubble.two{margin:65px 0 0 auto;font-size:17px;max-width:76%}
        .shape{position:absolute;bottom:16px;left:20px;font-size:65px;color:#182338;opacity:.7}
        small{opacity:.7}
      </style>
    </head>
    <body>
      <header><strong>COMIC LENS / DEMO</strong><button onclick="nextPage()">NEXT PAGE →</button></header>
      <main id="page">
        <section class="panel"><div class="bubble">We need to get out of here before sunrise!</div><div class="shape">★</div></section>
        <section class="panel"><div class="bubble two">There's still time. Trust me!</div><div class="shape">◆</div></section>
        <small>Demo artwork and text are original. Tap NEXT PAGE to test automatic detection.</small>
      </main>
      <script>
        let page = 0;
        const pages = [
          ["We need to get out of here before sunrise!", "There's still time. Trust me!"],
          ["Did you hear that? Something is moving behind us.", "Don't look back. Keep running!"],
          ["We made it. The city is safe for now.", "Tomorrow, we start again."]
        ];
        function nextPage() {
          page = (page + 1) % pages.length;
          document.querySelectorAll('.bubble').forEach((el,i)=>el.textContent=pages[page][i]);
        }
      </script>
    </body></html>
    """#

    /// Only these original sample lines have a deterministic translation fallback.
    /// Never apply this fixture translation to Kindle or to user-provided books.
    static func translation(for english: String) -> String? {
        let examples: [String: String] = [
            "We need to get out of here before sunrise!": "日の出前にここから脱出しないと！",
            "There's still time. Trust me!": "まだ間に合う。僕を信じて！",
            "Did you hear that? Something is moving behind us.": "今の聞こえた？ 後ろで何かが動いている。",
            "Don't look back. Keep running!": "振り返らないで。走り続けて！",
            "We made it. The city is safe for now.": "やったぞ。これで街はひとまず安全だ。",
            "Tomorrow, we start again.": "明日、また始めよう。"
        ]
        return examples[english.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}
