# MacKairu / MacConcierge

macOS の画面隅に常駐する、ネイティブ SwiftUI 製のデスクトップ・マスコット兼コンシェルジュ。透過・最前面・Dock 非表示で、クリックすると「Mac の操作」を答える AI チャットになる。Windows からの乗り換えユーザー向け。公開リポジトリ: github.com/tatsunoritojo/MacKairu

## 次セッション着手用
- 現在地: 全角（日本語）入力バグ修正＋コードベースのリファクタを `refactor/decompose-appmodel` ブランチで実施（**未 push・main 未マージ**）。各 Phase は build 通過・テストグリーン・Codex レビュー（`codex review --uncommitted`）で挙動不変を確認しながら進めた。
  - **IME 全角入力バグ修正** (`9f6d2d9`, ブランチ `fix/ime-fullwidth`): `ChatInput.swift` の `updateNSView` で、IME 変換中（`hasMarkedText()`）は SwiftUI 側 text を `.string` へ書き戻さないようガード。書き戻すと変換セッションが破棄され全角入力が始められなかった。実機で全角入力可を確認済み。
  - **リファクタ Phase 1** (`92c9585`): `RootView.swift`(666行) を分割 → `ChatInput.swift`（NSTextView 入力欄一式）/ `MarkdownText.swift`（`MarkdownText`/`MessageRow`）/ `RootView.swift`（`RootView`/`SpeechBubble`/`ChatPanel`）。
  - **リファクタ Phase 2** (`e9d030a`): `AppModel.swift`(1196行・神オブジェクト) を責務別 extension に分割。本体=状態＋init、`AppModel+Window`/`+Girl`/`+Mischief`/`+Chat`。ストアドプロパティは Swift 制約で本体に集約。分割意図は `AppModel.swift` 冒頭の doc-comment 参照。
  - **リファクタ Phase 3** (`4eea128`): テスト不能だった純粋ロジックを KairuCore へ抽出＋ユニットテスト。`WhirlAccumulator`（振り回しスコア）/ `LoadAssessment`（過負荷判定の閾値）。テスト 58→69 件。
- 次アクション: (1) `refactor/decompose-appmodel` を main へマージするか判断（Red 操作・要確認。マージ前に実機で POIN/チャット/おせっかいの体感回帰チェック推奨）。(2) claude-self-dashboard 側の改修（v1.0 ダッシュボード / ADR 追記 / 外観エディタ拡張）。
- 参照ファイル: `Sources/Kairu/ChatInput.swift`（`ChatInputTextView`/`ChatInputContainerView`/`ChatInputNSTextView`/`hasMarkedText` ガード）、`Sources/Kairu/AppModel+Girl.swift`（`tickGirl` の優先度チェーン・`handleMouseButton`・`maybeGreet`・`whirl`）、`Sources/Kairu/AppModel+Window.swift`（`characterSquare`/`girlHeadZone`/`startScrollResize`）、`Sources/KairuCore/WhirlAccumulator.swift`・`LoadAssessment.swift`、`Sources/Kairu/CharacterView.swift`（`greeting` モーション）。
- 未解決 / 別扱い: 実機フィール調整（スクロールの向き・感度 `factor = 1 + delta*0.004`／あいさつの跳ね幅／頭ゾーン値 `headCenterYFrac=0.30`等）はユーザーフィードバック待ち。検証用にローカル defaults（`character=girl`／`dolphinScale`／`girlGreetedV1` リセット）を変更したまま未復元（起動すると POIN で立ち上がる）。`/Applications` のコピーは配置時スナップショットで、`~/MacConcierge` を再ビルドしても自動更新されない（リファクタ後の実機確認は `./build.sh` → `open Kairu.app` で再配置）。
- 最終更新: 2026-06-15

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
