import Foundation

/// 画像添付（base64）。Vision 対応モデルに渡す。
public struct ImageAttachment: Equatable, Sendable {
    public let base64: String
    public let mediaType: String // 例: "image/png"

    public init(base64: String, mediaType: String = "image/png") {
        self.base64 = base64
        self.mediaType = mediaType
    }
}

/// 会話の 1 メッセージ。
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: Sendable { case user, assistant }
    public let id: UUID
    public let role: Role
    public var text: String
    /// 添付画像（スクショ等）。なければ nil。
    public var image: ImageAttachment?

    public init(id: UUID = UUID(), role: Role, text: String, image: ImageAttachment? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.image = image
    }
}
