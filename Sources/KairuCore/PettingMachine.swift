import Foundation

/// 裏キャラ（POIN）の頭なで状態機械。
///
/// UI / AppKit / 時計から完全に独立した純粋ロジック。呼び出し側（AppModel）は
/// マウス・ウィンドウから `PettingInput` を組み立てて `update` を呼ぶだけ。
/// 時刻は絶対時間ではなく毎フレームの経過秒 `dt` で駆動するので、テストで自由に進められる。
public struct PettingMachine: Sendable {

    /// 状態遷移の閾値。すべて名前付きにして調整・追加をしやすくする。
    public struct Config: Sendable {
        /// idle→notice に必要な頭ゾーン滞在時間（秒）。短いほどすぐ気づく。
        public var noticeHoverTime: Double = 0.06
        /// notice→pamper のフォールバック滞在時間（撫で動作が無くても甘える）。
        public var pamperHoverTime: Double = 0.18
        /// idle→notice を許す最大カーソル速度（px/s）。速く近づいても気づけるよう高め。
        public var noticeSpeedMax: Double = 1200
        /// pamper / pamperLoop から離脱する速度（px/s）。振り払い相当のみ離脱。
        public var releaseSpeed: Double = 1600
        /// 「撫でっぽい」と判定する左右ゆれ幅の下限・上限（px）。大きめのストロークも許容。
        public var petWobbleMin: Double = 6
        public var petWobbleMax: Double = 240
        /// 撫で判定で許す最大速度（px/s）。撫では速いので高く取る。
        public var petSpeedMax: Double = 1600
        /// pamper→pamperLoop に移るまでの時間（秒）。
        public var pamperFlipInterval: Double = 0.25
        /// 甘えループ中に pamper↔pamperLoop の画像を往復する間隔（秒）。
        public var loopFlipInterval: Double = 0.5
        /// 離脱の猶予（秒）。ゾーン外/速度超過がこの秒数“継続”して初めて終了する（ヒステリシス）。
        /// 撫で中の一瞬のはみ出しや速いストロークでは終わらせない。
        public var releaseGrace: Double = 0.35
        /// 余韻（end「…もう終わり？」）の表示時間（秒）。
        public var endDuration: Double = 0.5
        /// 余韻のあと再反応を抑えるクールダウン（秒）。実質ゼロ（すぐ撫で直せる）。
        public var cooldown: Double = 0.25

        /// この距離（px）より遠いと「眠そうな待機」(rest↔doze)へ。これ以内はきりっとした idle。
        public var restRadius: Double = 360
        /// 眠そうな待機の開き目(rest)・とろけ目(doze)の表示時間（秒）。ゆっくり往復。
        public var restOpenDuration: Double = 2.4
        public var restDozeDuration: Double = 0.9
        /// 駆け出し(run↔run2)の足の入れ替え間隔（秒）。小さいほど速く走って見える。
        public var runFlipInterval: Double = 0.16

        public init() {}
    }

    /// 1 フレーム分の入力。
    public struct Input: Sendable {
        /// 前フレームからの経過秒。
        public var dt: Double
        /// カーソルが頭の当たり判定の中にいるか。
        public var inZone: Bool
        /// カーソル速度（px/s）。
        public var speed: Double
        /// 直近の軌跡の左右ゆれ幅（px）。撫で動作らしさの指標。
        public var xWobble: Double
        /// キャラ中心からカーソルまでの距離（px）。遠い待機の判定に使う。
        public var distance: Double
        /// なで反応が有効か（なで設定 ON・画像あり・泳ぎ中でない・ウィンドウ有りを束ねた結果）。
        public var enabled: Bool
        /// キャラが掴まれている最中か（マウス左ボタン保持）。
        public var isHeld: Bool
        /// 掴んだまま移動中か（ドラッグ）。
        public var isDragging: Bool
        /// カーソルへ自分から泳ぎ寄っている最中か（駆け出し表示）。
        public var isMoving: Bool

        public init(dt: Double, inZone: Bool, speed: Double, xWobble: Double,
                    distance: Double = 0, enabled: Bool,
                    isHeld: Bool = false, isDragging: Bool = false, isMoving: Bool = false) {
            self.dt = dt
            self.inZone = inZone
            self.speed = speed
            self.xWobble = xWobble
            self.distance = distance
            self.enabled = enabled
            self.isHeld = isHeld
            self.isDragging = isDragging
            self.isMoving = isMoving
        }
    }

    public var config: Config

    /// 論理状態。
    public private(set) var state: GirlState = .idle
    /// 表示状態（甘えループ中は state と独立に画像を往復させる）。
    public private(set) var display: GirlState = .idle

    /// 撫でられている最中か（pamper / pamperLoop）。
    public var isBeingPatted: Bool { state == .pamper || state == .pamperLoop }

    private var headHoverTime: Double = 0
    private var pamperFlip: Double = 0
    private var cooldownRemaining: Double = 0
    private var endRemaining: Double = 0
    private var restPhase: Double = 0
    private var runPhase: Double = 0
    /// 離脱猶予の残り（秒）。撫で中に良条件へ戻るとリセットされる。
    private var releaseGraceRemaining: Double = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    /// 待機状態へ初期化（裏モードに入った瞬間など）。
    public mutating func reset() {
        state = .idle
        display = .idle
        headHoverTime = 0
        pamperFlip = 0
        cooldownRemaining = 0
        endRemaining = 0
        restPhase = 0
        releaseGraceRemaining = 0
    }

    /// 終了演出（sad）へ固定する。状態機械はこれ以降遷移しない（呼び出し側が update を止める想定）。
    public mutating func enterSad() {
        state = .sad
        display = .sad
    }

