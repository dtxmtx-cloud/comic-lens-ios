# COMIC LENS — iOS native proof of concept

A SwiftUI / WKWebView reader that opens [Kindle for Web Japan](https://read.amazon.co.jp/landing), reads **only the currently visible pixels** via `WKWebView.takeSnapshot`, recognizes English with Apple Vision, translates with the on-device Apple Foundation Models framework, and overlays Japanese text with SwiftUI.

This is a proof of concept, **not** a Kindle API client or an official Amazon integration. There is no Kindle download, DRM removal, DOM scraping, image network interception, account-password collection, proxy, or remote AI API. Screenshots and translations remain in app memory (last 8 page fingerprints) and are not stored on disk. Web browsing itself contacts the selected site as usual.

## First run

1. Build with Xcode 26+ or use the GitHub Actions simulator artifact.
2. Open COMIC LENS and tap **デモ** to test the original, locally bundled two-panel comic. Tap NEXT PAGE inside the demo to exercise change detection.
3. On a supported Apple Intelligence device, enable Apple Intelligence and allow its language model to finish downloading. Without it, the app reports that the model is unavailable (simulator builds do not prove translation works).
4. Tap **Kindle** to open `https://read.amazon.co.jp/landing` in the embedded `WKWebView`. Log in on Amazon's site. Navigate to an English-language book that Kindle for Web permits you to read.
5. Toggle **自動** to sample the visible page every 2.5 seconds, or use **翻訳** for a one-time scan. **原文／訳文** shows or hides the Japanese layer.

For now, OCR produces text-line boxes, **not exact speech-bubble polygons**. White boxes may cover illustrations and font sizes may need refinement. Reading order is approximate; it does not identify speakers. Page changes are detected by a small fingerprint of the WebView's visible snapshot, not by Kindle-specific page APIs.

### Display modes (readability-first)

The default **読書** mode leaves the comic artwork and its original text intact. A small numbered marker next to each recognized text block opens a fixed-size Japanese **訳文カード**. The card has previous/next controls, shows the source text, and can be closed; **訳文一覧** displays the entire page in larger scrollable text. This mode avoids a page full of tiny white translation rectangles.

The **上書き** mode is still an *experimental OCR-box overlay*; it is not true speech-balloon segmentation. It only draws a patch when the translation fits at 10pt or larger. **原文** shows the unmodified Kindle page. These are app display modes, not modifications to Amazon's book or DRM. Current OCR may still mistake cover credits or sound effects for dialogue, and no automatic image inpainting is performed.


### Reading-list grouping and manual correction

The OCR grouping algorithm now stitches fragments from a single printed row,
joins tightly spaced rows inside a text block and avoids merging adjacent
balloons/boxes across columns. The order is based on the blocks' top edges.
Short standalone all-caps signage/logo candidates are kept separately instead
of consuming translation slots by default. The **装飾・看板候補も翻訳する** switch
in the translation sheet enables them when a real dialogue is misclassified.

The numbered reader markers and **訳文一覧** use the same complete ordered
block list, including any block that stayed in English because translation
failed. Each entry shows a provisional "セリフ候補" or "地の文候補" label.

For a page where OCR still splits or joins the wrong rows, open **訳文一覧**.
Use **↑ / ↓** to adjust reading order, **次と結合** to combine adjacent
entries, or **2分割** to split an entry along its stored OCR row boundary.
Merge and split retranslate the affected text. Manual corrections are kept in
the current page's in-memory cache; they are not stored in the book or uploaded.
They may need to be repeated after page layout changes or app restart.

This remains a heuristic OCR grouping system, not a reliable detector of
physical speech-balloon or caption outlines. The "上書き" mode is experimental;
"読書" is recommended for readable large Japanese translations.

## Kindle limitations and safety

* Kindle for Web may reject an embedded browser, individual books may be unavailable on the web, or protected content may return blank/unsuitable snapshots. None of these cases is worked around. Try the built-in demo first.
* The native translation layer is outside the web view, so it does not modify Amazon's page, login, DRM or scripts.
* No camera/screen recording permission is used. The app can snapshot only **its own WKWebView**, not the separate Kindle app or Safari.
* Automatic scanning is limited to the built-in demo and `read.amazon.co.jp` / `read.amazon.com`; other HTTPS pages can be scanned only by explicitly tapping 翻訳.
* Translation quality, Japanese model availability, scrolling stability and the real Kindle login/snapshot path require testing on a physical iPhone.
* Use only content you are authorized to read. Do not redistribute copyrighted images or translation overlays.

## Development

`project.yml` is the XcodeGen source of truth. No paid dependencies and no API keys.

```sh
brew install xcodegen
cd comic-lens-ios
xcodegen generate
xcodebuild -project ComicLens.xcodeproj -scheme ComicLens \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The repository has two GitHub Actions workflows:

- `.github/workflows/ios.yml`: uploads the iOS **Simulator** app ZIP.
- `.github/workflows/ipa.yml`: compiles an **arm64 iPhone device build**, packages `Payload/ComicLens.app` into `ComicLens-unsigned.ipa`, validates it, and publishes the **raw `.ipa` as a GitHub Release asset**, without an extra ZIP download. Open [Releases](https://github.com/dtxmtx-cloud/comic-lens-ios/releases) → the latest `Comic Lens CI` prerelease → `ComicLens-unsigned.ipa`. The IPA itself contains the required internal ZIP structure, but the downloaded filename remains `.ipa`. **UNSIGNED: it cannot be installed on a normal iPhone.** Releases are created for push/manual builds, not pull requests.

### Optional signed IPA for registered iPhones

The same IPA workflow has a separate signing job. It is skipped until you provide your own Apple signing assets. Set this **Actions repository variable** in GitHub Settings → Secrets and variables → Actions → Variables:

| Variable | Value |
| --- | --- |
| `IOS_TEAM_ID` | Your 10-character Apple Developer Team ID |

Then configure these **Actions repository secrets** in Settings → Secrets and variables → Actions → Secrets:

| Secret | Value |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 of an **Apple Distribution** certificate exported with its private key as `.p12` |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Password for that `.p12` |
| `IOS_ADHOC_PROFILE_BASE64` | Base64 of the **Ad Hoc** `.mobileprovision` profile for the app ID `cloud.dtxmtx.comiclens` |

The Ad Hoc profile must include your iPhone's registered **UDID**, must match the certificate and Team ID, and must be valid/not expired. Generate it in your Apple Developer account. Never commit signing files, passwords, Apple IDs, or device UDIDs to the public repository or send them in chat.

To obtain base64 on macOS: `base64 -i distribution.p12 | tr -d '\n'`, and similarly for the `.mobileprovision` file. Keep the original private files in a secure location. The workflow imports them into a temporary CI keychain, archives with Xcode, exports using the Xcode `release-testing` (Ad Hoc) method, verifies the signature, and publishes `ComicLens-signed-AdHoc.ipa` directly to the **same GitHub Release**. The signed job runs only for non-PR events when `IOS_TEAM_ID` is set, after the unsigned IPA job completes. If any required secret is missing it fails explicitly with the missing **name**, not its value. It does not upload signing keys.

Apple documentation: [Distribute to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices) and [Create an Ad Hoc profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile). A signed Ad Hoc build can only run on iPhones listed in the profile; it is not the same as App Store/TestFlight distribution.

## Core implementation

| File | Responsibility |
| --- | --- |
| `ComicLensApp.swift` | SwiftUI app entry |
| `ReaderView.swift` | Reader controls, original/translation toggle, noninteractive native overlay |
| `ReaderModel.swift` | Persistent WKWebView, snapshots, page fingerprint, Vision OCR and short-lived memory cache |
| `OnDeviceTranslator.swift` | Foundation Models availability check, numbered per-page Japanese translation with fallback |
| `DemoPage.swift` | Original text-only comic fixture for testing without Kindle |

Requirements: iOS 26.4+, a device with Apple Intelligence enabled for generative translation. The app also supports Apple’s dedicated low-latency Translation framework after the English/Japanese language pack has been installed. iOS simulator compilation is independent of AI runtime availability.

Apple references: [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [WKWebView snapshots](https://developer.apple.com/documentation/webkit/wkwebview/takesnapshot%28with%3Acompletionhandler%3A%29), [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).

## Translation and overlay behavior

* Comic dialogue is processed independently. If the generative language model declines one block, its original English remains visible instead of discarding all other translations.
* When English/Japanese low-latency language resources are installed, the native Translation framework may translate blocks that the generative engine did not complete. Use **言語準備** in the app to authorize/download the language resources. This is a separate, on-device system translation service, not a change to Foundation Models guardrails. The diagnostics report AI translations, dedicated translator translations, and blocks left in English.
* Translation text is measured before display and clipped inside an actual UIView container. If a whole translation cannot fit legibly in its recognized text block, the patch is omitted rather than covering artwork; read it through **訳文一覧**. The full-text sheet also lists blocks that remain in English.
* Text blocks are not exact speech-balloon contours. Cover typography and credits may still be recognized as text; page-specific OCR and bubble segmentation require further work.
