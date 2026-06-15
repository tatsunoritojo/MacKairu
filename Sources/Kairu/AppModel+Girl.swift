import AppKit
import SwiftUI
import KairuCore

/// 裏キャラ（POIN）の頭なで状態機械、悲しい/復帰/ロック、キャラクター切替。
extension AppModel {

    // MARK: - 裏キャラ画像

    /// 裏キャラ画像フォルダ。
    static var girlDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-concierge/characters/girl")
    }

    /// 表示すべき裏キャラ画像。未配置の状態はフォールバック連鎖で近い既存画像に代替する。
    var girlCurrentImage: NSImage? {
        for s in girlDisplay.imageChain {
            if let img = girlImages[s] { return img }
        }
        return girlImages[.idle]
    }
    var hasGirlImages: Bool { girlImages[.idle] != nil }

    func loadGirlImages() {
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
    static func isTransparent(_ img: NSImage) -> Bool {
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return false }
        return rep.hasAlpha
    }

    /// なで反応の ON/OFF（既定オン）。
    var isNadeEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: "nadeReaction") == nil ? true : d.bool(forKey: "nadeReaction")
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
    func toggleSecretMode() {
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

    // MARK: - 頭なでなで 状態機械（裏モード）

    func resetGirlState() {
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

    func recordMouse() {
        guard character == .girl else { return }
        mouseHistory.append((NSEvent.mouseLocation, ProcessInfo.processInfo.systemUptime))
    }

    /// 左ボタンのイベントを掴み/ドラッグに変換する。
    func handleMouseButton(_ e: NSEvent) {
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
                whirl.begin(at: NSEvent.mouseLocation)
                updateGirlCursor() // 掴んだ瞬間に closedHand へ
            }
        case .leftMouseDragged:
            guard isHeld else { return }
            // 移動が起きて初めて「ドラッグ」。ここからカーソル位置へ追従させる。
            didDrag = true
            lastDragTime = ProcessInfo.processInfo.systemUptime
            whirl.add(NSEvent.mouseLocation)
            followDragToCursor()
        case .leftMouseUp:
            if isHeld {
                isHeld = false; didDrag = false; saveOrigin()
                // 振り回しが一定以上なら、手を離したあとふらふら目を回す。
                if whirl.exceedsThreshold { dizzyTimer = dizzyDuration; dizzyPhase = 0 }
                whirl.reset()
            }
            updateGirlCursor() // 離した瞬間に openHand へ
        default:
            break
        }
    }

    /// ドラッグ中、画像内に描かれたカーソル先端が現実のマウスに重なるようウィンドウを再配置する。
    func followDragToCursor() {
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

    /// 撫で状態の更新。マウス・ウィンドウから入力を組み立て、遷移は PettingMachine に委譲する。
    func tickGirl() {
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
        if !isHeld { whirl.decay(dt: dt) }

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
    func updateGirlCursor() {
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

    // MARK: - 悲しい / 復帰 / ロック

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

    /// 悲しい状態に入る（心無い言葉・エラー）。移動や発見シーケンスは止める。
    func enterSad() {
        guard character == .girl, !poinLocked else { return }
        isSad = true
        sadPetAccum = 0
        discoverTimer = 0; pendingApproach = false
    }

    /// 傷つける発話を1件登録する（悲しくなり、続けばロックへ）。
    func registerHurt() {
        guard character == .girl, !poinLocked else { return }
        hurtfulStreak += 1
        enterSad()
        if hurtfulStreak >= sadLockThreshold { lockPoin() }
    }

    /// POIN の返答末尾の気分タグ [[mood:...]] を取り除く（表示用）。
    static func stripMoodTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[\[mood:[a-zA-Z]+\]\]"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 撫でて慰められて泣き止む。累計回数を増やす。
    func recoverFromSad() {
        guard isSad else { return }
        isSad = false
        hurtfulStreak = 0
        sadPetAccum = 0
        poinRecoverCount += 1
        bubble = "ぐすっ…ありがとう。"
    }

    /// 悲しいまま傷つけ続けられ、POIN がロックされる。以後はイルカたちしか使えない。
    func lockPoin() {
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

    /// 初回だけ挨拶シーケンスを開始する（裏キャラが初めて現れた時）。
    func maybeGreet() {
        guard character == .girl, hasGirlImages else { return }
        guard !UserDefaults.standard.bool(forKey: greetedKey) else { return }
        UserDefaults.standard.set(true, forKey: greetedKey)
        greetTimer = greetDuration
        girlGreeting = true
        // 既に自アプリがアクティブな時だけ、そっと前面へ。
        // 他アプリで作業中にフォーカスを奪わないため NSApp.activate は使わない。
        if NSApp.isActive { window?.orderFront(nil) }
    }
}
