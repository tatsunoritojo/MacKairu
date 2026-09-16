import Foundation
import CoreGraphics

/// 保存位置や画面構成が変わっても、操作可能な辺を画面内へ戻す。
public enum WindowPlacement {
    public static func constrainedFrame(
        _ frame: CGRect,
        visibleFrames: [CGRect],
        keepTopVisible: Bool,
        allowSpanningDisplays: Bool = true
    ) -> CGRect {
        if allowSpanningDisplays, isFullyCovered(frame, by: visibleFrames) { return frame }
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

    /// 重なりを二重計上せず、frame全体が画面群の可視領域で覆われているか判定する。
    private static func isFullyCovered(_ frame: CGRect, by visibleFrames: [CGRect]) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return true }
        let clips = visibleFrames.map { frame.intersection($0) }.filter { !$0.isNull && !$0.isEmpty }
        let xs = Array(Set(clips.flatMap { [$0.minX, $0.maxX] })).sorted()
        guard xs.count >= 2 else { return false }

        var coveredArea: CGFloat = 0
        for index in 0 ..< xs.count - 1 {
            let left = xs[index], right = xs[index + 1]
            guard right > left else { continue }
            let intervals = clips
                .filter { $0.minX < right && $0.maxX > left }
                .map { ($0.minY, $0.maxY) }
                .sorted { $0.0 < $1.0 }
            guard var merged = intervals.first else { continue }
            var height: CGFloat = 0
            for interval in intervals.dropFirst() {
                if interval.0 <= merged.1 {
                    merged.1 = max(merged.1, interval.1)
                } else {
                    height += merged.1 - merged.0
                    merged = interval
                }
            }
            height += merged.1 - merged.0
            coveredArea += (right - left) * height
        }
        let frameArea = frame.width * frame.height
        return coveredArea >= frameArea - max(0.5, frameArea * 0.000_001)
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
