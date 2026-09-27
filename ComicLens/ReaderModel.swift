import Combine
import Foundation
import SwiftUI
import UIKit
import Vision
import WebKit

@MainActor
final class ReaderModel: NSObject, ObservableObject, WKNavigationDelegate {
    static let kindleURL = "https://read.amazon.co.jp/landing"

    let webView: WKWebView
    private let translator = OnDeviceTranslator()

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
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        openHome()
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
        guard !isWorking, !webView.isLoading, webView.bounds.width > 0,
              force || (autoTranslate && isAutoTranslationPage) else { return }
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
            lastFingerprint = fingerprint

            if let found = cached[fingerprint] {
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

            let segments = try await Self.recognize(cgImage)
            guard currentGeneration == generation else { return }
            guard !segments.isEmpty else {
                status = "英語の文字を検出できません。対象作品の表示や画面取得の制限を確認してください。"
                return
            }

            status = "\(segments.count)か所を端末内AIで翻訳しています…"
            let translations = try await translator.translate(segments)
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
            cached[fingerprint] = result
            cacheOrder.append(fingerprint)
            if cacheOrder.count > 8 {
                let oldest = cacheOrder.removeFirst()
                cached.removeValue(forKey: oldest)
            }
            status = "\(result.count)か所を翻訳しました。原文ボタンで切り替えられます。"
        } catch {
            guard currentGeneration == generation else { return }
            status = error.localizedDescription
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
        resetForPageChange()
        status = "ページを読み込んでいます…"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !demoMode { currentAddress = webView.url?.absoluteString ?? currentAddress }
        status = "表示できました。翻訳を開始できます。"
        if autoTranslate && isAutoTranslationPage { requestTranslation() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        status = "表示エラー：\(error.localizedDescription)"
    }
}