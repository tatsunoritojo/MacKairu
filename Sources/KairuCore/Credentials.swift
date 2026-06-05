import Foundation

/// API キーをローカルファイルに保存する（本人のみ読めるよう権限 0600）。
/// Keychain のようなパスワード確認プロンプトを出さない、CLI 標準的な方式。
/// 保存先: ~/.config/mac-concierge/credentials.json （provider → key）
public enum Credentials {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-concierge/credentials.json")
    }

    public static func get(for provider: Provider) -> String? {
        let v = load()[provider.rawValue]
        return (v?.isEmpty == false) ? v : nil
    }

    public static func set(_ value: String, for provider: Provider) {
        var dict = load()
        if value.isEmpty {
            dict.removeValue(forKey: provider.rawValue)
        } else {
            dict[provider.rawValue] = value
        }
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(dict) else { return }
        try? data.write(to: url)
        // 本人のみ読み書き可（0600）。
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }
}
