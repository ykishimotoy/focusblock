import SwiftUI

/// 起動時・スリープ復帰時・セッション終了時に表示する許可サイト確認プロンプト
/// 3分以内に閉じなければ自動でブロック開始
struct AllowedSitesPromptView: View {
    var onClose: () -> Void
    @EnvironmentObject var store: AllowedSitesStore
    @State private var newSiteInput = ""
    @State private var invalidInput = false
    @State private var secondsRemaining: Int = 180
    @State private var timerTask: Task<Void, Never>? = nil

    private var timerColor: Color {
        secondsRemaining <= 30 ? .red : (secondsRemaining <= 60 ? .orange : .secondary)
    }

    private var timerLabel: String {
        let m = secondsRemaining / 60
        let s = secondsRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ヘッダー
            HStack(alignment: .top) {
                Text("🍅")
                    .font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("次のフォーカスセッションで許可するサイトは？")
                        .font(.headline)
                    Text("今すぐ見直して、不要なサイトを削除しておきましょう。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // カウントダウン表示
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timerLabel)
                        .font(.system(size: 22, weight: .thin, design: .monospaced))
                        .foregroundColor(timerColor)
                    Text("後に自動開始")
                        .font(.caption2)
                        .foregroundColor(timerColor.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // カウントダウンプログレスバー
            ProgressView(value: Double(180 - secondsRemaining), total: 180)
                .tint(timerColor)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider()

            // サイトリスト
            if store.sites.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("許可サイトが登録されていません（このまま閉じると全サイトブロック）")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding(.vertical, 8)
            } else {
                List {
                    ForEach(store.sites, id: \.self) { site in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
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
                .frame(minHeight: 100, maxHeight: 180)
            }

            Divider()

            // 追加フォーム
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("example.com を追加", text: $newSiteInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSite)
                    Button("追加") { addSite() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newSiteInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if invalidInput {
                    Text("有効なドメイン名を入力してください（例: google.com）")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // フッター
            HStack {
                Text("\(store.sites.count) サイト登録済み")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("今すぐ開始") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 440)
        .onAppear { startTimer() }
        .onDisappear { timerTask?.cancel() }
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled && secondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { secondsRemaining -= 1 }
            }
            // 0になったら自動で閉じてブロック開始
            if !Task.isCancelled {
                await MainActor.run { onClose() }
            }
        }
    }

    private func addSite() {
        let input = newSiteInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        let before = store.sites.count
        store.add(input)
        if store.sites.count > before {
            newSiteInput = ""
            invalidInput = false
        } else {
            invalidInput = !store.sites.contains(where: { $0.contains(input.lowercased()) })
        }
    }
}
