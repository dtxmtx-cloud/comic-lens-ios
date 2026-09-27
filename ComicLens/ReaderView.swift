import SwiftUI
import WebKit

struct ReaderView: View {
    @StateObject private var model = ReaderModel()
    @State private var address = ReaderModel.kindleURL
    @State private var showDiagnostics = false
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
                            FittedTranslationLabel(text: item.japanese, availableSize: box.size)
                                .frame(width: box.width, height: box.height)
                                .background(.white.opacity(0.96),
                                            in: RoundedRectangle(cornerRadius: min(9, box.height / 4)))
                                .overlay(RoundedRectangle(cornerRadius: min(9, box.height / 4))
                                    .strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                                .position(x: box.midX, y: box.midY)
                                .accessibilityLabel("翻訳：\(item.japanese)。原文：\(item.source)")
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

/// SwiftUI's minimumScaleFactor does not reliably shrink multi-line Text.
/// Fit the entire translation using the *actual* UIKit multi-line label size.
private struct FittedTranslationLabel: UIViewRepresentable {
    let text: String
    let availableSize: CGSize

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .center
        label.textColor = .black
        label.backgroundColor = .clear
        label.adjustsFontSizeToFitWidth = false
        label.isAccessibilityElement = false
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        let width = max(2, availableSize.width - 6)
        let height = max(2, availableSize.height - 6)
        // Start legibly, then shrink until ALL lines fit both dimensions.
        // Small, zoomed-out bubbles can use a smaller minimum than demo bubbles.
        let maximum: CGFloat = 15
        let minimum: CGFloat = 3.5
        var chosen = minimum
        var candidate = maximum
        while candidate >= minimum {
            label.font = UIFont.systemFont(ofSize: candidate, weight: .semibold)
            let required = label.sizeThatFits(CGSize(width: width, height: 10_000))
            if required.height <= height && required.width <= width + 0.5 {
                chosen = candidate
                break
            }
            candidate -= 0.5
        }
        label.font = UIFont.systemFont(ofSize: chosen, weight: .semibold)
        label.setNeedsLayout()
    }
}

private struct EmbeddedBrowser: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}