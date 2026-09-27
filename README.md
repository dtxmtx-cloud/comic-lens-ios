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

`.github/workflows/ios.yml` runs on GitHub-hosted macOS 26 with its stable Xcode 26.x and uploads a `ComicLens.app` simulator ZIP. This **is not an installable iPhone IPA**. A signed device archive/TestFlight release requires your Apple Developer team, signing certificate, provisioning profile and appropriate private CI secrets; none are committed here.

## Core implementation

| File | Responsibility |
| --- | --- |
| `ComicLensApp.swift` | SwiftUI app entry |
| `ReaderView.swift` | Reader controls, original/translation toggle, noninteractive native overlay |
| `ReaderModel.swift` | Persistent WKWebView, snapshots, page fingerprint, Vision OCR and short-lived memory cache |
| `OnDeviceTranslator.swift` | Foundation Models availability check, numbered per-page Japanese translation with fallback |
| `DemoPage.swift` | Original text-only comic fixture for testing without Kindle |

Requirements: iOS 26+, a device with Apple Intelligence enabled for actual AI translation. iOS simulator compilation is independent of AI runtime availability.

Apple references: [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [WKWebView snapshots](https://developer.apple.com/documentation/webkit/wkwebview/takesnapshot%28with%3Acompletionhandler%3A%29), [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).