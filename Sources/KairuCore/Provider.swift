import Foundation

/// どの AI プロバイダを使うか。
public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case openai
    case gemini

    public var id: String { rawValue }

    /// 設定 UI に出す表示名。
    public var label: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini (Google)"
        }
    }

    /// API キーの取得ページ。
    public var keyURL: String {
        switch self {
        case .claude: return "https://console.anthropic.com/settings/keys"
        case .openai: return "https://platform.openai.com/api-keys"
        case .gemini: return "https://aistudio.google.com/app/apikey"
        }
    }

    /// プルダウンに出すモデル候補（先頭が既定）。
    public var models: [String] {
        switch self {
        case .claude: return ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5"]
        case .openai: return ["gpt-4o", "gpt-4o-mini", "gpt-4.1"]
        case .gemini: return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
        }
    }

    /// おすすめ既定モデル。
    public var defaultModel: String { models.first ?? "" }

    /// モデル ID に添える短い説明（プルダウン表示用）。
    public func modelNote(_ id: String) -> String {
        switch id {
        case "claude-opus-4-8": return "高性能・おすすめ"
        case "claude-sonnet-4-6": return "バランス"
        case "claude-haiku-4-5": return "高速・低コスト"
        case "gpt-4o": return "高性能"
        case "gpt-4o-mini": return "高速・低コスト"
        case "gpt-4.1": return "高性能"
        case "gemini-2.5-flash": return "高速・低コスト"
        case "gemini-2.5-pro": return "高性能"
        case "gemini-2.0-flash": return "軽量"
        default: return ""
        }
    }
}
