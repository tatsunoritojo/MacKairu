import SwiftUI
import AppKit
import KairuCore

/// 常駐ウィンドウの中身。下にイルカ、開くと上にチャットパネル。
struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer(minLength: 0) // コンテンツを下端に寄せる
            if model.isChatOpen {
                ChatPanel(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let bubble = model.bubble {
                SpeechBubble(text: bubble)
                    .transition(.opacity)
            }

            CharacterView(character: model.character, thinking: model.isThinking,
                          scale: model.dolphinScale, fat: model.fatness,
                          swimming: model.isSwimming,
                          flip: model.character == .girl ? model.girlFlip : model.facingLeft,
                          girlImage: model.girlCurrentImage, girlImageScale: model.girlDisplay.displayScale,
                          patted: model.isBeingPatted, dying: model.girlDying,
                          dizzy: model.girlDisplay == .dizzy || model.girlDisplay == .dizzy2)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        model.toggleChat()
                    }
                }
                // ピンチ（トラックパッド）でサイズ変更。移動は背景ドラッグ（ネイティブ）。
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in model.pinchChanged(value.magnification) }
                        .onEnded { _ in model.pinchEnded() }
                )
                .help("クリックで質問 / ドラッグで移動 / ピンチで大きさ変更")
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.isChatOpen)
    }
}

/// アイドル時のヒント吹き出し。
struct SpeechBubble: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
            .frame(maxWidth: 240, alignment: .trailing)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

