import Foundation
import KairuCore

/// 「消えても15分ごとに復活する」ための launchd ユーザーエージェント管理。
/// `open -g -a <Kairu.app>` を 15 分間隔で実行する。すでに起動中なら再アクティブ化だけ（重複起動しない）。
enum LaunchAgent {
    static let label = "com.tatsu.kairu.resurrect"
    static let installedAppPath = "/Applications/Kairu.app"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 有効または解除待ち（plist が残っている／launchd に登録済み）か。
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path) || isLoaded
    }

    /// 起動中のコピーが登録対象そのものか。QA/開発コピーから別版を起動しないために使う。
    static var canConfigureFromCurrentBundle: Bool {
        let target = LaunchTarget.preferredAppPath(
            installedAppPath: installedAppPath,
            currentBundlePath: Bundle.main.bundlePath,
            installedAppExists: FileManager.default.fileExists(atPath: installedAppPath))
        return LaunchTarget.shouldConfigureAgent(
            currentBundlePath: Bundle.main.bundlePath,
            preferredAppPath: target)
    }

    /// 有効化（インストール版を優先して plist を書き出し、launchd に登録）。
    @discardableResult
    static func enable() -> Bool {
        guard canConfigureFromCurrentBundle else { return false }
        guard let appPath = LaunchTarget.preferredAppPath(
            installedAppPath: installedAppPath,
            currentBundlePath: Bundle.main.bundlePath,
            installedAppExists: FileManager.default.fileExists(atPath: installedAppPath)) else {
            return false
        }
        let dir = plistURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try plistXML(appPath: appPath)
                .write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        let domain = "gui/\(getuid())"
        // 既存があれば一度解除してから登録（冪等にする）。
        if isLoaded, launchctl(["bootout", domain, plistURL.path]) != 0 {
            return false
        }
        guard launchctl(["bootstrap", domain, plistURL.path]) == 0 else {
            // 登録できなかったplistを「有効」と誤表示しない。
            try? FileManager.default.removeItem(at: plistURL)
            return false
        }
        return isEnabled
    }

    /// 無効化（登録解除して plist を削除）。
    @discardableResult
    static func disable() -> Bool {
        guard canConfigureFromCurrentBundle else { return false }
        if isLoaded,
           launchctl(["bootout", "gui/\(getuid())/\(label)"]) != 0 {
            return false
        }
        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
        } catch {
            return false
        }
        return !isLoaded && !FileManager.default.fileExists(atPath: plistURL.path)
    }

    // MARK: - 内部

    private static var isLoaded: Bool {
        launchctl(["print", "gui/\(getuid())/\(label)"]) == 0
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return -1
        }
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
