import CoreGraphics
import CoreText
import Foundation

/// 从系统 `CoreText` 字体（如 iOS 26+ 采用私有 `hvgl` 表的 `PingFangUI.ttc`）提取矢量轮廓，
/// 在本地缓存目录一次性合成为包含标准 `glyf` 与 `cmap`（Format 12）表的 TrueType 字体数据，
/// 供 `libass` / `FreeType` 在禁用 `ass_coretext` 后直接渲染简繁中文、日文假名与常用符号字幕。
public enum SubtitleTrueTypeFontSynthesizer {
  /// 默认提取的 BMP Unicode 码位区间（覆盖拉丁、西里尔、常用标点符号、日文假名、注音及全部简繁统一汉字与扩展 A 区）。
  public static let defaultRanges: [ClosedRange<UInt32>] = [
    0x0020...0x02FF,
    0x0370...0x04FF,
    0x2000...0x27BF,
    0x3000...0x33FF,
    0x3400...0x4DBF,
    0x4E00...0x9FFF,
    0xF900...0xFAFF,
    0xFE10...0xFFEF,
  ]

  /// 校验磁盘上的合成 TrueType 字体文件是否完整且具备合法 `0x00010000` SFNT 头魔数。
  public static func isValidTrueTypeFile(at url: URL, minimumBytes: Int = 1_000_000) -> Bool {
    guard
      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let fileSize = attrs[.size] as? NSNumber,
      fileSize.intValue >= minimumBytes,
      let handle = try? FileHandle(forReadingFrom: url)
    else {
      return false
    }
    defer { try? handle.close() }
    guard let header = try? handle.read(upToCount: 4), header.count == 4 else {
      return false
    }
    return header[header.startIndex] == 0x00
      && header[header.startIndex + 1] == 0x01
      && header[header.startIndex + 2] == 0x00
      && header[header.startIndex + 3] == 0x00
  }

