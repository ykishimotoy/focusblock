# FocusBlock

Safari・Chrome・Firefox などすべてのブラウザで、許可リスト以外のサイトを1時間ブロックするmacOS メニューバーアプリ。

解除するには **100マス計算（足し算）** の全問正解が必要。

---

## ブロックの仕組み

1. ローカルHTTP/CONNECTプロキシ（ポート 58080）を起動
2. macOS のシステムプロキシ設定（HTTP・HTTPS）を `127.0.0.1:58080` に変更
3. プロキシが許可リストのドメイン以外への接続を拒否（403 Forbidden）

HTTPS サイトには CONNECT トンネリングでホスト名チェックを行うため、**TLS 証明書は改ざんしない**（ブラウザの証明書エラーは発生しない）。

---

## Xcode でのビルド手順

### 1. 新規プロジェクト作成

Xcode を開き：
```
File > New > Project > macOS > App
```

設定：
- Product Name: `FocusBlock`
- Bundle Identifier: `com.focusblock.app`
- Interface: **SwiftUI**
- Language: **Swift**
- Use Core Data: **OFF**
- Include Tests: 任意

### 2. ソースファイルの配置

自動生成された `ContentView.swift` と `FocusBlockApp.swift` を**削除**し、このディレクトリの全 `.swift` ファイルをプロジェクトに追加：

```
FocusBlockApp.swift
AppDelegate.swift
FocusSessionManager.swift
AllowedSitesStore.swift
MathGridModel.swift
ProxyServer.swift
NetworkBlocker.swift
Views/MainMenuView.swift
Views/SettingsView.swift
Views/MathChallengeView.swift
```

Xcode の Project Navigator で右クリック → "Add Files to FocusBlock..." で選択。

### 3. Info.plist の設定

プロジェクト設定 → Target → Info タブで以下を確認・追加：

| Key | Value |
|-----|-------|
| `Application is agent (UIElement)` | `YES` |
| `Minimum system version` | `15.0` |

または `Info.plist` ファイルを直接置き換え。

### 4. Signing & Capabilities

- "Automatically manage signing" を **有効**
- Team を選択（個人の Apple ID でOK。無料アカウントでも動作する）
- App Sandbox は **OFF**（`networksetup` コマンドとプロキシサーバーに必要）

```
Target > Signing & Capabilities > App Sandbox のチェックを外す
```

> **重要**: App Sandbox が有効だと `networksetup` とプロキシサーバーのポート待受が機能しません。

### 5. ビルド & 実行

`Cmd + R` でビルド・起動。初回はセキュリティ警告が出る場合があります：
```
システム環境設定 > プライバシーとセキュリティ > 「このまま開く」をクリック
```

---

## 使い方

### 許可サイトの設定（セッション開始前に実施）

1. メニューバーの目のアイコンをクリック
2. 「設定」ボタンをクリック
3. `example.com` のようにドメインを入力して「追加」
4. サブドメイン込みで一致（`*.example.com` も許可）

### フォーカスセッション開始

1. メニューバーアイコンをクリック
2. 「1時間のフォーカス開始」をクリック
3. **管理者パスワードのダイアログが表示**される → 入力して許可
4. タイマーが開始。許可サイト以外はブロックされる

### セッション解除

**方法1: 1時間待つ**（タイマーがゼロになると自動解除）

**方法2: 100マス計算**
1. メニューバーアイコン → 「100マス計算で解除」
2. 10×10 のグリッドが表示される
3. 左端の数字 ＋ 上端の数字 = の答えを全マス入力
4. 全100問正解で自動解除

---

## トラブルシューティング

### プロキシが設定されたまま残った場合

```bash
# ターミナルで手動解除
networksetup -setwebproxystate Wi-Fi off
networksetup -setsecurewebproxystate Wi-Fi off
```

インターフェース名は `networksetup -listallnetworkservices` で確認。

### ポート 58080 が使用中のエラー

他のアプリがポート 58080 を使用している場合：

```bash
lsof -i :58080
```

該当プロセスを終了してから再試行。

### networksetup コマンドが失敗する

macOS のシステム整合性保護 (SIP) が有効な状態でも `networksetup` は動作するはずですが、もし失敗する場合は以下を確認：

```bash
sudo networksetup -setwebproxy Wi-Fi 127.0.0.1 58080
```

---

## アーキテクチャ

```
FocusBlockApp (@main)
  └── AppDelegate
        ├── NSStatusItem (メニューバー)
        ├── FocusSessionManager (@MainActor ObservableObject)
        │     ├── ProxyServer (actor, POSIX socket ベース、ポート58080)
        │     └── NetworkBlocker (networksetup via osascript)
        ├── AllowedSitesStore (UserDefaults 永続化)
        └── Views
              ├── MainMenuView (ポップオーバー)
              ├── SettingsView (許可サイト管理ウィンドウ)
              └── MathChallengeView (100マス計算ウィンドウ)
```
