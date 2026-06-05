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
