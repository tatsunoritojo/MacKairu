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

    /// 表示中のキャラクター。
    @Published var character: Character = .dolphin
    /// 裏モードで頭を撫でられている最中か。
    @Published var isBeingPatted = false
    /// キャラ変更を AppDelegate に伝える（メニューバー絵文字の更新など）。
    var onCharacterChanged: ((Character) -> Void)?

    /// イルカの大きさ倍率（0.6〜2.2）。ピンチやメニューで変更。
    @Published var dolphinScale: Double = 1.0

    /// 取り込み中の文脈（クリップボードのテキスト）。
    @Published var pendingText: String?
    /// 取り込み中の画像（スクショ等）。
    @Published var pendingImage: ImageAttachment?
    /// 取り込み画像のサムネ表示用。
    @Published var pendingImagePreview: NSImage?
    /// スクショ撮影中フラグ。
    @Published var isCapturing = false

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
    private let characterKey = "character"

    /// 裏キャラの画像（AI で用意した PNG）。
    @Published var girlImage: NSImage?
    private var patMonitorGlobal: Any?
    private var patMonitorLocal: Any?
    private var lastPatMouse: NSPoint?
    private var patResetWork: DispatchWorkItem?

    /// 裏キャラ画像の保存先。
    static var girlImageURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-concierge/characters/girl.png")
    }

    init() {
        self.config = AppConfig.load()
        let saved = UserDefaults.standard.double(forKey: scaleKey)
        if saved > 0 { dolphinScale = min(10.0, max(0.6, saved)) }
        if let raw = UserDefaults.standard.string(forKey: characterKey),
           let c = Character(rawValue: raw) {
            character = c
        }
        loadGirlImage()
        if config == nil || !(config?.hasKey ?? false) {
            bubble = "最初に API キーを設定してね（メニューバーの🐬→「設定…」）"
        }
    }

    private func loadGirlImage() {
        if let img = NSImage(contentsOf: Self.girlImageURL) { girlImage = img }
    }

    /// 履歴量に応じた太り具合（0〜1）。裏キャラは太らない。
    var fatness: Double {
        character == .girl ? 0 : Fatness.level(messageCount: messages.count)
    }

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

    // MARK: - キャラクター / 裏モード

    func setCharacter(_ c: Character) {
        character = c
        UserDefaults.standard.set(c.rawValue, forKey: characterKey)
        onCharacterChanged?(c)
        if c == .girl {
            startPatTracking()
            if girlImage == nil {
                bubble = "裏キャラの画像がまだないよ。設定 →「裏キャラ」で用意してね。"
            }
        } else {
            stopPatTracking()
            isBeingPatted = false
        }
        applyWindowSize(animated: true)
    }

    /// チャットの「裏モード」呪文でトグル。
    private func toggleSecretMode() {
        let goingSecret = character != .girl
        setCharacter(goingSecret ? .girl : .dolphin)
        messages.append(ChatMessage(role: .assistant,
            text: goingSecret ? "…裏モード。頭、撫でてくれてもいいんだよ？"
                              : "通常モードに戻すね。"))
    }

    /// 裏キャラ画像を差し替える（自分で用意した PNG を選ぶ）。
    func chooseGirlImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.message = "裏キャラに使う画像（透過PNG推奨）を選んでください"
        guard panel.runModal() == .OK, let src = panel.url else { return }
        saveGirlImage(from: src)
    }

    private func saveGirlImage(from src: URL) {
        let dst = Self.girlImageURL
        try? FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: src, to: dst)
        loadGirlImage()
        if character == .girl { bubble = nil }
    }

    /// OpenAI の画像生成で裏キャラを作る（OpenAI キー使用時のみ）。
    func generateGirlImage() {
        guard let config, config.provider == .openai, config.hasKey else {
            bubble = "AI生成は OpenAI キーが必要。ChatGPT/Gemini で作って「画像を選ぶ」でもOK。"
            return
        }
        bubble = "裏キャラを生成中…"
        let key = config.apiKey
        Task {
            if let data = await Self.openAIImage(key: key) {
                let dst = Self.girlImageURL
                try? FileManager.default.createDirectory(
                    at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: dst)
                self.loadGirlImage()
                self.bubble = nil
            } else {
                self.bubble = "生成に失敗。ChatGPT/Gemini で作って「画像を選ぶ」を試してね。"
            }
        }
    }

    private static func openAIImage(key: String) async -> Data? {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": "gpt-image-1",
            "prompt": "A cute chibi anime girl mascot, full body, friendly smile, "
                + "flat simple illustration, centered, transparent background, no text.",
            "size": "1024x1024",
            "background": "transparent",
            "n": 1,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]],
              let b64 = arr.first?["b64_json"] as? String,
              let imgData = Data(base64Encoded: b64) else { return nil }
        return imgData
    }

    // MARK: - 頭なでなで（裏モード）

    func startPatTracking() {
        guard patMonitorGlobal == nil else { return }
        patMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            DispatchQueue.main.async { self?.handleMouseMoved() }
        }
        patMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            DispatchQueue.main.async { self?.handleMouseMoved() }
            return e
        }
    }

    func stopPatTracking() {
        if let m = patMonitorGlobal { NSEvent.removeMonitor(m); patMonitorGlobal = nil }
        if let m = patMonitorLocal { NSEvent.removeMonitor(m); patMonitorLocal = nil }
        lastPatMouse = nil
    }

    private func handleMouseMoved() {
        guard character == .girl, let window else { return }
        let m = NSEvent.mouseLocation
        let f = window.frame
        // 頭の領域 = ウィンドウ上部。
        let head = NSRect(x: f.minX, y: f.minY + f.height * 0.45,
                          width: f.width, height: f.height * 0.55)
        guard head.contains(m) else { lastPatMouse = m; return }
        if let last = lastPatMouse, hypot(m.x - last.x, m.y - last.y) > 2 {
            isBeingPatted = true
            patResetWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.isBeingPatted = false }
            patResetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }
        lastPatMouse = m
    }

    // MARK: - 文脈の取り込み（クリップボード／スクショ）

    /// クリップボードを取り込む（テキスト優先、なければ画像）。
    func attachClipboard() {
        let pb = NSPasteboard.general
        if let s = pb.string(forType: .string),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingText = s
            pendingImage = nil
            pendingImagePreview = nil
            bubble = nil
        } else if let img = NSImage(pasteboard: pb), let b64 = Self.pngBase64(img) {
            pendingImage = ImageAttachment(base64: b64, mediaType: "image/png")
            pendingImagePreview = img
            pendingText = nil
        } else {
            bubble = "クリップボードに取り込める内容がありません"
        }
    }

    /// スクショ撮影を起動（範囲ドラッグ）。撮ったら画像として取り込む。
    func captureScreenshot() {
        guard !isCapturing else { return }
        isCapturing = true
        let path = NSTemporaryDirectory() + "kairu_capture.png"
        // 自分のUIを写さないよう、撮影中はパネルを隠す。
        window?.orderOut(nil)
        DispatchQueue.global().async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-x", path]
            try? p.run()
            p.waitUntilExit()
            let data = p.terminationStatus == 0
                ? try? Data(contentsOf: URL(fileURLWithPath: path)) : nil
            try? FileManager.default.removeItem(atPath: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.window?.orderFrontRegardless()
                self.isCapturing = false
                // キャンセル（Esc）時は data が nil。
                guard let data, let img = NSImage(data: data) else { return }
                self.pendingText = nil
                self.pendingImage = ImageAttachment(base64: data.base64EncodedString(),
                                                    mediaType: "image/png")
                self.pendingImagePreview = img
                self.isChatOpen = true
                self.applyWindowSize(animated: true)
                NSApp.activate(ignoringOtherApps: true)
                self.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// 取り込み中の文脈を破棄。
    func clearPending() {
        pendingText = nil
        pendingImage = nil
        pendingImagePreview = nil
    }

    /// 取り込み中の文脈があるか。
    var hasContext: Bool { pendingText != nil || pendingImage != nil }

    /// クイック操作（プリセット指示を入れて送信）。
    func quickAction(_ prompt: String) {
        draft = prompt
        send()
    }

    private static func pngBase64(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
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
        if character == .girl { startPatTracking() }
    }

    private func scheduleSwim() {
        swimTimer?.invalidate()
        let delay = Double.random(in: 7...16) // 頻度アップ
        swimTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.swim(); self?.scheduleSwim() }
        }
    }

    /// すーっと泳いで移動する。約20%の確率でマウスカーソルの位置へ寄ってくる。
    private func swim() {
        guard isAnnoyEnabled, !isChatOpen, !isThinking,
              let window, let screen = window.screen ?? NSScreen.main else { return }
        let size = window.frame.size
        let from = window.frame.origin
        let margin = dolphinSide * 0.5

        // 裏モードは100%カーソルへ。通常は20%。
        let goToCursor = character == .girl ? true : (Double.random(in: 0 ..< 1) < 0.2)
        let targetScreen: NSScreen
        var cx: CGFloat
        var cy: CGFloat
        if goToCursor {
            let mouse = NSEvent.mouseLocation // 画面座標（左下原点・frameと同じ系）
            targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? screen
            cx = mouse.x
            cy = mouse.y
        } else {
            targetScreen = screen
            // 移動距離はイルカの大きさに比例（大きいほど遠くへ）。
            let reach = max(300, dolphinSide * 1.2)
            let angle = Double.random(in: 0 ..< (2 * .pi))
            let mag = CGFloat.random(in: reach * 0.4 ... reach)
            cx = from.x + size.width / 2 + CGFloat(cos(angle)) * mag
            cy = from.y + size.height / 2 + CGFloat(sin(angle)) * mag
        }

        // 中心座標を画面±margin に収める（見失わない範囲で画面外まで遠征可）。
        let v = targetScreen.visibleFrame
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
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // 取り込み中の文脈があれば、入力が空でも送れる（クイック操作用）。
        guard (!typed.isEmpty || hasContext), !isThinking else { return }
        draft = ""

        // ネットミーム: 「お前を消す方法」（文脈の有無に関わらず生入力で判定）。
        if SelfDestruct.isTriggered(by: typed) {
            messages.append(ChatMessage(role: .user, text: typed))
            messages.append(ChatMessage(role: .assistant,
                text: "「お前を消す方法」について調べました。\n……さようなら。"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { KairuQuit.now() }
            return
        }

        // 裏モードの呪文。
        if SecretMode.isTriggered(by: typed) {
            messages.append(ChatMessage(role: .user, text: typed))
            toggleSecretMode()
            clearPending()
            return
        }

        // 取り込んだテキスト／画像を、ユーザーメッセージに合成する。
        var text = typed
        if let ctx = pendingText {
            let q = typed.isEmpty ? "これについて教えて。" : typed
            text = "次のテキストについて、\(q)\n\n\"\"\"\n\(ctx)\n\"\"\""
        } else if pendingImage != nil, typed.isEmpty {
            text = "この画面について、何ができるか・どう操作するか教えて。"
        }
        let image = pendingImage
        messages.append(ChatMessage(role: .user, text: text, image: image))
        clearPending()

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
