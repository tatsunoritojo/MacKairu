import AppKit
import ImageIO
import UniformTypeIdentifiers

let girlDir = "/Users/tatsu/MacConcierge/Resources/girl/"
let outDir = "/Users/tatsu/MacConcierge/docs/images/anim/"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func load(_ name: String) -> NSImage { NSImage(contentsOfFile: girlDir + name + ".png")! }
var cache: [String: NSImage] = [:]
func img(_ n: String) -> NSImage { if let c = cache[n] { return c }; let i = load(n); cache[n] = i; return i }

let W = 240, H = 300
let padY: CGFloat = 14

struct Spec {
    let name: String
    let loop: Double          // 1ループ秒
    let fps: Double
    let sprite: (Double) -> String
    var imgScale: (String) -> CGFloat = { _ in 1.0 }
    var rotAmp: CGFloat = 0
    var rotFreq: Double = 0
    var bobAmp: CGFloat = 4
    var bobFreq: Double = 1.6
    var scaleBase: CGFloat = 1.0
    var scalePulse: CGFloat = 0
    var scaleFreq: Double = 0
}

func renderFrame(_ s: Spec, _ t: Double) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 背景: 淡い縦グラデ
    let grad = NSGradient(starting: NSColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 1),
                          ending: NSColor(red: 0.88, green: 0.93, blue: 0.99, alpha: 1))!
    grad.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    let name = s.sprite(t)
    let image = img(name)
    let aspect = image.size.width / image.size.height
    let bob = sin(t * s.bobFreq) * s.bobAmp
    let scale = s.scaleBase + (s.scaleFreq > 0 ? (sin(t * s.scaleFreq) * 0.5 + 0.5) * s.scalePulse : 0)
    let drawH = (CGFloat(H) - 2 * padY) * s.imgScale(name) * scale
    let drawW = drawH * aspect
    let cx = CGFloat(W) / 2
    let cy = CGFloat(H) / 2 + bob

    let rot = sin(t * s.rotFreq) * s.rotAmp
    if rot != 0 {
        let tr = NSAffineTransform()
        tr.translateX(by: cx, yBy: cy); tr.rotate(byDegrees: rot); tr.translateX(by: -cx, yBy: -cy)
        tr.concat()
    }
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: cx - drawW/2, y: cy - drawH/2, width: drawW, height: drawH),
               from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

func makeGIF(_ s: Spec) {
    let url = URL(fileURLWithPath: outDir + s.name + ".gif")
    let n = max(2, Int(s.loop * s.fps))
    let delay = s.loop / Double(n)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, n, nil)!
    let gifProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
    CGImageDestinationSetProperties(dest, gifProps)
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
    for i in 0..<n {
        let t = Double(i) / s.fps
        CGImageDestinationAddImage(dest, renderFrame(s, t), frameProps)
    }
    CGImageDestinationFinalize(dest)
    print("wrote", s.name + ".gif", "frames:", n)
}

// アプリと同じタイミングのスプライト切替
func cycle(_ a: String, _ ad: Double, _ b: String, _ bd: Double) -> (Double) -> String {
    { t in t.truncatingRemainder(dividingBy: ad + bd) < ad ? a : b }
}

let specs: [Spec] = [
    Spec(name: "far-wait", loop: 3.3, fps: 12, sprite: cycle("rest", 2.4, "doze", 0.9), bobAmp: 3, bobFreq: 1.2),
    Spec(name: "run", loop: 0.64, fps: 25, sprite: cycle("run", 0.16, "run2", 0.16), bobAmp: 6, bobFreq: 8),
    Spec(name: "nade", loop: 1.0, fps: 16, sprite: cycle("pamper", 0.5, "pamperLoop", 0.5),
         bobAmp: 3, bobFreq: 1.6, scaleBase: 1.0, scalePulse: 0.06, scaleFreq: 6.0),
    Spec(name: "teaching", loop: 2.32, fps: 14, sprite: cycle("teaching", 2.0, "teaching2", 0.32),
         imgScale: { $0 == "teaching2" ? 0.963 : 1.0 }, bobAmp: 2.5, bobFreq: 1.6),
    Spec(name: "dizzy", loop: 1.12, fps: 20, sprite: cycle("dizzy", 0.28, "dizzy2", 0.28),
         imgScale: { $0 == "dizzy2" ? 0.983 : 1.0 }, rotAmp: 10, rotFreq: 6.5, bobAmp: 3, bobFreq: 3),
    Spec(name: "carry", loop: 1.4, fps: 16, sprite: { _ in "drag" }, rotAmp: 5, rotFreq: 4.5, bobAmp: 4, bobFreq: 3),
]
for s in specs { makeGIF(s) }
print("done")
