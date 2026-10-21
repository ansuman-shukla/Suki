// Renders Suki's app icon sources from code.
//
// Usage, from the repository root:
//   swift scripts/render-app-icon.swift
//   make icon && make icon APP_NAME=Suki
//
// Writes Resources/AppIcon-Source.png and Resources/AppIcon-Dev-Source.png
// (1024x1024). The design is a green glass orb (voice) behind a frosted text
// page, drawn in a baked Liquid Glass style. Dev builds add a hammer badge.

import AppKit
import CoreImage
import ImageIO

let canvas: CGFloat = 1024
let full = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [.workingColorSpace: srgb])

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ draw: (CGContext) -> Void) -> CGImage {
    let c = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(c)
    return c.makeImage()!
}

func blur(_ image: CGImage, _ sigma: CGFloat, clamp: Bool = false) -> CGImage {
    var ci = CIImage(cgImage: image)
    if clamp { ci = ci.clampedToExtent() }
    ci = ci.applyingGaussianBlur(sigma: sigma).cropped(to: full)
    return ciContext.createCGImage(ci, from: full)!
}

/// macOS icon tile outline, approximated by a superellipse.
func squircle(_ r: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    for i in 0..<1440 {
        let t = CGFloat(i) / 1440 * 2 * .pi, c = cos(t), s = sin(t)
        let point = CGPoint(x: r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c),
                            y: r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s))
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}
let tilePath = squircle(tileRect)

func vertical(_ c: CGContext, _ box: CGRect, _ colors: [CGColor], _ locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locations)!
    c.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ c: CGContext, _ center: CGPoint, _ radius: CGFloat, _ colors: [CGColor]) {
    let g = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: nil)!
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func circle(_ center: CGPoint, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r), transform: nil)
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func capsule(_ r: CGRect) -> CGPath { rounded(r, min(r.width, r.height) / 2) }

/// Draws only the shadow of `path` by rendering the shape off-canvas.
func softShadow(_ c: CGContext, _ path: CGPath, alpha: CGFloat, blur radius: CGFloat, dy: CGFloat) {
    let offset: CGFloat = 4000
    var shift = CGAffineTransform(translationX: offset, y: 0)
    c.saveGState()
    c.setShadow(offset: CGSize(width: -offset, height: dy), blur: radius, color: rgb(0, alpha))
    c.addPath(path.copy(using: &shift)!); c.setFillColor(rgb(0)); c.fillPath()
    c.restoreGState()
}

func glow(_ c: CGContext, _ path: CGPath, _ color: CGColor, sigma: CGFloat, mode: CGBlendMode = .normal, clip: CGPath? = nil) {
    let layer = render { l in l.addPath(path); l.setFillColor(color); l.fillPath() }
    c.saveGState()
    if let clip { c.addPath(clip); c.clip() }
    c.setBlendMode(mode); c.draw(blur(layer, sigma), in: full)
    c.restoreGState()
}

/// Colored glass slab: gradient body, luminous inner edge, specular rim and an optional frosted backdrop.
func glass(_ c: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor, opacity: CGFloat,
           frosted: Bool = false, edgeGlow: CGFloat, shadow: CGFloat = 0.45) {
    let box = path.boundingBoxOfPath
    let backdrop = frosted ? blur(c.makeImage()!, 22, clamp: true) : nil
    softShadow(c, path, alpha: shadow, blur: max(30, box.height * 0.10), dy: -(14 + box.height * 0.04))
    c.saveGState()
    c.addPath(path); c.clip()
    if let backdrop { c.draw(backdrop, in: full) }
    c.setAlpha(opacity); vertical(c, box, [top, bottom]); c.setAlpha(1)
    radial(c, CGPoint(x: box.midX, y: box.maxY - box.height * 0.1), max(box.width, box.height) * 0.6,
           [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)])
    let edge = render { l in
        l.addPath(path); l.setLineWidth(max(26, box.width * 0.06)); l.setStrokeColor(rgb(0xFFFFFF)); l.strokePath()
    }
    c.setAlpha(edgeGlow); c.draw(blur(edge, max(10, box.width * 0.025)), in: full); c.setAlpha(1)
    c.addPath(path); c.setLineWidth(10); c.replacePathWithStrokedPath(); c.clip()
    vertical(c, box, [rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0.15), rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 0.45)], [0, 0.3, 0.7, 1])
    c.restoreGState()
}

