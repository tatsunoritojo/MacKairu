import Foundation

/// 「消えても15分ごとに復活する」ための launchd ユーザーエージェント管理。
/// `open -g -a <Kairu.app>` を 15 分間隔で実行する。すでに起動中なら再アクティブ化だけ（重複起動しない）。
enum LaunchAgent {
    static let label = "com.tatsu.kairu.resurrect"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 有効（plist が存在する）か。
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 有効化（plist を現在のアプリパスで書き出し、launchd に登録）。
    static func enable() {
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? plistXML(appPath: Bundle.main.bundlePath)
            .write(to: plistURL, atomically: true, encoding: .utf8)
        let domain = "gui/\(getuid())"
        // 既存があれば一度解除してから登録（冪等にする）。
        launchctl(["bootout", domain, plistURL.path])
        launchctl(["bootstrap", domain, plistURL.path])
    }

    /// 無効化（登録解除して plist を削除）。
    static func disable() {
        launchctl(["bootout", "gui/\(getuid())", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    // MARK: - 内部

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static func plistXML(appPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-g</string>
                <string>-a</string>
                <string>\(appPath)</string>
            </array>
            <key>StartInterval</key><integer>900</integer>
            <key>RunAtLoad</key><true/>
        </dict>
        </plist>
        """
    }
}
