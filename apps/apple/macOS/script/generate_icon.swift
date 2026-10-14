import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = root.appendingPathComponent("Sources/TogetherApp/Resources/Assets.xcassets/AppIcon.appiconset")
let source = root.appendingPathComponent("Sources/TogetherApp/Resources/IconSource")
func heart() -> NSBezierPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: 1024-y) }
    let path = NSBezierPath(); path.move(to: p(512,808))
    path.curve(to: p(201,466), controlPoint1: p(482,779), controlPoint2: p(241,612))
    path.curve(to: p(333,242), controlPoint1: p(166,338), controlPoint2: p(227,248))
    path.curve(to: p(512,346), controlPoint1: p(407,238), controlPoint2: p(469,283))
    path.curve(to: p(691,242), controlPoint1: p(555,283), controlPoint2: p(617,238))
    path.curve(to: p(823,466), controlPoint1: p(797,248), controlPoint2: p(858,338))
    path.curve(to: p(512,808), controlPoint1: p(783,612), controlPoint2: p(542,779)); path.close()
    return path
}
func render(size: Int, dark: Bool) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.imageInterpolation = .high
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size)/1024); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 0,y:0,width:1024,height:1024), xRadius:224,yRadius:224)
    NSGradient(starting: dark ? NSColor(red:0.19,green:0.14,blue:0.17,alpha:1) : NSColor(red:1,green:0.988,blue:0.969,alpha:1), ending: dark ? NSColor(red:0.09,green:0.07,blue:0.085,alpha:1) : NSColor(red:0.97,green:0.935,blue:0.9,alpha:1))!.draw(in: background, angle:-45)
    NSGraphicsContext.saveGraphicsState()
    let shadow=NSShadow(); shadow.shadowColor=NSColor(red:0.65,green:0.30,blue:0.40,alpha:0.20); shadow.shadowBlurRadius=24; shadow.shadowOffset=NSSize(width:0,height:-16); shadow.set()
    NSColor(red:0.84,green:0.46,blue:0.54,alpha:1).setFill(); heart().fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting:NSColor(red:0.94,green:0.64,blue:0.70,alpha:1), ending:NSColor(red:0.73,green:0.32,blue:0.43,alpha:1))!.draw(in:heart(),angle:-90)
    let shine=NSBezierPath(); shine.move(to:NSPoint(x:275,y:1024-427)); shine.curve(to:NSPoint(x:388,y:1024-303),controlPoint1:NSPoint(x:260,y:1024-345),controlPoint2:NSPoint(x:324,y:1024-285)); shine.lineWidth=9; shine.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.32).setStroke(); shine.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using:.png,properties:[:])!
}
var images:[[String:Any]]=[]
for dark in [false,true] {
    for size in [16,32,128,256,512] {
        for scale in [1,2] {
            let name="icon-\(size)-\(scale)x\(dark ? "-dark" : "").png"
            try render(size:size*scale,dark:dark).write(to:assets.appendingPathComponent(name))
            var entry:[String:Any]=["filename":name,"idiom":"mac","size":"\(size)x\(size)","scale":"\(scale)x"]
            if dark { entry["appearances"]=[["appearance":"luminosity","value":"dark"]] }
            images.append(entry)
        }
    }
    try render(size:1024,dark:dark).write(to:source.appendingPathComponent(dark ? "preview-dark-1024.png" : "preview-1024.png"))
}
try JSONSerialization.data(withJSONObject:["images":images,"info":["author":"xcode","version":1]],options:[.prettyPrinted,.sortedKeys]).write(to:assets.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject:["info":["author":"xcode","version":1]],options:[.prettyPrinted]).write(to:assets.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Together icon SVG sources and PNG appearances ready")