func drawArtwork(_ c: CGContext) {
    vertical(c, tileRect, [rgb(0x145C38), rgb(0x0A2E1C), rgb(0x03120A)], [0, 0.45, 1])
    radial(c, CGPoint(x: 512, y: 960), 560, [rgb(0x4ADE80, 0.30), rgb(0x4ADE80, 0)])
    radial(c, CGPoint(x: 390, y: 400), 380, [rgb(0x30D158, 0.40), rgb(0x30D158, 0)])

    glass(c, circle(CGPoint(x: 398, y: 418), 192), top: rgb(0x7EEBA6), bottom: rgb(0x0F9A47), opacity: 0.97, edgeGlow: 0.45)

    let page = rounded(CGRect(x: 404, y: 326, width: 376, height: 444), 72)
    glass(c, page, top: rgb(0xFFFFFF), bottom: rgb(0xB9EFCD), opacity: 0.42, frosted: true, edgeGlow: 0.55, shadow: 0.42)
    glow(c, circle(CGPoint(x: 700, y: 360), 150), rgb(0x30D158, 0.45), sigma: 60, mode: .screen, clip: page)

    for (row, width) in ([248, 248, 160] as [CGFloat]).enumerated() {
        let line = capsule(CGRect(x: 468, y: 636 - CGFloat(row) * 98, width: width, height: 40))
        glow(c, line, rgb(0xFFFFFF, 0.75), sigma: 9)
        c.addPath(line); c.setFillColor(rgb(0xFFFFFF)); c.fillPath()
    }
}

func drawHammerBadge(_ c: CGContext) {
    let center = CGPoint(x: 806, y: 218)
    let disc = circle(center, 74)
    softShadow(c, disc, alpha: 0.45, blur: 16, dy: -5)
    c.saveGState()
    c.addPath(disc); c.clip()
    vertical(c, disc.boundingBoxOfPath, [rgb(0x2C2A3A), rgb(0x15141F)])
    c.addPath(disc); c.setLineWidth(6); c.replacePathWithStrokedPath(); c.clip()
    vertical(c, disc.boundingBoxOfPath, [rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0.05)])
    c.restoreGState()

    let handle = rounded(CGRect(x: -8, y: -50, width: 16, height: 74), 8)
    let face = rounded(CGRect(x: -40, y: 12, width: 40, height: 36), 7)
    let claw = CGMutablePath()
    claw.move(to: CGPoint(x: -4, y: 46)); claw.addLine(to: CGPoint(x: -4, y: 18))
    claw.addQuadCurve(to: CGPoint(x: 40, y: 22), control: CGPoint(x: 22, y: 12))
    claw.addQuadCurve(to: CGPoint(x: -4, y: 46), control: CGPoint(x: 26, y: 40))
    var place = CGAffineTransform(translationX: center.x + 4, y: center.y - 2).rotated(by: .pi / 4.5)
    let hammer = handle.union(face).union(claw).copy(using: &place)!
    c.saveGState()
    c.addPath(hammer); c.clip()
    vertical(c, hammer.boundingBoxOfPath, [rgb(0xFFD873), rgb(0xF5A524)])
    c.restoreGState()
}

func renderIcon(devBadge: Bool) -> CGImage {
    let artwork = render { c in c.addPath(tilePath); c.clip(); drawArtwork(c) }
    return render { c in
        softShadow(c, tilePath, alpha: 0.32, blur: 26, dy: -10)
        c.draw(artwork, in: full)
        c.saveGState()
        c.addPath(tilePath); c.setLineWidth(6); c.replacePathWithStrokedPath(); c.clip()
        vertical(c, tileRect, [rgb(0xFFFFFF, 0.5), rgb(0xFFFFFF, 0.04), rgb(0xFFFFFF, 0.18)], [0, 0.5, 1])
        c.restoreGState()
        if devBadge { drawHammerBadge(c) }
    }
}

func savePNG(_ image: CGImage, _ path: String) {
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Cannot write \(path); run from the repository root")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Failed to write \(path)") }
    print("wrote \(path)")
}

savePNG(renderIcon(devBadge: false), "Resources/AppIcon-Source.png")
savePNG(renderIcon(devBadge: true), "Resources/AppIcon-Dev-Source.png")
