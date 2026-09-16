import AppKit
import SwiftUI
import KairuCore

/// ウィンドウ／キャラのサイズ、当たり判定ゾーン、リサイズ、位置の永続化。
extension AppModel {

    /// 履歴量に応じた太り具合（0〜1）。裏キャラは太らない。
    var fatness: Double {
        character == .girl ? 0 : Fatness.level(messageCount: messages.count)
    }

    // MARK: - ウィンドウサイズ（イルカの倍率＋太り具合に応じて変わる）

    var dolphinSide: CGFloat { 120 * dolphinScale * (1 + fatness * 0.25) }

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
    static let contentPad: CGFloat = 12
    /// 頭ゾーン: 正方形上端からの中心 Y 位置・楕円半径（いずれも side に対する割合・実機調整値）。
    static let headCenterYFrac: CGFloat = 0.30
    static let headRadiusXFrac: CGFloat = 0.42
    static let headRadiusYFrac: CGFloat = 0.30

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

    // MARK: - チャット開閉 / ウィンドウ追従

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
        let proposed = NSRect(x: old.maxX - target.width, y: old.minY,
                              width: target.width, height: target.height)
        let newFrame = WindowPlacement.constrainedFrame(
            proposed,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            keepTopVisible: isChatOpen)
        window.setFrame(newFrame, display: true, animate: animated)
        saveOrigin()
    }

    /// 保存座標やディスプレイ構成変更で画面外へ出たウィンドウを回収する。
    func ensureWindowVisible() {
        guard let window else { return }
        let constrained = WindowPlacement.constrainedFrame(
            window.frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            keepTopVisible: isChatOpen)
        guard constrained != window.frame else { return }
        window.setFrame(constrained, display: true)
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
    ///
    /// 設計メモ:
    /// - 全キャラ共通の機能なので girl 専用の startPatTracking/stopPatTracking とは別管理。
    ///   アプリ生存期間と同じ寿命の単一モニタとして持ち、明示的な解放はしない（多重登録のみ guard で防ぐ）。
    /// - 他のローカルモニタと違い、ここでは「イベントを消費(nil)するか素通り(e)させるか」を同期で
    ///   返す必要があるため、DispatchQueue.main.async には逃がせない。scrollWheel のローカルモニタは
    ///   main スレッドで発火するので、@MainActor 隔離状態へ同期アクセスして問題ない。
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
        chatRequestGate.invalidate()
        chatTask?.cancel()
        chatTask = nil
        isThinking = false
        messages = []
        chatError = nil
        bubble = nil
    }

    // MARK: - 位置の永続化

    func persistPosition() { saveOrigin() }

    func saveOrigin() {
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
