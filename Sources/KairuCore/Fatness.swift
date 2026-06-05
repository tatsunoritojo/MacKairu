import Foundation

/// チャット履歴の量に応じた「太り具合」(0.0〜1.0)。
/// 履歴をクリアすると 0（スリム）に戻る。
public enum Fatness {
    /// これ以上は太らないメッセージ数。
    public static let maxMessages = 30

    public static func level(messageCount: Int) -> Double {
        guard messageCount > 0 else { return 0 }
        return min(1.0, Double(messageCount) / Double(maxMessages))
    }
}
