# MacKairu / MacConcierge

macOS の画面隅に常駐する、ネイティブ SwiftUI 製のデスクトップ・マスコット兼コンシェルジュ。透過・最前面・Dock 非表示で、クリックすると「Mac の操作」を答える AI チャットになる。Windows からの乗り換えユーザー向け。公開リポジトリ: github.com/tatsunoritojo/MacKairu

## 次セッション着手用
- 現在地: POIN（裏キャラ）一式を main へマージ・push 済み（origin/main と同期）。今セッションでは撫で余韻を「撫で時間連動の指数飽和カーブ（下限0.5s・上限4s・τ=6）」化、チャット欄のリサイズ対応、ウィンドウの画面内動的配置を実装。テスト58件グリーン。
- 次アクション: 残課題なし。あえて挙げれば、余韻カーブ（τ=6／下限0.5s）とチャットリサイズ・グリップの実機体感チューニング（ユーザーフィードバック待ち）。
- 参照ファイル: `Sources/KairuCore/PettingMachine.swift`（`endPamper` の余韻式・`Config`）、`Sources/Kairu/AppModel.swift`（`applyWindowSize` 画面内クランプ・`chatResize*`）、`Sources/Kairu/RootView.swift`（`resizeGrip`）
- 未解決 / 別扱い: Codex レビューはユーザー判断で通さずマージ確定（対象外）。
- 最終更新: 2026-06-06

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
