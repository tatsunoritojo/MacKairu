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

/// 裏キャラ（女の子）の頭なで・移動・ドラッグ状態。各状態に対応する画像ファイル名を持つ。
public enum GirlState: String, CaseIterable, Sendable {
    case idle        // ん…？（カーソルが近い時のきりっとした待機）
    case rest        // ふぅ…（カーソルが遠い時の待機・開き目）
    case doze        // すぅ…（カーソルが遠い時の待機・とろけ目／眠そう）
    case run         // たっ（カーソルへ駆け出す・1枚目）
    case run2        // たたっ（カーソルへ駆け出す・2枚目／走りループ）
    case notice      // 待ってください、そっちですか？（気づき/反応開始）
    case pamper      // えへへ（甘え始め）
    case pamperLoop  // えへ（甘え継続ループ）
    case hold        // わっ（掴まれて持ち上げられた・驚き）
    case drag        // えへへ（掴まれたまま運ばれている・うれしい）
    case teaching    // ここがポイント！（チャットで解説している時）
    case end         // …もう終わり？（余韻）
    case sad         // 「お前を消す方法」で終了される時の悲しい顔（演出専用）

    /// 画像ファイル名（girl/<name>.png）。
    public var fileName: String { rawValue + ".png" }

    /// 表示用フォールバック連鎖。新規画像が未配置でも近い既存画像で代替し、欠けは idle で埋める。
    public var imageChain: [GirlState] {
        switch self {
        case .doze:       return [.doze, .rest, .idle]
        case .rest:       return [.rest, .idle]
        case .run2:       return [.run2, .run, .idle]
        case .run:        return [.run, .idle]
        case .pamperLoop: return [.pamperLoop, .pamper, .idle]
        case .drag:       return [.drag, .hold, .pamper, .idle]
        case .hold:       return [.hold, .notice, .idle]
        case .teaching:   return [.teaching, .notice, .idle]
        default:          return [self, .idle]
        }
    }

    /// 取り込んだファイル名から状態を推定（noticed/waiting/pampering/run/hold/drag/rest/doze/sad 等）。
    public static func from(fileName name: String) -> GirlState? {
        let n = name.lowercased()
        if n.contains("sad") { return .sad }
        if n.contains("afterglow") || n == "end" { return .end }
        if n.contains("teach") || n.contains("tip") || n.contains("explain") { return .teaching }
        if n.contains("drag") { return .drag }
        if n.contains("hold") || n.contains("grab") || n.contains("lift") || n.contains("pick") { return .hold }
        if n.contains("run2") || n.contains("dash2") || n.contains("walk2") { return .run2 }
        if n.contains("run") || n.contains("dash") || n.contains("walk") { return .run }
        if n.contains("pampering2") || n.contains("pamperloop") { return .pamperLoop }
        if n.contains("pamper") { return .pamper }
        if n.contains("doze") || n.contains("sleep") || n.contains("rest2") { return .doze }
        if n.contains("rest") || n.contains("relax") { return .rest }
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
