import Foundation
import SwiftUI
import Combine

@MainActor
class AllowedSitesStore: ObservableObject {

    private static let defaultsKey = "com.focusblock.allowedSites"

    @Published private(set) var sites: [String] = []

    init() {
        load()
    }

    // MARK: - CRUD

    func add(_ input: String) {
        guard let host = normalize(input), !host.isEmpty else { return }
        guard !sites.contains(host) else { return }
        sites.append(host)
        sites.sort()
        persist()
    }

    func remove(_ host: String) {
        sites.removeAll { $0 == host }
        persist()
    }

    func removeAll() {
        sites = []
        persist()
    }

    // MARK: - Proxy 判定用

    /// ホスト名がホワイトリストに含まれるか（サブドメイン込み）
    func isAllowed(_ hostname: String) -> Bool {
        let bare = stripPort(hostname).lowercased()
        return sites.contains(where: { site in
            bare == site || bare.hasSuffix("." + site)
        })
    }

    var hostsSet: Set<String> {
        Set(sites)
    }

    // MARK: - Private

    private func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // URL 形式 (https://example.com/path) の場合
        let withScheme = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: withScheme), let host = url.host {
            return stripPort(host)
        }

        // ホスト名として直接使用
        let bare = stripPort(trimmed)
        // 最低限のバリデーション（英数字・ハイフン・ドット・国際化ドメイン）
        let invalid = CharacterSet.alphanumerics
            .union(.init(charactersIn: ".-_"))
            .inverted
        if bare.unicodeScalars.contains(where: { invalid.contains($0) }) { return nil }
        return bare.isEmpty ? nil : bare
    }

    private func stripPort(_ host: String) -> String {
        if let colonIdx = host.lastIndex(of: ":"),
           let portNum = Int(host[host.index(after: colonIdx)...]),
           portNum > 0 && portNum <= 65535 {
            return String(host[..<colonIdx])
        }
        return host
    }

    private func persist() {
        UserDefaults.standard.set(sites, forKey: Self.defaultsKey)
    }

    private func load() {
        sites = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
    }
}
