import Foundation

/// 非同期応答が現在の会話へ追加可能かを判定する世代管理。
public struct ChatRequestGate: Sendable {
    public private(set) var currentID: UUID?

    public init() {}

    public mutating func begin() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    public func isCurrent(_ id: UUID) -> Bool {
        currentID == id
    }

    @discardableResult
    public mutating func finish(_ id: UUID) -> Bool {
        guard currentID == id else { return false }
        currentID = nil
        return true
    }

    public mutating func invalidate() {
        currentID = nil
    }
}
