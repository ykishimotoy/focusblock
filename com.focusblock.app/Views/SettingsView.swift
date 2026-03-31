import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AllowedSitesStore
    @State private var newSiteInput = ""
    @State private var invalidInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // タイトル
            HStack {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundColor(.accentColor)
                Text("許可サイト設定")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // サイトリスト
            if store.sites.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("許可サイトが登録されていません")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    Text("下のフォームからドメインを追加してください")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 160)
            } else {
                List {
                    ForEach(store.sites, id: \.self) { site in
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                            Text(site)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                store.remove(site)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 160)
            }

            Divider()

            // 追加フォーム
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("example.com または https://example.com", text: $newSiteInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSite)

                    Button("追加") { addSite() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newSiteInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if invalidInput {
                    Text("有効なドメイン名を入力してください（例: google.com）")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                // よく使うサイトのプリセット
                HStack(spacing: 6) {
                    Text("プリセット:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) {
                            store.add(preset)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .font(.caption2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // 全削除ボタン
            HStack {
                Spacer()
                Button("全て削除") { store.removeAll() }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.8))
                    .font(.caption)
                    .disabled(store.sites.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 420, height: 380)
    }

    // MARK: -

    private let presets = ["google.com", "github.com", "stackoverflow.com"]

    private func addSite() {
        let input = newSiteInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        let before = store.sites.count
        store.add(input)
        let after = store.sites.count

        if after > before {
            newSiteInput = ""
            invalidInput = false
        } else {
            // 追加されなかった = 無効 or 重複
            invalidInput = !store.sites.contains(where: {
                $0.contains(input.components(separatedBy: "/").last?.lowercased() ?? "")
            })
        }
    }
}
