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
    @Published var bubble: String? = "やあ！Mac のことなら何でも聞いてね"

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

    /// 裏キャラ（女の子）の論理状態と表示状態。
    @Published var girlState: GirlState = .idle
    @Published var girlDisplay: GirlState = .idle
    private var girlImages: [GirlState: NSImage] = [:]
    /// 表示すべき裏キャラ画像。
    var girlCurrentImage: NSImage? { girlImages[girlDisplay] ?? girlImages[.idle] }
    var hasGirlImages: Bool { girlImages[.idle] != nil }

    private var patMonitorGlobal: Any?
    private var patMonitorLocal: Any?
    private var girlTimer: Timer?
    private var mouseHistory: [(p: NSPoint, t: Double)] = []
    private var headHoverTime: Double = 0
    private var cooldownUntil: Double = 0
    private var endUntil: Double = 0
    private var lastTick: Double = 0
    private var pamperFlip: Double = 0

    /// 裏キャラ画像フォルダ。
    static var girlDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-concierge/characters/girl")
    }

    /// なで反応の ON/OFF（既定オン）。
    var isNadeEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: "nadeReaction") == nil ? true : d.bool(forKey: "nadeReaction")
    }

    init() {
        self.config = AppConfig.load()
        let saved = UserDefaults.standard.double(forKey: scaleKey)
        if saved > 0 { dolphinScale = min(10.0, max(0.6, saved)) }
        if let raw = UserDefaults.standard.string(forKey: characterKey),
           let c = Character(rawValue: raw) {
            character = c
        }
        loadGirlImages()
        if config == nil || !(config?.hasKey ?? false) {
            bubble = "最初に API キーを設定してね（メニューバーの\(character.emoji)→「設定…」）"
        } else {
            bubble = "やあ！Mac のことなら何でも聞いてね \(character.emoji)"
        }
    }

    private func loadGirlImages() {
        for s in GirlState.allCases {
            let url = Self.girlDir.appendingPathComponent(s.fileName)
            if let img = NSImage(contentsOf: url) { girlImages[s] = img }
        }
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
            bubble = "準備OK！何でも聞いてね \(character.emoji)"
        } else {
            bubble = "API キーがまだ未設定です（\(character.emoji)→「設定…」から入力）"
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
            resetGirlState()
            startPatTracking()
            bubble = hasGirlImages
                ? "…裏モード。頭、撫でてくれてもいいんだよ？"
                : "裏キャラの画像がまだないよ。設定 →「裏キャラ」で取り込んでね。"
        } else {
            stopPatTracking()
            bubble = "\(c.emoji) になったよ"
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

    /// 裏キャラの画像（5枚: 待機/気づき/甘え/甘えループ/余韻）を取り込む。
    /// ファイル名で状態に振り分ける（noticed/waiting/pampering/pampering2/afterglowing 等）。
    func importGirlImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = true
        panel.message = "裏キャラの画像（5枚）を選んでください。ファイル名で自動振り分けします。"
        guard panel.runModal() == .OK else { return }
        let dir = Self.girlDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in panel.urls {
            let name = url.deletingPathExtension().lastPathComponent
            guard let state = GirlState.from(fileName: name) else { continue }
            let dst = dir.appendingPathComponent(state.fileName)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: url, to: dst)
        }
        loadGirlImages()
        if character == .girl {
            bubble = hasGirlImages ? nil : "うまく振り分けできなかったかも。ファイル名を確認してね。"
        }
    }

    // MARK: - 頭なでなで 状態機械（裏モード）

    private func resetGirlState() {
        girlState = .idle
        headHoverTime = 0
        cooldownUntil = 0
        mouseHistory = []
        lastTick = 0
        isBeingPatted = false
    }

    func startPatTracking() {
        guard patMonitorGlobal == nil else { return }
        patMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            DispatchQueue.main.async { self?.recordMouse() }
        }
        patMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            DispatchQueue.main.async { self?.recordMouse() }
            return e
        }
        // 20fps で状態を更新。
        girlTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickGirl() }
        }
    }

    func stopPatTracking() {
        if let m = patMonitorGlobal { NSEvent.removeMonitor(m); patMonitorGlobal = nil }
        if let m = patMonitorLocal { NSEvent.removeMonitor(m); patMonitorLocal = nil }
        girlTimer?.invalidate(); girlTimer = nil
        mouseHistory = []
    }

    private func recordMouse() {
        guard character == .girl else { return }
        mouseHistory.append((NSEvent.mouseLocation, ProcessInfo.processInfo.systemUptime))
    }

    /// 撫で状態の更新（仕様の状態機械）。
    private func tickGirl() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTick == 0 ? 0.05 : now - lastTick
        lastTick = now
        // 直近 0.4 秒の軌跡だけ残す。
        mouseHistory.removeAll { now - $0.t > 0.4 }

        // なで反応 OFF / 泳ぎ中 / 画像なし は待機に戻す。
        guard character == .girl, isNadeEnabled, hasGirlImages, !isSwimming, let window else {
            if girlState != .idle && girlState != .end { setGirlState(.idle) }
            return
        }

        let m = NSEvent.mouseLocation
        // 速度（px/sec）。
        var speed: CGFloat = 0
        if let first = mouseHistory.first, mouseHistory.count >= 2 {
            let span = now - first.t
            if span > 0.01 { speed = hypot(m.x - first.p.x, m.y - first.p.y) / CGFloat(span) }
        }
        // 頭の当たり判定（横長楕円・頭頂〜前髪あたり）。
        let f = window.frame
        let hx = f.midX, hy = f.maxY - f.height * 0.20
        let rx = f.width * 0.32, ry = f.height * 0.16
        let nx = (m.x - hx) / rx, ny = (m.y - hy) / ry
        let inZone = (nx * nx + ny * ny) <= 1
        // 頭付近での左右の揺れ（撫でっぽさ）。
        let xs = mouseHistory.map { $0.p.x }
        let xWobble = (xs.max() ?? 0) - (xs.min() ?? 0)
        let petLike = inZone && xWobble > 8 && xWobble < 140 && speed < 500

        if cooldownUntil > now, girlState != .end {
            setGirlState(.idle); headHoverTime = 0; return
        }

        switch girlState {
        case .idle:
            if inZone && speed < 400 {
                headHoverTime += dt
                if headHoverTime > 0.18 { setGirlState(.notice) }
            } else { headHoverTime = 0 }
        case .notice:
            if !inZone { setGirlState(.idle); headHoverTime = 0 }
            else if petLike || headHoverTime > 0.35 { setGirlState(.pamper); pamperFlip = 0 }
            else { headHoverTime += dt }
        case .pamper:
            if !inZone || speed > 500 { endPamper(now) }
            else { pamperFlip += dt; if pamperFlip > 0.25 { pamperFlip = 0; girlState = .pamperLoop } }
        case .pamperLoop:
            if !inZone || speed > 500 { endPamper(now) }
            else {
                // 甘え中は pamper ↔ pamperLoop の画像をゆっくり往復。
                pamperFlip += dt
                if pamperFlip > 0.5 {
                    pamperFlip = 0
                    girlDisplay = (girlDisplay == .pamperLoop) ? .pamper : .pamperLoop
                }
            }
        case .end:
            if now > endUntil { setGirlState(.idle) }
        }
        isBeingPatted = (girlState == .pamper || girlState == .pamperLoop)
    }

    private func setGirlState(_ s: GirlState) {
        girlState = s
        girlDisplay = s
        if s != .pamper && s != .pamperLoop { isBeingPatted = false }
    }

    private func endPamper(_ now: Double) {
        setGirlState(.end)
        endUntil = now + 0.5
        cooldownUntil = now + 1.5
        isBeingPatted = false
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
        // 裏モードで撫でられ中は動かない（落ち着いて甘えさせる）。
        if character == .girl && girlState != .idle { return }
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
                text: "設定が読み込めません。\(character.emoji)→「設定…」から API キーを入れてください。"))
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
