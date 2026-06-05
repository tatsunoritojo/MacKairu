import AppKit
import SwiftUI
import KairuCore

/// アプリ全体の状態。SwiftUI ビューと AppKit ウィンドウをつなぐ。
@MainActor
final class AppModel: ObservableObject {
    @Published var messages: [ChatMessage] = [] {
        didSet { applyWindowSize(animated: true) } // 太り具合が変わるのでウィンドウも追従
    }
    @Published var draft: String = ""
    @Published var isChatOpen = false
    @Published var isThinking = false
    /// 吹き出しに出す一言（アイドル時のヒントやエラー表示）。
    @Published var bubble: String? = "やあ！Mac のことなら何でも聞いてね 🐬"

    /// イルカの大きさ倍率（0.6〜2.2）。ピンチやメニューで変更。
    @Published var dolphinScale: Double = 1.0

    /// 泳ぎ中か（ヒレを大きく振る）。
    @Published var isSwimming = false
    /// 左を向いているか（泳ぐ向きで反転）。
    @Published var facingLeft = false

    private var swimTimer: Timer?
    private var chatterTimer: Timer?

    /// 常駐ウィンドウ（リサイズ・位置保存に使う）。移動は AppKit のネイティブ機能。
    weak var window: NSWindow?
    private var pinchStart: Double?

    /// 設定ウィンドウを開く（AppDelegate が実体を提供）。
    var presentSettings: (() -> Void)?

    var config: AppConfig?

    private let scaleKey = "dolphinScale"
    private let originXKey = "windowOriginX"
    private let originYKey = "windowOriginY"

    init() {
        self.config = AppConfig.load()
        let saved = UserDefaults.standard.double(forKey: scaleKey)
        if saved > 0 { dolphinScale = min(10.0, max(0.6, saved)) }
        if config == nil || !(config?.hasKey ?? false) {
            bubble = "最初に API キーを設定してね（メニューバーの🐬→「設定…」）"
        }
    }

    /// 履歴量に応じた太り具合（0〜1）。
    var fatness: Double { Fatness.level(messageCount: messages.count) }

    // MARK: - ウィンドウサイズ（イルカの倍率＋太り具合に応じて変わる）

    private var dolphinSide: CGFloat { 120 * dolphinScale * (1 + fatness * 0.25) }

    var closedSize: NSSize {
        NSSize(width: max(300, dolphinSide + 80), height: dolphinSide + 100)
    }

    var openSize: NSSize {
        NSSize(width: max(324, dolphinSide + 24), height: 380 + 8 + dolphinSide + 24 + 16)
    }

    var currentTargetSize: NSSize { isChatOpen ? openSize : closedSize }

    func reloadConfig() {
        config = AppConfig.load()
        if config?.hasKey == true {
            bubble = "準備OK！何でも聞いてね 🐬"
        } else {
            bubble = "API キーがまだ未設定です（🐬→「設定…」から入力）"
        }
    }

    func toggleChat() {
        isChatOpen.toggle()
        applyWindowSize(animated: true)
        if isChatOpen {
            bubble = nil
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func applyWindowSize(animated: Bool) {
        guard let window else { return }
        let target = currentTargetSize
        let old = window.frame
        let newFrame = NSRect(
            x: old.maxX - target.width, y: old.minY,
            width: target.width, height: target.height)
        window.setFrame(newFrame, display: true, animate: animated)
        saveOrigin()
    }

    // MARK: - サイズ変更

    func setScale(_ value: Double) {
        dolphinScale = min(10.0, max(0.6, value))
        UserDefaults.standard.set(dolphinScale, forKey: scaleKey)
        applyWindowSize(animated: true)
    }

    func pinchChanged(_ magnification: Double) {
        if pinchStart == nil { pinchStart = dolphinScale }
        let base = pinchStart ?? 1.0
        dolphinScale = min(10.0, max(0.6, base * magnification))
        applyWindowSize(animated: false)
    }

    func pinchEnded() {
        pinchStart = nil
        UserDefaults.standard.set(dolphinScale, forKey: scaleKey)
        saveOrigin()
    }

    /// 履歴をクリアしてスリムに戻す。
    func clearChat() {
        messages = []
        bubble = nil
    }

    // MARK: - いたずら（おせっかいモード）

    /// 未設定なら既定オン。
    var isAnnoyEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: "annoyMode") == nil ? true : d.bool(forKey: "annoyMode")
    }

