import Foundation

public enum AIError: LocalizedError, Equatable {
    case noKey
    case badResponse(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .noKey:
            return "API キーが未設定です。設定からキーを入れてください。"
        case .badResponse(let s):
            return "AI からの応答を解釈できませんでした: \(s)"
        case .network(let s):
            return "通信エラー: \(s)"
        }
    }
}

/// プロバイダごとの HTTP リクエスト生成と応答解析（純粋関数・ネットワーク非依存・テスト可能）。
public enum RequestBuilder {

    /// system プロンプト＋会話履歴から URLRequest を作る。
    public static func makeRequest(config: AppConfig, history: [ChatMessage]) throws -> URLRequest {
        switch config.provider {
        case .claude: return try claude(config, history)
        case .openai: return try openai(config, history)
        case .gemini: return try gemini(config, history)
        }
    }

    /// 応答 JSON からアシスタントのテキストを取り出す。失敗時は nil。
    public static func parseReply(provider: Provider, json: [String: Any]) -> String? {
        switch provider {
        case .claude:
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            let text = content.compactMap { block -> String? in
                (block["type"] as? String) == "text" ? block["text"] as? String : nil
            }.joined()
            return text.isEmpty ? nil : text
        case .openai:
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String else { return nil }
            return text
        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            let text = parts.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
    }

    /// 応答 JSON からエラーメッセージを取り出す（あれば）。
    public static func parseError(_ json: [String: Any]) -> String? {
        (json["error"] as? [String: Any])?["message"] as? String
    }

    // MARK: - プロバイダ別

    private static func claude(_ config: AppConfig, _ history: [ChatMessage]) throws -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let messages = history.map { m -> [String: Any] in
            let role = m.role == .user ? "user" : "assistant"
            guard let img = m.image else {
                return ["role": role, "content": m.text]
            }
            // 画像つきは content をブロック配列に。
            let content: [[String: Any]] = [
                ["type": "image",
                 "source": ["type": "base64", "media_type": img.mediaType, "data": img.base64]],
                ["type": "text", "text": m.text],
            ]
            return ["role": role, "content": content]
        }
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 1024,
            "system": config.effectiveSystemPrompt,
            "messages": messages,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func openai(_ config: AppConfig, _ history: [ChatMessage]) throws -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        var messages: [[String: Any]] = [["role": "system", "content": config.effectiveSystemPrompt]]
        messages += history.map { m -> [String: Any] in
            let role = m.role == .user ? "user" : "assistant"
            guard let img = m.image else {
                return ["role": role, "content": m.text]
            }
            let content: [[String: Any]] = [
                ["type": "text", "text": m.text],
                ["type": "image_url",
                 "image_url": ["url": "data:\(img.mediaType);base64,\(img.base64)"]],
            ]
            return ["role": role, "content": content]
        }
        let body: [String: Any] = ["model": config.model, "messages": messages]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func gemini(_ config: AppConfig, _ history: [ChatMessage]) throws -> URLRequest {
        var comps = URLComponents(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(config.model):generateContent")!
        comps.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let contents = history.map { m -> [String: Any] in
            let role = m.role == .user ? "user" : "model"
            var parts: [[String: Any]] = []
            if let img = m.image {
                parts.append(["inline_data": ["mime_type": img.mediaType, "data": img.base64]])
            }
            parts.append(["text": m.text])
            return ["role": role, "parts": parts]
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": config.effectiveSystemPrompt]]],
            "contents": contents,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}
