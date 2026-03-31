import Foundation
import Darwin

// MARK: - ProxyState（スレッドセーフな共有状態）

/// acceptループとProxyHandlerからバックグラウンドスレッドで参照されるため、
/// NSLock で保護した独立クラスとして定義する。
final class ProxyState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isBlocking = false
    private var _allowedHosts: Set<String> = []

    func setMode(blocking: Bool, hosts: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        _isBlocking = blocking
        _allowedHosts = hosts
        print("[ProxyServer] mode=\(blocking ? "BLOCKING allowedHosts=\(hosts)" : "PASS-THROUGH")")
    }

    /// ホスト名がアクセス許可されているか
    func isAllowed(_ hostname: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if !_isBlocking { return true }   // セッション外はすべて通す
        let bare = hostname.components(separatedBy: ":").first?.lowercased() ?? hostname.lowercased()
        return _allowedHosts.contains(where: { bare == $0 || bare.hasSuffix("." + $0) })
    }
}

// MARK: - ProxyServer

actor ProxyServer {

    static let port: UInt16 = 58080

    private var serverFd: Int32 = -1
    /// acceptループ・ProxyHandler と共有する状態オブジェクト
    let state = ProxyState()

    // MARK: - Lifecycle

    /// アプリ起動時に一度だけ呼ぶ（管理者権限不要）
    func start() async throws {
        guard serverFd < 0 else { return }   // 二重起動防止
        print("[ProxyServer] starting on port \(Self.port)")

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 {
            let e = errno
            print("[ProxyServer] socket() failed. errno=\(e) (\(String(cString: strerror(e))))")
            throw FocusError.proxyStartFailed(errno: e)
        }
        print("[ProxyServer] socket fd=\(fd)")

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,   &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE,   &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = Self.port.bigEndian
        addr.sin_addr   = in_addr(s_addr: 0)   // INADDR_ANY

        // bind — errno をクロージャ内で即キャプチャ
        var bindErrno: Int32 = 0
        let bindResult: Int32 = withUnsafeMutablePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                let r = Darwin.bind(fd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                if r != 0 { bindErrno = errno }
                return r
            }
        }
        if bindResult != 0 {
            print("[ProxyServer] bind() failed. errno=\(bindErrno) (\(String(cString: strerror(bindErrno))))")
            Darwin.close(fd)
            if bindErrno == EADDRINUSE { throw FocusError.proxyPortBusy }
            if bindErrno == EACCES || bindErrno == EPERM { throw FocusError.proxyPermissionDenied }
            throw FocusError.proxyStartFailed(errno: bindErrno)
        }
        print("[ProxyServer] bind() succeeded")

        let listenResult = Darwin.listen(fd, 64)
        if listenResult != 0 {
            let e = errno
            print("[ProxyServer] listen() failed. errno=\(e) (\(String(cString: strerror(e))))")
            Darwin.close(fd)
            throw FocusError.proxyStartFailed(errno: e)
        }
        print("[ProxyServer] listening on port \(Self.port)")

        serverFd = fd
        let sharedState = state
        DispatchQueue.global(qos: .utility).async {
            runAcceptLoop(serverFd: fd, state: sharedState)
        }
    }

    func stop() async {
        if serverFd >= 0 {
            Darwin.close(serverFd)
            serverFd = -1
        }
    }

    // MARK: - Mode Control

    /// セッション開始: blocking=true でホワイトリスト外をブロック
    func setBlocking(_ blocking: Bool, allowedHosts: Set<String> = []) {
        state.setMode(blocking: blocking, hosts: allowedHosts)
    }
}

// MARK: - Accept Loop

private func runAcceptLoop(serverFd: Int32, state: ProxyState) {
    while true {
        var clientAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.accept(serverFd, $0, &len)
            }
        }
        guard clientFd >= 0 else { return }
        DispatchQueue.global(qos: .utility).async {
            ProxyHandler(clientFd: clientFd, state: state).run()
        }
    }
}

// MARK: - ProxyHandler

private class ProxyHandler {
    let clientFd: Int32
    let state: ProxyState

    init(clientFd: Int32, state: ProxyState) {
        self.clientFd = clientFd
        self.state = state
    }

    func run() {
        defer { Darwin.close(clientFd) }

        guard let (headerData, extra) = readUntilBlankLine(fd: clientFd) else { return }
        guard let requestStr = String(data: headerData, encoding: .utf8) else { return }
        let firstLine = requestStr.components(separatedBy: "\r\n").first ?? ""

        if firstLine.hasPrefix("CONNECT ") {
            handleCONNECT(firstLine: firstLine)
        } else {
            handleHTTP(requestStr: requestStr, headerData: headerData, extra: extra)
        }
    }