    private static let quips = [
        "保存した？ ⌘S だよ。",
        "ちょっと休憩したら？",
        "Spotlight は ⌘Space で開くよ。",
        "Windows が恋しくなってない？",
        "スクショは ⌘⇧4 で範囲選択だよ。",
        "水分とってる？",
        "⌘Q で僕を消せるけど…消さないよね？",
        "Finder で困ったら聞いてね。",
        "アプリ切り替えは ⌘Tab。Alt+Tab じゃないよ。",
        "今日もおつかれさま。",
        "ねえ、見て見て。",
        "僕の話、聞いてる？",
        "右クリックは二本指タップでもできるよ。",
        "そろそろ画面、見すぎじゃない？",
        "ねえねえ、ひまなの？",
        "ゴミ箱は ⌘Delete だよ。",
        "あ、今いいところだった？ごめんね。",
        "デスクトップ散らかってない？",
        "バックアップは Time Machine でね。",
        "僕、消されてもまた来るからね。",
    ]

    /// 泳ぎ・話しかけのタイマーを開始する。
    func startMischief() {
        scheduleSwim()
        scheduleChatter()
    }

    private func scheduleSwim() {
        swimTimer?.invalidate()
        let delay = Double.random(in: 7...16) // 頻度アップ
        swimTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.swim(); self?.scheduleSwim() }
        }
    }

    /// 画面内のランダムな位置へ、すーっと泳いで移動する（移動距離大きめ）。
    private func swim() {
        guard isAnnoyEnabled, !isChatOpen, !isThinking,
              let window, let screen = window.screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let size = window.frame.size
        let from = window.frame.origin

        // 移動距離はイルカの大きさに比例（大きいほど遠くへ大きく泳ぐ）。
        let reach = max(300, dolphinSide * 1.2)
        let angle = Double.random(in: 0 ..< (2 * .pi))
        let mag = CGFloat.random(in: reach * 0.4 ... reach)
        let dx = CGFloat(cos(angle)) * mag
        let dy = CGFloat(sin(angle)) * mag

        // 中心座標で扱い、画面±margin に収める（大きいほど画面外まで遠征するが見失わない範囲）。
        let margin = dolphinSide * 0.5
        var cx = from.x + size.width / 2 + dx
        var cy = from.y + size.height / 2 + dy
        cx = min(max(cx, v.minX - margin), v.maxX + margin)
        cy = min(max(cy, v.minY - margin), v.maxY + margin)
        let x = cx - size.width / 2
        let y = cy - size.height / 2

        // 距離に応じて泳ぎ時間を決める（近いとサッ、遠いと少し長め）。
        let dist = hypot(x - from.x, y - from.y)
        let duration = min(4.0, max(1.0, Double(dist) / 600))

        facingLeft = x < from.x
        isSwimming = true
        // animator は frame ならアニメーションする（setFrameOrigin は効かない）。
        let target = NSRect(x: x, y: y, width: size.width, height: size.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isSwimming = false
                self?.facingLeft = false
                self?.persistPosition()
            }
        })
    }

    private func scheduleChatter() {
        chatterTimer?.invalidate()
        let delay = Double.random(in: 30...70) // 頻度アップ
        chatterTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.sayRandomQuip(); self?.scheduleChatter() }
        }
    }

    private func sayRandomQuip() {
        guard isAnnoyEnabled, !isChatOpen else { return }
        bubble = Self.quips.randomElement()
        // 数秒で引っ込める。
        Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.isChatOpen == false { self?.bubble = nil }
            }
        }
    }

    // MARK: - メッセージ送信

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))

        // ネットミーム: 「お前を消す方法」と尋ねられたら、自分自身を消す。
        // API キー未設定でも動く（AI に送る前に処理）。
        if SelfDestruct.isTriggered(by: text) {
            messages.append(ChatMessage(role: .assistant,
                text: "「お前を消す方法」について調べました。\n……さようなら。"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { KairuQuit.now() }
            return
        }

        guard let config else {
            messages.append(ChatMessage(role: .assistant,
                text: "設定が読み込めません。🐬→「設定…」から API キーを入れてください。"))
            return
        }
        isThinking = true
        let client = AIClient(config: config)
        let history = messages
        Task {
            do {
                let reply = try await client.send(history: history)
                self.messages.append(ChatMessage(role: .assistant, text: reply))
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.messages.append(ChatMessage(role: .assistant, text: "⚠️ \(msg)"))
            }
            self.isThinking = false
        }
    }

    // MARK: - 位置の永続化

    func persistPosition() { saveOrigin() }

    private func saveOrigin() {
        guard let origin = window?.frame.origin else { return }
        UserDefaults.standard.set(origin.x, forKey: originXKey)
        UserDefaults.standard.set(origin.y, forKey: originYKey)
    }

    var savedOrigin: NSPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: originXKey) != nil, d.object(forKey: originYKey) != nil else { return nil }
        return NSPoint(x: d.double(forKey: originXKey), y: d.double(forKey: originYKey))
    }
}
