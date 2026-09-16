import XCTest
@testable import KairuCore

/// 保存の成功・失敗を、実秘密ファイル（~/.config/mac-concierge/）を触らず検証する。
final class PersistenceTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairu-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
    }

    private var credURL: URL { tmpDir.appendingPathComponent("credentials.json") }
    private var configURL: URL { tmpDir.appendingPathComponent("config.json") }

    // MARK: - 既定パス（ファイルは読まない）

    func testDefaultURLsStayUnderConfigDir() {
        XCTAssertTrue(
            Credentials.fileURL.path.hasSuffix("/.config/mac-concierge/credentials.json"))
        XCTAssertTrue(
            AppConfig.fileURL.path.hasSuffix("/.config/mac-concierge/config.json"))
        XCTAssertFalse(Credentials.fileURL.path.hasPrefix(tmpDir.path))
        XCTAssertFalse(AppConfig.fileURL.path.hasPrefix(tmpDir.path))
    }

    func testPersistenceErrorMessagesAreJapanese() {
        XCTAssertEqual(
            PersistenceError.createDirectory("/tmp/x").errorDescription,
            "保存先フォルダを作成できませんでした（/tmp/x）。")
        XCTAssertEqual(
            PersistenceError.read("/tmp/r").errorDescription,
            "既存ファイルを読み込めませんでした（/tmp/r）。")
        XCTAssertEqual(
            PersistenceError.decode("/tmp/d").errorDescription,
            "既存ファイルが壊れているため保存を中止しました（/tmp/d）。")
        XCTAssertEqual(
            PersistenceError.encode.errorDescription,
            "保存データを作れませんでした。")
        XCTAssertEqual(
            PersistenceError.write("/tmp/y").errorDescription,
            "ファイルを書き込めませんでした（/tmp/y）。")
        XCTAssertEqual(
            PersistenceError.setPermissions("/tmp/z").errorDescription,
            "ファイルの権限を設定できませんでした（/tmp/z）。")
    }

    // MARK: - Credentials

    func testCredentialsRoundTripAndPermissions() throws {
        try Credentials.set("sk-test-claude", for: .claude, at: credURL)
        XCTAssertEqual(Credentials.get(for: .claude, from: credURL), "sk-test-claude")
        XCTAssertNil(Credentials.get(for: .openai, from: credURL))

        let attrs = try FileManager.default.attributesOfItem(atPath: credURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(perms, 0o600)
    }

    func testCredentialsEmptyValueRemovesKey() throws {
        try Credentials.set("a", for: .claude, at: credURL)
        try Credentials.set("b", for: .openai, at: credURL)
        try Credentials.set("", for: .claude, at: credURL)
        XCTAssertNil(Credentials.get(for: .claude, from: credURL))
        XCTAssertEqual(Credentials.get(for: .openai, from: credURL), "b")
    }

    func testCredentialsSetThrowsWhenParentIsFile() throws {
        let blocker = tmpDir.appendingPathComponent("not-a-dir")
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        let url = blocker.appendingPathComponent("credentials.json")
        XCTAssertThrowsError(try Credentials.set("k", for: .claude, at: url)) { error in
            guard let e = error as? PersistenceError else {
                return XCTFail("expected PersistenceError, got \(error)")
            }
            XCTAssertEqual(e, .createDirectory(blocker.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCredentialsSetThrowsWhenDestinationIsDirectory() throws {
        try FileManager.default.createDirectory(at: credURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try Credentials.set("k", for: .claude, at: credURL)) { error in
            guard let e = error as? PersistenceError else {
                return XCTFail("expected PersistenceError, got \(error)")
            }
            XCTAssertEqual(e, .read(credURL.path))
        }
    }

    func testCredentialsSetDoesNotOverwriteCorruptedFile() throws {
        let corrupted = Data("not-json".utf8)
        try corrupted.write(to: credURL)

        XCTAssertThrowsError(try Credentials.set("k", for: .claude, at: credURL)) { error in
            XCTAssertEqual(error as? PersistenceError, .decode(credURL.path))
        }
        XCTAssertEqual(try Data(contentsOf: credURL), corrupted)
    }

    // MARK: - AppConfig.save

    func testAppConfigSaveWritesBothAndSanitizesConfig() throws {
        let cfg = AppConfig(
            provider: .openai, apiKey: "secret-key",
            model: "gpt-4o", systemPrompt: "指示")
        try cfg.save(to: configURL, credentialsURL: credURL)

        XCTAssertEqual(Credentials.get(for: .openai, from: credURL), "secret-key")
        XCTAssertNil(Credentials.get(for: .claude, from: credURL))

        let disk = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(disk.contains("secret-key"))
        XCTAssertTrue(disk.contains("openai") || disk.contains("gpt-4o"))

        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))
        XCTAssertEqual(decoded.apiKey, "")
        XCTAssertEqual(decoded.provider, .openai)
        XCTAssertEqual(decoded.model, "gpt-4o")
        XCTAssertEqual(decoded.systemPrompt, "指示")
    }

    func testAppConfigSaveDoesNotWriteConfigWhenCredentialsFail() throws {
        let credBlocker = tmpDir.appendingPathComponent("cred-blocker")
        try "x".write(to: credBlocker, atomically: true, encoding: .utf8)
        let badCred = credBlocker.appendingPathComponent("credentials.json")
        let cfg = AppConfig(
            provider: .claude, apiKey: "secret-key",
            model: "claude-opus-4-8", systemPrompt: nil)

        XCTAssertThrowsError(try cfg.save(to: configURL, credentialsURL: badCred))
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: badCred.path))
    }

    func testAppConfigSaveThrowsWhenConfigDestinationIsDirectory() throws {
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        let cfg = AppConfig(
            provider: .gemini, apiKey: "secret-key",
            model: "gemini-2.5-flash", systemPrompt: nil)

        XCTAssertThrowsError(try cfg.save(to: configURL, credentialsURL: credURL)) { error in
            guard let e = error as? PersistenceError else {
                return XCTFail("expected PersistenceError, got \(error)")
            }
            XCTAssertEqual(e, .write(configURL.path))
        }
        // 設定本体が失敗した時点で止まり、credentials は変更しない。
        XCTAssertNil(Credentials.get(for: .gemini, from: credURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: credURL.path))
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }
}
