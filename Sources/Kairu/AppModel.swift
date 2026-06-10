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

    /// チャット欄のサイズ（リサイズ可能・永続化）。グリップのドラッグで変える。
    @Published var chatWidth: CGFloat = 300
    @Published var chatHeight: CGFloat = 380
    /// リサイズ開始時のサイズ（ドラッグ中の基準）。
    private var chatResizeStart: NSSize?
    /// チャット欄サイズの可動域。
    static let chatMinSize = NSSize(width: 280, height: 300)
    static let chatMaxSize = NSSize(width: 720, height: 820)

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
    /// 左を向いているか（泳ぐ向きで反転）。通常キャラの泳ぎ向き用。
    @Published var facingLeft = false
    /// 裏キャラ画像の左右反転（発見ポーズでカーソル方向を向く用）。
    @Published var girlFlip = false

    /// 発見モーションの残り時間と、その後カーソルへ走るための保留。
    private var discoverTimer: Double = 0
    private var pendingApproach = false
    private var approachFlip = false

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
    private let chatWidthKey = "chatWidth"
    private let chatHeightKey = "chatHeight"

    /// 裏キャラ（女の子）の論理状態と表示状態。
    @Published var girlState: GirlState = .idle
    @Published var girlDisplay: GirlState = .idle
    /// 「お前を消す方法」で消される最中（悲しくフェードアウト中）。
    @Published var girlDying = false
    /// 初回挨拶の最中（弾むモーションを出すフラグ）。
    @Published var girlGreeting = false
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
    /// スクロールでのサイズ調整の監視（チャット入力待ち中にキャラ上で有効）。
    private var scrollMonitorLocal: Any?
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

    /// 悲しい状態（心無い言葉・エラー）。撫でて慰めるまで持続し、全表示に優先する。
    @Published var isSad = false
    private var sadPhase: Double = 0
    private let upsetFlip: Double = 0.5
    private var sadPetAccum: Double = 0          // 撫でて慰めた累積時間
    private let sadComfortTime: Double = 0.9     // これだけ撫でると泣き止む
    private var hurtfulStreak = 0                // 復帰させずに傷つけ続けた回数
    private let sadLockThreshold = 15            // これを超えると POIN をロック
    private var hurtRegisteredForSend = false    // 同一送信での二重カウント防止

    /// POIN を泣き止ませた累計回数（それを目的に遊ぶ人向けの計測）。
    private(set) var poinRecoverCount: Int {
        get { UserDefaults.standard.integer(forKey: "poinRecoverCount") }
        set { UserDefaults.standard.set(newValue, forKey: "poinRecoverCount") }
    }
    /// POIN がロックされているか（イルカたちしか使えない）。
    var poinLocked: Bool {
        get { UserDefaults.standard.bool(forKey: "poinLocked") }
        set { UserDefaults.standard.set(newValue, forKey: "poinLocked") }
    }

    /// 自己モニタリング（過負荷）。メモリ計測・OSのメモリ圧迫・コンテキスト量で判定。
    private var memPressureSrc: DispatchSourceMemoryPressure?
    private var memWarning = false
    private var memCritical = false
    private var lastFootprintMB: Double = 0
    private var footprintTick = 0
    private var overloadPhase: Double = 0

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
        let cw = UserDefaults.standard.double(forKey: chatWidthKey)
        let ch = UserDefaults.standard.double(forKey: chatHeightKey)
        if cw > 0 { chatWidth = min(Self.chatMaxSize.width, max(Self.chatMinSize.width, cw)) }
        if ch > 0 { chatHeight = min(Self.chatMaxSize.height, max(Self.chatMinSize.height, ch)) }
        if let raw = UserDefaults.standard.string(forKey: characterKey),
           let c = Character(rawValue: raw) {
            character = c
        }
        // ロック中に POIN で保存されていたらイルカに戻す（イルカたちしか使えない）。
        if character == .girl, UserDefaults.standard.bool(forKey: "poinLocked") {
            character = .dolphin
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
        // チャット欄（可変）＋キャラの大きさの両方を収めるウィンドウサイズ。
        // 横: チャット幅とキャラ幅の大きい方＋左右パディング。縦: チャット＋間隔＋キャラ＋余白。
        NSSize(width: max(chatWidth + 24, dolphinSide + 24),
               height: chatHeight + 8 + dolphinSide + 24 + 16)
    }

    var currentTargetSize: NSSize { isChatOpen ? openSize : closedSize }

    // MARK: - 当たり判定ゾーン（キャラ実寸基準）

    /// 頭/体の当たり判定ゾーン。ウィンドウ・ローカル座標（左上原点・y 下向き）で返す。
    /// キャラは `dolphinSide` の正方形として右下寄せ＋パディング `Self.contentPad` で描画されるので、
    /// ウィンドウ枠の割合ではなくキャラ実寸から導出する。これでスケール変更に当たり判定が追従する。
    struct GirlZone {
        var center: CGPoint   // ローカル座標（左上原点）
        var rx: CGFloat
        var ry: CGFloat
    }

    /// RootView の外周パディング。当たり判定の右下基準に使う。
    private static let contentPad: CGFloat = 12
    /// 頭ゾーン: 正方形上端からの中心 Y 位置・楕円半径（いずれも side に対する割合・実機調整値）。
    private static let headCenterYFrac: CGFloat = 0.30
    private static let headRadiusXFrac: CGFloat = 0.42
    private static let headRadiusYFrac: CGFloat = 0.30

    /// キャラ正方形（ローカル座標・左上原点）。右下寄せ＋パディング。
    /// 頭の当たり判定とスクロールでのサイズ調整のホバー判定で共有する。
    func characterSquare(windowSize: CGSize) -> CGRect {
        let s = dolphinSide
        let x = windowSize.width - Self.contentPad - s
        let y = windowSize.height - Self.contentPad - s
        return CGRect(x: x, y: y, width: s, height: s)
    }

    /// 頭の当たり判定ゾーン（ローカル座標）。キャラ正方形の上部中央付近。
    func girlHeadZone(windowSize: CGSize) -> GirlZone {
        let sq = characterSquare(windowSize: windowSize)
        let s = sq.width
        return GirlZone(center: CGPoint(x: sq.midX, y: sq.minY + s * Self.headCenterYFrac),
                        rx: s * Self.headRadiusXFrac,
                        ry: s * Self.headRadiusYFrac)
    }

    /// キャラの当たり矩形（スクリーン座標・左下原点）。スクロールでのサイズ調整のホバー判定に使う。
    func characterScreenRect() -> CGRect? {
        guard let f = window?.frame else { return nil }
        let sq = characterSquare(windowSize: f.size)   // ローカル（左上原点）
        // ローカル → スクリーン（左下原点）。sq.maxY が下端、sq.minY が上端。
        return CGRect(x: f.minX + sq.minX, y: f.maxY - sq.maxY,
                      width: sq.width, height: sq.height)
    }

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
        // 右下を基準に成長（maxX・minY を固定）。
        var x = old.maxX - target.width
        var y = old.minY
        // 画面サイズ・キャラの大きさに合わせて動的調整: はみ出すなら画面内へ寄せる。
        // チャットを開いた時や大きいキャラの時に、欄が画面外に出て見切れるのを防ぐ。
        if let screen = window.screen ?? NSScreen.main {
            let v = screen.visibleFrame
            if target.width <= v.width { x = min(max(x, v.minX), v.maxX - target.width) }
            if target.height <= v.height { y = min(max(y, v.minY), v.maxY - target.height) }
        }
        let newFrame = NSRect(x: x, y: y, width: target.width, height: target.height)
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

    /// スクロールでのサイズ調整を有効化（アプリ起動時に一度だけ）。
    /// チャット入力待ち（チャットを開いている）かつカーソルがキャラの上にある時だけ、
    /// スクロール量に連動して倍率を変える。メッセージリスト上のスクロールは妨げない。
    func startScrollResize() {
        guard scrollMonitorLocal == nil else { return }
        scrollMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self else { return e }
            guard self.isChatOpen,
                  let rect = self.characterScreenRect(),
                  rect.contains(NSEvent.mouseLocation) else { return e }
            // トラックパッドはピクセル精度、マウスホイールはライン単位。どちらも scrollingDeltaY を使う。
            let delta = e.scrollingDeltaY
            guard delta != 0 else { return nil }
            // 上スクロールで拡大。慣性で急変しないよう感度は控えめ。
            let factor = 1 + delta * 0.004
            self.dolphinScale = min(10.0, max(0.6, self.dolphinScale * factor))
            UserDefaults.standard.set(self.dolphinScale, forKey: self.scaleKey)
            self.applyWindowSize(animated: false)
            return nil   // キャラ上のスクロールは消費し、メッセージリストへ流さない。
        }
    }

    // MARK: - チャット欄のリサイズ（グリップのドラッグ）

    /// リサイズ開始（基準サイズを記録）。
    func chatResizeBegan() {
        if chatResizeStart == nil {
            chatResizeStart = NSSize(width: chatWidth, height: chatHeight)
        }
    }

    /// ドラッグ量からチャット欄サイズを更新する（基準サイズ＋累積移動）。
    func chatResizeChanged(dx: CGFloat, dy: CGFloat) {
        let base = chatResizeStart ?? NSSize(width: chatWidth, height: chatHeight)
        chatWidth = min(Self.chatMaxSize.width, max(Self.chatMinSize.width, base.width + dx))
        chatHeight = min(Self.chatMaxSize.height, max(Self.chatMinSize.height, base.height + dy))
        applyWindowSize(animated: false)
    }

    /// リサイズ確定（サイズを永続化）。
    func chatResizeEnded() {
        chatResizeStart = nil
        UserDefaults.standard.set(chatWidth, forKey: chatWidthKey)
        UserDefaults.standard.set(chatHeight, forKey: chatHeightKey)
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
                ? "…ぼくのこと、呼んだ？頭、撫でてくれてもいいんだよ？"
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
        if goingSecret, poinLocked {
            // ロック中は POIN を呼べない。イルカたちしか使えない。
            messages.append(ChatMessage(role: .assistant, text: "……POIN は、まだ拗ねてるみたい。"))
            return
        }
        setCharacter(goingSecret ? .girl : .dolphin)
        messages.append(ChatMessage(role: .assistant,
            text: goingSecret ? "…ぼくのこと、呼んだ？頭、撫でてくれてもいいんだよ？"
                              : "またね。呼んだら来るね。"))
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
        if appliedGirlCursor != nil { NSCursor.arrow.set(); appliedGirlCursor = nil }
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
                discoverTimer = 0; pendingApproach = false // 掴んだら発見シーケンスは中断
                whirlScore = 0
                lastWhirlPos = NSEvent.mouseLocation
                lastWhirlAngle = nil
                updateGirlCursor() // 掴んだ瞬間に closedHand へ
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
            updateGirlCursor() // 離した瞬間に openHand へ
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
            // 頭の当たり判定（横長楕円）。キャラ実寸（dolphinSide）と右下固定配置から導出。
            // ゾーンはローカル座標（左上原点）。スクリーン座標（左下原点）へ変換して判定する。
            let zone = girlHeadZone(windowSize: f.size)
            let hx = f.minX + zone.center.x          // ローカル x → スクリーン x
            let hy = f.maxY - zone.center.y          // ローカル y(下向き) → スクリーン y(上向き)
            let nx = (m.x - hx) / zone.rx, ny = (m.y - hy) / zone.ry
            inZone = (nx * nx + ny * ny) <= 1
            // 頭付近での左右の揺れ（撫でっぽさ）。
            let xs = mouseHistory.map { $0.p.x }
            xWobble = (xs.max() ?? 0) - (xs.min() ?? 0)
            // キャラ中心からカーソルまでの距離（遠い待機の判定）。キャラ正方形の中心を基準にする。
            let sq = characterSquare(windowSize: f.size)
            let charCX = f.minX + sq.midX, charCY = f.maxY - sq.midY
            distance = hypot(m.x - charCX, m.y - charCY)

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

        // 悲しい時は、撫でて慰めると泣き止む（一定時間の頭なでで復帰）。
        // チャットを開いている間は当たり判定がパネル側にズレるので、復帰させない。
        if isSad, !isChatOpen {
            if pettingMachine.isBeingPatted {
                sadPetAccum += dt
                if sadPetAccum >= sadComfortTime { recoverFromSad() }
            } else {
                sadPetAccum = max(0, sadPetAccum - dt * 0.5)
            }
        }

        // 振り回しの累積は穏やかだと少しずつ冷める。
        if !isHeld && whirlScore > 0 {
            whirlScore = max(0, whirlScore - dt * whirlDecayPerSec)
        }

        girlFlip = false // 既定は反転なし（発見ポーズの時だけ向きを変える）

        // 自己モニタリング: フットプリントを ~1.5 秒ごとにサンプリング。
        footprintTick += 1
        if footprintTick >= 30 { footprintTick = 0; lastFootprintMB = Self.appFootprintMB() }

        if isSad {
            // 悲しいは全てに優先し、撫でて慰められるまで常に悲しむ。
            sadPhase += dt
            girlDisplay = sadPhase.truncatingRemainder(dividingBy: upsetFlip * 2) < upsetFlip
                ? .upset : .upset2
            // 慰められている時だけ手応え（ふわっと反応）を残す。
            isBeingPatted = !isChatOpen && pettingMachine.isBeingPatted
            girlFlip = false
        } else if discoverTimer > 0, !isHeld, !isChatOpen {
            // 移動直前の発見ポーズ。カーソル方向を向き、知覚できる間を置いてから走り出す。
            discoverTimer -= dt
            girlDisplay = .found
            girlFlip = approachFlip
            isBeingPatted = false
            if discoverTimer <= 0, pendingApproach {
                pendingApproach = false
                performSwim(goToCursor: true)
            }
        } else if dizzyTimer > 0, !isHeld {
            // 手を離したあと、ふらふら目を回す（掴み直したら中断）。
            dizzyTimer -= dt
            dizzyPhase += dt
            girlDisplay = dizzyPhase.truncatingRemainder(dividingBy: dizzyFlip * 2) < dizzyFlip
                ? .dizzy : .dizzy2
            isBeingPatted = false
        } else if greetTimer > 0, !isHeld {
            // 初回起動の挨拶。3枚＋吹き出し3段を順番に見せ、弾むモーションで存在感を出す（掴んだら中断）。
            greetTimer -= dt
            let idx = Int((greetDuration - greetTimer) / 1.4) % 3
            girlDisplay = idx == 0 ? .greet : (idx == 1 ? .greet2 : .greet3)
            let lines = ["やっほー！", "こんにちはー！", "よろしくねー！"]
            if !isChatOpen { bubble = lines[idx] }
            girlGreeting = true
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
        } else if isUnderLoad, girlState == .idle, !isHeld {
            // 自己モニタリング（過負荷）: 大袈裟に ぐるぐる(build)→プシュー！(burst)。
            overloadPhase += dt
            let p = overloadPhase.truncatingRemainder(dividingBy: 1.6) // build 1.2s + burst 0.4s
            girlDisplay = p < 1.2 ? .overload : .overload2
            isBeingPatted = false
        } else {
            teachingWinking = false
            teachingTimer = Double.random(in: 1.8...3.6)
            thinkingAlt = false
            thinkingTimer = 0
            overloadPhase = 0
            // 挨拶が終わった直後に一度だけモーションを止め、待機の吹き出しへ戻す。
            if girlGreeting {
                girlGreeting = false
                if !isChatOpen, hasGirlImages {
                    bubble = "…ぼくのこと、呼んだ？頭、撫でてくれてもいいんだよ？"
                }
            }
            // 発見シーケンスが中断された場合は破棄。
            if discoverTimer > 0 { discoverTimer = 0; pendingApproach = false }
        }

        updateGirlCursor()
    }

    /// POIN に重なった時は openHand（掴める）、掴んでいる間は closedHand（掴んでる）。
    /// 自分のウィンドウ上にいる時だけ変更し、他アプリのカーソルには触れない。
    private var appliedGirlCursor: NSCursor?
    private func updateGirlCursor() {
        guard character == .girl, !isChatOpen, let window else {
            if appliedGirlCursor != nil { NSCursor.arrow.set(); appliedGirlCursor = nil }
            return
        }
        let over = window.frame.contains(NSEvent.mouseLocation)
        let want: NSCursor? = isHeld ? .closedHand : (over ? .openHand : nil)
        if want !== appliedGirlCursor {
            (want ?? NSCursor.arrow).set()
            appliedGirlCursor = want
        }
    }

    // MARK: - 自己モニタリング（過負荷の自己検知）

    /// OS のメモリ圧迫通知を購読する（1回だけ）。
    private func startSelfMonitor() {
        guard memPressureSrc == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let ev = src?.data else { return }
            self.memCritical = ev.contains(.critical)
            self.memWarning = ev.contains(.warning) || self.memCritical
        }
        src.resume()
        memPressureSrc = src
    }

    /// 自プロセスの物理メモリフットプリント（MB）。
    private static func appFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / (1024 * 1024) : 0
    }

    /// 画像付きメッセージ数（キャッシュ圧迫の代理指標）。
    private var imageMessageCount: Int { messages.reduce(0) { $0 + ($1.image != nil ? 1 : 0) } }

    /// 高負荷（パニック寄り）か。
    private var loadSevere: Bool {
        memCritical || lastFootprintMB >= 1200 || messages.count >= 80 || imageMessageCount >= 10
    }
    /// 何らかの負荷がかかっているか（過負荷表現を出す閾値）。
    private var isUnderLoad: Bool {
        loadSevere || memWarning || lastFootprintMB >= 700
            || messages.count >= 40 || imageMessageCount >= 5
    }

    // MARK: - 悲しい / 復帰 / ロック

    /// 悲しい状態に入る（心無い言葉・エラー）。移動や発見シーケンスは止める。
    private func enterSad() {
        guard character == .girl, !poinLocked else { return }
        isSad = true
        sadPetAccum = 0
        discoverTimer = 0; pendingApproach = false
    }

    /// 傷つける発話を1件登録する（悲しくなり、続けばロックへ）。
    private func registerHurt() {
        guard character == .girl, !poinLocked else { return }
        hurtfulStreak += 1
        enterSad()
        if hurtfulStreak >= sadLockThreshold { lockPoin() }
    }

    /// POIN の返答末尾の気分タグ [[mood:...]] を取り除く（表示用）。
    private static func stripMoodTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[\[mood:[a-zA-Z]+\]\]"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 撫でて慰められて泣き止む。累計回数を増やす。
    private func recoverFromSad() {
        guard isSad else { return }
        isSad = false
        hurtfulStreak = 0
        sadPetAccum = 0
        poinRecoverCount += 1
        bubble = "ぐすっ…ありがとう。"
    }

    /// 悲しいまま傷つけ続けられ、POIN がロックされる。以後はイルカたちしか使えない。
    private func lockPoin() {
        poinLocked = true
        isSad = false
        hurtfulStreak = 0
        messages.append(ChatMessage(role: .assistant,
            text: "……もう、いやだ。\nぼく、しばらく出てこないね。"))
        setCharacter(.dolphin)
    }

    /// POIN のロックを解除する（設定から呼び戻す）。
    func unlockPoin() {
        poinLocked = false
        hurtfulStreak = 0
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
        girlGreeting = true
        // 既に自アプリがアクティブな時だけ、そっと前面へ。
        // 他アプリで作業中にフォーカスを奪わないため NSApp.activate は使わない。
        if NSApp.isActive { window?.orderFront(nil) }
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
        startSelfMonitor()
        if character == .girl { startPatTracking(); maybeGreet() }
    }

    private func scheduleSwim() {
        swimTimer?.invalidate()
        let delay = Double.random(in: 7...16) // 頻度アップ
        swimTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.swim(); self?.scheduleSwim() }
        }
    }

    /// 移動のトリガ。裏モードはまず「発見ポーズ」を挟んでから走る。通常キャラは即移動。
    private func swim() {
        guard isAnnoyEnabled, !isChatOpen, !isThinking, let window else { return }
        if isSwimming || discoverTimer > 0 { return }
        if character == .girl {
            // 悲しい時は動かず、その場で悲しむ。
            if girlState != .idle || girlDying || isSad { return }
            // カーソルを見つける発見モーションを挟む。マウスが自分より右なら反転して向く。
            approachFlip = NSEvent.mouseLocation.x > window.frame.midX
            discoverTimer = Double.random(in: 0.6...1.0) // 知覚できる発見の間
            pendingApproach = true
            return
        }
        performSwim(goToCursor: Double.random(in: 0 ..< 1) < 0.2)
    }

    /// 実際に泳いで移動する。裏モードは常にカーソルへ、通常は引数で制御。
    private func performSwim(goToCursor: Bool) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        if character == .girl && girlDying { return }
        let size = window.frame.size
        let from = window.frame.origin
        let margin = dolphinSide * 0.5

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

        // 心無い言葉の判定。明白な語はキーワードで即反応（遅延ゼロ）。
        // 微妙な冷たさは、POIN 自身の返答に付く気分タグ（後述）で拾う。
        hurtRegisteredForSend = false
        if character == .girl, !poinLocked, HurtfulText.isHurtful(typed) {
            registerHurt()
            hurtRegisteredForSend = true
        }

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
                var reply = try await client.send(history: history)
                // 裏モードは返答末尾の気分タグを読み取り、表示からは消す。
                var hurt = false
                if self.character == .girl {
                    hurt = reply.contains("[[mood:hurt]]")
                    reply = Self.stripMoodTags(reply)
                }
                self.messages.append(ChatMessage(role: .assistant, text: reply))
                // POIN 自身が「傷ついた」と示したら悲しくなる（キーワード未検知時のみ）。
                if hurt, !self.hurtRegisteredForSend { self.registerHurt() }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.messages.append(ChatMessage(role: .assistant, text: "⚠️ \(msg)"))
                // 処理失敗・エラーでも悲しい顔になる（撫でて慰めると戻る）。
                self.enterSad()
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
