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
    /// 「お前を消す方法」で消される最中（悲しくフェードアウト中）。
    @Published var girlDying = false
    private var girlImages: [GirlState: NSImage] = [:]
    /// 表示すべき裏キャラ画像。未配置の状態はフォールバック連鎖で近い既存画像に代替する。
    var girlCurrentImage: NSImage? {
        for s in girlDisplay.imageChain {
            if let img = girlImages[s] { return img }
        }
        return girlImages[.idle]
    }
    var hasGirlImages: Bool { girlImages[.idle] != nil }

    private var patMonitorGlobal: Any?
    private var patMonitorLocal: Any?
    private var girlTimer: Timer?
    private var mouseHistory: [(p: NSPoint, t: Double)] = []
    private var lastTick: Double = 0
    /// 頭なで状態機械（純粋ロジックは KairuCore 側）。
    private var pettingMachine = PettingMachine()
    /// 掴み（左ボタン保持）の追跡。mouseDown/Up/Dragged イベントで即時更新する。
    private var isHeld = false
    private var heldStart: Double = 0
    private var didDrag = false
    private var lastDragTime: Double = 0
    /// 掴み表示までの遅延（秒）。短いほど反応が良い。クリックでチャットを開く誤爆を弾く最小限。
    private let holdShowDelay: Double = 0.08
    /// 左ボタンのイベント監視（掴み/ドラッグ検出）。
    private var btnMonitorGlobal: Any?
    private var btnMonitorLocal: Any?
    /// 振り回し量の累積（方向転換×移動量）。閾値超で目を回す。
    private var whirlScore: Double = 0
    private var lastWhirlPos: NSPoint?
    private var lastWhirlAngle: Double?
    private let whirlThreshold: Double = 9      // これを超えて振り回されると目を回す
    private let whirlDecayPerSec: Double = 2.5   // 振り回しが穏やかだと冷める速さ
    /// 目を回している残り時間（秒）と表情往復用フェーズ。
    private var dizzyTimer: Double = 0
    private var dizzyPhase: Double = 0
    private let dizzyDuration: Double = 2.6
    private let dizzyFlip: Double = 0.28         // dizzy↔dizzy2 の往復間隔

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
            // 1) ユーザーが取り込んだ上書き（config）→ 2) プロジェクト同梱（バンドル）。
            let override = Self.girlDir.appendingPathComponent(s.fileName)
            if let img = NSImage(contentsOf: override), Self.isTransparent(img) {
                girlImages[s] = img
            } else if let url = Bundle.main.resourceURL?
                .appendingPathComponent("girl/\(s.fileName)"),
                let img = NSImage(contentsOf: url), Self.isTransparent(img) {
                girlImages[s] = img
            }
        }
    }

    /// 透過アルファを持つ画像か。背景が不透明な画像は白box事故になるので採用しない（フォールバックさせる）。
    private static func isTransparent(_ img: NSImage) -> Bool {
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return false }
        return rep.hasAlpha
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
        // 裏キャラはドラッグ時にカーソル位置へ自前追従するので、ネイティブ背景ドラッグは切る。
        window?.isMovableByWindowBackground = (c != .girl)
        if c == .girl {
            resetGirlState()
            startPatTracking()
            maybeGreet() // 初めて POIN が現れた時だけ挨拶
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

    /// 裏キャラの画像（最大12枚: 待機/遠待機2/駆け出し2/気づき/甘え2/掴み/ドラッグ/余韻/悲しみ）を取り込む。
    /// ファイル名で状態に振り分ける（idle/rest/doze/run/run2/notice/pamper/pamperLoop/hold/drag/end/sad 等）。
    func importGirlImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = true
        panel.message = "裏キャラの画像を選んでください（最大12枚）。ファイル名で自動振り分けします。"
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
        pettingMachine.reset()
        girlState = .idle
        girlDisplay = .idle
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
        // 掴み/ドラッグはイベント駆動で即時検出（ポーリングのラグを無くす）。
        let btnMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        btnMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: btnMask) { [weak self] e in
            Task { @MainActor in self?.handleMouseButton(e) }
        }
        btnMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: btnMask) { [weak self] e in
            Task { @MainActor in self?.handleMouseButton(e) }
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
        if let m = btnMonitorGlobal { NSEvent.removeMonitor(m); btnMonitorGlobal = nil }
        if let m = btnMonitorLocal { NSEvent.removeMonitor(m); btnMonitorLocal = nil }
        girlTimer?.invalidate(); girlTimer = nil
        mouseHistory = []
        isHeld = false; didDrag = false
    }

    private func recordMouse() {
        guard character == .girl else { return }
        mouseHistory.append((NSEvent.mouseLocation, ProcessInfo.processInfo.systemUptime))
    }

    /// 左ボタンのイベントを掴み/ドラッグに変換する。
    private func handleMouseButton(_ e: NSEvent) {
        guard character == .girl, hasGirlImages else { return }
        switch e.type {
        case .leftMouseDown:
            // チャットを開いている時の入力操作は掴み扱いしない。
            guard !isChatOpen, let window else { return }
            // キャラのウィンドウ上で押した時だけ掴み開始（即時）。
            if window.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
                isHeld = true
                heldStart = ProcessInfo.processInfo.systemUptime
                didDrag = false
                whirlScore = 0
                lastWhirlPos = NSEvent.mouseLocation
                lastWhirlAngle = nil
            }
        case .leftMouseDragged:
            guard isHeld else { return }
            // 移動が起きて初めて「ドラッグ」。ここからカーソル位置へ追従させる。
            didDrag = true
            lastDragTime = ProcessInfo.processInfo.systemUptime
            accumulateWhirl(NSEvent.mouseLocation)
            followDragToCursor()
        case .leftMouseUp:
            if isHeld {
                isHeld = false; didDrag = false; saveOrigin()
                // 振り回しが一定以上なら、手を離したあとふらふら目を回す。
                if whirlScore > whirlThreshold { dizzyTimer = dizzyDuration; dizzyPhase = 0 }
                whirlScore = 0; lastWhirlPos = nil; lastWhirlAngle = nil
            }
        default:
            break
        }
    }

    /// ドラッグ中、画像内に描かれたカーソル先端が現実のマウスに重なるようウィンドウを再配置する。
    private func followDragToCursor() {
        guard let window,
              let anchor = girlDisplay.cursorAnchor ?? GirlState.drag.cursorAnchor,
              let img = girlImages[.drag] ?? girlCurrentImage else { return }
        let mouse = NSEvent.mouseLocation
        let side = dolphinSide                       // 裏キャラの一辺（fat=0）
        let r = img.size.width / max(img.size.height, 1)
        let imgW = side * r                          // 正方フレーム内で高さ合わせ → 横は中央寄せ
        let pad: CGFloat = 12                         // RootView の padding(12)
        let winW = window.frame.width
        let boxLeft = winW - pad - side               // キャラ枠は bottomTrailing
        let imgLeft = boxLeft + (side - imgW) / 2
        // アンカー（画像左上原点）をウィンドウのローカル座標（左下原点）へ。
        let px = imgLeft + CGFloat(anchor.x) * imgW
        let py = pad + side * (1 - CGFloat(anchor.y))
        window.setFrameOrigin(NSPoint(x: mouse.x - px, y: mouse.y - py))
    }

    /// ドラッグの「振り回し」量を累積する。方向転換が大きいほど・速いほど多く溜まる。
    /// まっすぐ運ぶだけでは溜まらず、ブンブン振り回すと一気に溜まる。
    private func accumulateWhirl(_ p: NSPoint) {
        defer { lastWhirlPos = p }
        guard let lp = lastWhirlPos else { return }
        let dx = p.x - lp.x, dy = p.y - lp.y
        let dist = hypot(dx, dy)
        guard dist > 3 else { return }
        let angle = atan2(dy, dx)
        if let last = lastWhirlAngle {
            var d = abs(angle - last)
            if d > .pi { d = 2 * .pi - d }      // 0〜π の方向転換量
            whirlScore += Double(d) * Double(min(dist, 40)) / 40
        }
        lastWhirlAngle = angle
    }

    /// 撫で状態の更新。マウス・ウィンドウから入力を組み立て、遷移は PettingMachine に委譲する。
    private func tickGirl() {
        if girlDying { return } // 終了演出中は何もしない
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTick == 0 ? 0.05 : now - lastTick
        lastTick = now
        // 直近 0.4 秒の軌跡だけ残す。
        mouseHistory.removeAll { now - $0.t > 0.4 }

        let enabled = character == .girl && isNadeEnabled && hasGirlImages && !isSwimming && window != nil

        var inZone = false
        var speed: CGFloat = 0
        var xWobble: CGFloat = 0
        var distance: CGFloat = 0
        var reportHeld = false
        var dragging = false
        if let window {
            let m = NSEvent.mouseLocation
            // 速度（px/sec）。
            if let first = mouseHistory.first, mouseHistory.count >= 2 {
                let span = now - first.t
                if span > 0.01 { speed = hypot(m.x - first.p.x, m.y - first.p.y) / CGFloat(span) }
            }
            let f = window.frame
            // 頭の当たり判定（横長楕円）。撫でやすいよう頭〜上半身を広めにカバー。
            let hx = f.midX, hy = f.maxY - f.height * 0.22
            let rx = f.width * 0.42, ry = f.height * 0.24
            let nx = (m.x - hx) / rx, ny = (m.y - hy) / ry
            inZone = (nx * nx + ny * ny) <= 1
            // 頭付近での左右の揺れ（撫でっぽさ）。
            let xs = mouseHistory.map { $0.p.x }
            xWobble = (xs.max() ?? 0) - (xs.min() ?? 0)
            // キャラ中心からカーソルまでの距離（遠い待機の判定）。
            distance = hypot(m.x - f.midX, m.y - f.midY)

            // 掴み／ドラッグは handleMouseButton（イベント駆動）で更新済み。ここでは表示判定のみ。
            // 安全策: mouseUp を取りこぼしても、ボタンが上がっていれば解除する。
            if isHeld, (NSEvent.pressedMouseButtons & 0x1) == 0 {
                isHeld = false; didDrag = false; saveOrigin()
            }
            if isHeld {
                dragging = didDrag && (now - lastDragTime < 0.16)
                // クリックでチャットを開く誤爆を避けるため、掴み表示は少しだけ溜める。
                // ドラッグ（移動）が起きていれば即座に表示。
                reportHeld = dragging || (now - heldStart > holdShowDelay)
            }
        }

        pettingMachine.update(PettingMachine.Input(
            dt: dt, inZone: inZone, speed: Double(speed),
            xWobble: Double(xWobble), distance: Double(distance), enabled: enabled,
            isHeld: reportHeld, isDragging: dragging, isMoving: isSwimming))

        girlState = pettingMachine.state
        girlDisplay = pettingMachine.display
        isBeingPatted = pettingMachine.isBeingPatted

        // 振り回しの累積は穏やかだと少しずつ冷める。
        if !isHeld && whirlScore > 0 {
            whirlScore = max(0, whirlScore - dt * whirlDecayPerSec)
        }

        if dizzyTimer > 0, !isHeld {
            // 手を離したあと、ふらふら目を回す（掴み直したら中断）。
            dizzyTimer -= dt
            dizzyPhase += dt
            girlDisplay = dizzyPhase.truncatingRemainder(dividingBy: dizzyFlip * 2) < dizzyFlip
                ? .dizzy : .dizzy2
            isBeingPatted = false
        } else if greetTimer > 0, !isHeld {
            // 初回起動の挨拶。3枚を順番に見せる（掴んだら中断）。
            greetTimer -= dt
            let idx = Int((greetDuration - greetTimer) / 1.4) % 3
            girlDisplay = idx == 0 ? .greet : (idx == 1 ? .greet2 : .greet3)
            isBeingPatted = false
        } else if isThinking, !isHeld {
            // AIが返答を考えている間（うーん…／むむ…をゆっくり往復）。
            thinkingTimer -= dt
            if thinkingTimer <= 0 {
                thinkingAlt.toggle()
                thinkingTimer = Double.random(in: 0.9...1.5)
            }
            girlDisplay = thinkingAlt ? .thinking2 : .thinking
            isBeingPatted = false
        } else if isChatOpen, messages.last?.role == .assistant,
                  girlState != .hold, girlState != .drag {
            // 回答を提示している間は解説ポーズ。ときどきウインク（話してる感）。
            // 開いている時間は 1.8〜3.6 秒のランダムで、機械的な周期感を消す。
            teachingTimer -= dt
            if teachingTimer <= 0 {
                teachingWinking.toggle()
                teachingTimer = teachingWinking
                    ? teachingWinkDuration
                    : Double.random(in: 1.8...3.6)
            }
            girlDisplay = teachingWinking ? .teaching2 : .teaching
            isBeingPatted = false
        } else {
            teachingWinking = false
            teachingTimer = Double.random(in: 1.8...3.6)
            thinkingAlt = false
            thinkingTimer = 0
        }
    }

    private var teachingWinking = false
    private var teachingTimer: Double = 0
    private let teachingWinkDuration: Double = 0.32
    private var thinkingAlt = false
    private var thinkingTimer: Double = 0
    /// 初回挨拶の残り時間（秒）。
    private var greetTimer: Double = 0
    private let greetDuration: Double = 4.6
    /// 初回挨拶を一度だけ出すためのフラグキー。
    private let greetedKey = "girlGreetedV1"

    /// 初回だけ挨拶シーケンスを開始する（裏キャラが初めて現れた時）。
    private func maybeGreet() {
        guard character == .girl, hasGirlImages else { return }
        guard !UserDefaults.standard.bool(forKey: greetedKey) else { return }
        UserDefaults.standard.set(true, forKey: greetedKey)
        greetTimer = greetDuration
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
        if character == .girl { startPatTracking(); maybeGreet() }
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
        // 裏モードで撫でられ中・終了演出中は動かない。
        if character == .girl && (girlState != .idle || girlDying) { return }
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
            if character == .girl, girlImages[.sad] != nil {
                // 裏モード: 悲しい顔でブルブル震えながら 5 秒かけてフェードアウト。
                messages.append(ChatMessage(role: .assistant,
                    text: "え…ぼくを、消すんですか…？\n……ばいばい。"))
                stopPatTracking()
                pettingMachine.enterSad()
                girlDisplay = .sad
                girlDying = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { KairuQuit.now() }
            } else {
                messages.append(ChatMessage(role: .assistant,
                    text: "「お前を消す方法」について調べました。\n……さようなら。"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { KairuQuit.now() }
            }
            clearPending()
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
        // 裏モード（POIN）のときは少女の人格プロンプトに差し替える。
        var requestConfig = config
        if character == .girl { requestConfig.systemPrompt = AppConfig.girlSystemPrompt }
        let client = AIClient(config: requestConfig)
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
