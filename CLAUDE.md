# MacKairu / MacConcierge

macOS の画面隅に常駐する、ネイティブ SwiftUI 製のデスクトップ・マスコット兼コンシェルジュ。透過・最前面・Dock 非表示で、クリックすると「Mac の操作」を答える AI チャットになる。Windows からの乗り換えユーザー向け。公開リポジトリ: github.com/tatsunoritojo/MacKairu

## 次セッション着手用
- 現在地: UI詰め一式を `fix/girl-hitzone` で実装し main へ `--no-ff` マージ・**push 済み**（origin/main 同期、マージコミット `d849a3d`、ブランチ削除済み）。内容: (1) POIN頭の当たり判定をキャラ実寸基準に、(2) チャット入力を Return=送信/Shift+Return=改行＋日本語IME変換確定を修正し入力欄を NSTextView 化（IME根本原因は Codex で特定）、(3) 入力欄を chatHeight 連動＋行幅いっぱい、(4) チャット入力待ち中にキャラ上スクロールでサイズ調整、(5) 初回あいさつ強化（吹き出し3段＋弾むモーション）。テスト58件グリーン・ビルド通過。さらに `/Applications/Kairu.app`（表示名 MacKairu）へ配置し Finder/Launchpad から起動可能にした。
- 次アクション: 残課題なし（下記フィール調整がフィードバック待ち）。
- 参照ファイル: `Sources/Kairu/RootView.swift`（`ChatInputTextView`/`ChatInputContainerView`/`ChatInputNSTextView`/`NonInteractiveLabel`/`inputMaxLines`/`canSend`）、`Sources/Kairu/AppModel.swift`（`characterSquare`/`girlHeadZone`/`characterScreenRect`・`startScrollResize`・`tickGirl` の greet 分岐・`maybeGreet`）、`Sources/Kairu/CharacterView.swift`（`greeting` モーション）、`Sources/Kairu/App.swift`（起動時 `startScrollResize` 呼び出し）。
- 未解決 / 別扱い: 実機フィール調整（スクロールの向き・感度 `factor = 1 + delta*0.004`／あいさつの跳ね幅／頭ゾーン値 `headCenterYFrac=0.30`等）はユーザーフィードバック待ち。検証用にローカル defaults（`character=girl`／`dolphinScale`／`girlGreetedV1` リセット）を変更したまま未復元（起動すると POIN で立ち上がる）。`/Applications` のコピーは配置時スナップショットで、`~/MacConcierge` を再ビルドしても自動更新されない。
- 最終更新: 2026-06-13

## 技術スタック

- Swift 6.3 / SwiftUI + AppKit / SwiftPM（swift-tools 5.9、macOS 14+）
- アニメーション・ロジックは純粋層 `KairuCore`（時計非依存の状態機械・テスト対象）と UI 層 `Kairu`（FloatingPanel・描画・状態）に分離
- 動物キャラはコード内ベクター描画。裏キャラ POIN は透過 PNG 画像（`Resources/girl/`）
- 開発コマンドは `Package.swift` / `build.sh` を参照（重複記載しない）
  - テスト: `swift test`　ビルド: `./build.sh`（`Kairu.app` を生成）　起動: `open Kairu.app`

## このプロジェクト固有のルール

- ユーザー向けテキスト・コメント・コミットは日本語、絵文字は使わない（キャラの絵文字はプロダクト内容として例外）
- 所属企業名・業態は一切書かない（README・docs・コミット・コード内すべて）
- 機密（API キー）は `~/.config/mac-concierge/credentials.json`（権限600）。リポジトリや会話に値を出さない
- 裏キャラ POIN の状態は純粋状態機械（`PettingMachine`）に集約。表示優先順位は `AppModel.tickGirl` のチェーンで決まる
- 状態追加時は `GirlState`（`Character.swift`）と `CharacterTests` の件数アサートを同時更新
- main / force push は Red（毎回確認）。ひとまとまりは feature ブランチ → レビュー → main マージ → ブランチ削除
