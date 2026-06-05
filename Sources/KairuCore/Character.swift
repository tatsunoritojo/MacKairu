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
        case .girl: return "✨"
        }
    }
}

/// 裏キャラ（女の子）の頭なで・移動・ドラッグ状態。各状態に対応する画像ファイル名を持つ。
public enum GirlState: String, CaseIterable, Sendable {
    case idle        // ん…？（カーソルが近い時のきりっとした待機）
    case rest        // ふぅ…（旧・遠い待機。現在は未使用、フォールバック用に保持）
    case doze        // すぅ…（旧・遠い待機。現在は未使用）
    case search      // どこ…？（カーソルが遠い時、キョロキョロ探す1）
    case search2     // んー…？（キョロキョロ探す2）
    case found       // いた！（移動直前の発見ポーズ）
    case run         // たっ（カーソルへ駆け出す・1枚目）
    case run2        // たたっ（カーソルへ駆け出す・2枚目／走りループ）
    case notice      // 待ってください、そっちですか？（気づき/反応開始）
    case pamper      // えへへ（甘え始め）
    case pamperLoop  // えへ（甘え継続ループ）
    case hold        // わっ（掴まれて持ち上げられた・驚き）
    case drag        // えへへ（掴まれたまま運ばれている・うれしい）
    case thinking    // うーん…（AIが返答を考えている間）
    case thinking2   // むむ…（思考中の差分）
    case teaching    // ここがポイント！（チャットで解説している時）
    case teaching2   // ね？（解説中の表情差分・ウインク）
    case dizzy       // ぐるぐる…（振り回されて目を回している）
    case dizzy2      // ふらふら…（目回しの差分）
    case greet       // やっほー！（初回起動の挨拶1）
    case greet2      // こんにちはー！（初回起動の挨拶2）
    case greet3      // よろしくねー！（初回起動の挨拶3）
    case upset       // ぐすっ…（心無い言葉やエラーで悲しい1）
    case upset2      // うぅ…（悲しい2）
    case overload    // ふぅ…（自己モニタリング: 負荷が重い・処理中）
    case overload2   // ぱんく！（自己モニタリング: 高負荷でパニック）
    case end         // …もう終わり？（余韻）
    case sad         // 「お前を消す方法」で終了される時の悲しい顔（演出専用）

    /// 画像ファイル名（girl/<name>.png）。
    public var fileName: String { rawValue + ".png" }

    /// 絵ごとのキャラ描画サイズ差を吸収する表示倍率。
    /// teaching2 は素材内でキャラが約3.7%大きく描かれているため、teaching と同じ見かけに合わせる。
    public var displayScale: Double {
        switch self {
        case .teaching2: return 0.963
        case .dizzy2:    return 0.983  // dizzy と同じ見かけサイズに合わせる
        case .thinking2: return 1.015  // thinking と同じ見かけサイズに合わせる
        case .search2:   return 1.028  // search と同じ見かけサイズに合わせる
        default:         return 1.0
        }
    }

    /// 画像内に描かれたカーソル先端の位置（画像座標・左上原点の正規化 0〜1）。
    /// 掴み/ドラッグ時に、現実のマウスをこの位置へ重ねるためのアンカー。無い状態は nil。
    public var cursorAnchor: (x: Double, y: Double)? {
        switch self {
        case .drag: return (0.52, 0.05)
        case .hold: return (0.61, 0.05)
        default:    return nil
        }
    }

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
        case .thinking:   return [.thinking, .teaching, .notice, .idle]
        case .thinking2:  return [.thinking2, .thinking, .teaching, .idle]
        case .teaching:   return [.teaching, .notice, .idle]
        case .teaching2:  return [.teaching2, .teaching, .notice, .idle]
        case .dizzy:      return [.dizzy, .idle]
        case .dizzy2:     return [.dizzy2, .dizzy, .idle]
        case .search:     return [.search, .idle]
        case .search2:    return [.search2, .search, .idle]
        case .found:      return [.found, .notice, .idle]
        case .upset:      return [.upset, .sad, .idle]
        case .upset2:     return [.upset2, .upset, .sad, .idle]
        case .overload:   return [.overload, .overload2, .idle]
        case .overload2:  return [.overload2, .overload, .idle]
        case .greet2:     return [.greet2, .greet, .idle]
        case .greet3:     return [.greet3, .greet, .idle]
        default:          return [self, .idle]
        }
    }

    /// 取り込んだファイル名から状態を推定（noticed/waiting/pampering/run/hold/drag/rest/doze/sad 等）。
    public static func from(fileName name: String) -> GirlState? {
        let n = name.lowercased()
        if n.contains("sad") { return .sad }
        if n.contains("afterglow") || n == "end" { return .end }
        if n.contains("teaching2") || n.contains("teach2") || n.contains("tip2") { return .teaching2 }
        if n.contains("teach") || n.contains("tip") || n.contains("explain") { return .teaching }
        if n.contains("confused2") || n.contains("dizzy2") { return .dizzy2 }
        if n.contains("confus") || n.contains("dizzy") { return .dizzy }
        if n.contains("thinking2") || n.contains("thiking2") || n.contains("think2") { return .thinking2 }
        if n.contains("thinking") || n.contains("thiking") || n.contains("think") { return .thinking }
        if n.contains("greeting2") || n.contains("greet2") { return .greet2 }
        if n.contains("greeting3") || n.contains("greet3") { return .greet3 }
        if n.contains("greet") || n.contains("hello") || n.contains("hi") { return .greet }
        if n.contains("wondering2") || n.contains("search2") || n.contains("look2") { return .search2 }
        if n.contains("wondering") || n.contains("search") || n.contains("look") { return .search }
        if n.contains("got_it") || n.contains("gotit") || n.contains("found") { return .found }
        if n.contains("upset2") || n.contains("cry2") || n.contains("sad2") { return .upset2 }
        if n.contains("upset") || n.contains("cry") || n.contains("teary") { return .upset }
        if n.contains("overload2") || n.contains("panic") { return .overload2 }
        if n.contains("overload") || n.contains("heavy") || n.contains("overheat") { return .overload }
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

/// 心無い言葉の判定（POIN を悲しませる）。誤検知を避けて控えめな語彙のみ。
public enum HurtfulText {
    private static let words = [
        "死ね", "しね", "氏ね", "消えろ", "きえろ", "うざい", "ウザい", "うっとうしい",
        "きもい", "キモい", "気持ち悪い", "ばか", "バカ", "馬鹿", "あほ", "アホ",
        "ブス", "ぶす", "クズ", "くず", "ゴミ", "無能", "黙れ", "だまれ", "うるさい",
        "嫌い", "きらい", "むかつく", "ムカつく",
        "stupid", "idiot", "ugly", "useless", "shut up", "i hate you", "dumb",
    ]
    public static func isHurtful(_ text: String) -> Bool {
        let t = text.lowercased()
        return words.contains { t.contains($0.lowercased()) }
    }
}

/// POIN 呼び出しの呪文判定（チャットに打つと切り替わる）。
/// 「POIN」で召喚。旧「裏モード」も後方互換で残す。
public enum SecretMode {
    public static func isTriggered(by text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        // 短い英単語の誤爆（point 等）を避けるため、英字呪文は完全一致で判定。
        let exact = ["poin", "ぽいん", "ポイン"]
        let legacy = ["裏モード", "うらもーど", "裏もーど"]
        return exact.contains(t) || legacy.contains { t.contains($0) }
    }
}