    /// 1 フレーム進める。
    public mutating func update(_ input: Input) {
        // クールダウンは実時間で減衰させる（無効中・余韻中も進む）。
        if cooldownRemaining > 0 { cooldownRemaining = max(0, cooldownRemaining - input.dt) }

        // 掴み／ドラッグは最優先（なで設定に関係なく成立する）。
        if input.isHeld {
            headHoverTime = 0
            pamperFlip = 0
            cooldownRemaining = 0
            setState(input.isDragging ? .drag : .hold)
            return
        }
        // 掴みが離れた直後は待機へ戻す。
        if state == .hold || state == .drag { setState(.idle) }

        // カーソルへ駆け出している間は run↔run2 を素早く往復（掴みの次に優先）。
        if input.isMoving {
            headHoverTime = 0
            pamperFlip = 0
            if state != .run {
                state = .run
                display = .run
                runPhase = 0
            } else {
                runPhase += input.dt
                if runPhase > config.runFlipInterval {
                    runPhase = 0
                    display = (display == .run) ? .run2 : .run
                }
            }
            return
        }
        // 駆け出しが終わった直後は待機へ戻す。
        if state == .run { setState(.idle) }

        // なで無効時は待機へ戻す（ただし余韻はそのまま終わらせる）。
        guard input.enabled else {
            if state != .idle && state != .end { setState(.idle) }
            return
        }

        let petLike = input.inZone
            && input.xWobble > config.petWobbleMin
            && input.xWobble < config.petWobbleMax
            && input.speed < config.petSpeedMax

        // クールダウン中は（余韻表示を除き）待機に固定。
        if cooldownRemaining > 0, state != .end {
            setState(.idle)
            headHoverTime = 0
            updateRestDisplay(input)
            return
        }

        switch state {
        case .idle:
            if petLike {
                // 明確な撫で動作なら notice を飛ばして即甘える。
                beginPamper()
            } else if input.inZone && input.speed < config.noticeSpeedMax {
                headHoverTime += input.dt
                if headHoverTime > config.noticeHoverTime { setState(.notice) }
            } else {
                headHoverTime = 0
                // idle 中はカーソル距離で表示を切替（遠い=眠そう、近い=きりっと）。
                updateRestDisplay(input)
            }

        case .notice:
            if !input.inZone {
                setState(.idle); headHoverTime = 0
            } else if petLike || headHoverTime > config.pamperHoverTime {
                beginPamper()
            } else {
                headHoverTime += input.dt
            }

        case .pamper:
            if pamperContinues(input) {
                pamperFlip += input.dt
                if pamperFlip > config.pamperFlipInterval {
                    pamperFlip = 0
                    state = .pamperLoop
                    display = .pamperLoop
                }
            }

        case .pamperLoop:
            if pamperContinues(input) {
                // 甘え中は pamper↔pamperLoop の画像をゆっくり往復。
                pamperFlip += input.dt
                if pamperFlip > config.loopFlipInterval {
                    pamperFlip = 0
                    display = (display == .pamperLoop) ? .pamper : .pamperLoop
                }
            }

        case .end:
            // 余韻中でも撫で直したら即復帰（取りこぼさない）。
            if petLike { beginPamper(); break }
            endRemaining -= input.dt
            if endRemaining <= 0 { setState(.idle) }

        case .sad:
            break // 演出専用。状態機械では遷移しない。

        case .run, .run2, .hold, .drag, .rest, .doze, .teaching:
            // run/hold/drag は上の優先分岐で扱う。rest/doze/teaching は表示専用で state には入らない。
            // 万一ここへ来たら（保持/移動が解けた直後など）待機へ。
            setState(.idle)
        }
    }

    /// idle 中の表示をカーソル距離で切り替える（論理状態は idle のまま）。
    /// 近い: きりっとした待機(idle)。遠い: 開き目(rest)↔とろけ目(doze)をゆっくり往復。
    private mutating func updateRestDisplay(_ input: Input) {
        guard input.distance > config.restRadius else {
            restPhase = 0
            display = .idle
            return
        }
        restPhase += input.dt
        let cycle = config.restOpenDuration + config.restDozeDuration
        let p = cycle > 0 ? restPhase.truncatingRemainder(dividingBy: cycle) : 0
        display = p < config.restOpenDuration ? .rest : .doze
    }

    /// 甘え開始（idle/notice/end のどこからでも）。離脱猶予を満タンにする。
    private mutating func beginPamper() {
        setState(.pamper)
        pamperFlip = 0
        headHoverTime = 0
        releaseGraceRemaining = config.releaseGrace
    }

    /// 甘えを継続すべきか（離脱はヒステリシス付き判定）。
    /// 良条件（ゾーン内かつ速度OK）なら猶予を満タンに戻し true（表示を進めてよい）。
    /// 悪条件（ゾーン外 or 振り払い速度）が `releaseGrace` 秒“継続”したら終了して false。
    /// 猶予中（一瞬のはみ出し）は撫で表示を保ったまま false（画像はそのまま待つ）。
    private mutating func pamperContinues(_ input: Input) -> Bool {
        let bad = !input.inZone || input.speed > config.releaseSpeed
        if bad {
            releaseGraceRemaining -= input.dt
            if releaseGraceRemaining <= 0 { endPamper() }
            return false
        }
        releaseGraceRemaining = config.releaseGrace
        return true
    }

    private mutating func endPamper() {
        setState(.end)
        endRemaining = config.endDuration
        cooldownRemaining = config.cooldown
        releaseGraceRemaining = 0
    }

    private mutating func setState(_ s: GirlState) {
        state = s
        display = s
    }
}
