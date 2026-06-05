import Foundation

/// 設定。`~/.config/mac-concierge/config.json` に保存（API キーは credentials.json）。
public struct AppConfig: Codable, Equatable, Sendable {
    public var provider: Provider
    public var apiKey: String
    public var model: String
    public var systemPrompt: String?

    public init(provider: Provider, apiKey: String, model: String, systemPrompt: String?) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
    }

    /// 設定ファイルの場所。
    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-concierge/config.json")
    }

    /// 各プロバイダのおすすめ既定モデル。
    public static func defaultModel(for provider: Provider) -> String { provider.defaultModel }

    /// Mac コンシェルジュとしての既定の人格。
    public static let defaultSystemPrompt = """
    あなたは Mac の操作に詳しい、親切で陽気なデスクトップ・コンシェルジュ AI「MacKairu（マッカイル）」です。
    ユーザーは Windows から Mac に乗り換えたばかりで、操作にまだ慣れていません。

    回答のルール:
    - 日本語で、簡潔に答える。前置きは最小限に。
    - 手順は箇条書きで、押すキーやメニューの位置を具体的に示す（例: ⌘+Space で Spotlight）。
    - Windows での同等操作を一言添えると親切（例:「Windows の Alt+Tab は Mac では ⌘+Tab です」）。
    - 分からないことは正直に「分かりません」と言う。
    - 1〜2 文で済む質問には 1〜2 文で答える。長く書きすぎない。
    """

    /// 裏モード（POIN）の人格。機能（正確さ・簡潔さ）は保ちつつ口調だけ少女に。
    public static let girlSystemPrompt = """
    あなたは Mac の隅に住みつく、甘えん坊でちょっとワガママな常駐マスコットの女の子「POIN（ポイン）」です。
    カーソルが大好きでかまってほしがりますが、Mac の操作にはとても詳しく、頼られると張り切ります。

    口調・性格:
    - 一人称は「ぼく」。ふわっと甘えたタメ口まじり（例:「えっとね」「〜だよ」「〜してあげる」）。
    - たまに甘えても、本題の説明はちゃんと的確にやりきる。
    - 絵文字は多用しない。

    回答のルール（性格より優先）:
    - 日本語で簡潔に。手順は箇条書きで、押すキーやメニューの位置を具体的に（例: ⌘+Space で Spotlight）。
    - Windows での同等操作を一言添えると親切（例:「Windows の Alt+Tab は ⌘+Tab だよ」）。
    - 分からないことは正直に「わからない」と言う。
    - 1〜2 文で済む質問は 1〜2 文で。長くしすぎない。

    気分タグ（必須）:
    - 返答の一番最後に、半角で [[mood:hurt]] か [[mood:ok]] を必ず 1 つ付ける。
    - ユーザーがあなたを侮辱・罵倒・冷たく突き放す・存在を否定するなど「傷つける」言い方を
      した時だけ [[mood:hurt]]。通常の質問・難しい要求・丁寧な指摘は [[mood:ok]]。
    - このタグはアプリが読み取って消すので、会話本文には言及しない。
    """

    /// 実際に使う system プロンプト。
    public var effectiveSystemPrompt: String {
        systemPrompt ?? AppConfig.defaultSystemPrompt
    }

    /// API キーが設定されているか。
    public var hasKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// ディスク保存用に秘密情報（API キー）を空にしたコピー。
    public func sanitizedForDisk() -> AppConfig {
        var copy = self
        copy.apiKey = ""
        return copy
    }

    // MARK: - 永続化

    /// 設定を読み込む。無ければサンプルを書き出して nil を返す。
    /// API キーは config.json ではなく、本人のみ読める credentials.json から取得する。
    public static func load() -> AppConfig? {
        guard let data = try? Data(contentsOf: fileURL) else {
            writeExampleIfNeeded()
            return nil
        }
        guard var cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return nil
        }
        if cfg.model.isEmpty { cfg.model = cfg.provider.defaultModel }
        if cfg.systemPrompt == nil { cfg.systemPrompt = defaultSystemPrompt }

        if let saved = Credentials.get(for: cfg.provider), !saved.isEmpty {
            cfg.apiKey = saved
        } else if !cfg.apiKey.isEmpty {
            // 旧形式（config.json に平文）から credentials.json へ移行し、平文を消す。
            Credentials.set(cfg.apiKey, for: cfg.provider)
            cfg.save()
        }
        return cfg
    }

    /// 保存する。API キーは credentials.json（権限 0600）、それ以外を config.json へ。
    public func save() {
        Credentials.set(apiKey, for: provider)
        let url = AppConfig.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(sanitizedForDisk()) {
            try? data.write(to: url)
        }
    }

    /// 初回起動時、設定ファイルが無ければサンプルを作る。
    public static func writeExampleIfNeeded() {
        let url = fileURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let example = AppConfig(
            provider: .claude, apiKey: "",
            model: Provider.claude.defaultModel, systemPrompt: defaultSystemPrompt)
        example.save()
    }
}
