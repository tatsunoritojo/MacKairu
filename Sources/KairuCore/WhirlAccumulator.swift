import Foundation

/// ドラッグの「振り回し」量を累積する純粋ロジック。
///
/// 方向転換が大きいほど・速いほど多く溜まり、まっすぐ運ぶだけでは溜まらない。
/// ブンブン振り回すと一気に溜まる。手を離したときスコアが閾値を超えていれば、
/// 「目を回す」演出（dizzy）に使う。UI / AppKit から独立しており、座標を渡すだけ。
public struct WhirlAccumulator: Sendable {
    /// 累積スコア。
    public private(set) var score: Double = 0
    private var lastPos: CGPoint?
    private var lastAngle: Double?

    /// これを超えて振り回されると目を回す。
    public static let threshold: Double = 9
    /// 振り回しが穏やかだと冷める速さ（score / 秒）。
    public static let decayPerSec: Double = 2.5

    public init() {}

    /// 掴み始め。基準位置を置き、スコアと角度履歴をリセットする。
    public mutating func begin(at p: CGPoint) {
        score = 0
        lastPos = p
        lastAngle = nil
    }

    /// 新しいカーソル位置を取り込み、方向転換量に応じてスコアを足す。
    /// 微小な移動（3px 以下）は無視し、向きが変わったぶんだけ（移動量で重み付け）加算する。
    public mutating func add(_ p: CGPoint) {
        defer { lastPos = p }
        guard let lp = lastPos else { return }
        let dx = p.x - lp.x, dy = p.y - lp.y
        let dist = hypot(dx, dy)
        guard dist > 3 else { return }
        let angle = atan2(dy, dx)
        if let last = lastAngle {
            var d = abs(angle - last)
            if d > .pi { d = 2 * .pi - d }      // 0〜π の方向転換量
            score += Double(d) * Double(min(dist, 40)) / 40
        }
        lastAngle = angle
    }

    /// 穏やかな時間経過でスコアを少しずつ冷ます。
    public mutating func decay(dt: Double) {
        if score > 0 { score = max(0, score - dt * Self.decayPerSec) }
    }

    /// 手を離したとき「目を回す」ほど振り回されたか。
    public var exceedsThreshold: Bool { score > Self.threshold }

    /// 掴み終わり。スコアと履歴をクリアする。
    public mutating func reset() {
        score = 0
        lastPos = nil
        lastAngle = nil
    }
}
