import Foundation

/// 自己モニタリング（過負荷の自己検知）の判定ロジック。
///
/// メモリ圧迫・自プロセスのフットプリント・会話量（メッセージ数／画像枚数）から、
/// 「負荷がかかっている」「高負荷（パニック寄り）」を判定する純粋ロジック。
/// 閾値をここに集約することで、過負荷表現を出すかどうかの方針をテストで固定できる。
public struct LoadAssessment: Sendable {
    public var memCritical: Bool
    public var memWarning: Bool
    public var footprintMB: Double
    public var messageCount: Int
    public var imageMessageCount: Int

    public init(memCritical: Bool, memWarning: Bool, footprintMB: Double,
                messageCount: Int, imageMessageCount: Int) {
        self.memCritical = memCritical
        self.memWarning = memWarning
        self.footprintMB = footprintMB
        self.messageCount = messageCount
        self.imageMessageCount = imageMessageCount
    }

    /// 高負荷（パニック寄り）か。
    public var isSevere: Bool {
        memCritical || footprintMB >= 1200 || messageCount >= 80 || imageMessageCount >= 10
    }

    /// 何らかの負荷がかかっているか（過負荷表現を出す閾値）。
    public var isUnderLoad: Bool {
        isSevere || memWarning || footprintMB >= 700
            || messageCount >= 40 || imageMessageCount >= 5
    }
}
