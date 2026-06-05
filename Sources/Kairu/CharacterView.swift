import SwiftUI
import KairuCore

/// ベクター描画の常駐キャラクター。種類を選べる（イルカ/ねこ/ペンギン/ひよこ）。
/// 画像アセット不要・無限に拡大しても綺麗。
struct CharacterView: View {
    var character: Character
    var thinking: Bool
    var scale: Double = 1.0
    /// 太り具合（0〜1）。
    var fat: Double = 0.0
    /// 泳ぎ/移動中（大きく揺れる）。
    var swimming: Bool = false
    /// 左向き（進行方向で反転）。
    var flip: Bool = false
    /// 裏キャラの画像。
    var girlImage: NSImage? = nil
    /// 裏キャラ画像ごとの見かけサイズ補正（素材間の描画サイズ差を吸収）。
    var girlImageScale: Double = 1.0
    /// 裏キャラが頭を撫でられている最中。
    var patted: Bool = false
    /// 「お前を消す方法」で消される最中（ブルブル震えてフェードアウト）。
    var dying: Bool = false
    /// 振り回されて目を回している最中（ふらふら揺れる）。
    var dizzy: Bool = false

    @State private var dyingStart: Double?

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let amp = swimming ? 7.0 : 4.0
            let bob = sin(t * (swimming ? 2.6 : 1.6)) * amp
            let blinkPhase = t.truncatingRemainder(dividingBy: 4.0)
            let isBlinking = blinkPhase < 0.15
            let swimWiggle = swimming ? sin(t * 8) * 6 : 0
            let dizzyWobble = dizzy ? sin(t * 6.5) * 10 : 0
            let tilt = (thinking ? sin(t * 3) * 6 : 0) + swimWiggle + dizzyWobble
            let fatW = 1 + fat * 0.12
            let fatH = 1 + fat * 0.24
            let side = 120 * scale

            Group {
                if character == .girl {
                    girlView(side: side, t: t)
                        .scaleEffect(x: flip ? -1 : 1, y: 1)
                } else {
                    Canvas { ctx, size in
                        switch character {
                        case .dolphin: drawDolphin(&ctx, size, isBlinking, fat)
                        case .cat:     drawCat(&ctx, size, isBlinking, fat)
                        case .penguin: drawPenguin(&ctx, size, isBlinking, fat)
                        case .chick:   drawChick(&ctx, size, isBlinking, fat)
                        case .girl:    break // 画像で別途描画
                        }
                    }
                    .frame(width: side * fatW, height: side * fatH)
                    .scaleEffect(x: flip ? -1 : 1, y: 1)
                }
            }
            .rotationEffect(.degrees(tilt))
            .offset(y: bob * scale)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: fat)
            .animation(.easeInOut(duration: 0.3), value: flip)
            .animation(.easeInOut(duration: 0.25), value: character)
            .onChange(of: dying) { _, d in
                dyingStart = d ? Date().timeIntervalSinceReferenceDate : nil
            }
        }
    }

    /// 裏キャラ（画像＋なでなで＋終了演出）。
    @ViewBuilder
    private func girlView(side: CGFloat, t: Double) -> some View {
        // 終了演出: 5 秒かけてフェード、ブルブル震える。
        let elapsed = dying ? max(0, t - (dyingStart ?? t)) : 0
        let fade = dying ? max(0, 1 - elapsed / 5) : 1
        let shakeX = dying ? CGFloat(sin(t * 47)) * 3 : 0
        let shakeY = dying ? CGFloat(cos(t * 53)) * 2.5 : 0

        ZStack {
            if let img = girlImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)      // 最高画質で補間
                    .antialiased(true)
                    .scaledToFit()
                    .scaleEffect(girlImageScale)   // 素材間サイズ差の補正
                    .scaleEffect((patted && !dying) ? 1.06 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: patted)
                    .offset(x: shakeX, y: shakeY)
                    .opacity(fade)
            } else {
                ZStack {
                    Circle().fill(Color.pink.opacity(0.18))
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: side * 0.32))
                        .foregroundStyle(.pink.opacity(0.7))
                }
            }
        }
        .frame(width: side, height: side)
    }
}

