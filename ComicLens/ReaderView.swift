import SwiftUI
import Translation
import WebKit

struct ReaderView: View {
    @StateObject private var model = ReaderModel()
    @State private var address = ReaderModel.kindleURL
    @State private var showDiagnostics = false
    @State private var showTranslations = false
    @State private var languageSetup: TranslationSession.Configuration?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.book.closed.fill")
                    .foregroundStyle(.indigo)
                Text("COMIC LENS")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                Spacer()
                if model.tabDepth > 0 {
                    Button {
                        model.closeCurrentTab()
                    } label: {
                        Label("タブ戻る", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("元のタブに戻る")
                }
                Button("Kindle") { model.openHome() }
                    .buttonStyle(.bordered)
                Button("デモ") { model.openDemo() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            HStack(spacing: 7) {
                Button { model.back() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("戻る")
                Button { model.forward() } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("進む")
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("更新")
                TextField("HTTPSのURL", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.open(address) }
                    .accessibilityLabel("ブラウザーのURL")
                Button { model.open(address) } label: { Image(systemName: "arrow.right.circle.fill") }
                    .accessibilityLabel("URLを開く")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            HStack(spacing: 10) {
                Toggle("自動", isOn: $model.autoTranslate)
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: true, vertical: false)
                    .toggleStyle(.switch)
                Spacer(minLength: 0)
                Button {
                    model.requestTranslation()
                } label: {
                    Label(model.isWorking ? "処理中" : "翻訳", systemImage: "character.bubble")
                }
                .disabled(model.isWorking)
                .buttonStyle(.borderedProminent)
                Button("言語準備") {
                    languageSetup = TranslationSession.Configuration(
                        source: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: "ja"),
                        preferredStrategy: .lowLatency)
                    languageSetup?.invalidate()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                Button {
                    model.showOriginal.toggle()
                } label: {
                    Label(model.showOriginal ? "訳文" : "原文",
                          systemImage: model.showOriginal ? "text.bubble" : "text.quote")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    EmbeddedBrowser(webView: model.webView)
                        .id(ObjectIdentifier(model.webView))

                    if !model.showOriginal {
                        ForEach(model.overlays) { item in
                            let box = TranslationOverlayGeometry.frame(for: item.box,
                                                                        in: geometry.size)
                            if let fontSize = TranslationTextLayout.fittedFont(
                                text: item.japanese, size: box.size) {
                                FittedTranslationLabel(text: item.japanese, fontSize: fontSize)
                                    .frame(width: box.width, height: box.height)
                                    .background(.white.opacity(0.97),
                                                in: RoundedRectangle(cornerRadius: min(7, box.height / 5)))
                                    .overlay(RoundedRectangle(cornerRadius: min(7, box.height / 5))
                                        .strokeBorder(.black.opacity(0.20), lineWidth: 0.5))
                                    .position(x: box.midX, y: box.midY)
                                    .accessibilityLabel("翻訳：\(item.japanese)。原文：\(item.source)")
                            }
                            // Unfittable text is readable in the full translation list
                            // rather than rendering giant black text over the artwork.
                        }
                        .allowsHitTesting(false)
                    }
                }
                .clipped()
            }

            Divider()
            HStack(spacing: 7) {
                if model.isWorking { ProgressView().controlSize(.mini) }
                Text(model.status)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(height: 34)
            .padding(.horizontal, 12)
            if !model.overlays.isEmpty || !model.untranslated.isEmpty {
                Button {
                    showTranslations = true
                } label: {
                    Label("訳文一覧（\(model.overlays.count)件）", systemImage: "text.book.closed")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }
            Button {
                showDiagnostics.toggle()
            } label: {
                HStack {
                    Text(showDiagnostics ? "診断を閉じる" : "翻訳診断を表示")
                    Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                    Spacer()
                }
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            if showDiagnostics {
                ScrollView(.vertical) {
                    Text(model.diagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 52)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .translationTask(languageSetup) { session in
            do {
                try await session.prepareTranslation()
                model.status = "英語・日本語の翻訳言語を準備しました。再度「翻訳」を押してください。"
            } catch {
                model.status = "言語準備: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showTranslations) {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.overlays) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(item.id + 1). \(item.japanese)")
                                    .font(.body)
                                    .textSelection(.enabled)
                                Text(item.source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Divider()
                        }
                        if !model.untranslated.isEmpty {
                            Text("原文を維持した箇所")
                                .font(.headline)
                            ForEach(model.untranslated.indices, id: \.self) { index in
                                Text(model.untranslated[index])
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .navigationTitle("訳文一覧")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") { showTranslations = false }
                    }
                }
            }
        }
        .onAppear { model.startMonitoring() }
        .onDisappear { model.stopMonitoring() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { model.startMonitoring() }
            else { model.stopMonitoring() }
        }
        .onChange(of: model.currentAddress) { _, newValue in
            address = newValue
        }
    }
}

enum TranslationOverlayGeometry {
    /// Convert Vision's bottom-left normalized bounding box into the visible WebView.
    /// Avoid the former 105pt minimum width / 42pt height that caused dozens of
    /// tiny word translations to cover one another.
    static func frame(for normalized: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 4 && size.height > 4 else { return .zero }
        let centerX = normalized.midX * size.width
        let centerY = (1 - normalized.midY) * size.height
        let width = min(size.width - 4, max(38, normalized.width * size.width + 12))
        let height = min(size.height - 4, max(20, normalized.height * size.height + 10))
        let x = max(2, min(size.width - width - 2, centerX - width / 2))
        let y = max(2, min(size.height - height - 2, centerY - height / 2))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Determine whether the entire Japanese string can fit before drawing a
/// white patch. This prevents credits/long OCR text from escaping its rectangle.
private enum TranslationTextLayout {
    static func fittedFont(text: String, size: CGSize) -> CGFloat? {
        let width = size.width - 8
        let height = size.height - 6
        guard width > 10 && height > 8 else { return nil }
        let probe = UILabel()
        probe.numberOfLines = 0
        probe.lineBreakMode = .byCharWrapping
        probe.text = text
        var fontSize: CGFloat = 15
        while fontSize >= 5 {
            probe.font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
            let required = probe.sizeThatFits(CGSize(width: width, height: 100_000))
            if required.height <= height && required.width <= width + 0.5 {
                return fontSize
            }
            fontSize -= 0.5
        }
        return nil
    }
}

/// A clipped UIKit container: UILabel itself has an intrinsic content size that
/// can otherwise extend outside the parent SwiftUI .frame(width:height:).
private struct FittedTranslationLabel: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> TranslationTextContainer {
        TranslationTextContainer()
    }

    func updateUIView(_ container: TranslationTextContainer, context: Context) {
        container.label.text = text
        container.label.font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
    }
}

private final class TranslationTextContainer: UIView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .center
        label.textColor = .black
        label.backgroundColor = .clear
        label.isAccessibilityElement = false
        label.clipsToBounds = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(frame:)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 4, dy: 3)
    }
}

private struct EmbeddedBrowser: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}