import AVFoundation
import AppKit
let src = URL(fileURLWithPath: "/Users/tatsu/MacConcierge/docs/videos/girl-petting.mp4")
let asset = AVURLAsset(url: src)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
let dur = CMTimeGetSeconds(asset.duration)
let t = CMTime(seconds: min(1.5, dur*0.45), preferredTimescale: 600)
let cg = try gen.copyCGImage(at: t, actualTime: nil)
// 幅480に縮小
let scale = 480.0 / Double(cg.width)
let w = Int(Double(cg.width)*scale), h = Int(Double(cg.height)*scale)
let rep = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:w, pixelsHigh:h, bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
NSImage(cgImage: cg, size: .zero).draw(in: NSRect(x:0,y:0,width:w,height:h))
NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath:"/Users/tatsu/MacConcierge/docs/images/girl-petting-poster.png")
try rep.representation(using:.png, properties:[:])!.write(to: out)
print("poster", w, "x", h, "dur", dur)
