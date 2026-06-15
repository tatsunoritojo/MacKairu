import SwiftUI
import AppKit

/// チャット入力欄。NSTextView ベースで複数行・IME（日本語変換）・行数連動の高さを扱う。
/// SwiftUI の TextEditor では IME 確定や行数連動の高さ制御が難しいため AppKit を直接包む。
struct ChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxLines: Int
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> ChatInputContainerView {
        let container = ChatInputContainerView(placeholder: placeholder)
        container.textView.delegate = context.coordinator
        container.textView.onSubmit = onSubmit
        container.textView.font = .systemFont(ofSize: 13)
        container.maxLines = maxLines
        container.textView.string = text
        container.updatePlaceholder()
        return container
    }

    func updateNSView(_ nsView: ChatInputContainerView, context: Context) {
        context.coordinator.parent = self
        nsView.maxLines = maxLines
        nsView.placeholderLabel.stringValue = placeholder
        nsView.textView.onSubmit = onSubmit
        nsView.textView.font = .systemFont(ofSize: 13)
        nsView.placeholderLabel.font = .systemFont(ofSize: 13)
        // IME変換中（未確定マークテキストあり）は .string を書き戻さない。
        // ここで上書きすると変換セッションが破棄され、全角（日本語）入力が始められなくなる。
        // 確定は textDidChange 経由で text に反映されるので、確定後の再評価で同期は追いつく。
        if !nsView.textView.hasMarkedText(), nsView.textView.string != text {
            nsView.textView.string = text
        }
        nsView.updatePlaceholder()
        nsView.invalidateIntrinsicContentSize()

        if isFocused.wrappedValue {
            DispatchQueue.main.async {
                if nsView.window?.firstResponder !== nsView.textView {
                    nsView.window?.makeFirstResponder(nsView.textView)
                }
            }
        }
    }

    // SwiftUI は NSViewRepresentable の高さをここで決める（intrinsicContentSize ではなく）。
    // 提案された幅で内容の高さを測り、1行〜maxLines にクランプして返す。
    // text の変化ごとに再評価されるので、改行に応じて伸び縮みする。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatInputContainerView, context: Context) -> CGSize? {
        let width: CGFloat
        if let w = proposal.width, w.isFinite, w > 0 {
            width = w
        } else {
            width = nsView.bounds.width > 0 ? nsView.bounds.width : 200
        }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputTextView

        init(parent: ChatInputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? ChatInputNSTextView,
                  let container = textView.enclosingScrollView?.superview as? ChatInputContainerView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            container.updatePlaceholder()
            container.invalidateIntrinsicContentSize()
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }
    }
}

/// プレースホルダ用ラベル。クリックを下のテキストビューへ通すため hitTest を無効化する。
/// （これを通常の NSTextField にすると、ラベルが入力域を覆ってクリックを奪い、フォーカスできなくなる）
final class NonInteractiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ChatInputContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = ChatInputNSTextView()
    let placeholderLabel = NonInteractiveLabel(frame: .zero)
    var maxLines: Int = 3 {
        didSet { invalidateIntrinsicContentSize() }
    }

    init(placeholder: String) {
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.isBordered = false
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.stringValue = placeholder
        placeholderLabel.font = .systemFont(ofSize: 13)
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.lineBreakMode = .byTruncatingTail

        scrollView.documentView = textView
        addSubview(scrollView)
        addSubview(placeholderLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var lineHeight: CGFloat {
        textView.layoutManager?.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: 13)) ?? 18
    }

    /// 指定幅での表示高さ。内容に応じて1行〜maxLines にクランプする（SwiftUI の sizeThatFits 用）。
    func height(forWidth width: CGFloat) -> CGFloat {
        let used = measuredTextHeight(forWidth: width)
        let maxHeight = lineHeight * CGFloat(maxLines)
        return min(max(used, lineHeight), maxHeight)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: max(bounds.width, 1)))
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        textView.textContainer?.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = CGRect(
            x: 0, y: 0,
            width: bounds.width,
            height: max(bounds.height, measuredTextHeight(forWidth: bounds.width))
        )
        placeholderLabel.frame = CGRect(x: 0, y: bounds.height - 16, width: bounds.width, height: 16)
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.string.isEmpty || textView.hasMarkedText()
    }

    /// 指定幅で内容を折り返したときの実描画高さ。
    private func measuredTextHeight(forWidth width: CGFloat) -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return lineHeight
        }
        textContainer.containerSize = NSSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).height)
    }
}

final class ChatInputNSTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard isReturnKey(event) else {
            super.keyDown(with: event)
            return
        }

        // IME変換中（未確定文字がある）の Return は横取りせず、IMEに変換確定させる。
        // ここを通さないと「変換→Enter で確定」が送信に化けてしまう（本不具合の核心）。
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        // 確定済み: Shift+Return は改行、素の Return は送信。
        if event.modifierFlags.contains(.shift) {
            insertNewline(nil)
            return
        }

        onSubmit?()
    }

    private func isReturnKey(_ event: NSEvent) -> Bool {
        event.keyCode == 36 || event.keyCode == 76
    }
}
