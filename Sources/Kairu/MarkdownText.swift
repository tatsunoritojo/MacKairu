import SwiftUI
import AppKit
import KairuCore

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
