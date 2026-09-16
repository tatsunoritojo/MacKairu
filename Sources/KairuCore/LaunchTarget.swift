import Foundation

/// LaunchAgent が起動するアプリのパスを決める純粋ロジック。
public enum LaunchTarget {
    public static func preferredAppPath(
        installedAppPath: String,
        currentBundlePath: String,
        installedAppExists: Bool
    ) -> String? {
        if installedAppExists { return installedAppPath }
        // 開発ビルドから常駐登録すると、リポジトリの削除・移動後に起動不能になる。
        guard currentBundlePath.hasPrefix("/Applications/") else { return nil }
        return currentBundlePath
    }
}
