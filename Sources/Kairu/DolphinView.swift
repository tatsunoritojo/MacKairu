import SwiftUI

/// ベクター描画のイルカ「カイル」。ゆらゆら浮遊＋瞬きする。
/// 画像アセットは不要（コードで描いているので差し替えも容易）。
struct DolphinView: View {
    var thinking: Bool
    var scale: Double = 1.0
    /// 太り具合（0〜1）。大きいほど縦に膨らんでぽっちゃりする。
    var fat: Double = 0.0
    /// 泳ぎ中（ヒレを大きく振る）。
    var swimming: Bool = false
    /// 左向き（泳ぐ方向で反転）。
    var flip: Bool = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // ふわふわ上下する量。泳ぎ中は大きめ・速め。
            let amp = swimming ? 7.0 : 4.0
            let bob = sin(t * (swimming ? 2.6 : 1.6)) * amp
            // 瞬き: だいたい 4 秒に 1 回、0.15 秒ほど閉じる。
            let blinkPhase = t.truncatingRemainder(dividingBy: 4.0)
            let isBlinking = blinkPhase < 0.15
            // 考え中はゆっくり傾く。泳ぎ中は体をくねらせる。
            let swimWiggle = swimming ? sin(t * 8) * 6 : 0
            let tilt = (thinking ? sin(t * 3) * 6 : 0) + swimWiggle
            // 太るほど横にやや広く、縦にぷっくり。
            let fatW = 1 + fat * 0.10
            let fatH = 1 + fat * 0.28

            Canvas { ctx, size in
                drawDolphin(ctx: &ctx, size: size, blink: isBlinking, fat: fat)
            }
            .frame(width: 120 * scale * fatW, height: 120 * scale * fatH)
            .scaleEffect(x: flip ? -1 : 1, y: 1) // 進行方向に向く
            .rotationEffect(.degrees(tilt))
            .offset(y: bob * scale)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: fat)
            .animation(.easeInOut(duration: 0.3), value: flip)
        }
    }

    private func drawDolphin(ctx: inout GraphicsContext, size: CGSize, blink: Bool, fat: Double) {
        let w = size.width
        let h = size.height
        // お腹側（下側）を太るほど下に膨らませる量。
        let bulge = fat * 0.10
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }

        let bodyBlue = Color(red: 0.30, green: 0.62, blue: 0.92)
        let bellyWhite = Color(red: 0.93, green: 0.97, blue: 1.0)
        let finBlue = Color(red: 0.22, green: 0.50, blue: 0.82)

        // 尾びれ
        var tail = Path()
        tail.move(to: p(0.18, 0.50))
        tail.addQuadCurve(to: p(0.05, 0.34), control: p(0.10, 0.40))
        tail.addQuadCurve(to: p(0.20, 0.46), control: p(0.16, 0.44))
        tail.addQuadCurve(to: p(0.05, 0.66), control: p(0.10, 0.60))
        tail.addQuadCurve(to: p(0.18, 0.50), control: p(0.16, 0.56))
        ctx.fill(tail, with: .color(finBlue))

        // 胴体
        var body = Path()
        body.move(to: p(0.18, 0.50))
        body.addCurve(to: p(0.62, 0.28), control1: p(0.28, 0.34), control2: p(0.46, 0.28))
        body.addCurve(to: p(0.86, 0.46), control1: p(0.74, 0.28), control2: p(0.84, 0.36))
        body.addCurve(to: p(0.78, 0.55 + bulge), control1: p(0.88, 0.50), control2: p(0.84, 0.54 + bulge))
        body.addCurve(to: p(0.62, 0.62 + bulge), control1: p(0.72, 0.58 + bulge), control2: p(0.68, 0.60 + bulge))
        body.addCurve(to: p(0.18, 0.50), control1: p(0.44, 0.72 + bulge * 1.5), control2: p(0.28, 0.66 + bulge))
        body.closeSubpath()
        ctx.fill(body, with: .color(bodyBlue))

        // お腹（白）
        var belly = Path()
        belly.move(to: p(0.30, 0.58 + bulge * 0.5))
        belly.addQuadCurve(to: p(0.70, 0.58 + bulge * 0.5), control: p(0.50, 0.70 + bulge * 1.6))
        belly.addQuadCurve(to: p(0.30, 0.58 + bulge * 0.5), control: p(0.50, 0.50))
        ctx.fill(belly, with: .color(bellyWhite))

        // 背びれ
        var dorsal = Path()
        dorsal.move(to: p(0.48, 0.31))
        dorsal.addQuadCurve(to: p(0.40, 0.12), control: p(0.40, 0.22))
        dorsal.addQuadCurve(to: p(0.58, 0.30), control: p(0.52, 0.22))
        ctx.fill(dorsal, with: .color(finBlue))

        // 胸びれ
        var flipper = Path()
        flipper.move(to: p(0.56, 0.56))
        flipper.addQuadCurve(to: p(0.50, 0.74), control: p(0.50, 0.66))
        flipper.addQuadCurve(to: p(0.64, 0.60), control: p(0.60, 0.70))
        ctx.fill(flipper, with: .color(finBlue))

        // 口先（ビーク）
        var beak = Path()
        beak.move(to: p(0.84, 0.45))
        beak.addQuadCurve(to: p(0.97, 0.46), control: p(0.92, 0.42))
        beak.addQuadCurve(to: p(0.84, 0.50), control: p(0.92, 0.50))
        ctx.fill(beak, with: .color(bodyBlue))
        // 口のライン
        var mouth = Path()
        mouth.move(to: p(0.86, 0.49))
        mouth.addQuadCurve(to: p(0.96, 0.47), control: p(0.91, 0.49))
        ctx.stroke(mouth, with: .color(finBlue.opacity(0.7)), lineWidth: 1.2)

        // 目
        let eyeCenter = p(0.74, 0.43)
        if blink {
            var lid = Path()
            lid.move(to: CGPoint(x: eyeCenter.x - 5, y: eyeCenter.y))
            lid.addLine(to: CGPoint(x: eyeCenter.x + 5, y: eyeCenter.y))
            ctx.stroke(lid, with: .color(.black), lineWidth: 1.6)
        } else {
            let eyeRect = CGRect(x: eyeCenter.x - 4, y: eyeCenter.y - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: eyeRect), with: .color(.black))
            let glintRect = CGRect(x: eyeCenter.x - 1, y: eyeCenter.y - 3, width: 2.5, height: 2.5)
            ctx.fill(Path(ellipseIn: glintRect), with: .color(.white))
        }
    }
}
