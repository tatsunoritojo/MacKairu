import AppKit
import SwiftUI
import KairuCore

/// おせっかいモード（泳ぎ・話しかけ）と自己モニタリング（過負荷の自己検知）。
extension AppModel {

    // MARK: - いたずら（おせっかいモード）

    /// 未設定なら既定オン。
    var isAnnoyEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: "annoyMode") == nil ? true : d.bool(forKey: "annoyMode")
    }

    static let quips = [
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

    func scheduleSwim() {
        swimTimer?.invalidate()
        let delay = Double.random(in: 7...16) // 頻度アップ
        swimTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.swim(); self?.scheduleSwim() }
        }
    }

    /// 移動のトリガ。裏モードはまず「発見ポーズ」を挟んでから走る。通常キャラは即移動。
    func swim() {
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
    func performSwim(goToCursor: Bool) {
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

    func scheduleChatter() {
        chatterTimer?.invalidate()
        let delay = Double.random(in: 30...70) // 頻度アップ
        chatterTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.sayRandomQuip(); self?.scheduleChatter() }
        }
    }

    func sayRandomQuip() {
        guard isAnnoyEnabled, !isChatOpen else { return }
        bubble = Self.quips.randomElement()
        // 数秒で引っ込める。
        Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.isChatOpen == false { self?.bubble = nil }
            }
        }
    }

    // MARK: - 自己モニタリング（過負荷の自己検知）

    /// OS のメモリ圧迫通知を購読する（1回だけ）。
    func startSelfMonitor() {
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
    static func appFootprintMB() -> Double {
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
    var imageMessageCount: Int { messages.reduce(0) { $0 + ($1.image != nil ? 1 : 0) } }

    /// 現在の負荷状況（閾値判定は KairuCore 側）。
    var currentLoad: LoadAssessment {
        LoadAssessment(memCritical: memCritical, memWarning: memWarning,
                       footprintMB: lastFootprintMB, messageCount: messages.count,
                       imageMessageCount: imageMessageCount)
    }
    /// 高負荷（パニック寄り）か。
    var loadSevere: Bool { currentLoad.isSevere }
    /// 何らかの負荷がかかっているか（過負荷表現を出す閾値）。
    var isUnderLoad: Bool { currentLoad.isUnderLoad }
}
