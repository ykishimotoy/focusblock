import SwiftUI
import AppKit

struct MainMenuView: View {
    var onOpenSettings: () -> Void = {}
    @EnvironmentObject var sessionManager: FocusSessionManager
    @EnvironmentObject var allowedSitesStore: AllowedSitesStore
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Image(systemName: sessionManager.isActive ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(sessionManager.isActive ? .red : .accentColor)
                    .font(.title2)
                Text("FocusBlock")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // メインコンテンツ
            Group {
                switch sessionManager.state {
                case .idle:
                    idleContent
                case .active:
                    activeContent
                case .unlocking:
                    unlockingContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // フッター
            HStack {
                Button("設定") {
                    openSettings()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(sessionManager.isActive)

                Spacer()

                Button("終了") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(sessionManager.isActive ? .secondary.opacity(0.4) : .secondary)
                .disabled(sessionManager.isActive)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .alert("エラー", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Idle State

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("フォーカスセッションを開始すると、\n許可リスト以外のサイトが1時間ブロックされます。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("許可サイト: \(allowedSitesStore.sites.count) 件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: startSession) {
                HStack {
                    Spacer()
                    Image(systemName: "timer")
                    Text("1時間のフォーカス開始")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(allowedSitesStore.sites.isEmpty)
            .controlSize(.large)

            if allowedSitesStore.sites.isEmpty {
                Text("先に「設定」から許可サイトを追加してください")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Active State

    private var activeContent: some View {
        VStack(spacing: 14) {
            // タイマー表示
            VStack(spacing: 4) {
                Text(sessionManager.remainingTimeString)
                    .font(.system(size: 44, weight: .thin, design: .monospaced))
                    .foregroundColor(.primary)
                Text("残り時間")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // プログレスバー
            ProgressView(value: Double(Int(FocusSessionManager.sessionDuration) - sessionManager.remainingSeconds),
                         total: FocusSessionManager.sessionDuration)
                .tint(.blue)

            // 解除ボタン
            Button(action: { sessionManager.requestUnlock() }) {
                HStack {
                    Spacer()
                    Image(systemName: "lock.open")
                    Text("100マス計算で解除")
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    // MARK: - Unlocking State

    private var unlockingContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
            Text("数学チャレンジウィンドウを確認してください")
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("チャレンジをキャンセル") {
                sessionManager.cancelUnlock()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func startSession() {
        Task {
            do {
                try await sessionManager.startSession(
                    allowedHosts: allowedSitesStore.hostsSet
                )
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func openSettings() {
        onOpenSettings()
    }
}
