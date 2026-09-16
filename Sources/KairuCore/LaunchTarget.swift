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

    /// 現在実行中のアプリ自身が登録対象の時だけ、起動時の再登録を許可する。
    /// 開発・QAコピーからインストール版をRunAtLoadすると、別プロセスが同時起動するため。
    public static func shouldConfigureAgent(
        currentBundlePath: String,
        preferredAppPath: String?
    ) -> Bool {
        guard let preferredAppPath else { return false }
        let current = URL(fileURLWithPath: currentBundlePath).standardizedFileURL.path
        let preferred = URL(fileURLWithPath: preferredAppPath).standardizedFileURL.path
        return current == preferred
    }
}