  /// 使用系统简繁日韩回退字体链合成标准 TrueType（`.ttf`）二进制数据。
  public static func synthesizeFontData(
    familyName: String = "MPPingFangSub",
    codepointRanges: [ClosedRange<UInt32>] = defaultRanges
  ) -> Data? {
    let unitsPerEm: CGFloat = 1000.0
    let baseFont = CTFontCreateWithName("Helvetica" as CFString, unitsPerEm, nil)
    let scFont = CTFontCreateForString(
      baseFont, "简体中文" as CFString, CFRange(location: 0, length: 4))
    let tcFont = CTFontCreateForString(
      baseFont, "繁體國語" as CFString, CFRange(location: 0, length: 4))
    let jpFont = CTFontCreateForString(
      baseFont, "あいうえお" as CFString, CFRange(location: 0, length: 5))
    let candidateFonts = [scFont, tcFont, jpFont, baseFont]

    var totalCandidates = 0
    for range in codepointRanges {
      totalCandidates += Int(range.upperBound - range.lowerBound + 1)
    }

    var glyfWriter = DataWriter()
    glyfWriter.reserve(min(18 * 1024 * 1024, max(64 * 1024, totalCandidates * 560)))
    // 0 号字形（.notdef）占用空轮廓区间 [0, 0]，未命中字符不显示刺眼方框。
    var locaOffsets: [UInt32] = [0, 0]
    locaOffsets.reserveCapacity(totalCandidates + 2)
    var hmtxMetrics: [(adv: UInt16, lsb: Int16)] = [(adv: 500, lsb: 0)]
    hmtxMetrics.reserveCapacity(totalCandidates + 1)
    var cmapPairs: [(cp: UInt32, gid: UInt32)] = []
    cmapPairs.reserveCapacity(totalCandidates)

    var globalXMin: Int16 = 0
    var globalYMin: Int16 = 0
    var globalXMax: Int16 = 1000
    var globalYMax: Int16 = 1000
    var maxAdv: UInt16 = 500
    var maxPts: UInt16 = 0
    var maxContours: UInt16 = 0

    let collector = PathCollector()

    outerLoop: for range in codepointRanges {
      for cp in range {
        if (0xD800...0xDFFF).contains(cp) || cp > 0xFFFF {
          continue
        }
        var utf16 = [UniChar(cp)]
        var chosenFont: CTFont?
        var chosenGlyph: CGGlyph = 0
        for font in candidateFonts {
          var glyph: CGGlyph = 0
          if CTFontGetGlyphsForCharacters(font, &utf16, &glyph, 1), glyph != 0 {
            chosenFont = font
            chosenGlyph = glyph
            break
          }
        }
        guard let font = chosenFont else { continue }

        var glyph = chosenGlyph
        var advSize = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advSize, 1)
        let advU16 = UInt16(clamping: max(0, Int(advSize.width.rounded())))
        if advU16 > maxAdv { maxAdv = advU16 }

        let gid = UInt32(hmtxMetrics.count)
        if gid >= 65535 {
          break outerLoop
        }

        collector.reset()
        if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
          path.applyWithBlock { elemPtr in
            let elem = elemPtr.pointee
            switch elem.type {
            case .moveToPoint:
              collector.move(to: elem.points[0])
            case .addLineToPoint:
              collector.line(to: elem.points[0])
            case .addQuadCurveToPoint:
              collector.quad(ctrl: elem.points[0], to: elem.points[1])
            case .addCurveToPoint:
              collector.cubic(c1: elem.points[0], c2: elem.points[1], to: elem.points[2])
            case .closeSubpath:
              collector.closeContour()
            @unknown default:
              break
            }
          }
          collector.closeContour()
        }

        if collector.contours.isEmpty {
          hmtxMetrics.append((adv: advU16, lsb: 0))
          locaOffsets.append(UInt32(glyfWriter.bytes.count))
          cmapPairs.append((cp: cp, gid: gid))
          continue
        }

        var xMin = Int16.max
        var yMin = Int16.max
        var xMax = Int16.min
        var yMax = Int16.min
        var totalPts = 0
        for contour in collector.contours {
          totalPts += contour.count
          for pt in contour {
            if pt.x < xMin { xMin = pt.x }
            if pt.y < yMin { yMin = pt.y }
            if pt.x > xMax { xMax = pt.x }
            if pt.y > yMax { yMax = pt.y }
          }
        }
        if xMin < globalXMin { globalXMin = xMin }
        if yMin < globalYMin { globalYMin = yMin }
        if xMax > globalXMax { globalXMax = xMax }
        if yMax > globalYMax { globalYMax = yMax }
        if totalPts > Int(maxPts) { maxPts = UInt16(clamping: totalPts) }
        if collector.contours.count > Int(maxContours) {
          maxContours = UInt16(clamping: collector.contours.count)
        }

        glyfWriter.i16(Int16(collector.contours.count))
        glyfWriter.i16(xMin)
        glyfWriter.i16(yMin)
        glyfWriter.i16(xMax)
        glyfWriter.i16(yMax)
        var endIdx = -1
        for contour in collector.contours {
          endIdx += contour.count
          glyfWriter.u16(UInt16(endIdx))
        }
        glyfWriter.u16(0)
        for contour in collector.contours {
          for pt in contour {
            glyfWriter.u8(pt.onCurve ? 0x01 : 0x00)
          }
        }
        var prevX: Int16 = 0
        for contour in collector.contours {
          for pt in contour {
            glyfWriter.i16(pt.x &- prevX)
            prevX = pt.x
          }
        }
        var prevY: Int16 = 0
        for contour in collector.contours {
          for pt in contour {
            glyfWriter.i16(pt.y &- prevY)
            prevY = pt.y
          }
        }
        glyfWriter.pad4()

        hmtxMetrics.append((adv: advU16, lsb: xMin))
        locaOffsets.append(UInt32(glyfWriter.bytes.count))
        cmapPairs.append((cp: cp, gid: gid))
      }
    }

    guard !cmapPairs.isEmpty else { return nil }

    let numGlyphs = UInt16(hmtxMetrics.count)
    let ascender = Int16(clamping: Int(CTFontGetAscent(scFont).rounded()))
    let descender = -Int16(clamping: Int(CTFontGetDescent(scFont).rounded()))
    let lineGap = Int16(clamping: Int(CTFontGetLeading(scFont).rounded()))

    var head = DataWriter()
    head.u32(0x0001_0000)
    head.u32(0x0001_0000)
    head.u32(0)
    head.u32(0x5F0F_3CF5)
    head.u16(0x000B)
    head.u16(1000)
    head.i64(0)
    head.i64(0)
    head.i16(globalXMin)
    head.i16(globalYMin)
    head.i16(globalXMax)
    head.i16(globalYMax)
    head.u16(0)
    head.u16(8)
    head.i16(2)
    head.i16(1)
    head.i16(0)

    var hhea = DataWriter()
    hhea.u32(0x0001_0000)
    hhea.i16(ascender)
    hhea.i16(descender)
    hhea.i16(lineGap)
    hhea.u16(maxAdv)
    hhea.i16(globalXMin)
    hhea.i16(0)
    hhea.i16(globalXMax)
    hhea.i16(1)
    for _ in 0..<7 { hhea.i16(0) }
    hhea.u16(numGlyphs)

    var maxp = DataWriter()
    maxp.u32(0x0001_0000)
    maxp.u16(numGlyphs)
    maxp.u16(maxPts)
    maxp.u16(maxContours)
    for _ in 0..<11 { maxp.u16(0) }

    var os2 = DataWriter()
    os2.u16(4)
    os2.i16(500)
    os2.u16(400)
    os2.u16(5)
    os2.u16(0)
    os2.i16(650)
    os2.i16(600)
    os2.i16(0)
    os2.i16(75)
    os2.i16(650)
    os2.i16(600)
    os2.i16(0)
    os2.i16(350)
    os2.i16(50)
    os2.i16(300)
    os2.i16(0)
    for _ in 0..<10 { os2.u8(0) }
    os2.u32(0xA000_02FF)
    os2.u32(0x4D00_0000)
    os2.u32(0x0000_0000)
    os2.u32(0x0000_0000)
    os2.tag("MP  ")
    os2.u16(0x0040)
    os2.u16(0x0020)
    os2.u16(0xFFFD)
    os2.i16(ascender)
    os2.i16(descender)
    os2.i16(lineGap)
    os2.u16(UInt16(max(0, Int(ascender))))
    os2.u16(UInt16(max(0, Int(-descender))))
    os2.u32(0x001E_0001)
    os2.u32(0x0000_0000)
    os2.i16(500)
    os2.i16(700)
    os2.u16(0)
    os2.u16(0)
    os2.u16(256)

    var hmtx = DataWriter()
    hmtx.reserve(hmtxMetrics.count * 4)
    for metric in hmtxMetrics {
      hmtx.u16(metric.adv)
      hmtx.i16(metric.lsb)
    }

    var loca = DataWriter()
    loca.reserve(locaOffsets.count * 4)
    for off in locaOffsets {
      loca.u32(off)
    }

    var groups: [(start: UInt32, end: UInt32, startGid: UInt32)] = []
    for pair in cmapPairs {
      if let last = groups.last,
        pair.cp == last.end + 1,
        pair.gid == last.startGid + (pair.cp - last.start)
      {
        groups[groups.count - 1].end = pair.cp
      } else {
        groups.append((start: pair.cp, end: pair.cp, startGid: pair.gid))
      }
    }

    var cmapSub12 = DataWriter()
    cmapSub12.u16(12)
    cmapSub12.u16(0)
    cmapSub12.u32(UInt32(16 + groups.count * 12))
    cmapSub12.u32(0)
    cmapSub12.u32(UInt32(groups.count))
    for group in groups {
      cmapSub12.u32(group.start)
      cmapSub12.u32(group.end)
      cmapSub12.u32(group.startGid)
    }

    var cmap = DataWriter()
    cmap.u16(0)
    cmap.u16(2)
    cmap.u16(0)
    cmap.u16(4)
    cmap.u32(20)
    cmap.u16(3)
    cmap.u16(10)
    cmap.u32(20)
    cmap.append(cmapSub12.bytes)

    let postScriptName = "\(familyName.replacingOccurrences(of: " ", with: ""))-Regular"
    let nameEntries: [(id: UInt16, val: String)] = [
      (1, familyName),
      (2, "Regular"),
      (3, familyName),
      (4, familyName),
      (5, "Version 1.0"),
      (6, postScriptName),
    ]
    var nameStrBytes = DataWriter()
    var nameRecs: [(id: UInt16, len: UInt16, off: UInt16)] = []
    for entry in nameEntries {
      let off = UInt16(nameStrBytes.bytes.count)
      for unit in entry.val.utf16 {
        nameStrBytes.u16(unit)
      }
      let len = UInt16(nameStrBytes.bytes.count) - off
      nameRecs.append((id: entry.id, len: len, off: off))
    }
    var nameTbl = DataWriter()
    nameTbl.u16(0)
    nameTbl.u16(UInt16(nameRecs.count))
    nameTbl.u16(UInt16(6 + nameRecs.count * 12))
    for rec in nameRecs {
      nameTbl.u16(3)
      nameTbl.u16(1)
      nameTbl.u16(0x0409)
      nameTbl.u16(rec.id)
      nameTbl.u16(rec.len)
      nameTbl.u16(rec.off)
    }
    nameTbl.append(nameStrBytes.bytes)

    var post = DataWriter()
    post.u32(0x0003_0000)
    post.i32(0)
    post.i16(-100)
    post.i16(50)
    for _ in 0..<5 { post.u32(0) }

    let tables: [(String, [UInt8])] = [
      ("OS/2", os2.bytes),
      ("cmap", cmap.bytes),
      ("glyf", glyfWriter.bytes),
      ("head", head.bytes),
      ("hhea", hhea.bytes),
      ("hmtx", hmtx.bytes),
      ("loca", loca.bytes),
      ("maxp", maxp.bytes),
      ("name", nameTbl.bytes),
      ("post", post.bytes),
    ]

    var out = DataWriter()
    let numTables = UInt16(tables.count)
    out.u32(0x0001_0000)
    out.u16(numTables)
    out.u16(128)
    out.u16(3)
    out.u16(numTables * 16 - 128)

    var offset = UInt32(12 + tables.count * 16)
    var headOffset = 0
    for (tag, tableBytes) in tables {
      if tag == "head" { headOffset = Int(offset) }
      out.tag(tag)
      out.u32(calculateTableChecksum(tableBytes))
      out.u32(offset)
      out.u32(UInt32(tableBytes.count))
      let paddedLen = (tableBytes.count + 3) & ~3
      offset += UInt32(paddedLen)
    }
    for (_, tableBytes) in tables {
      out.append(tableBytes)
      out.pad4()
    }

    let totalSum = calculateTableChecksum(out.bytes)
    let checksumAdjustment = 0xB1B0_AFBA &- totalSum
    out.bytes[headOffset + 8] = UInt8((checksumAdjustment >> 24) & 0xFF)
    out.bytes[headOffset + 9] = UInt8((checksumAdjustment >> 16) & 0xFF)
    out.bytes[headOffset + 10] = UInt8((checksumAdjustment >> 8) & 0xFF)
    out.bytes[headOffset + 11] = UInt8(checksumAdjustment & 0xFF)

    return Data(out.bytes)
  }

  private static func calculateTableChecksum(_ bytes: [UInt8]) -> UInt32 {
    var sum: UInt32 = 0
    var idx = 0
    while idx + 3 < bytes.count {
      let word =
        (UInt32(bytes[idx]) << 24)
        | (UInt32(bytes[idx + 1]) << 16)
        | (UInt32(bytes[idx + 2]) << 8)
        | UInt32(bytes[idx + 3])
      sum = sum &+ word
      idx += 4
    }
    if idx < bytes.count {
      var tail: UInt32 = 0
      for rem in 0..<4 {
        tail = (tail << 8) | (idx + rem < bytes.count ? UInt32(bytes[idx + rem]) : 0)
      }
      sum = sum &+ tail
    }
    return sum
  }
}

