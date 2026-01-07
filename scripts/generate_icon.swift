import AppKit
import Foundation

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let iconsetPath = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, filename) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.2

    // Background gradient (dark purple to deep blue)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.15, green: 0.05, blue: 0.25, alpha: 1.0),
        NSColor(red: 0.05, green: 0.10, blue: 0.20, alpha: 1.0)
    ])!

    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    gradient.draw(in: path, angle: -45)

    // Draw sound wave bars
    let barCount = 5
    let barWidth = CGFloat(size) * 0.08
    let gap = CGFloat(size) * 0.04
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
    let startX = (CGFloat(size) - totalWidth) / 2
    let centerY = CGFloat(size) / 2

    let heights: [CGFloat] = [0.25, 0.45, 0.6, 0.45, 0.25]

    for i in 0..<barCount {
        let barHeight = CGFloat(size) * heights[i]
        let x = startX + CGFloat(i) * (barWidth + gap)
        let y = centerY - barHeight / 2

        let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

        // Gradient for bars (cyan to purple)
        let barGradient = NSGradient(colors: [
            NSColor(red: 0.3, green: 0.9, blue: 0.9, alpha: 1.0),
            NSColor(red: 0.6, green: 0.4, blue: 0.9, alpha: 1.0)
        ])!
        barGradient.draw(in: barPath, angle: 90)
    }

    image.unlockFocus()

    // Save as PNG
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: iconsetPath).appendingPathComponent(filename)
        try? pngData.write(to: url)
    }
}

print("Iconset created")
