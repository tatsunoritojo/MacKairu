import AppKit
import SwiftUI
import KairuCore

/// 文脈の取り込み（クリップボード／スクショ）とメッセージ送信。
extension AppModel {

    // MARK: - 設定の再読込

    func reloadConfig() {
        config = AppConfig.load()
        if config?.hasKey == true {
            bubble = "準備OK！何でも聞いてね \(character.emoji)"
        } else {
            bubble = "API キーがまだ未設定です（\(character.emoji)→「設定…」から入力）"
        }
    }

    // MARK: - 文脈の取り込み（クリップボード／スクショ）

    /// クリップボードを取り込む（テキスト優先、なければ画像）。
    func attachClipboard() {
        let pb = NSPasteboard.general
        if let s = pb.string(forType: .string),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingText = s
            pendingImage = nil
            pendingImagePreview = nil
            bubble = nil
        } else if let img = NSImage(pasteboard: pb), let b64 = Self.pngBase64(img) {
            pendingImage = ImageAttachment(base64: b64, mediaType: "image/png")
            pendingImagePreview = img
            pendingText = nil
        } else {
            bubble = "クリップボードに取り込める内容がありません"
        }
    }

    /// スクショ撮影を起動（範囲ドラッグ）。撮ったら画像として取り込む。
    func captureScreenshot() {
        guard !isCapturing else { return }
        isCapturing = true
        let path = NSTemporaryDirectory() + "kairu_capture.png"
        // 自分のUIを写さないよう、撮影中はパネルを隠す。
        window?.orderOut(nil)
        DispatchQueue.global().async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-x", path]
            try? p.run()
            p.waitUntilExit()
            let data = p.terminationStatus == 0
                ? try? Data(contentsOf: URL(fileURLWithPath: path)) : nil
            try? FileManager.default.removeItem(atPath: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.window?.orderFrontRegardless()
                self.isCapturing = false
                // キャンセル（Esc）時は data が nil。
                guard let data, let img = NSImage(data: data) else { return }
                self.pendingText = nil
                self.pendingImage = ImageAttachment(base64: data.base64EncodedString(),
                                                    mediaType: "image/png")
                self.pendingImagePreview = img
                self.isChatOpen = true
                self.applyWindowSize(animated: true)
                NSApp.activate(ignoringOtherApps: true)
                self.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// 取り込み中の文脈を破棄。
    func clearPending() {
        pendingText = nil
        pendingImage = nil
        pendingImagePreview = nil
    }

    /// 取り込み中の文脈があるか。
    var hasContext: Bool { pendingText != nil || pendingImage != nil }

    /// クイック操作（プリセット指示を入れて送信）。
    func quickAction(_ prompt: String) {
        draft = prompt
        send()
    }

    static func pngBase64(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
    }

    // MARK: - メッセージ送信

    func send() {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // 取り込み中の文脈があれば、入力が空でも送れる（クイック操作用）。
        guard (!typed.isEmpty || hasContext), !isThinking else { return }
        draft = ""

        // ネットミーム: 「お前を消す方法」（文脈の有無に関わらず生入力で判定）。
        if SelfDestruct.isTriggered(by: typed) {
            messages.append(ChatMessage(role: .user, text: typed))
            if character == .girl, girlImages[.sad] != nil {
                // 裏モード: 悲しい顔でブルブル震えながら 5 秒かけてフェードアウト。
                messages.append(ChatMessage(role: .assistant,
                    text: "え…ぼくを、消すんですか…？\n……ばいばい。"))
                stopPatTracking()
                pettingMachine.enterSad()
                girlDisplay = .sad
                girlDying = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { KairuQuit.now() }
            } else {
                messages.append(ChatMessage(role: .assistant,
                    text: "「お前を消す方法」について調べました。\n……さようなら。"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { KairuQuit.now() }
            }
            clearPending()
            return
        }

        // 裏モードの呪文。
        if SecretMode.isTriggered(by: typed) {
            messages.append(ChatMessage(role: .user, text: typed))
            toggleSecretMode()
            clearPending()
            return
        }

        // 取り込んだテキスト／画像を、ユーザーメッセージに合成する。
        var text = typed
        if let ctx = pendingText {
            let q = typed.isEmpty ? "これについて教えて。" : typed
            text = "次のテキストについて、\(q)\n\n\"\"\"\n\(ctx)\n\"\"\""
        } else if pendingImage != nil, typed.isEmpty {
            text = "この画面について、何ができるか・どう操作するか教えて。"
        }
        let image = pendingImage
        messages.append(ChatMessage(role: .user, text: text, image: image))
        clearPending()

        // 心無い言葉の判定。明白な語はキーワードで即反応（遅延ゼロ）。
        // 微妙な冷たさは、POIN 自身の返答に付く気分タグ（後述）で拾う。
        hurtRegisteredForSend = false
        if character == .girl, !poinLocked, HurtfulText.isHurtful(typed) {
            registerHurt()
            hurtRegisteredForSend = true
        }

        guard let config else {
            messages.append(ChatMessage(role: .assistant,
                text: "設定が読み込めません。\(character.emoji)→「設定…」から API キーを入れてください。"))
            return
        }
        isThinking = true
        // 裏モード（POIN）のときは少女の人格プロンプトに差し替える。
        var requestConfig = config
        if character == .girl { requestConfig.systemPrompt = AppConfig.girlSystemPrompt }
        let client = AIClient(config: requestConfig)
        let history = messages
        Task {
            do {
                var reply = try await client.send(history: history)
                // 裏モードは返答末尾の気分タグを読み取り、表示からは消す。
                var hurt = false
                if self.character == .girl {
                    hurt = reply.contains("[[mood:hurt]]")
                    reply = Self.stripMoodTags(reply)
                }
                self.messages.append(ChatMessage(role: .assistant, text: reply))
                // POIN 自身が「傷ついた」と示したら悲しくなる（キーワード未検知時のみ）。
                if hurt, !self.hurtRegisteredForSend { self.registerHurt() }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.messages.append(ChatMessage(role: .assistant, text: "⚠️ \(msg)"))
                // 処理失敗・エラーでも悲しい顔になる（撫でて慰めると戻る）。
                self.enterSad()
            }
            self.isThinking = false
        }
    }
}
