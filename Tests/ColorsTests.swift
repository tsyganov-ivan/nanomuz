import XCTest
import AppKit

func parseHexColor(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
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
    return (CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255)
}

func calculateLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
    return 0.299 * r + 0.587 * g + 0.114 * b
}

func isLightColor(r: CGFloat, g: CGFloat, b: CGFloat) -> Bool {
    return calculateLuminance(r: r, g: g, b: b) > 0.5
}

struct TestDynamicColors {
    let baseR: CGFloat, baseG: CGFloat, baseB: CGFloat
    let opacity: CGFloat
    let isLight: Bool

    var textR: CGFloat { isLight ? 0 : 1 }
    var textG: CGFloat { isLight ? 0 : 1 }
    var textB: CGFloat { isLight ? 0 : 1 }

    init(r: CGFloat, g: CGFloat, b: CGFloat, opacity: CGFloat) {
        self.baseR = r
        self.baseG = g
        self.baseB = b
        self.opacity = opacity
        self.isLight = isLightColor(r: r, g: g, b: b)
    }
}

final class ColorsTests: XCTestCase {

    // MARK: - Hex Parsing Tests

    func testHexParsing6DigitsRed() {
        let (r, g, b) = parseHexColor("FF0000")

        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testHexParsing6DigitsGreen() {
        let (r, g, b) = parseHexColor("00FF00")

        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(g, 1.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testHexParsing6DigitsBlue() {
        let (r, g, b) = parseHexColor("0000FF")

        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 1.0, accuracy: 0.01)
    }

    func testHexParsingWithHashPrefix() {
        let (r, g, b) = parseHexColor("#FF0000")

        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testHexParsingInvalidFallsBackToDefault() {
        let (r, g, b) = parseHexColor("invalid")

        XCTAssertEqual(r, 30.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(g, 30.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 30.0 / 255.0, accuracy: 0.01)
    }

    func testHexParsingEmptyStringFallsBackToDefault() {
        let (r, g, b) = parseHexColor("")

        XCTAssertEqual(r, 30.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(g, 30.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 30.0 / 255.0, accuracy: 0.01)
    }

    func testHexParsingLowercaseHex() {
        let (r, g, b) = parseHexColor("ff8800")

        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 136.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testHexParsingMixedCase() {
        let (r, g, b) = parseHexColor("FfAa00")

        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 170.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    // MARK: - Luminance Tests

    func testLuminanceWhite() {
        let luminance = calculateLuminance(r: 1.0, g: 1.0, b: 1.0)
        XCTAssertEqual(luminance, 1.0, accuracy: 0.01)
    }

    func testLuminanceBlack() {
        let luminance = calculateLuminance(r: 0.0, g: 0.0, b: 0.0)
        XCTAssertEqual(luminance, 0.0, accuracy: 0.01)
    }

    func testLuminanceRed() {
        let luminance = calculateLuminance(r: 1.0, g: 0.0, b: 0.0)
        XCTAssertEqual(luminance, 0.299, accuracy: 0.01)
    }

    func testLuminanceGreen() {
        let luminance = calculateLuminance(r: 0.0, g: 1.0, b: 0.0)
        XCTAssertEqual(luminance, 0.587, accuracy: 0.01)
    }

    func testLuminanceBlue() {
        let luminance = calculateLuminance(r: 0.0, g: 0.0, b: 1.0)
        XCTAssertEqual(luminance, 0.114, accuracy: 0.01)
    }

    func testLuminanceGray() {
        let luminance = calculateLuminance(r: 0.5, g: 0.5, b: 0.5)
        XCTAssertEqual(luminance, 0.5, accuracy: 0.01)
    }

    // MARK: - isLight Tests

    func testIsLightWhite() {
        XCTAssertTrue(isLightColor(r: 1.0, g: 1.0, b: 1.0))
    }

    func testIsLightBlack() {
        XCTAssertFalse(isLightColor(r: 0.0, g: 0.0, b: 0.0))
    }

    func testIsLightYellow() {
        let (r, g, b) = parseHexColor("FFFF00")
        XCTAssertTrue(isLightColor(r: r, g: g, b: b))
    }

    func testIsLightDarkBlue() {
        let (r, g, b) = parseHexColor("000080")
        XCTAssertFalse(isLightColor(r: r, g: g, b: b))
    }

    func testIsLightMidGray() {
        XCTAssertFalse(isLightColor(r: 0.5, g: 0.5, b: 0.5))
    }

    func testIsLightBrightGray() {
        XCTAssertTrue(isLightColor(r: 0.6, g: 0.6, b: 0.6))
    }

    // MARK: - DynamicColors Tests

    func testDynamicColorsWithLightBase() {
        let colors = TestDynamicColors(r: 1.0, g: 1.0, b: 1.0, opacity: 0.5)

        XCTAssertEqual(colors.opacity, 0.5, accuracy: 0.01)
        XCTAssertTrue(colors.isLight)
        XCTAssertEqual(colors.textR, 0.0, accuracy: 0.01)
        XCTAssertEqual(colors.textG, 0.0, accuracy: 0.01)
        XCTAssertEqual(colors.textB, 0.0, accuracy: 0.01)
    }

    func testDynamicColorsWithDarkBase() {
        let colors = TestDynamicColors(r: 0.0, g: 0.0, b: 0.0, opacity: 0.8)

        XCTAssertEqual(colors.opacity, 0.8, accuracy: 0.01)
        XCTAssertFalse(colors.isLight)
        XCTAssertEqual(colors.textR, 1.0, accuracy: 0.01)
        XCTAssertEqual(colors.textG, 1.0, accuracy: 0.01)
        XCTAssertEqual(colors.textB, 1.0, accuracy: 0.01)
    }

    func testDynamicColorsBaseColorPreserved() {
        let (r, g, b) = parseHexColor("657A91")
        let colors = TestDynamicColors(r: r, g: g, b: b, opacity: 0.5)

        XCTAssertEqual(colors.baseR, r, accuracy: 0.01)
        XCTAssertEqual(colors.baseG, g, accuracy: 0.01)
        XCTAssertEqual(colors.baseB, b, accuracy: 0.01)
    }

    func testDynamicColorsOpacityBounds() {
        let colorsMin = TestDynamicColors(r: 0.5, g: 0.5, b: 0.5, opacity: 0.0)
        let colorsMax = TestDynamicColors(r: 0.5, g: 0.5, b: 0.5, opacity: 1.0)

        XCTAssertEqual(colorsMin.opacity, 0.0, accuracy: 0.01)
        XCTAssertEqual(colorsMax.opacity, 1.0, accuracy: 0.01)
    }
}
