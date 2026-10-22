import Cocoa

let size = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext
let bounds = CGRect(x: 0, y: 0, width: size, height: size)

// Background: rounded squircle with gradient
let cornerRadius: CGFloat = 224
let iconRect = bounds.insetBy(dx: 48, dy: 48)
let path = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

ctx.addPath(path)
ctx.clip()

// Deep charcoal / violet background gradient
let colorSpace = CGColorSpaceCreateDeviceRGB()
let colors = [
    CGColor(red: 0.08, green: 0.09, blue: 0.14, alpha: 1.0),
    CGColor(red: 0.14, green: 0.12, blue: 0.22, alpha: 1.0)
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: CGFloat(size), y: CGFloat(size)), options: [])

// Glow circle in center
let glowColors = [
    CGColor(red: 0.38, green: 0.25, blue: 0.95, alpha: 0.45),
    CGColor(red: 0.08, green: 0.65, blue: 0.95, alpha: 0.0)
] as CFArray
let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(glowGradient, startCenter: CGPoint(x: size/2, y: size/2), startRadius: 40, endCenter: CGPoint(x: size/2, y: size/2), endRadius: 360, options: [])

// Outer border
ctx.addPath(path)
ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15))
ctx.setLineWidth(6)
ctx.strokePath()

// Draw microphone capsule
let center = CGPoint(x: size / 2, y: size / 2 + 30)
let micWidth: CGFloat = 130
let micHeight: CGFloat = 260
let micCapsuleRect = CGRect(x: center.x - micWidth/2, y: center.y - micHeight/2, width: micWidth, height: micHeight)
let micCapsulePath = CGPath(roundedRect: micCapsuleRect, cornerWidth: micWidth/2, cornerHeight: micWidth/2, transform: nil)

let micColors = [
    CGColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0),
    CGColor(red: 0.65, green: 0.35, blue: 1.0, alpha: 1.0)
] as CFArray
let micGradient = CGGradient(colorsSpace: colorSpace, colors: micColors, locations: [0.0, 1.0])!

ctx.saveGState()
ctx.addPath(micCapsulePath)
ctx.clip()
ctx.drawLinearGradient(micGradient, start: CGPoint(x: micCapsuleRect.minX, y: micCapsuleRect.maxY), end: CGPoint(x: micCapsuleRect.maxX, y: micCapsuleRect.minY), options: [])
ctx.restoreGState()

// Microphone arc
let arcRadius: CGFloat = 120
let arcCenter = CGPoint(x: center.x, y: center.y - 10)
ctx.setStrokeColor(CGColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 0.9))
ctx.setLineWidth(24)
ctx.setLineCap(.round)

let arcPath = CGMutablePath()
arcPath.addArc(center: arcCenter, radius: arcRadius, startAngle: CGFloat.pi * 0.05, endAngle: CGFloat.pi * 0.95, clockwise: false)
ctx.addPath(arcPath)
ctx.strokePath()

// Mic stand stem
let stemPath = CGMutablePath()
stemPath.move(to: CGPoint(x: center.x, y: arcCenter.y - arcRadius))
stemPath.addLine(to: CGPoint(x: center.x, y: arcCenter.y - arcRadius - 80))
ctx.addPath(stemPath)
ctx.strokePath()

// Mic base
let basePath = CGMutablePath()
basePath.move(to: CGPoint(x: center.x - 80, y: arcCenter.y - arcRadius - 80))
basePath.addLine(to: CGPoint(x: center.x + 80, y: arcCenter.y - arcRadius - 80))
ctx.addPath(basePath)
ctx.strokePath()

img.unlockFocus()

// Save to 1024x1024 PNG
let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!

let outputDir = URL(fileURLWithPath: "Assets")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let pngURL = outputDir.appendingPathComponent("AppIcon.png")
try! png.write(to: pngURL)
print("Saved AppIcon.png")
