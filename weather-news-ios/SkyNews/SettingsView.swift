import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sources: SourceStore
    @ObservedObject var interest: InterestStore
    let refresh: () -> Void

    @AppStorage("news.scrollSpeed") private var scrollSpeed = 17.0
    @AppStorage("news.fontSize") private var fontSize = 20.0
    @AppStorage("news.preferencePercent") private var preferencePercent = 70
    @AppStorage("news.fetchWebBodies") private var fetchWebBodies = true
    @AppStorage("gaze.enabled") private var gazeEnabled = false
    @AppStorage("gaze.stopDelay") private var gazeStopDelay = 0.8
    @AppStorage("gaze.resumeDelay") private var gazeResumeDelay = 0.5
    @State private var newSourceName = ""
    @State private var newSourceURL = ""
    @State private var invalidURL = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("ニュースの流れ方") {
                    VStack(alignment: .leading) {
                        Text("スクロール速度：\(Int(scrollSpeed)) pt/秒")
                        Slider(value: $scrollSpeed, in: 4...60, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("文字サイズ：\(Int(fontSize)) pt")
                        Slider(value: $fontSize, in: 14...30, step: 1)
                    }
                    Text("画面下部の一時停止ボタンで、いつでも止められます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("視線連動スクロール") {
                    Toggle("画面を見ている間だけスクロール", isOn: $gazeEnabled)
                    VStack(alignment: .leading) {
                        Text(String(format: "視線が外れて %.1f 秒で停止", gazeStopDelay))
                        Slider(value: $gazeStopDelay, in: 0.2...3.0, step: 0.1)
                    }
                    .disabled(!gazeEnabled)
                    VStack(alignment: .leading) {
                        Text(String(format: "画面を見ると %.1f 秒で再開", gazeResumeDelay))
                        Slider(value: $gazeResumeDelay, in: 0.2...3.0, step: 0.1)
                    }
                    .disabled(!gazeEnabled)
                    Text("視線はARKitによる推定です。初回にカメラの使用許可が必要です。非対応機種・権限なし・カメラエラー時は通常スクロールします。手動の一時停止は常に優先されます。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("カメラ画像や顔・視線データを記録・送信しません。アプリの表示中だけカメラを使用します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("好みの学習") {
                    VStack(alignment: .leading) {
                        Text("好みの記事：\(preferencePercent)%")
                        Slider(value: Binding(
                            get: { Double(preferencePercent) },
                            set: { preferencePercent = Int($0) }
                        ), in: 0...90, step: 10)
                        Text("残りは最新記事と新しい話題に割り当てます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("興味あり \(interest.votes.values.filter { $0 == 1 }.count)件 ・ 興味なし \(interest.votes.values.filter { $0 == -1 }.count)件")
                        .font(.footnote)
                    Button("好みの学習履歴を初期化", role: .destructive) {
                        confirmReset = true
                    }
                }

                Section("記事本文") {
                    Toggle("RSSが概要のみなら記事URLから本文を取得", isOn: $fetchWebBodies)
                    Text("一般公開されたHTML本文のみを抽出します。配信元の条件やアクセス制限により取得できない場合は、RSSの概要を表示します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("RSS配信元") {
                    ForEach(sources.sources) { source in
                        Toggle(isOn: Binding(
                            get: { source.enabled },
                            set: { sources.setEnabled(source.id, $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                Text(source.address)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .onDelete(perform: sources.remove)
                }

                Section("RSSを追加") {
                    TextField("配信元の名前", text: $newSourceName)
                    TextField("https://example.com/feed.xml", text: $newSourceURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Button("RSSを追加") {
                        if sources.add(name: newSourceName, address: newSourceURL) {
                            newSourceName = ""
                            newSourceURL = ""
                        } else {
                            invalidURL = true
                        }
                    }
                }

                Section("記事本文について") {
                    Text("RSSに全文があればそのまま表示します。概要だけの場合は一般公開HTMLからの本文抽出を試み、できない場合は概要と元記事リンクを表示します。ログインや有料記事の制限は回避しません。")
                        .font(.footnote)
                    Text("評価履歴は端末内にのみ保存します。ニュース取得と天気取得には通信が必要です。")
                        .font(.footnote)
                }
            }
            .navigationTitle("表示・配信設定")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { refresh(); dismiss() }
                }
            }
            .alert("RSS URLを確認してください", isPresented: $invalidURL) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("有効なHTTPS URLを入力してください。同じURLは追加できません。")
            }
            .confirmationDialog("学習結果をすべて削除しますか？", isPresented: $confirmReset) {
                Button("学習履歴を削除", role: .destructive) { interest.reset() }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }
}