import CoreText
import XCTest
@testable import Shell
@testable import UI

final class WordmarkTests: XCTestCase {
    /// The bundled Bricolage Grotesque loads, and each part of the
    /// wordmark gets its own weight (the file's default instance is 800).
    func testBundledFontLoadsWithTheWordmarkWeights() throws {
        let base = try XCTUnwrap(Wordmark.baseDescriptor, "BricolageGrotesque.ttf is in the bundle")
        let font = CTFontCreateWithFontDescriptor(base, 22, nil)
        XCTAssertEqual(CTFontCopyFamilyName(font) as String, "Bricolage Grotesque")
        let wght: UInt32 = "wght".utf8.reduce(0) { $0 << 8 | UInt32($1) }
        for weight in [600.0, 350, 500] {
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(
                base, [kCTFontVariationAttribute: [NSNumber(value: wght): NSNumber(value: weight)]] as CFDictionary)
            let variant = CTFontCreateWithFontDescriptor(descriptor, 22, nil)
            let applied = (CTFontCopyVariation(variant) as? [NSNumber: NSNumber])?[NSNumber(value: wght)]
            XCTAssertEqual(applied?.doubleValue ?? 0, weight, accuracy: 0.5)
        }
    }
}
