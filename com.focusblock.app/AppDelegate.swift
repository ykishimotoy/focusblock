import AppKit
import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?
    private var mathWindow: NSWindow?
    private var promptWindow: NSWindow?

    let sessionManager = FocusSessionManager()
    let allowedSitesStore = AllowedSitesStore()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SIGPIPE を無視する（ソケット書き込み先が閉じられても強制終了しないように）
        signal(SIGPIPE, SIG_IGN)

        // 前の起動インスタンスを終了させてポートを解放する
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0 != NSRunningApplication.current }
        for app in others { app.terminate() }
        if !others.isEmpty { Thread.sleep(forTimeInterval: 0.6) }

        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        registerLoginItem()
        setupWakeNotification()

        sessionManager.onTick = { [weak self] in self?.updateStatusItemTitle() }
        sessionManager.onStateChange = { [weak self] in
            self?.updateStatusItemTitle()
            self?.handleStateChange()
        }

        // ProxyServer起動 + 初回のみシステムプロキシ設定（管理者パスワード）
        Task {
            do {
                try await sessionManager.initialize()
            } catch {
                await MainActor.run { self.showError(error.localizedDescription) }
            }
            // 起動後に許可サイト確認プロンプトを表示
            await MainActor.run { self.showPromptWindow() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionManager.forceStop()
    }

    /// セッション中は終了を拒否する
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if sessionManager.isActive {
            showError("フォーカスセッション中はアプリを終了できません。\n解除するには100マス計算を解くか、1時間待ってください。")
            return .terminateCancel
        }
        return .terminateNow
    }

    // MARK: - Login Item（Mac起動時の自動起動）

    private func registerLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            guard service.status != .enabled else { return }
            do {
                try service.register()
                print("[AppDelegate] login item registered")
            } catch {
                print("[AppDelegate] login item registration failed: \(error)")
            }
        }
    }

    // MARK: - Sleep Wake

    private func setupWakeNotification() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.sessionManager.isActive {
                // セッション中はそのまま継続（何もしない）
                return
            }
            // アイドル状態ならアプリを再起動してフレッシュな状態で起動
            self.relaunchApp()
        }
    }

    private func relaunchApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [bundlePath]
        try? task.run()
        // 新プロセスが起動し始めてから現プロセスを終了
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = menuBarImage()
        button.imagePosition = .imageLeading
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func menuBarImage() -> NSImage? {
        if let img = NSImage(named: "tomato") ?? loadTomatoFromBundle() {
            let resized = NSImage(size: NSSize(width: 18, height: 18))
            resized.lockFocus()
            img.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            resized.unlockFocus()
            resized.isTemplate = false
            return resized
        }
        return NSImage(systemSymbolName: "eye", accessibilityDescription: "FocusBlock")
    }

    private func loadTomatoFromBundle() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "tomato", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        DispatchQueue.main.async {
            switch self.sessionManager.state {
            case .active, .unlocking:
                button.title = " \(self.sessionManager.remainingTimeString)"
            default:
                button.title = ""
            }
        }
    }

    private func handleStateChange() {
        DispatchQueue.main.async {
            switch self.sessionManager.state {
            case .unlocking:
                self.showMathWindow()
            case .idle:
                self.mathWindow?.close()
                self.mathWindow = nil
                self.showPromptWindow()   // セッション終了時にプロンプト表示
            default:
                break
            }
        }
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if let p = popover, p.isShown { closePopover() } else { openPopover(sender) }
    }

    private func openPopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            let p = NSPopover()
            p.contentSize = NSSize(width: 300, height: 380)
            p.behavior = .transient
            p.contentViewController = NSHostingController(
                rootView: MainMenuView(onOpenSettings: { [weak self] in self?.openSettings() })
                    .environmentObject(sessionManager)
                    .environmentObject(allowedSitesStore)
            )
            popover = p
        }
        popover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        DispatchQueue.main.async {
            self.popover?.contentViewController?.view.window?.collectionBehavior =
                [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        NSApp.activate(ignoringOtherApps: true)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.closePopover() }
    }

    private func closePopover() {
        popover?.performClose(nil)
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - Session Start on Window Close

    /// ウィンドウが閉じられたら即座にセッション開始（アイドル時のみ）
    private func startSessionIfIdle() {
        guard sessionManager.state == .idle else { return }
        Task {
            try? await sessionManager.startSession(allowedHosts: allowedSitesStore.hostsSet)
        }
    }

    /// NSWindow に close 通知を登録する（重複登録を防ぐため毎回新規ウィンドウに対してのみ呼ぶ）
    private func observeWindowClose(_ window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.startSessionIfIdle()
        }
    }

    // MARK: - Settings Window

    func openSettings() {
        if settingsWindow == nil || !(settingsWindow?.isVisible ?? false) {
            let vc = NSHostingController(rootView: SettingsView().environmentObject(allowedSitesStore))
            let w = NSWindow(contentViewController: vc)
            w.title = "許可サイト設定"
            w.setContentSize(NSSize(width: 420, height: 380))
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            observeWindowClose(w)   // 閉じたらセッション開始
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Allowed Sites Prompt（起動時・スリープ復帰時・セッション終了時）

    func showPromptWindow() {
        guard !sessionManager.isActive else { return }

        if promptWindow == nil || !(promptWindow?.isVisible ?? false) {
            let vc = NSHostingController(
                rootView: AllowedSitesPromptView(onClose: { [weak self] in
                    self?.promptWindow?.close()   // close → willCloseNotification → startSessionIfIdle
                }).environmentObject(allowedSitesStore)
            )
            let w = NSWindow(contentViewController: vc)
            w.title = "FocusBlock — 許可サイトの確認"
            w.setContentSize(NSSize(width: 420, height: 420))
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            observeWindowClose(w)   // ×ボタンでも閉じたらセッション開始
            promptWindow = w
        }
        promptWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Math Challenge Window

    private func showMathWindow() {
        if mathWindow == nil || !(mathWindow?.isVisible ?? false) {
            let model = MathGridModel()
            model.onCompleted = { [weak self] in
                Task { await self?.sessionManager.completeMathChallenge() }
            }
            let vc = NSHostingController(
                rootView: MathChallengeView(model: model).environmentObject(sessionManager)
            )
            let w = NSWindow(contentViewController: vc)
            w.title = "100マス計算 — フォーカスを解除するには全問正解してください"
            w.setContentSize(NSSize(width: 520, height: 560))
            w.styleMask = [.titled, .resizable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            mathWindow = w
        }
        mathWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Error Alert

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "FocusBlock"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