// MARK: - 共通の目

private func drawEye(_ ctx: inout GraphicsContext, _ c: CGPoint, blink: Bool, r: CGFloat = 4) {
    if blink {
        var lid = Path()
        lid.move(to: CGPoint(x: c.x - r - 1, y: c.y))
        lid.addLine(to: CGPoint(x: c.x + r + 1, y: c.y))
        ctx.stroke(lid, with: .color(.black), lineWidth: 1.6)
    } else {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(.black))
        let g: CGFloat = r * 0.5
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - g * 0.2, y: c.y - r * 0.7, width: g, height: g)),
                 with: .color(.white))
    }
}

// MARK: - イルカ

private func drawDolphin(_ ctx: inout GraphicsContext, _ size: CGSize, _ blink: Bool, _ fat: Double) {
    let w = size.width, h = size.height
    let bulge = fat * 0.10
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }
    let bodyBlue = Color(red: 0.30, green: 0.62, blue: 0.92)
    let bellyWhite = Color(red: 0.93, green: 0.97, blue: 1.0)
    let finBlue = Color(red: 0.22, green: 0.50, blue: 0.82)

    var tail = Path()
    tail.move(to: p(0.18, 0.50))
    tail.addQuadCurve(to: p(0.05, 0.34), control: p(0.10, 0.40))
    tail.addQuadCurve(to: p(0.20, 0.46), control: p(0.16, 0.44))
    tail.addQuadCurve(to: p(0.05, 0.66), control: p(0.10, 0.60))
    tail.addQuadCurve(to: p(0.18, 0.50), control: p(0.16, 0.56))
    ctx.fill(tail, with: .color(finBlue))

    var body = Path()
    body.move(to: p(0.18, 0.50))
    body.addCurve(to: p(0.62, 0.28), control1: p(0.28, 0.34), control2: p(0.46, 0.28))
    body.addCurve(to: p(0.86, 0.46), control1: p(0.74, 0.28), control2: p(0.84, 0.36))
    body.addCurve(to: p(0.78, 0.55 + bulge), control1: p(0.88, 0.50), control2: p(0.84, 0.54 + bulge))
    body.addCurve(to: p(0.62, 0.62 + bulge), control1: p(0.72, 0.58 + bulge), control2: p(0.68, 0.60 + bulge))
    body.addCurve(to: p(0.18, 0.50), control1: p(0.44, 0.72 + bulge * 1.5), control2: p(0.28, 0.66 + bulge))
    body.closeSubpath()
    ctx.fill(body, with: .color(bodyBlue))

    var belly = Path()
    belly.move(to: p(0.30, 0.58 + bulge * 0.5))
    belly.addQuadCurve(to: p(0.70, 0.58 + bulge * 0.5), control: p(0.50, 0.70 + bulge * 1.6))
    belly.addQuadCurve(to: p(0.30, 0.58 + bulge * 0.5), control: p(0.50, 0.50))
    ctx.fill(belly, with: .color(bellyWhite))

    var dorsal = Path()
    dorsal.move(to: p(0.48, 0.31))
    dorsal.addQuadCurve(to: p(0.40, 0.12), control: p(0.40, 0.22))
    dorsal.addQuadCurve(to: p(0.58, 0.30), control: p(0.52, 0.22))
    ctx.fill(dorsal, with: .color(finBlue))

    var flipper = Path()
    flipper.move(to: p(0.56, 0.56))
    flipper.addQuadCurve(to: p(0.50, 0.74), control: p(0.50, 0.66))
    flipper.addQuadCurve(to: p(0.64, 0.60), control: p(0.60, 0.70))
    ctx.fill(flipper, with: .color(finBlue))

    var beak = Path()
    beak.move(to: p(0.84, 0.45))
    beak.addQuadCurve(to: p(0.97, 0.46), control: p(0.92, 0.42))
    beak.addQuadCurve(to: p(0.84, 0.50), control: p(0.92, 0.50))
    ctx.fill(beak, with: .color(bodyBlue))

    drawEye(&ctx, p(0.74, 0.43), blink: blink, r: 4)
}

