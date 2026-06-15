import AppKit
import SwiftUI
import KairuCore

/// アプリ全体の状態。SwiftUI ビューと AppKit ウィンドウをつなぐ。
///
/// このクラスは責務ごとに extension で分割している（ストアドプロパティは Swift の制約上ここに集約）:
/// - `AppModel+Window.swift`  : ウィンドウ/キャラのサイズ・当たり判定・リサイズ・位置永続化
/// - `AppModel+Girl.swift`    : 裏キャラ（POIN）の頭なで状態機械・悲しい/復帰/ロック・キャラ切替
/// - `AppModel+Mischief.swift`: おせっかいモード（泳ぎ・話しかけ）・自己モニタリング（過負荷）
/// - `AppModel+Chat.swift`    : 文脈取り込み（クリップボード/スクショ）・メッセージ送信
@MainActor
final class AppModel: ObservableObject {

    // MARK: - チャット / 会話

    @Published var messages: [ChatMessage] = [] {
        didSet { applyWindowSize(animated: true) } // 太り具合が変わるのでウィンドウも追従
    }
    @Published var draft: String = ""
    @Published var isChatOpen = false
    @Published var isThinking = false
    /// 吹き出しに出す一言（アイドル時のヒントやエラー表示）。
    @Published var bubble: String? = "やあ！Mac のことなら何でも聞いてね"

    // MARK: - キャラクター表示

    /// 表示中のキャラクター。
    @Published var character: Character = .dolphin
    /// 裏モードで頭を撫でられている最中か。
    @Published var isBeingPatted = false
    /// キャラ変更を AppDelegate に伝える（メニューバー絵文字の更新など）。
    var onCharacterChanged: ((Character) -> Void)?

    /// イルカの大きさ倍率（0.6〜2.2）。ピンチやメニューで変更。
    @Published var dolphinScale: Double = 1.0

    // MARK: - チャット欄サイズ（リサイズ可能・永続化）

    @Published var chatWidth: CGFloat = 300
    @Published var chatHeight: CGFloat = 380
    /// リサイズ開始時のサイズ（ドラッグ中の基準）。
    var chatResizeStart: NSSize?
    /// チャット欄サイズの可動域。
    static let chatMinSize = NSSize(width: 280, height: 300)
    static let chatMaxSize = NSSize(width: 720, height: 820)

    // MARK: - 文脈の取り込み

    /// 取り込み中の文脈（クリップボードのテキスト）。
    @Published var pendingText: String?
    /// 取り込み中の画像（スクショ等）。
    @Published var pendingImage: ImageAttachment?
    /// 取り込み画像のサムネ表示用。
    @Published var pendingImagePreview: NSImage?
    /// スクショ撮影中フラグ。
    @Published var isCapturing = false

    // MARK: - 泳ぎ / 向き / 発見シーケンス

    /// 泳ぎ中か（ヒレを大きく振る）。
    @Published var isSwimming = false
    /// 左を向いているか（泳ぐ向きで反転）。通常キャラの泳ぎ向き用。
    @Published var facingLeft = false
    /// 裏キャラ画像の左右反転（発見ポーズでカーソル方向を向く用）。
    @Published var girlFlip = false

    /// 発見モーションの残り時間と、その後カーソルへ走るための保留。
    var discoverTimer: Double = 0
    var pendingApproach = false
    var approachFlip = false

    var swimTimer: Timer?
    var chatterTimer: Timer?

    // MARK: - ウィンドウ / 設定 / 永続化キー

    /// 常駐ウィンドウ（リサイズ・位置保存に使う）。移動は AppKit のネイティブ機能。
    weak var window: NSWindow?
    var pinchStart: Double?

    /// 設定ウィンドウを開く（AppDelegate が実体を提供）。
    var presentSettings: (() -> Void)?

    var config: AppConfig?

    let scaleKey = "dolphinScale"
    let originXKey = "windowOriginX"
    let originYKey = "windowOriginY"
    let characterKey = "character"
    let chatWidthKey = "chatWidth"
    let chatHeightKey = "chatHeight"