private struct DataWriter {
  var bytes: [UInt8] = []

  mutating func reserve(_ capacity: Int) {
    bytes.reserveCapacity(capacity)
  }

  mutating func u8(_ value: UInt8) {
    bytes.append(value)
  }

  mutating func i16(_ value: Int16) {
    u16(UInt16(bitPattern: value))
  }

  mutating func u16(_ value: UInt16) {
    bytes.append(UInt8((value >> 8) & 0xFF))
    bytes.append(UInt8(value & 0xFF))
  }

  mutating func i32(_ value: Int32) {
    u32(UInt32(bitPattern: value))
  }

  mutating func u32(_ value: UInt32) {
    bytes.append(UInt8((value >> 24) & 0xFF))
    bytes.append(UInt8((value >> 16) & 0xFF))
    bytes.append(UInt8((value >> 8) & 0xFF))
    bytes.append(UInt8(value & 0xFF))
  }

  mutating func i64(_ value: Int64) {
    u32(UInt32(truncatingIfNeeded: value >> 32))
    u32(UInt32(truncatingIfNeeded: value))
  }

  mutating func tag(_ text: String) {
    for byte in text.utf8.prefix(4) {
      bytes.append(byte)
    }
  }

  mutating func append(_ other: [UInt8]) {
    bytes.append(contentsOf: other)
  }

