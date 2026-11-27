import CoreGraphics
import CoreText
import Foundation
import MoviePilotCore
import XCTest

final class SubtitleTrueTypeFontSynthesizerTests: XCTestCase {
  /// 验证合成的 TrueType 字体具备标准 `glyf` 矢量轮廓、正确的 `loca` 偏移（无差一错位）以及正数空格步进。
  func testSynthesizedFontContainsCrispSimplifiedAndTraditionalGlyphOutlines() throws {
    let sampleText = "蜘蛛侠：崭新之日 · 繁體國語 Spider-Man"
    var codepoints = Set<UInt32>([0x0020])
    for scalar in sampleText.unicodeScalars {
      codepoints.insert(scalar.value)
    }
    let sortedRanges = codepoints.sorted().map { $0...$0 }

    let data = try XCTUnwrap(
      SubtitleTrueTypeFontSynthesizer.synthesizeFontData(
        familyName: "MPPingFangSub",
        codepointRanges: sortedRanges
      )
    )
    XCTAssertGreaterThan(data.count, 1024)
    XCTAssertEqual(Array(data.prefix(4)), [0x00, 0x01, 0x00, 0x00])

    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    let cgFont = try XCTUnwrap(CGFont(provider))
    let ctFont = CTFontCreateWithGraphicsFont(cgFont, 48.0, nil, nil)
    XCTAssertEqual(CTFontCopyFamilyName(ctFont) as String, "MPPingFangSub")

    for ch in ["蜘", "蛛", "侠", "崭", "新", "日", "繁", "體", "國", "S", "p"] {
      var utf16 = Array(ch.utf16)
      var glyph: CGGlyph = 0
      XCTAssertTrue(
        CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyph, 1),
        "字符 \(ch) 必须命中有效字形而非 .notdef"
      )
      XCTAssertNotEqual(glyph, 0, "字符 \(ch) 不能回退到 0 号 .notdef 方框字形")
      let path = try XCTUnwrap(
        CTFontCreatePathForGlyph(ctFont, glyph, nil),
        "字符 \(ch) 必须拥有非空 glyf 矢量轮廓"
      )
      XCTAssertFalse(path.isEmpty)
      XCTAssertGreaterThan(path.boundingBoxOfPath.width, 1.0)
      XCTAssertGreaterThan(path.boundingBoxOfPath.height, 1.0)
    }

    var spaceUTF16: [UniChar] = [0x0020]
    var spaceGlyph: CGGlyph = 0
    XCTAssertTrue(CTFontGetGlyphsForCharacters(ctFont, &spaceUTF16, &spaceGlyph, 1))
    XCTAssertNotEqual(spaceGlyph, 0)
    var spaceAdvance = CGSize.zero
    _ = CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &spaceGlyph, &spaceAdvance, 1)
    XCTAssertGreaterThan(spaceAdvance.width, 4.0)
  }
}
