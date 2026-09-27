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
                            Text(item.japanese)
                                .font(.system(size: min(18, max(11, box.height / 2.5)),
                                              weight: .semibold))
                                .foregroundStyle(.black)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.65)
                                .lineLimit(4)
                                .padding(4)
                                .frame(width: box.width, height: box.height)
                                .background(.white.opacity(0.96),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.black.opacity(0.30), lineWidth: 1))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
                Text(model.diagnostics)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
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
    /// Convert Vision's bottom-left normalized image coordinates to the view's top-left points.
    static func frame(for normalized: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0 && size.height > 0 else { return .zero }
        let left = max(0, min(size.width - 1, normalized.minX * size.width - 5))
        let top = max(0, min(size.height - 1, (1 - normalized.maxY) * size.height - 5))
        let width = min(size.width - left, max(105, normalized.width * size.width + 18))
        let height = min(size.height - top, max(42, normalized.height * size.height + 16))
        return CGRect(x: left, y: top, width: max(1, width), height: max(1, height))
    }
}

private struct EmbeddedBrowser: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}