  mutating func pad4() {
    while (bytes.count & 3) != 0 {
      bytes.append(0)
    }
  }
}

private final class PathCollector {
  struct ContourPoint {
    var x: Int16
    var y: Int16
    var onCurve: Bool
  }

  var contours: [[ContourPoint]] = []
  var current: [ContourPoint] = []
  var lastPoint: CGPoint = .zero

  func reset() {
    contours.removeAll(keepingCapacity: true)
    current.removeAll(keepingCapacity: true)
    lastPoint = .zero
  }

  private func clampI16(_ value: CGFloat) -> Int16 {
    Int16(clamping: Int(value.rounded()))
  }

  func move(to point: CGPoint) {
    closeContour()
    current = [ContourPoint(x: clampI16(point.x), y: clampI16(point.y), onCurve: true)]
    lastPoint = point
  }

  func line(to point: CGPoint) {
    let candidate = ContourPoint(x: clampI16(point.x), y: clampI16(point.y), onCurve: true)
    if let last = current.last, last.x == candidate.x, last.y == candidate.y, last.onCurve {
      lastPoint = point
      return
    }
    current.append(candidate)
    lastPoint = point
  }

  func quad(ctrl: CGPoint, to point: CGPoint) {
    current.append(ContourPoint(x: clampI16(ctrl.x), y: clampI16(ctrl.y), onCurve: false))
    current.append(ContourPoint(x: clampI16(point.x), y: clampI16(point.y), onCurve: true))
    lastPoint = point
  }

