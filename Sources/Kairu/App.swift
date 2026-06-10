import AppKit
import SwiftUI
import KairuCore

/// アプリのどこからでも呼べる、確実な終了処理。
/// `NSApp.terminate` が何かに阻まれても保険の `exit()` で必ずプロセスを落とす。
enum KairuQuit {
    /// おせっかい（うざ）モードが有効か。未設定なら既定オン。
    @MainActor static var isAnnoyEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: "annoyMode") == nil ? true : d.bool(forKey: "annoyMode")
    }

    /// 直接終了（メメの「お前を消す方法」など、確認なしで消えるべき経路用）。
    @MainActor static func now() {
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(EXIT_SUCCESS) }
    }

    /// しつこい引き止めつき終了（メニュー・⌘Q・ボタン用）。
    @MainActor static func request() {
        guard isAnnoyEnabled else { now(); return }
        NSApp.activate(ignoringOtherApps: true)

        let steps: [(String, String, String)] = [
            ("本当に消すの…？", "僕、Mac のことなら何でも教えるのに…", "消す"),
            ("ほんとに…？さみしいよ…", "もう一回だけ考え直してくれない？", "それでも消す"),
            ("……わかった。最後にひとつだけ。", "また呼んでくれる？（15分後にこっそり戻るけどね）", "さようなら"),
        ]
        let cancelTitle = "やっぱりやめる"
        for (title, info, confirmTitle) in steps {
            let a = NSAlert()
            a.messageText = title
            a.informativeText = info
            // 「消す」と「やめる」の位置とデフォルト(Enter)をランダムに入れ替える。
            // → 同じ場所を連打しても約半々で「やめる」に当たり、消えない。
            let confirmFirst = Bool.random()
            if confirmFirst {
                a.addButton(withTitle: confirmTitle)
                a.addButton(withTitle: cancelTitle)
            } else {
                a.addButton(withTitle: cancelTitle)
                a.addButton(withTitle: confirmTitle)
            }
            let resp = a.runModal()
            let confirmed = confirmFirst
                ? (resp == .alertFirstButtonReturn)
                : (resp == .alertSecondButtonReturn)
            guard confirmed else { return }
        }
        now()
    }
}

/// 最前面に浮かぶ、フォーカスを奪わないパネル。
/// borderless でもテキスト入力できるよう canBecomeKey を許可する。
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var panel: FloatingPanel!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var quitMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = model.closedSize
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // 背景ドラッグでネイティブ移動。裏キャラだけは自前でカーソル追従するため後で切り替える。
        panel.isMovableByWindowBackground = (model.character != .girl)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: RootView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        model.window = panel

        if let saved = model.savedOrigin {
            panel.setFrameOrigin(saved)
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - size.width - 20, y: v.minY + 20))
        }
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification, object: panel)

        model.presentSettings = { [weak self] in self?.openSettings() }
        model.onCharacterChanged = { [weak self] c in
            self?.statusItem?.button?.title = c.emoji
        }

        setupMainMenu()
        setupQuitMonitor()
        setupStatusItem()
        setupResurrection()
        model.startMischief() // 勝手に泳ぐ・話しかける
        model.startScrollResize() // チャット入力待ち中、キャラ上スクロールでサイズ調整
    }

    /// 「15分ごとに復活」を初回は既定オンで有効化。以降は現在のアプリパスへ更新。
    private func setupResurrection() {
        let key = "resurrectInitialized"
        let d = UserDefaults.standard
        if !d.bool(forKey: key) {
            LaunchAgent.enable() // 初回: 既定オン
            d.set(true, forKey: key)
        } else if LaunchAgent.isEnabled {
            LaunchAgent.enable() // パスが変わっている場合に追従
        }
    }

    // MARK: - 終了（最優先で処理）

    /// 終了「お前を消す方法」をメインメニュー（最優先コマンド）に登録。
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    /// ⌘Q をアプリ最上位で横取り。入力欄（SecureField 等）より先に処理する。
    private func setupQuitMonitor() {
        quitMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "q" {
                DispatchQueue.main.async { KairuQuit.request() }
                return nil
            }
            return event
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    @objc private func quit() { KairuQuit.request() }

    // MARK: - メニューバー

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = model.character.emoji
        let menu = NSMenu()
        menu.autoenablesItems = false // 常に有効（無効化で押せない事故を防ぐ）

        addItem(to: menu, "MacKairu を表示", #selector(showDolphin))

        // キャラクター切替（裏キャラは除く）
        let charItem = NSMenuItem(title: "キャラクター", action: nil, keyEquivalent: "")
        let charMenu = NSMenu()
        charMenu.autoenablesItems = false
        for c in Character.selectable {
            let item = NSMenuItem(title: "\(c.emoji) \(c.label)",
                                  action: #selector(changeCharacter(_:)), keyEquivalent: "")
            item.representedObject = c.rawValue
            item.target = self
            charMenu.addItem(item)
        }
        charItem.submenu = charMenu
        menu.addItem(charItem)

        let sizeItem = NSMenuItem(title: "サイズ", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        sizeMenu.autoenablesItems = false
        for (label, value) in [("小", 0.8), ("中（標準）", 1.0), ("大", 1.4), ("特大", 1.8),
                               ("巨大", 4.0), ("超巨大（10倍）", 10.0)] {
            let item = NSMenuItem(title: label, action: #selector(changeSize(_:)), keyEquivalent: "")
            item.representedObject = value
            item.target = self
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(.separator())
        addItem(to: menu, "設定…（API キー）", #selector(openSettings), key: ",")
        addItem(to: menu, "設定ファイルを開く（上級者向け）", #selector(openConfig))
        addItem(to: menu, "設定を再読み込み", #selector(reloadConfig), key: "r")
        menu.addItem(.separator())
        // ⌘Q はメインメニュー側に集約し、ここはクリック専用（キー重複を避ける）。
        // ※「お前を消す方法」のメメは、チャット入力欄にその語を打つと発動する。
        addItem(to: menu, "終了", #selector(quit))
        statusItem.menu = menu
    }

    /// target を明示してメニュー項目を追加する小ヘルパー。
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        menu.addItem(item)
    }

    @objc private func showDolphin() { panel.orderFrontRegardless() }

    @objc private func changeSize(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double { model.setScale(value) }
    }

    @objc private func changeCharacter(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let c = Character(rawValue: raw) {
            model.setCharacter(c)
            panel.orderFrontRegardless()
        }
    }

    @objc private func openConfig() {
        AppConfig.writeExampleIfNeeded()
        NSWorkspace.shared.open(AppConfig.fileURL)
    }

    @objc private func reloadConfig() {
        model.reloadConfig()
        panel.orderFrontRegardless()
    }

    @objc private func windowMoved() { model.persistPosition() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            w.title = "MacKairu 設定"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(
                rootView: SettingsView(model: model,
                                       onSaved: { [weak self] in self?.settingsWindow?.close() }))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

@main
struct KairuApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
