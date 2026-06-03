#!/usr/bin/env swift
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func makeIconPNG(size: Int) -> Data {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // Flip coords so 0,0 = top-left
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    // Rounded rect clip
    let r = s * 0.22
    let path = CGPath(roundedRect: CGRect(x:0,y:0,width:s,height:s),
                      cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.addPath(path); ctx.clip()

    // Background gradient: orange → deep red (top → bottom)
    let gradColors = [
        CGColor(red:1.00, green:0.52, blue:0.10, alpha:1),
        CGColor(red:0.82, green:0.10, blue:0.10, alpha:1),
    ] as CFArray
    let locs: [CGFloat] = [0,1]
    let grad = CGGradient(colorsSpace: cs, colors: gradColors, locations: locs)!
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: s/2, y: 0), end: CGPoint(x: s/2, y: s), options: [])

    // Subtle sheen (top-left white overlay)
    let sheenColors = [
        CGColor(red:1,green:1,blue:1,alpha:0.18),
        CGColor(red:1,green:1,blue:1,alpha:0.00),
    ] as CFArray
    let sheen = CGGradient(colorsSpace: cs, colors: sheenColors, locations: locs)!
    ctx.drawRadialGradient(sheen,
        startCenter: CGPoint(x: s*0.3, y: s*0.2), startRadius: 0,
        endCenter:   CGPoint(x: s*0.3, y: s*0.2), endRadius: s*0.7,
        options: [])

    let u = s / 100.0  // unit

    // ── Thermometer tube ──
    let bulbR: CGFloat = 14 * u
    let tubeW: CGFloat = 8.5 * u
    let tubeHalfW = tubeW / 2
    let centerX = s * 0.50
    let bulbCY  = s * 0.76     // bulb at bottom
    let tubeTop = s * 0.18     // top of tube

    // Outer tube (white, low opacity)
    let tubeRect = CGRect(x: centerX - tubeHalfW, y: tubeTop,
                          width: tubeW, height: bulbCY - tubeTop - bulbR * 0.5)
    ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:0.30))
    let outerTube = CGPath(roundedRect: tubeRect,
                           cornerWidth: tubeHalfW, cornerHeight: tubeHalfW, transform: nil)
    ctx.addPath(outerTube); ctx.fillPath()

    // Tube fill (white, solid) — bottom 60% of tube
    let fillH = tubeRect.height * 0.60
    let fillRect = CGRect(x: centerX - tubeHalfW + 1.5*u,
                          y: tubeRect.maxY - fillH,
                          width: tubeW - 3*u, height: fillH)
    ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:0.92))
    let innerTube = CGPath(roundedRect: fillRect,
                           cornerWidth: tubeHalfW - 1.5*u,
                           cornerHeight: tubeHalfW - 1.5*u, transform: nil)
    ctx.addPath(innerTube); ctx.fillPath()

    // Tick marks (right side of tube)
    ctx.setStrokeColor(CGColor(red:1,green:1,blue:1,alpha:0.60))
    ctx.setLineWidth(1.2 * u)
    ctx.setLineCap(.round)
    let tickArea = tubeRect.height - 6*u
    for i in 1...5 {
        let ty = tubeTop + 3*u + tickArea / 6.0 * CGFloat(i)
        let tickLen = (i % 2 == 0) ? 5.5*u : 3.5*u
        ctx.move(to:    CGPoint(x: centerX + tubeHalfW + 1.5*u, y: ty))
        ctx.addLine(to: CGPoint(x: centerX + tubeHalfW + 1.5*u + tickLen, y: ty))
        ctx.strokePath()
    }

    // Bulb (white circle at bottom)
    ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:0.95))
    ctx.addEllipse(in: CGRect(x: centerX - bulbR, y: bulbCY - bulbR,
                              width: bulbR*2, height: bulbR*2))
    ctx.fillPath()

    // Bulb gloss (small highlight)
    ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:0.40))
    let glossR = bulbR * 0.38
    ctx.addEllipse(in: CGRect(x: centerX - glossR*1.1, y: bulbCY - bulbR*0.62,
                              width: glossR, height: glossR * 0.8))
    ctx.fillPath()

    // Convert to PNG data
    let cgImg = ctx.makeImage()!
    let mutableData = NSMutableData()
    let dest = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cgImg, nil)
    CGImageDestinationFinalize(dest)
    return mutableData as Data
}

let iconsetDir = "/Users/henryngo/Desktop/ThermalMonitor/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// Required iconset sizes
let specs: [(String, Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png",1024),
]

for (name, px) in specs {
    let data = makeIconPNG(size: px)
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(name)")
    try! data.write(to: url)
    print("✓ \(name)")
}

print("\nAll done!")