  func cubic(c1: CGPoint, c2: CGPoint, to p3: CGPoint) {
    let p0 = lastPoint
    let m01 = CGPoint(x: (p0.x + c1.x) * 0.5, y: (p0.y + c1.y) * 0.5)
    let m12 = CGPoint(x: (c1.x + c2.x) * 0.5, y: (c1.y + c2.y) * 0.5)
    let m23 = CGPoint(x: (c2.x + p3.x) * 0.5, y: (c2.y + p3.y) * 0.5)
    let m012 = CGPoint(x: (m01.x + m12.x) * 0.5, y: (m01.y + m12.y) * 0.5)
    let m123 = CGPoint(x: (m12.x + m23.x) * 0.5, y: (m12.y + m23.y) * 0.5)
    let mid = CGPoint(x: (m012.x + m123.x) * 0.5, y: (m012.y + m123.y) * 0.5)
    let q1 = CGPoint(
      x: 0.75 * (m01.x + m012.x) - 0.25 * (p0.x + mid.x),
      y: 0.75 * (m01.y + m012.y) - 0.25 * (p0.y + mid.y)
    )
    let q2 = CGPoint(
      x: 0.75 * (m123.x + m23.x) - 0.25 * (mid.x + p3.x),
      y: 0.75 * (m123.y + m23.y) - 0.25 * (mid.y + p3.y)
    )
    quad(ctrl: q1, to: mid)
    quad(ctrl: q2, to: p3)
  }

  func closeContour() {
    if current.count >= 2, let first = current.first, let last = current.last,
      first.x == last.x, first.y == last.y, first.onCurve, last.onCurve
    {
      current.removeLast()
    }
    if current.count >= 3 {
      contours.append(current)
    }
    current.removeAll(keepingCapacity: true)
  }
}
