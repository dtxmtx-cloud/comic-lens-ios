import Combine
import Foundation
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
    private var previousTabs: [(view: WKWebView, isDemo: Bool)] = []

    @Published var overlays: [TranslationOverlay] = []
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
    private var cached: [UInt64: [TranslationOverlay]] = [:]
    private var cacheOrder: [UInt64] = []
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
        lastFingerprint = nil
        diagnostics = "画面: 未取得 / OCR: 未実行 / AI: \(translator.readinessMessage)"
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
            diagnostics = "画面: 取得成功 / OCR: 処理前 / AI: \(translator.readinessMessage)"

            if let found = cached[fingerprint] {
                lastFingerprint = fingerprint
                overlays = found
                status = "翻訳を再表示しました（メモリ内キャッシュ）"
                return
            }

            overlays = []
            status = "画面内の英語を認識しています…"
            guard let cgImage = image.cgImage else {
                status = "画像の解析に対応していません。"
                return
            }

            let visionSegments = try await Self.recognize(cgImage)
            guard currentGeneration == generation else { return }

            // Only the bundled demo uses DOM coordinates. Kindle/external websites
            // are recognized from displayed pixels only; their DOM is never inspected.
            let demoSegments = demoMode ? (try? await demoBubbleSegments()) ?? [] : []
            let segments = demoSegments.isEmpty ? visionSegments : demoSegments
            diagnostics = "画面: 取得成功 / Vision OCR: \(visionSegments.count)件 / " +
                (demoMode ? "デモの吹き出し: \(demoSegments.count)件 / " : "") +
                "AI: \(translator.readinessMessage)"
            guard !segments.isEmpty else {
                status = "英語を検出できません。画面取得と作品の表示状態を確認してください。"
                lastFingerprint = fingerprint
                return
            }

            status = "\(segments.count)か所を翻訳しています…"
            let translations: [String]
            if demoMode, !demoSegments.isEmpty {
                do {
                    translations = try await translator.translate(segments)
                    diagnostics += " / 翻訳方式: Apple Intelligence"
                } catch {
                    // The fixed translation is ONLY for the original demo fixture.
                    let samples = segments.compactMap { DemoPage.translation(for: $0.source) }
                    guard samples.count == segments.count else { throw error }
                    translations = samples
                    diagnostics += " / 翻訳方式: デモ固定訳（AI未使用） / AIの問題: \(error.localizedDescription)"
                }
            } else {
                translations = try await translator.translate(segments)
                diagnostics += " / 翻訳方式: Apple Intelligence"
            }
            guard currentGeneration == generation, segments.count == translations.count else { return }

            // If the reader page changed during inference, discard the outdated overlay.
            let latest = try await snapshot()
            guard Self.fingerprint(latest) == fingerprint else {
                overlays = []
                lastFingerprint = nil
                status = "ページ変更を検出しました。次のページを翻訳します。"
                return
            }

            let result = zip(segments, translations).map { pair in
                TranslationOverlay(id: pair.0.index, source: pair.0.source,
                                   japanese: pair.1, box: pair.0.box)
            }
            overlays = result
            lastFingerprint = fingerprint
            cached[fingerprint] = result
            cacheOrder.append(fingerprint)
            if cacheOrder.count > 8 {
                let oldest = cacheOrder.removeFirst()
                cached.removeValue(forKey: oldest)
            }
            status = "\(result.count)か所を表示しました。原文ボタンで切り替えられます。"
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

    private static func recognize(_ image: CGImage) async throws -> [OCRSegment] {
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
            // Page reading order: top to bottom, then left to right.
            let sorted = raw.sorted {
                if abs($0.1.midY - $1.1.midY) > 0.025 { return $0.1.midY > $1.1.midY }
                return $0.1.minX < $1.1.minX
            }
            return Array(sorted.prefix(16).enumerated()).map {
                OCRSegment(index: $0.offset, source: $0.element.0, box: $0.element.1)
            }
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
