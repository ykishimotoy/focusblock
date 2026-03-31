import Foundation

// MARK: - NetworkBlocker

struct NetworkBlocker {

    private let proxyHost = "127.0.0.1"
    private let proxyPort = ProxyServer.port

    // MARK: - 初回セットアップ（管理者パスワードを一度だけ要求）

    private static let configuredKey = "com.focusblock.proxyConfigured"

    private var isProxyConfigured: Bool {
        get { UserDefaults.standard.bool(forKey: Self.configuredKey) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.configuredKey) }
    }

    /// システムプロキシが未設定なら一度だけ設定する（管理者パスワードを初回のみ要求）
    func setupIfNeeded() async throws {
        if isProxyConfigured {
            print("[NetworkBlocker] already configured, skipping")
            return
        }
        print("[NetworkBlocker] first-time setup: configuring system proxy")
        try await enableProxy()
        isProxyConfigured = true
    }

    /// 強制的に再設定（設定をリセットしたい場合）
    func forceSetup() async throws {
        print("[NetworkBlocker] force setup: configuring system proxy")
        try await enableProxy()
        isProxyConfigured = true
    }

    /// 設定済みフラグをリセット（次回起動時に再設定させる）
    func resetConfiguration() {
        UserDefaults.standard.removeObject(forKey: Self.configuredKey)
    }

    // MARK: - システムプロキシ設定（async）

    private func enableProxy() async throws {
        let services = try await listActiveNetworkServices()
        guard !services.isEmpty else { throw NetworkBlockerError.noServicesFound }

        let cmds = services.map { svc -> String in
            let s = shellEscape(svc)
            return "networksetup -setwebproxy \(s) \(proxyHost) \(proxyPort) && networksetup -setsecurewebproxy \(s) \(proxyHost) \(proxyPort) && networksetup -setwebproxystate \(s) on && networksetup -setsecurewebproxystate \(s) on"
        }.joined(separator: " && ")

        try await runAsAdmin(cmds)
    }

    func disableProxy() async throws {
        let services = try await listActiveNetworkServices()
        let cmds = services.map { svc -> String in
            let s = shellEscape(svc)
            return "networksetup -setwebproxystate \(s) off && networksetup -setsecurewebproxystate \(s) off"
        }.joined(separator: " && ")
        try await runAsAdmin(cmds)
    }

    /// アプリ終了時の同期版
    func disableProxySync() {
        guard let services = try? listNetworkServicesSync(), !services.isEmpty else { return }
        let cmds = services.map { svc -> String in
            let s = shellEscape(svc)
            return "networksetup -setwebproxystate \(s) off; networksetup -setsecurewebproxystate \(s) off"
        }.joined(separator: "; ")
        try? runAsAdminSync(cmds)
    }

    // MARK: - ネットワークサービス一覧

    private func listActiveNetworkServices() async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    continuation.resume(returning: try self.listNetworkServicesSync())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func listNetworkServicesSync() throws -> [String] {
        let output = try runShell("/usr/sbin/networksetup", args: ["-listallnetworkservices"])
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
    }

    // MARK: - Shell 実行

    private func runAsAdmin(_ script: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                do {
                    try self.runAsAdminSync(script)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runAsAdminSync(_ script: String) throws {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            if process.terminationStatus == 1 { throw NetworkBlockerError.userCancelled }
            throw NetworkBlockerError.commandFailed(status: process.terminationStatus)
        }
    }

    private func runShell(_ path: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func shellEscape(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

// MARK: - Errors

enum NetworkBlockerError: LocalizedError {
    case noServicesFound
    case commandFailed(status: Int32)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .noServicesFound:   return "有効なネットワークサービスが見つかりません。"
        case .commandFailed(let s): return "ネットワーク設定コマンドが失敗しました（終了コード: \(s)）。"
        case .userCancelled:     return "管理者権限の認証がキャンセルされました。"
        }
    }
}
