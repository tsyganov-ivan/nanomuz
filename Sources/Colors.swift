import AppKit

// MARK: - Color Extraction

extension NSImage {
    func dominantColor() -> NSColor? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        let smallSize = 20
        guard let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: smallSize,
            pixelsHigh: smallSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: smallSize * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        bitmap.draw(in: NSRect(x: 0, y: 0, width: smallSize, height: smallSize))
        NSGraphicsContext.restoreGraphicsState()

        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
        var count: CGFloat = 0

        for y in 0..<smallSize {
            for x in 0..<smallSize {
                guard let color = resized.colorAt(x: x, y: y) else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)

                let brightness = (r + g + b) / 3
                if brightness > 0.1 && brightness < 0.9 {
                    let maxC = max(r, g, b), minC = min(r, g, b)
                    let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                    let weight = 1 + saturation

                    totalR += r * weight
                    totalG += g * weight
                    totalB += b * weight
                    count += weight
                }
            }
        }

        guard count > 0 else { return nil }
        return NSColor(red: totalR / count, green: totalG / count, blue: totalB / count, alpha: 1.0)
    }
}

// MARK: - Color Helpers

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (30, 30, 30)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1.0
        )
    }

    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    var isLight: Bool {
        luminance > 0.5
    }
}

// MARK: - Dynamic Colors

struct DynamicColors {
    let baseColor: NSColor
    let background: NSColor
    let text: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let buttonBackground: NSColor
    let buttonBackgroundHover: NSColor

    init(baseColor: NSColor, opacity: CGFloat) {
        self.baseColor = baseColor
        background = baseColor.withAlphaComponent(opacity)

        if baseColor.isLight {
            text = NSColor.black.withAlphaComponent(0.9)
            textSecondary = NSColor.black.withAlphaComponent(0.6)
            textTertiary = NSColor.black.withAlphaComponent(0.4)
            buttonBackground = NSColor.black.withAlphaComponent(0.08)
            buttonBackgroundHover = NSColor.black.withAlphaComponent(0.15)
        } else {
            text = NSColor.white.withAlphaComponent(0.95)
            textSecondary = NSColor.white.withAlphaComponent(0.6)
            textTertiary = NSColor.white.withAlphaComponent(0.4)
            buttonBackground = NSColor.white.withAlphaComponent(0.08)
            buttonBackgroundHover = NSColor.white.withAlphaComponent(0.15)
        }
    }
}
