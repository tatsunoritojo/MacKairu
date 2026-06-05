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

            DolphinView(thinking: model.isThinking, scale: model.dolphinScale, fat: model.fatness,
                        swimming: model.isSwimming, flip: model.facingLeft)
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
            Divider().opacity(0.4)
            inputBar
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        .frame(width: 300, height: 380)
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("🐬 MacKairu").font(.system(size: 13, weight: .semibold))
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

    private var inputBar: some View {
        HStack(spacing: 6) {
            TextField("質問を入力…", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { model.send() }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Button { model.send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(model.draft.isEmpty ? .secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isThinking)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// 1 メッセージの吹き出し。
struct MessageRow: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 30) }
            Text(message.text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(Color.accentColor.opacity(0.9))
                        : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            if message.role == .assistant { Spacer(minLength: 30) }
        }
    }
}
