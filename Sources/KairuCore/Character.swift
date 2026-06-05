import Foundation

/// 常駐キャラクターの種類。
public enum Character: String, CaseIterable, Identifiable, Sendable {
    case dolphin
    case cat
    case penguin
    case chick
    case girl // 裏モード（通常のメニューには出さない）

    public var id: String { rawValue }

    /// 通常のキャラ選択に出す一覧（裏モードは除く）。
    public static var selectable: [Character] { [.dolphin, .cat, .penguin, .chick] }

    public var label: String {
        switch self {
        case .dolphin: return "イルカ"
        case .cat: return "ねこ"
        case .penguin: return "ペンギン"
        case .chick: return "ひよこ"
        case .girl: return "???"
        }
    }

    /// メニューバー/ヘッダーに出す絵文字。
    public var emoji: String {
        switch self {
        case .dolphin: return "🐬"
        case .cat: return "🐱"
        case .penguin: return "🐧"
        case .chick: return "🐤"
        case .girl: return "💗"
        }
    }
}

/// 裏キャラ（女の子）の頭なで状態。各状態に対応する画像ファイル名を持つ。
public enum GirlState: String, CaseIterable, Sendable {
    case idle        // ん…？（待機）
    case notice      // 待ってください、そっちですか？（気づき/反応開始）
    case pamper      // えへへ（甘え始め）
    case pamperLoop  // えへ（甘え継続ループ）
    case end         // …もう終わり？（余韻）

    /// 画像ファイル名（~/.config/mac-concierge/characters/girl/<name>.png）。
    public var fileName: String { rawValue + ".png" }

    /// 取り込んだファイル名から状態を推定（noticed/waiting/pampering/pampering2/afterglowing 等）。
    public static func from(fileName name: String) -> GirlState? {
        let n = name.lowercased()
        if n.contains("afterglow") || n == "end" { return .end }
        if n.contains("pampering2") || n.contains("pamperloop") { return .pamperLoop }
        if n.contains("pamper") { return .pamper }
        if n.contains("wait") || n == "notice" { return .notice }
        if n.contains("notic") || n == "idle" { return .idle }
        return nil
    }
}

/// 裏モードの呪文判定（チャットに打つと切り替わる）。
public enum SecretMode {
    public static func isTriggered(by text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let spells = ["裏モード", "うらもーど", "裏もーど"]
        return spells.contains { t.contains($0) }
    }
}
