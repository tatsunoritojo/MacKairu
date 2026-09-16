import Foundation
import CoreGraphics

/// 保存位置や画面構成が変わっても、操作可能な辺を画面内へ戻す。
public enum WindowPlacement {
    public static func constrainedFrame(
        _ frame: CGRect,
        visibleFrames: [CGRect],
        keepTopVisible: Bool
    ) -> CGRect {
        guard let screen = targetScreen(for: frame, visibleFrames: visibleFrames) else {
            return frame
        }

        var result = frame
        if frame.width <= screen.width {
            result.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
        } else {
            // キャラクターと操作部が右寄せなので、横長時は右端を残す。
            result.origin.x = screen.maxX - frame.width
        }

        if frame.height <= screen.height {
            result.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        } else {
            // チャット中は上部操作、閉じている時は下部キャラクターを画面内に残す。
            result.origin.y = keepTopVisible ? screen.maxY - frame.height : screen.minY
        }
        return result
    }

    private static func targetScreen(for frame: CGRect, visibleFrames: [CGRect]) -> CGRect? {
        guard !visibleFrames.isEmpty else { return nil }
        let intersections = visibleFrames.map { screen in
            let intersection = frame.intersection(screen)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (screen, area)
        }
        if let best = intersections.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return visibleFrames.min { lhs, rhs in
            squaredDistance(from: center, to: lhs) < squaredDistance(from: center, to: rhs)
        }
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - x
        let dy = point.y - y
        return dx * dx + dy * dy
    }
}