// MARK: - ねこ

private func drawCat(_ ctx: inout GraphicsContext, _ size: CGSize, _ blink: Bool, _ fat: Double) {
    let w = size.width, h = size.height
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }
    func tri(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var t = Path(); t.move(to: a); t.addLine(to: b); t.addLine(to: c); t.closeSubpath(); return t
    }
    let fur = Color(red: 0.96, green: 0.66, blue: 0.34)
    let furDark = Color(red: 0.90, green: 0.56, blue: 0.26)
    let pink = Color(red: 0.96, green: 0.66, blue: 0.66)
    let bw = fat * 0.08 // 太ると横に広がる

    // しっぽ
    var tail = Path()
    tail.move(to: p(0.78, 0.86))
    tail.addQuadCurve(to: p(0.98, 0.66), control: p(0.97, 0.86))
    tail.addQuadCurve(to: p(0.82, 0.80), control: p(0.90, 0.74))
    ctx.fill(tail, with: .color(furDark))

    // 体
    ctx.fill(Path(ellipseIn: CGRect(x: w*(0.24 - bw), y: h*0.50,
                                    width: w*(0.52 + bw*2), height: h*0.50)), with: .color(fur))
    // 耳
    ctx.fill(tri(p(0.30, 0.26), p(0.30, 0.05), p(0.46, 0.20)), with: .color(fur))
    ctx.fill(tri(p(0.70, 0.26), p(0.70, 0.05), p(0.54, 0.20)), with: .color(fur))
    ctx.fill(tri(p(0.34, 0.22), p(0.34, 0.10), p(0.43, 0.19)), with: .color(pink))
    ctx.fill(tri(p(0.66, 0.22), p(0.66, 0.10), p(0.57, 0.19)), with: .color(pink))
    // 頭
    ctx.fill(Path(ellipseIn: CGRect(x: w*0.27, y: h*0.16, width: w*0.46, height: h*0.42)),
             with: .color(fur))
    // 目
    drawEye(&ctx, p(0.41, 0.36), blink: blink, r: 4)
    drawEye(&ctx, p(0.59, 0.36), blink: blink, r: 4)
    // 鼻
    ctx.fill(tri(p(0.47, 0.43), p(0.53, 0.43), p(0.50, 0.47)), with: .color(pink))
    // ひげ
    for dy in [-0.01, 0.03] {
        var wl = Path(); wl.move(to: p(0.44, 0.45 + dy)); wl.addLine(to: p(0.26, 0.43 + dy))
        ctx.stroke(wl, with: .color(furDark), lineWidth: 1)
        var wr = Path(); wr.move(to: p(0.56, 0.45 + dy)); wr.addLine(to: p(0.74, 0.43 + dy))
        ctx.stroke(wr, with: .color(furDark), lineWidth: 1)
    }
}

// MARK: - ペンギン

