import Foundation

/// ネットミーム「お前を消す方法」判定。
/// チャット入力がこの語に一致したら、MacKairu は自分自身を終了する。
public enum SelfDestruct {
    /// 入力テキストが自己消去コマンドかどうか。
    public static func isTriggered(by text: String) -> Bool {
        // 全角/半角スペースを除いて正規化してから部分一致で判定。
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let triggers = ["お前を消す方法", "おまえを消す方法", "オマエを消す方法"]
        return triggers.contains { normalized.contains($0) }
    }
}
