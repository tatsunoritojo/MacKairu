import Foundation

/// 会話の 1 メッセージ。
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: Sendable { case user, assistant }
    public let id: UUID
    public let role: Role
    public var text: String

    public init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}
