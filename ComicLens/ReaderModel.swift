import Combine
import Foundation
import FoundationModels
import SwiftUI
import UIKit
import Vision
import WebKit

@MainActor
final class ReaderModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let kindleURL = "https://read.amazon.co.jp/landing"

    @Published private(set) var webView: WKWebView
    @Published private(set) var tabDepth = 0
    @Published var diagnostics = "画面: 未取得 / OCR: 未実行 / AI: 未確認"
    private let translator = OnDeviceTranslator()
    private var modelReadiness: String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale(identifier: "ja_JP"))
                ? "利用可能（日本語対応）" : "利用可能だが日本語未対応"
        case .unavailable(let reason):
            return "利用不可: \(String(describing: reason))"
        }
    }
    private var previousTabs: [(view: WKWebView, isDemo: Bool)] = []

    @Published var overlays: [TranslationOverlay] = []
    @Published var untranslated: [String] = []
    @Published var translationDetails = ""
    @Published var translationRevision = 0
    @Published var isWorking = false
    @Published var status = "Kindleを開いています"
    @Published var currentAddress = kindleURL
    @Published var showOriginal = false
    @Published var autoTranslate = true {
        didSet {
            if autoTranslate { requestTranslation() }
            else { status = "自動翻訳を停止しました。手動翻訳は利用できます。" }
        }
    }

    private var timer: Timer?
    private var generation = 0
    private var lastFingerprint: UInt64?
    private struct CachedPage {
        let overlays: [TranslationOverlay]
        let untranslated: [String]
        let details: String
    }
    private var cached: [UInt64: CachedPage] = [:]
    private var cacheOrder: [UInt64] = []
    private var textCache: [String: [String?]] = [:]
    private var textCacheOrder: [String] = []
    private var demoMode = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configure(webView)
        openHome()
    }

    private func configure(_ view: WKWebView) {
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
    }

    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoTranslate else { return }
                await self.scan(force: false)
            }
        }
        requestTranslation()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func openHome() { open(Self.kindleURL) }

    func open(_ rawAddress: String) {
        let candidate = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = candidate.contains("://") ? candidate : "https://" + candidate
        guard let url = URL(string: normalized), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else {
            status = "HTTPSのURLを入力してください。"
            return
        }
        demoMode = false
        resetForPageChange()
        currentAddress = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func openDemo() {
        demoMode = true
        resetForPageChange()
        currentAddress = "COMIC LENS / DEMO"
        webView.loadHTMLString(DemoPage.html, baseURL: URL(string: "https://comic-lens.invalid/"))
    }

    func back() {
        if webView.canGoBack { webView.goBack() }
        else if tabDepth > 0 { closeCurrentTab() }
    }

    func closeCurrentTab() {
        guard let previous = previousTabs.popLast() else { return }
        webView.stopLoading()
        webView = previous.view
        demoMode = previous.isDemo
        tabDepth = previousTabs.count
        resetForPageChange()
        currentAddress = demoMode ? "COMIC LENS / DEMO" : (webView.url?.absoluteString ?? Self.kindleURL)
        status = "前のタブに戻りました。"
        if autoTranslate { requestTranslation() }
    }

    func forward() {
        if webView.canGoForward { webView.goForward() }
    }

    func reload() {
        webView.reload()
    }

    func requestTranslation() {
        Task { @MainActor [weak self] in
            await self?.scan(force: true)
        }
    }

    private var isAutoTranslationPage: Bool {
        if demoMode { return true }
        guard let host = webView.url?.host?.lowercased() else { return false }
        // Do not automatically scan Amazon sign-in pages or unrelated websites.
        return host == "read.amazon.co.jp" || host == "read.amazon.com"
    }

    private func resetForPageChange() {
        generation += 1
        overlays = []
        untranslated = []
        translationDetails = ""
        translationRevision += 1
        lastFingerprint = nil
        diagnostics = "画面: 未取得 / OCR: 未実行 / AI: \(modelReadiness)"
    }

    private func snapshot() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, error in
                if let error { continuation.resume(throwing: error) }
                else if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: SnapshotIssue.empty) }
            }
        }
    }

    private enum SnapshotIssue: LocalizedError {
        case empty
        var errorDescription: String? { "ブラウザー画面を取得できませんでした。" }
    }

    private func scan(force: Bool) async {
        guard !isWorking else { return }
        guard !webView.isLoading, webView.bounds.width > 0 else {
            if force { status = "ブラウザーの表示完了後に翻訳してください。" }
            return
        }
        guard force || (autoTranslate && isAutoTranslationPage) else { return }
        isWorking = true
        defer { isWorking = false }
        let currentGeneration = generation

        do {
            let image = try await snapshot()
            guard let fingerprint = Self.fingerprint(image) else {
                status = "画面画像を取得できませんでした。"
                return
            }
            if !force && lastFingerprint == fingerprint { return }
            diagnostics = "画面: 取得成功 / OCR: 処理前 / AI: \(modelReadiness)"

            if let found = cached[fingerprint] {
                lastFingerprint = fingerprint
                overlays = found.overlays
                untranslated = found.untranslated
                translationDetails = found.details
                translationRevision += 1
                status = "翻訳を再表示しました（メモリ内キャッシュ）"
                return
            }

            overlays = []
            status = "画面内の英語を認識しています…"
            guard let cgImage = image.cgImage else {
                status = "画像の解析に対応していません。"
                return
            }

            let vision: (segments: [OCRSegment], lineCount: Int)
            if demoMode {
                // The fixture remains testable even if Vision reports an OCR error.
                vision = (try? await Self.recognize(cgImage)) ?? (segments: [], lineCount: 0)
            } else {
                vision = try await Self.recognize(cgImage)
            }
            guard currentGeneration == generation else { return }

            // Only the bundled demo uses DOM coordinates. Kindle/external websites
            // are recognized from displayed pixels only; their DOM is never inspected.
            let demoSegments = demoMode ? (try? await demoBubbleSegments()) ?? [] : []
            let segments = demoSegments.isEmpty ? vision.segments : demoSegments
            diagnostics = "画面: 取得成功 / OCR: \(vision.lineCount)行 → " +
                "\(vision.segments.count)ブロック / " +
                (demoMode ? "デモの吹き出し: \(demoSegments.count)件 / " : "") +
                "AI: \(modelReadiness)"
            guard !segments.isEmpty else {
                status = "英語を検出できません。画面取得と作品の表示状態を確認してください。"
                lastFingerprint = fingerprint
                return
            }

            status = "\(segments.count)か所を翻訳しています…"
            let scope = demoMode ? "bundled-demo" : (webView.url?.absoluteString ?? "")
            let textKey = PageIdentity.cacheKey(scope: scope, lines: segments.map(\.source))
            let translations: [String?]
            if segments.count >= 2, let saved = textCache[textKey],
               saved.count == segments.count {
                translations = saved
                diagnostics += " / 翻訳方式: 本文キャッシュ"
            } else if demoMode, !demoSegments.isEmpty {
                do {
                    translations = try await translator.translate(segments).map(Optional.some)
                    diagnostics += " / 翻訳方式: Apple Intelligence"
                } catch {
                    // Fixed translations are only for the bundled original demo.
                    translations = segments.map { DemoPage.translation(for: $0.source) }
                    diagnostics += " / 翻訳方式: デモ固定訳（AI未使用） / AIの問題: \(error.localizedDescription)"
                }
            } else {
                let page = await translator.translatePage(segments)
                translations = page.texts
                diagnostics += " / AI: \(page.aiCount)件 / 翻訳専用モデル: \(page.systemCount)件 / 原文維持: \(page.originalCount)件"
                if page.languagePackNeeded {
                    diagnostics += " / 言語パック未導入（言語準備ボタン）"
                }
            }
            guard currentGeneration == generation, segments.count == translations.count else { return }

            // Screenshot pixels can change from lazy rendering, a blinking cursor, etc.
            // Revalidate *visible dialogue* after inference, not the entire pixel hash.
            let latest = try await snapshot()
            guard currentGeneration == generation,
                  let latestFingerprint = Self.fingerprint(latest) else { return }
            let latestSegments: [OCRSegment]
            if demoMode, !demoSegments.isEmpty {
                latestSegments = try await demoBubbleSegments()
            } else if latestFingerprint == fingerprint {
                // Unchanged image means the recognized text/positions are unchanged.
                latestSegments = segments
            } else {
                guard let latestImage = latest.cgImage else { throw SnapshotIssue.empty }
                latestSegments = try await Self.recognize(latestImage).segments
            }
            guard currentGeneration == generation else { return }
            guard PageIdentity.matches(segments.map(\.source),
                                       latestSegments.map(\.source)) else {
                overlays = []
                lastFingerprint = nil
                diagnostics += " / 再検証: 本文変更（翻訳を破棄）"
                status = "本文の変更を検出しました。現在のページを再翻訳してください。"
                return
            }
            diagnostics += " / 再検証: 英文一致"
            if latestFingerprint != fingerprint {
                diagnostics += "（画像差分は許容）"
            }

            // Use the latest visible text rectangles so scrolling/layout changes
            // do not leave the overlay at the original screen coordinates.
            let result = zip(latestSegments, translations).compactMap { pair -> TranslationOverlay? in
                guard let japanese = pair.1, !japanese.isEmpty else { return nil }
                return TranslationOverlay(id: pair.0.index, source: pair.0.source,
                                          japanese: japanese, box: pair.0.box)
            }
            untranslated = zip(latestSegments, translations).compactMap { pair in
                pair.1 == nil ? pair.0.source : nil
            }
            translationDetails = result.map {
                "\($0.id + 1). \($0.japanese)\n原文: \($0.source)"
            }.joined(separator: "\n\n")
            overlays = result
            translationRevision += 1
            lastFingerprint = latestFingerprint
            cached[latestFingerprint] = CachedPage(
                overlays: result, untranslated: untranslated, details: translationDetails
            )
            cacheOrder.append(latestFingerprint)
            if cacheOrder.count > 8 {
                let oldest = cacheOrder.removeFirst()
                cached.removeValue(forKey: oldest)
            }
            if segments.count >= 2, textCache[textKey] == nil {
                textCache[textKey] = translations
                textCacheOrder.append(textKey)
                if textCacheOrder.count > 8 {
                    let oldest = textCacheOrder.removeFirst()
                    textCache.removeValue(forKey: oldest)
                }
            }
            status = "\(result.count)か所を翻訳しました。原文維持: \(untranslated.count)件。長文は訳文一覧で確認できます。"
        } catch {
            guard currentGeneration == generation else { return }
            diagnostics += " / エラー: \(error.localizedDescription)"
            status = "翻訳エラー：\(error.localizedDescription)"
            lastFingerprint = nil
        }
    }

    private func demoBubbleSegments() async throws -> [OCRSegment] {
        let script = """
        (() => ({ width: innerWidth, height: innerHeight,
          bubbles: [...document.querySelectorAll('.bubble')].map(el => {
            const r = el.getBoundingClientRect();
            return { text: el.textContent.trim(), x: r.left, y: r.top,
                     width: r.width, height: r.height };
          })
        }))()
        """
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any],
              let width = (result["width"] as? NSNumber)?.doubleValue,
              let height = (result["height"] as? NSNumber)?.doubleValue,
              width > 0, height > 0,
              let bubbles = result["bubbles"] as? [[String: Any]] else { return [] }
        return bubbles.enumerated().compactMap { index, bubble in
            guard let text = bubble["text"] as? String,
                  let x = (bubble["x"] as? NSNumber)?.doubleValue,
                  let y = (bubble["y"] as? NSNumber)?.doubleValue,
                  let w = (bubble["width"] as? NSNumber)?.doubleValue,
                  let h = (bubble["height"] as? NSNumber)?.doubleValue,
                  w > 0, h > 0 else { return nil }
            let rect = CGRect(x: x / width, y: 1 - (y + h) / height,
                              width: w / width, height: h / height)
            return OCRSegment(index: index, source: text, box: rect)
        }
    }

    /// A small quantized color fingerprint, used only to notice visible page changes.
    /// Images and recognized text are not written to disk or uploaded.
    private static func fingerprint(_ image: UIImage) -> UInt64? {
        guard let source = image.cgImage else { return nil }
        let width = 32, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress,
                                          width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var value: UInt64 = 14_695_981_039_346_656_037
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for component in 0..<3 {
                value = (value ^ UInt64(pixels[index + component] & 0xF0))
                    &* 1_099_511_628_211
            }
        }
        return value
    }

    private static func recognize(_ image: CGImage)
        async throws -> (segments: [OCRSegment], lineCount: Int) {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let raw: [(String, CGRect)] = (request.results ?? []).compactMap { observation in
                guard let top = observation.topCandidates(1).first, top.confidence >= 0.2 else { return nil }
                let value = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.range(of: "[A-Za-z]{2}", options: .regularExpression) != nil else { return nil }
                return (value, observation.boundingBox)
            }
            // Merge line OCR before translating, so one bubble does not consume
            // several slots. Process ALL detected blocks, not just the first 16.
            let groups = OCRGrouping.merge(raw.map { OCRLine(text: $0.0, box: $0.1) })
            let segments = groups.enumerated().map {
                OCRSegment(index: $0.offset, source: $0.element.text, box: $0.element.box)
            }
            return (segments: segments, lineCount: raw.count)
        }.value
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        resetForPageChange()
        status = "ページを読み込んでいます…"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        if !demoMode { currentAddress = webView.url?.absoluteString ?? currentAddress }
        status = "表示できました。翻訳を開始できます。"
        if autoTranslate && isAutoTranslationPage { requestTranslation() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard webView === self.webView else { return }
        status = "表示エラー：\(error.localizedDescription)"
    }

    // A real child WKWebView is required for target=_blank and window.open.
    // Returning nil without handling the request silently loses Kindle book tabs.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        configure(popup)
        previousTabs.append((view: self.webView, isDemo: demoMode))
        self.webView = popup
        demoMode = false
        tabDepth = previousTabs.count
        resetForPageChange()
        currentAddress = navigationAction.request.url?.absoluteString ?? "新しいタブ"
        status = "新しいタブをアプリ内で開きました。タブ戻るで戻れます。"
        // WebKit loads the request in the returned WKWebView automatically.
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === self.webView { closeCurrentTab() }
    }
}
