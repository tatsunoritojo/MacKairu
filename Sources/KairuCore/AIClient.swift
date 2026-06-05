import Foundation

/// Claude / OpenAI / Gemini を共通インターフェースで呼ぶクライアント。
public struct AIClient {
    public let config: AppConfig

    public init(config: AppConfig) {
        self.config = config
    }

    /// system プロンプト＋会話履歴を送り、アシスタントの返答テキストを得る。
    public func send(history: [ChatMessage]) async throws -> String {
        guard config.hasKey else { throw AIError.noKey }
        let request = try RequestBuilder.makeRequest(config: config, history: history)
        let json = try await perform(request)
        if let reply = RequestBuilder.parseReply(provider: config.provider, json: json) {
            return reply
        }
        if let msg = RequestBuilder.parseError(json) {
            throw AIError.badResponse(msg)
        }
        throw AIError.badResponse("\(json)")
    }

    private func perform(_ request: URLRequest) async throws -> [String: Any] {
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIError.badResponse(String(data: data, encoding: .utf8) ?? "不明")
            }
            return json
        } catch let e as AIError {
            throw e
        } catch {
            throw AIError.network(error.localizedDescription)
        }
    }
}
