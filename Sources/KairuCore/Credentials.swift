import Foundation

/// 設定・API キーのディスク保存に失敗したとき。呼び出し側（設定画面）が表示する。
public enum PersistenceError: LocalizedError, Equatable {
    case createDirectory(String)
    case read(String)
    case decode(String)
    case encode
    case write(String)
    case setPermissions(String)

    public var errorDescription: String? {
        switch self {
        case .createDirectory(let path):
            return "保存先フォルダを作成できませんでした（\(path)）。"
        case .read(let path):
            return "既存ファイルを読み込めませんでした（\(path)）。"
        case .decode(let path):
            return "既存ファイルが壊れているため保存を中止しました（\(path)）。"
        case .encode:
            return "保存データを作れませんでした。"
        case .write(let path):
            return "ファイルを書き込めませんでした（\(path)）。"
        case .setPermissions(let path):
            return "ファイルの権限を設定できませんでした（\(path)）。"
        }
    }
}

/// API キーをローカルファイルに保存する（本人のみ読めるよう権限 0600）。
/// Keychain のようなパスワード確認プロンプトを出さない、CLI 標準的な方式。
/// 保存先: ~/.config/mac-concierge/credentials.json （provider → key）
public enum Credentials {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-concierge/credentials.json")
    }

    public static func get(for provider: Provider) -> String? {
        get(for: provider, from: fileURL)
    }

    /// 指定 URL から読む（テスト用。実秘密ファイルを触らない）。
    static func get(for provider: Provider, from url: URL) -> String? {
        let v = load(from: url)[provider.rawValue]
        return (v?.isEmpty == false) ? v : nil
    }

    public static func set(_ value: String, for provider: Provider) throws {
        try set(value, for: provider, at: fileURL)
    }

    /// 指定 URL に保存する（テスト用。実秘密ファイルを触らない）。
    static func set(_ value: String, for provider: Provider, at url: URL) throws {
        var dict = try loadForUpdate(from: url)
        if value.isEmpty {
            dict.removeValue(forKey: provider.rawValue)
        } else {
            dict[provider.rawValue] = value
        }
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
        } catch {
            throw PersistenceError.createDirectory(dir.path)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data: Data
        do {
            data = try encoder.encode(dict)
        } catch {
            throw PersistenceError.encode
        }
        let temporaryURL = dir.appendingPathComponent(".credentials-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do {
            try data.write(to: temporaryURL, options: .atomic)
        } catch {
            throw PersistenceError.write(url.path)
        }
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
        } catch {
            throw PersistenceError.setPermissions(url.path)
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            throw PersistenceError.write(url.path)
        }
    }

    private static func load(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func loadForUpdate(from url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PersistenceError.read(url.path)
        }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw PersistenceError.decode(url.path)
        }
    }
}