private func drawPenguin(_ ctx: inout GraphicsContext, _ size: CGSize, _ blink: Bool, _ fat: Double) {
    let w = size.width, h = size.height
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }
    func tri(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var t = Path(); t.move(to: a); t.addLine(to: b); t.addLine(to: c); t.closeSubpath(); return t
    }
    let black = Color(red: 0.18, green: 0.21, blue: 0.26)
    let white = Color(red: 0.97, green: 0.98, blue: 1.0)
    let orange = Color(red: 0.98, green: 0.62, blue: 0.16)
    let bw = fat * 0.08

    // 足
    ctx.fill(tri(p(0.36, 0.94), p(0.30, 1.0), p(0.46, 1.0)), with: .color(orange))
    ctx.fill(tri(p(0.64, 0.94), p(0.54, 1.0), p(0.70, 1.0)), with: .color(orange))
    // 体（黒）
    ctx.fill(Path(ellipseIn: CGRect(x: w*(0.20 - bw), y: h*0.12,
                                    width: w*(0.60 + bw*2), height: h*0.84)), with: .color(black))
    // 羽
    ctx.fill(Path(ellipseIn: CGRect(x: w*(0.10 - bw), y: h*0.40, width: w*0.16, height: h*0.40)),
             with: .color(black))
    ctx.fill(Path(ellipseIn: CGRect(x: w*(0.74 + bw), y: h*0.40, width: w*0.16, height: h*0.40)),
             with: .color(black))
    // お腹（白）
    ctx.fill(Path(ellipseIn: CGRect(x: w*0.30, y: h*0.30, width: w*0.40, height: h*0.62)),
             with: .color(white))
    // 顔の白
    ctx.fill(Path(ellipseIn: CGRect(x: w*0.33, y: h*0.18, width: w*0.34, height: h*0.30)),
             with: .color(white))
    // 目
    drawEye(&ctx, p(0.43, 0.32), blink: blink, r: 3.5)
    drawEye(&ctx, p(0.57, 0.32), blink: blink, r: 3.5)
    // くちばし
    ctx.fill(tri(p(0.46, 0.40), p(0.54, 0.40), p(0.50, 0.47)), with: .color(orange))
}

// MARK: - ひよこ

private func drawChick(_ ctx: inout GraphicsContext, _ size: CGSize, _ blink: Bool, _ fat: Double) {
    let w = size.width, h = size.height
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }
    func tri(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var t = Path(); t.move(to: a); t.addLine(to: b); t.addLine(to: c); t.closeSubpath(); return t
    }
    let yellow = Color(red: 1.0, green: 0.84, blue: 0.25)
    let yellowDark = Color(red: 0.98, green: 0.76, blue: 0.16)
    let orange = Color(red: 0.97, green: 0.58, blue: 0.12)
    let bw = fat * 0.08

    // 足
    var lf = Path(); lf.move(to: p(0.43, 0.92)); lf.addLine(to: p(0.40, 1.0))
    ctx.stroke(lf, with: .color(orange), lineWidth: 2)
    var rf = Path(); rf.move(to: p(0.57, 0.92)); rf.addLine(to: p(0.60, 1.0))
    ctx.stroke(rf, with: .color(orange), lineWidth: 2)
    // 体
    ctx.fill(Path(ellipseIn: CGRect(x: w*(0.22 - bw), y: h*0.42,
                                    width: w*(0.56 + bw*2), height: h*0.52)), with: .color(yellow))
    // 翼
    ctx.fill(Path(ellipseIn: CGRect(x: w*(0.16 - bw), y: h*0.50, width: w*0.16, height: h*0.30)),
             with: .color(yellowDark))
    ctx.fill(Path(ellipseIn: CGRect(x: w*(0.68 + bw), y: h*0.50, width: w*0.16, height: h*0.30)),
             with: .color(yellowDark))
    // 頭
    ctx.fill(Path(ellipseIn: CGRect(x: w*0.26, y: h*0.14, width: w*0.48, height: h*0.44)),
             with: .color(yellow))
    // 髪の毛（ぴょん）
    var hair = Path(); hair.move(to: p(0.50, 0.16)); hair.addLine(to: p(0.50, 0.04))
    ctx.stroke(hair, with: .color(yellowDark), lineWidth: 2)
    // 目
    drawEye(&ctx, p(0.43, 0.34), blink: blink, r: 3.5)
    drawEye(&ctx, p(0.57, 0.34), blink: blink, r: 3.5)
    // くちばし
    ctx.fill(tri(p(0.46, 0.42), p(0.54, 0.42), p(0.50, 0.48)), with: .color(orange))
    ctx.fill(tri(p(0.46, 0.42), p(0.54, 0.42), p(0.50, 0.37)), with: .color(orange))
}
