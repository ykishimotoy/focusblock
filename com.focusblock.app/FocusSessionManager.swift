import Foundation
import Combine

// MARK: - Session State

enum SessionState: Equatable {
    case idle
    case active
    case unlocking

    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.active, .active), (.unlocking, .unlocking): return true
        default: return false
        }
    }
}

// MARK: - FocusSessionManager

@MainActor
class FocusSessionManager: ObservableObject {

    static let sessionDuration: TimeInterval = 3600

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var remainingSeconds: Int = Int(sessionDuration)

    // AppDelegate からの通知用コールバック
    var onTick: (() -> Void)?
    var onStateChange: (() -> Void)?

    let proxyServer = ProxyServer()   // AppDelegate からも参照
    private let networkBlocker = NetworkBlocker()
    private var timerTask: Task<Void, Never>?

    // MARK: - Computed

    var remainingTimeString: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var isActive: Bool { state == .active || state == .unlocking }

    // MARK: - 初期化（アプリ起動時に一度だけ呼ぶ）

    /// ProxyServerを起動し、システムプロキシを初回のみ設定する
    func initialize() async throws {
        try await proxyServer.start()
        try await networkBlocker.setupIfNeeded()
    }

    // MARK: - Session Control

    func startSession(allowedHosts: Set<String>) async throws {
        guard state == .idle else { return }
        // 許可サイト0件のまま開始した場合は全サイトブロックになる

        // プロキシをブロックモードに切り替え（管理者不要）
        await proxyServer.setBlocking(true, allowedHosts: allowedHosts)

        remainingSeconds = Int(Self.sessionDuration)
        state = .active
        onStateChange?()
        startCountdown()
    }

    func requestUnlock() {
        guard state == .active else { return }
        state = .unlocking
        onStateChange?()
    }

    func cancelUnlock() {
        guard state == .unlocking else { return }
        state = .active
        onStateChange?()
    }

    func completeMathChallenge() async {
        guard state == .unlocking else { return }
        await stopSession()
    }

    /// アプリ強制終了時（プロキシ停止はしない。常時ON設計）
    func forceStop() {
        timerTask?.cancel()
        timerTask = nil
        // プロキシはパススルーに戻すだけ
        Task { await proxyServer.setBlocking(false) }
        state = .idle
    }

    // MARK: - Private

    private func startCountdown() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.tick() }
            }
        }
    }

    private func tick() {
        guard state == .active || state == .unlocking else { return }
        remainingSeconds -= 1
        onTick?()
        if remainingSeconds <= 0 {
            Task { await stopSession() }
        }
    }

    func stopSession() async {
        timerTask?.cancel()
        timerTask = nil
        // パススルーに戻すだけ（networksetup は触らない）
        await proxyServer.setBlocking(false)
        remainingSeconds = Int(Self.sessionDuration)
        state = .idle
        onStateChange?()
    }
}

// MARK: - Errors

enum FocusError: LocalizedError {
    case noAllowedSites
    case proxyPortBusy
    case proxyPermissionDenied
    case proxyStartFailed(errno: Int32)
    case adminRequired

    var errorDescription: String? {
        switch self {
        case .noAllowedSites:
            return "許可サイトが設定されていません。設定から追加してください。"
        case .proxyPortBusy:
            return "ポート\(ProxyServer.port)が他のアプリに使用中です。アプリを再起動してください。"
        case .proxyPermissionDenied:
            return "ポート\(ProxyServer.port)へのバインドが拒否されました（権限エラー）。"
        case .proxyStartFailed(let e):
            return "プロキシサーバーの起動に失敗しました（ポート\(ProxyServer.port)、errno=\(e)）。"
        case .adminRequired:
            return "プロキシ設定には管理者権限が必要です。"
        }
    }
}
