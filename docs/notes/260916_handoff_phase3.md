# MacKairu Phase 3 引き継ぎ

最終更新: 2026-09-16

## 現在地

- 作業ディレクトリ: `/Users/tatsu/MacConcierge`
- ブランチ: `fix/qa-high-priority`
- GitHub最新コミット: `3e2fd45 fix(qa): 設定・常駐・複数画面の回帰を修正`
- Phase 1〜3の変更はcommit・push済み。`main` には反映していない。
- Phase 3時点で `swift test` は94件成功、releaseビルド成功。

## 今回完了したこと

- 設定画面のプロバイダ・モデル・APIキー状態の保持を修正。
- LaunchAgentの登録状態確認、解除失敗時の表示、開発・QAコピーからの誤登録を修正。
- `⌘Q` は⌘単独だけを終了確認へ送り、`⇧⌘Q` などを奪わないよう修正。
- 複数ディスプレイ間の表示位置保持と、Separate Spaces環境での画面内回収を修正。
- キャラクター、チャット欄、各操作ボタンにアクセシビリティラベル・操作を追加。
- 応答中も履歴クリア操作を実行できるようにし、実行時は応答キャンセルと履歴削除を明示。

## 次に着手する1件

Phase 4として、実機での手動探索QAを行う。

優先順:

1. 設定画面を閉じて再度開いたときの入力値・保存状態・常駐トグル。
2. IME入力中の送信、`⌘Q` と `⇧⌘Q`、応答中の履歴クリア。
3. VoiceOverでのキャラクター操作、チャット欄リサイズ、送信・添付・設定ボタン。
4. 複数ディスプレイ、Separate Spaces、画面抜き差し後のウィンドウ位置。
5. LaunchAgentのオン・オフ切替とログイン後の再起動挙動。

## 参照ファイル

- `Sources/Kairu/LaunchAgent.swift`
- `Sources/Kairu/SettingsView.swift`
- `Sources/Kairu/App.swift`
- `Sources/Kairu/RootView.swift`
- `Sources/Kairu/AppModel+Window.swift`
- `Sources/KairuCore/LaunchTarget.swift`
- `Sources/KairuCore/WindowPlacement.swift`
- `Tests/KairuCoreTests/LaunchTargetTests.swift`
- `Tests/KairuCoreTests/WindowPlacementTests.swift`

## 検証コマンド

```bash
cd /Users/tatsu/MacConcierge
swift test
swift build -c release --product Kairu
git diff --check
git status --short --branch
```

## 未解決・別扱い

- POINの20Hz論理タイマーは機能上必要なため、CPU実測が低い現状では次段へ保留。
- クリップボードにテキストと画像が同時にある場合の優先順位は未変更。
- 送信Aの失敗中に送信Bを開始した場合の履歴表示は、現仕様を確認してから判断する。
- 実キー入力、VoiceOver、複数ディスプレイの実機操作はmacOSアクセシビリティ権限の制約で未完了。
- `/Applications/Kairu.app` は検証用release成果物へ置換していない。GitHubブランチの作業状態のみ更新済み。

## 再開時の指示

この文書を読み、`fix/qa-high-priority` の最新状態からPhase 4の手動探索QAを開始する。問題を再現したら、再現手順・期待結果・実結果を記録し、critical/high/mediumを先に修正する。修正後はテスト、releaseビルド、実機確認を再実行する。
