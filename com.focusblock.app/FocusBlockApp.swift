import SwiftUI
import AppKit

@main
struct FocusBlockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // メニューバーアプリなのでウィンドウシーンは不要
        // Settings {} も AppDelegate 側で NSWindow を直接管理するため省略
    }
}