    // MARK: - 裏キャラ（女の子）の状態

    /// 裏キャラ（女の子）の論理状態と表示状態。
    @Published var girlState: GirlState = .idle
    @Published var girlDisplay: GirlState = .idle
    /// 「お前を消す方法」で消される最中（悲しくフェードアウト中）。
    @Published var girlDying = false
    /// 初回挨拶の最中（弾むモーションを出すフラグ）。
    @Published var girlGreeting = false
    var girlImages: [GirlState: NSImage] = [:]

    // MARK: - 頭なで入力監視

    var patMonitorGlobal: Any?
    var patMonitorLocal: Any?
    var girlTimer: Timer?
    var mouseHistory: [(p: NSPoint, t: Double)] = []
    var lastTick: Double = 0
    /// 頭なで状態機械（純粋ロジックは KairuCore 側）。
    var pettingMachine = PettingMachine()
    /// 掴み（左ボタン保持）の追跡。mouseDown/Up/Dragged イベントで即時更新する。
    var isHeld = false
    var heldStart: Double = 0
    var didDrag = false
    var lastDragTime: Double = 0
    /// 掴み表示までの遅延（秒）。短いほど反応が良い。クリックでチャットを開く誤爆を弾く最小限。
    let holdShowDelay: Double = 0.08
    /// 左ボタンのイベント監視（掴み/ドラッグ検出）。
    var btnMonitorGlobal: Any?
    var btnMonitorLocal: Any?
    /// スクロールでのサイズ調整の監視（チャット入力待ち中にキャラ上で有効）。
    var scrollMonitorLocal: Any?
    /// 振り回し量の累積（方向転換×移動量）。閾値超で目を回す。
    var whirlScore: Double = 0
    var lastWhirlPos: NSPoint?
    var lastWhirlAngle: Double?
    let whirlThreshold: Double = 9      // これを超えて振り回されると目を回す
    let whirlDecayPerSec: Double = 2.5   // 振り回しが穏やかだと冷める速さ
    /// 目を回している残り時間（秒）と表情往復用フェーズ。
    var dizzyTimer: Double = 0
    var dizzyPhase: Double = 0
    let dizzyDuration: Double = 2.6
    let dizzyFlip: Double = 0.28         // dizzy↔dizzy2 の往復間隔
    /// POIN に重なった時の適用中カーソル（自ウィンドウ上だけ変える）。
    var appliedGirlCursor: NSCursor?

    // MARK: - 悲しい / 復帰 / ロック

    /// 悲しい状態（心無い言葉・エラー）。撫でて慰めるまで持続し、全表示に優先する。
    @Published var isSad = false
    var sadPhase: Double = 0
    let upsetFlip: Double = 0.5
    var sadPetAccum: Double = 0          // 撫でて慰めた累積時間
    let sadComfortTime: Double = 0.9     // これだけ撫でると泣き止む
    var hurtfulStreak = 0                // 復帰させずに傷つけ続けた回数
    let sadLockThreshold = 15            // これを超えると POIN をロック
    var hurtRegisteredForSend = false    // 同一送信での二重カウント防止

    // MARK: - 表情タイマー（解説 / 思考中 / 挨拶）

    var teachingWinking = false
    var teachingTimer: Double = 0
    let teachingWinkDuration: Double = 0.32
    var thinkingAlt = false
    var thinkingTimer: Double = 0
    /// 初回挨拶の残り時間（秒）。
    var greetTimer: Double = 0
    let greetDuration: Double = 4.6
    /// 初回挨拶を一度だけ出すためのフラグキー。
    let greetedKey = "girlGreetedV1"

    // MARK: - 自己モニタリング（過負荷）

    /// 自己モニタリング（過負荷）。メモリ計測・OSのメモリ圧迫・コンテキスト量で判定。
    var memPressureSrc: DispatchSourceMemoryPressure?
    var memWarning = false
    var memCritical = false
    var lastFootprintMB: Double = 0
    var footprintTick = 0
    var overloadPhase: Double = 0

    // MARK: - 初期化

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
}