    // MARK: CONNECT（HTTPSトンネル）

    private func handleCONNECT(firstLine: String) {
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }

        let (host, port) = parseHostPort(String(parts[1]), defaultPort: 443)

        guard state.isAllowed(host) else {
            sendBlocked(to: clientFd, host: host)
            return
        }

        guard let targetFd = connectTCP(host: host, port: port) else {
            let resp = "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n"
            sendAll(fd: clientFd, data: Data(resp.utf8))
            return
        }
        defer { Darwin.close(targetFd) }

        sendAll(fd: clientFd, data: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8))
        relay(fd1: clientFd, fd2: targetFd)
    }

    // MARK: HTTP プロキシ

    private func handleHTTP(requestStr: String, headerData: Data, extra: Data) {
        let lines = requestStr.components(separatedBy: "\r\n")
        let hostLine = lines.first(where: { $0.lowercased().hasPrefix("host:") }) ?? ""
        let hostValue = String(hostLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        let host = hostValue.components(separatedBy: ":").first ?? ""

        guard !host.isEmpty, state.isAllowed(host) else {
            sendBlocked(to: clientFd, host: host.isEmpty ? "(unknown)" : host)
            return
        }

        guard let targetFd = connectTCP(host: host, port: 80) else { return }
        defer { Darwin.close(targetFd) }

        sendAll(fd: targetFd, data: headerData)
        if !extra.isEmpty { sendAll(fd: targetFd, data: extra) }
        relay(fd1: clientFd, fd2: targetFd)
    }

    // MARK: Helpers

    private func parseHostPort(_ s: String, defaultPort: Int) -> (String, Int) {
        if let idx = s.lastIndex(of: ":"), let p = Int(s[s.index(after: idx)...]) {
            return (String(s[..<idx]), p)
        }
        return (s, defaultPort)
    }

    private func sendBlocked(to fd: Int32, host: String) {
        let body = """
        <html><head><meta charset="utf-8"><title>FocusBlock</title>
        <style>body{font-family:system-ui;text-align:center;padding:60px;background:#f5f5f7}</style>
        </head><body><h1>\u{1F6E1} FocusBlock</h1>
        <p><strong>\(host)</strong> はブロックされています。</p>
        <p>フォーカスセッション中は許可リスト以外のサイトにアクセスできません。</p>
        </body></html>
        """
        let resp = "HTTP/1.1 403 Forbidden\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        sendAll(fd: fd, data: Data(resp.utf8))
    }
}

// MARK: - Socket ユーティリティ

private func readUntilBlankLine(fd: Int32) -> (Data, Data)? {
    var buf = [UInt8](repeating: 0, count: 4096)
    var accumulated = Data()
    let separator = Data([0x0d, 0x0a, 0x0d, 0x0a])

    while accumulated.count < 16384 {
        let n = Darwin.recv(fd, &buf, buf.count, 0)
        guard n > 0 else { return nil }
        accumulated.append(contentsOf: buf[..<n])
        if let range = accumulated.range(of: separator) {
            return (Data(accumulated[..<range.upperBound]), Data(accumulated[range.upperBound...]))
        }
    }
    return nil
}

private func connectTCP(host: String, port: Int) -> Int32? {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM

    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &result) == 0,
          let firstAddr = result else { return nil }
    defer { freeaddrinfo(result) }

    var current: UnsafeMutablePointer<addrinfo>? = firstAddr
    while let a = current {
        let fd = Darwin.socket(a.pointee.ai_family, SOCK_STREAM, 0)
        if fd >= 0 {
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            if Darwin.connect(fd, a.pointee.ai_addr, a.pointee.ai_addrlen) == 0 { return fd }
            Darwin.close(fd)
        }
        current = a.pointee.ai_next
    }
    return nil
}

private func sendAll(fd: Int32, data: Data) {
    var sent = 0
    while sent < data.count {
        let n = data.withUnsafeBytes { ptr in
            Darwin.send(fd, ptr.baseAddress!.advanced(by: sent), data.count - sent, 0)
        }
        guard n > 0 else { return }
        sent += n
    }
}

private func relay(fd1: Int32, fd2: Int32) {
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .utility).async {
        pipeData(from: fd1, to: fd2)
        Darwin.shutdown(fd2, SHUT_WR)
        group.leave()
    }
    pipeData(from: fd2, to: fd1)
    Darwin.shutdown(fd1, SHUT_WR)
    group.wait()
}

private func pipeData(from src: Int32, to dst: Int32) {
    var buf = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = Darwin.recv(src, &buf, buf.count, 0)
        guard n > 0 else { return }
        sendAll(fd: dst, data: Data(buf[..<n]))
    }
}