/// 会話パネル。
struct ChatPanel: View {
    @ObservedObject var model: AppModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            messageList
            if model.hasContext || model.isCapturing {
                Divider().opacity(0.4)
                contextBar
            }
            Divider().opacity(0.4)
            inputBar
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        // 左上のグリップをドラッグして大きさ変更（ウィンドウは右下基準で上・左へ伸びる）。
        .overlay(alignment: .topLeading) { resizeGrip }
        .frame(width: model.chatWidth, height: model.chatHeight)
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .onAppear { inputFocused = true }
    }

    /// 左上のリサイズグリップ。上・左へドラッグすると広がる。
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
            .padding(5)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .gesture(
                // 画面座標で測ると、リサイズで欄が動いても値が暴れない。
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        model.chatResizeBegan()
                        // 左へ(width 負)・上へ(height 負)で拡大 → 符号反転。
                        model.chatResizeChanged(dx: -v.translation.width, dy: -v.translation.height)
                    }
                    .onEnded { _ in model.chatResizeEnded() }
            )
            .help("ドラッグでチャット欄の大きさを変更")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("\(model.character.emoji) MacKairu").font(.system(size: 13, weight: .semibold))
            Spacer()
            // 履歴クリア（クリアするとイルカがスリムに戻る）
            Button {
                withAnimation { model.clearChat() }
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("履歴をクリア（スリムに戻る）")
            .disabled(model.messages.isEmpty)

            Button { model.presentSettings?() } label: {
                Image(systemName: "gearshape.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("設定（API キー）")

            // ウィンドウ内からの終了（おせっかいモード時は引き止められる）
            Button { KairuQuit.request() } label: {
                Image(systemName: "power").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("終了")

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.toggleChat() }
            } label: {
                Image(systemName: "chevron.down.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.messages.isEmpty {
                        Text("Mac の操作で困ったことを聞いてください。\n例:「スクリーンショットの撮り方は？」\n（※「お前を消す方法」と打つと、私は消えます）")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    ForEach(model.messages) { msg in
                        MessageRow(message: msg).id(msg.id)
                    }
                    if model.isThinking {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("考え中…").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: model.isThinking) { _, thinking in
                if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    // 取り込み中の文脈（テキスト/画像）＋クイック操作。
    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isCapturing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("画面の範囲を選択中…（Esc で中止）")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    if let img = model.pendingImagePreview {
                        Image(nsImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 46, height: 32).clipped()
                            .cornerRadius(5)
                        Text("画面を取り込み中").font(.system(size: 11))
                    } else if let t = model.pendingText {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 11))
                        Text(t).lineLimit(1).truncationMode(.tail)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.clearPending() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                // クイック操作
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickActions, id: \.0) { item in
                            Button(item.0) { model.quickAction(item.1) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var quickActions: [(String, String)] {
        if model.pendingImage != nil {
            return [
                ("操作を教えて", "この画面でやりたいことの手順を、押すキーやボタンの位置まで具体的に教えて。"),
                ("説明", "この画面に何が表示されているか説明して。"),
                ("文字を読む", "画像内の文字をそのまま読み取って書き出して。"),
            ]
        } else {
            return [
                ("翻訳", "日本語に翻訳して。"),
                ("英訳", "英語に翻訳して。"),
                ("要約", "3行で要約して。"),
                ("説明", "わかりやすく説明して。"),
            ]
        }
    }

    /// 入力欄の最大表示行数。チャット欄の高さに連動させる。
    /// 空のときは1行のまま、打つほどこの上限まで伸びる。
    /// 上限を chatHeight の約4分の1（おおよそ1行18pt換算）に抑え、メッセージログを圧迫しないようにする。
    /// 下限3〜上限10行でクランプ。
    private var inputMaxLines: Int {
        let lines = Int((model.chatHeight * 0.25) / 18)
        return min(10, max(3, lines))
    }

    /// 送信可能か。send() のガードと揃える（改行のみの入力は空とみなす／文脈があれば空でも可）。
    private var canSend: Bool {
        let typed = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!typed.isEmpty || model.hasContext) && !model.isThinking
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            Button { model.attachClipboard() } label: {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("クリップボードを取り込む")
            Button { model.captureScreenshot() } label: {
                Image(systemName: "camera.viewfinder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("スクショで質問")

            TextField("質問を入力…（Shift+Enter で改行）", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...inputMaxLines)
                .focused($inputFocused)
                // onSubmit に頼らず、キー入力側で明示分岐する。
                // Return=送信／Shift+Return=改行（後者はフィールド既定の挿入に委ねてカーソル位置を保つ）。
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    model.send()
                    return .handled
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Button { model.send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// 簡易 Markdown 表示。見出し・箇条書き・番号・コードブロック・区切り線＋インライン装飾（**太字**・`コード`・[リンク]）に対応。
struct MarkdownText: View {
    let text: String

    private enum Block {
        case heading(String, Int)   // テキスト, レベル
        case bullet(String)
        case ordered(String, String) // マーカー, テキスト
        case code(String)
        case rule
        case paragraph(String)
        case blank
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var codeLines: [String] = []
        var inCode = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode { result.append(.code(codeLines.joined(separator: "\n"))); codeLines = [] }
                inCode.toggle()
                continue
            }
            if inCode { codeLines.append(line); continue }
            if trimmed.isEmpty { result.append(.blank); continue }
            if trimmed == "---" || trimmed == "***" { result.append(.rule); continue }
            if let h = heading(trimmed) { result.append(.heading(h.1, h.0)); continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                result.append(.bullet(String(trimmed.dropFirst(2)))); continue
            }
            if let m = orderedMarker(trimmed) { result.append(.ordered(m.0, m.1)); continue }
            result.append(.paragraph(trimmed))
        }
        if inCode, !codeLines.isEmpty { result.append(.code(codeLines.joined(separator: "\n"))) }
        return result
    }

    private func heading(_ s: String) -> (Int, String)? {
        for level in [3, 2, 1] {
            let prefix = String(repeating: "#", count: level) + " "
            if s.hasPrefix(prefix) { return (level, String(s.dropFirst(prefix.count))) }
        }
        return nil
    }

    private func orderedMarker(_ s: String) -> (String, String)? {
        // "1. text" のような番号付き
        guard let dot = s.firstIndex(of: "."), s.distance(from: s.startIndex, to: dot) <= 2 else { return nil }
        let num = s[s.startIndex..<dot]
        guard !num.isEmpty, num.allSatisfy(\.isNumber),
              s.index(after: dot) < s.endIndex, s[s.index(after: dot)] == " " else { return nil }
        return ("\(num).", String(s[s.index(dot, offsetBy: 2)...]))
    }

    /// インラインの Markdown 装飾を解釈（改行は保持）。
    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let t, let level):
                    inline(t).font(.system(size: level == 1 ? 15 : (level == 2 ? 14 : 13), weight: .semibold))
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").font(.system(size: 12.5))
                        inline(t).font(.system(size: 12.5))
                    }
                case .ordered(let marker, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        inline(t).font(.system(size: 12.5))
                    }
                case .code(let t):
                    Text(t)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                case .rule:
                    Divider()
                case .paragraph(let t):
                    inline(t).font(.system(size: 12.5))
                case .blank:
                    Color.clear.frame(height: 2)
                }
            }
        }
    }
}

/// 1 メッセージの吹き出し。
struct MessageRow: View {
    let message: ChatMessage

    private var thumbnail: NSImage? {
        guard let b64 = message.image?.base64,
              let data = Data(base64Encoded: b64),
              let img = NSImage(data: data) else { return nil }
        return img
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 30) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable().scaledToFit()
                        .frame(maxWidth: 180, maxHeight: 120)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                }
                Group {
                    if message.role == .assistant {
                        // アシスタントの返答は Markdown 表示（見出し・箇条書き・コード・装飾）。
                        MarkdownText(text: message.text)
                    } else {
                        Text(message.text).font(.system(size: 12.5))
                    }
                }
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(Color.accentColor.opacity(0.9))
                            : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            }
            if message.role == .assistant { Spacer(minLength: 30) }
        }
    }
}
