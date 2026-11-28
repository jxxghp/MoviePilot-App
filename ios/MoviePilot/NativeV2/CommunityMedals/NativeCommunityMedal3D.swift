import CoreGraphics
import Foundation
import ImageIO
import MoviePilotCore
import SceneKit
import SwiftUI
import UIKit

// MARK: - 颜色与资源加载

/// 从十六进制字符串解析 SwiftUI Color / UIColor。
enum CommunityMedalColor {
  static func uiColor(hex: String, alpha: CGFloat = 1) -> UIColor {
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
      return UIColor(white: 0.7, alpha: alpha)
    }
    let r = CGFloat((value >> 16) & 0xFF) / 255.0
    let g = CGFloat((value >> 8) & 0xFF) / 255.0
    let b = CGFloat(value & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: alpha)
  }

  static func color(hex: String, alpha: Double = 1) -> Color {
    Color(uiColor: uiColor(hex: hex, alpha: CGFloat(alpha)))
  }
}

/// 加载内置 `CommunityMedals` 目录中的 WebP 纹理与轮廓 JSON，并提供轻量内存缓存。
final class CommunityMedalAssetLoader: @unchecked Sendable {
  static let shared = CommunityMedalAssetLoader()

  private let lock = NSLock()
  private var imageCache: [String: UIImage] = [:]
  private var thumbnailCache: [String: UIImage] = [:]
  private var outlineCache: [String: CommunityMedalOutline] = [:]

  func webpImage(named stem: String) -> UIImage? {
    lock.lock()
    if let cached = imageCache[stem] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    guard
      let url =
        Bundle.main.url(
          forResource: stem, withExtension: "webp", subdirectory: "CommunityMedals")
        ?? Bundle.main.url(forResource: stem, withExtension: "webp"),
      let image = UIImage(contentsOfFile: url.path)
    else { return nil }

    lock.lock()
    if imageCache.count > 48 {
      imageCache.removeAll(keepingCapacity: true)
    }
    imageCache[stem] = image
    lock.unlock()
    return image
  }

  func outline(named stem: String) -> CommunityMedalOutline? {
    lock.lock()
    if let cached = outlineCache[stem] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    guard
      let url =
        Bundle.main.url(
          forResource: "\(stem).outline", withExtension: "json", subdirectory: "CommunityMedals")
        ?? Bundle.main.url(forResource: "\(stem).outline", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode(CommunityMedalOutline.self, from: data)
    else { return nil }

    lock.lock()
    outlineCache[stem] = decoded
    lock.unlock()
    return decoded
  }

  func badgeImage(for record: CommunityMedalRecord) -> UIImage? {
    let stem = CommunityMedalCatalog.badgeAssetStem(for: record)
    return webpImage(named: stem) ?? webpImage(named: "\(record.key)-badge")
  }

  func frontImage(for record: CommunityMedalRecord) -> UIImage? {
    let stem = CommunityMedalCatalog.frontAssetStem(for: record)
    return webpImage(named: stem) ?? webpImage(named: "\(record.key)-front")
  }

  // MARK: 网格缩略图（降采样 + 烘焙阴影）

  /// 网格缩略图画布在勋章本体四周预留的阴影余量（pt），需容纳模糊半径与下移偏移。
  static let gridThumbnailShadowInset: CGFloat = 16

  /// 网格缩略图画布边长（pt）：勋章本体边长加两侧阴影余量。
  static func gridThumbnailCanvasSide(medalSide: CGFloat) -> CGFloat {
    medalSide + gridThumbnailShadowInset * 2
  }

  /// 网格缩略图的候选素材名，顺序与原网格取图一致：分档正面图 → 通用正面图 → 分档徽标 → 通用徽标。
  static func gridThumbnailStems(for record: CommunityMedalRecord) -> [String] {
    [
      CommunityMedalCatalog.frontAssetStem(for: record),
      "\(record.key)-front",
      CommunityMedalCatalog.badgeAssetStem(for: record),
      "\(record.key)-badge",
    ]
  }

  /// 网格缩略图缓存键，覆盖素材、显示边长、屏幕倍率与深浅色阴影。
  static func gridThumbnailKey(
    stems: [String], medalSide: CGFloat, scale: CGFloat, isDark: Bool
  ) -> String {
    "\(stems.first ?? "")|\(Int(medalSide.rounded()))|\(Int((scale * 100).rounded()))|\(isDark)"
  }

  /// 同步读取已生成的网格缩略图，供首帧直接呈现。
  func cachedGridThumbnail(forKey key: String) -> UIImage? {
    lock.lock()
    defer { lock.unlock() }
    return thumbnailCache[key]
  }

  /// 生成网格缩略图：用 ImageIO 把 1200px 原图直接降采样到显示像素并立即解码，再把投影一次性烘焙进位图，
  /// 滚动时不再逐帧缩放大纹理和离屏计算阴影。可在后台线程调用。
  func makeGridThumbnail(
    stems: [String], medalSide: CGFloat, scale: CGFloat, isDark: Bool
  ) -> UIImage? {
    let key = Self.gridThumbnailKey(
      stems: stems, medalSide: medalSide, scale: scale, isDark: isDark)
    if let cached = cachedGridThumbnail(forKey: key) { return cached }

    let maxPixel = max(Int((medalSide * scale).rounded(.up)), 1)
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    var downsampled: CGImage?
    for stem in stems {
      guard
        let url =
          Bundle.main.url(
            forResource: stem, withExtension: "webp", subdirectory: "CommunityMedals")
          ?? Bundle.main.url(forResource: stem, withExtension: "webp"),
        let source = CGImageSourceCreateWithURL(
          url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      else { continue }
      downsampled = image
      break
    }
    guard let downsampled else { return nil }

    let canvasSide = Self.gridThumbnailCanvasSide(medalSide: medalSide)
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: canvasSide, height: canvasSide), format: format)
    let pixelWidth = CGFloat(downsampled.width)
    let pixelHeight = CGFloat(downsampled.height)
    let fit = medalSide / max(pixelWidth, pixelHeight, 1)
    let drawSize = CGSize(width: pixelWidth * fit, height: pixelHeight * fit)
    let drawRect = CGRect(
      x: (canvasSide - drawSize.width) / 2,
      y: (canvasSide - drawSize.height) / 2,
      width: drawSize.width,
      height: drawSize.height)
    let baked = renderer.image { context in
      // 与原 `.shadow(radius: 6, y: 3)` 对齐：Core Graphics 的 blur 约为图层阴影半径的两倍。
      context.cgContext.setShadow(
        offset: CGSize(width: 0, height: 3),
        blur: 12,
        color: UIColor.black.withAlphaComponent(isDark ? 0.42 : 0.18).cgColor)
      UIImage(cgImage: downsampled).draw(in: drawRect)
    }

    lock.lock()
    if thumbnailCache.count > 64 {
      thumbnailCache.removeAll(keepingCapacity: true)
    }
    thumbnailCache[key] = baked
    lock.unlock()
    return baked
  }
}

// MARK: - 背面铭牌动态雕刻（复刻 Web communityMedalEngrave.ts）

/// 在背面纹理的 `dial` 铭牌区域内按金属基色自动配色并三遍凹雕铭文与 MoviePilot 标志。
enum CommunityMedalEngraver {
  private struct InkPalette {
    let groove: UIColor
    let shadow: UIColor
    let edge: UIColor
  }

  private struct LayoutRow {
    enum Kind {
      case title
      case body
      case mark
    }
    let kind: Kind
    let text: String
    var fontSize: CGFloat
    let weight: UIFont.Weight
    let tracking: CGFloat
    let lineHeightRatio: CGFloat
  }

  static func engrave(
    backImage: UIImage,
    dial: CommunityMedalOutline.DialRect?,
    engraving: CommunityMedalEngraving
  ) -> UIImage {
    guard let cgImage = backImage.cgImage else { return backImage }
    let width = cgImage.width
    let height = cgImage.height
    let size = CGSize(width: width, height: height)

    let dialRect: CGRect
    if let dial {
      let dw = CGFloat(dial.width) * size.width
      let dh = CGFloat(dial.height) * size.height
      let dx = CGFloat(dial.x) * size.width - dw * 0.5
      let dy = CGFloat(dial.y) * size.height - dh * 0.5
      dialRect = CGRect(x: dx, y: dy, width: dw, height: dh)
    } else {
      dialRect = CGRect(
        x: size.width * 0.25, y: size.height * 0.38, width: size.width * 0.50,
        height: size.height * 0.24)
    }

    let metalRGB = sampleAverageMetalRGB(cgImage: cgImage, rect: dialRect)
    let ink = makeInkPalette(metalRGB: metalRGB)

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: size, format: format)

    return renderer.image { ctx in
      let cg = ctx.cgContext
      backImage.draw(in: CGRect(origin: .zero, size: size))

      let innerW = dialRect.width * 0.90
      let innerH = dialRect.height * 0.90
      let minFont = max(14, size.width / 380.0 * 9.0)
      let layout = fitLayout(
        engraving: engraving,
        dialWidth: dialRect.width,
        maxWidth: innerW,
        maxHeight: innerH,
        minFont: minFont
      )
      guard !layout.rows.isEmpty else { return }

      let totalHeight = measureTotalHeight(rows: layout.rows, gapRatio: layout.gapRatio)
      var currentY = dialRect.midY - totalHeight * 0.5
      let bevel = max(1.0, (size.width / 300.0).rounded())

      for (index, row) in layout.rows.enumerated() {
        let rowHeight = row.fontSize * row.lineHeightRatio
        let centerY = currentY + rowHeight * 0.5
        if row.kind == .mark {
          drawMakerMark(
            in: cg,
            text: row.text,
            centerX: dialRect.midX,
            centerY: centerY,
            fontSize: row.fontSize,
            tracking: row.tracking,
            bevel: bevel,
            ink: ink
          )
        } else {
          drawCarvedText(
            text: row.text,
            centerX: dialRect.midX,
            centerY: centerY,
            fontSize: row.fontSize,
            weight: row.weight,
            tracking: row.tracking,
            bevel: bevel,
            ink: ink
          )
        }
        currentY += rowHeight
        if index < layout.rows.count - 1 {
          currentY += row.fontSize * (layout.gapRatio - 1.0)
        }
      }
    }
  }

  private static func sampleAverageMetalRGB(cgImage: CGImage, rect: CGRect) -> (
    CGFloat, CGFloat, CGFloat
  ) {
    let w = cgImage.width
    let h = cgImage.height
    let bytesPerRow = w * 4
    var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: &pixels,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return (168 / 255, 164 / 255, 156 / 255) }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

    let minX = max(0, Int(rect.minX.rounded()))
    let maxX = min(w - 1, Int(rect.maxX.rounded()))
    let minY = max(0, Int(rect.minY.rounded()))
    let maxY = min(h - 1, Int(rect.maxY.rounded()))
    guard minX < maxX, minY < maxY else { return (168 / 255, 164 / 255, 156 / 255) }

    var rSum: Double = 0
    var gSum: Double = 0
    var bSum: Double = 0
    var count: Double = 0

    for y in stride(from: minY, through: maxY, by: 4) {
      let rowOffset = y * bytesPerRow
      for x in stride(from: minX, through: maxX, by: 4) {
        let offset = rowOffset + x * 4
        let a = pixels[offset + 3]
        guard a >= 200 else { continue }
        let af = Double(a) / 255.0
        rSum += min(255.0, Double(pixels[offset]) / af)
        gSum += min(255.0, Double(pixels[offset + 1]) / af)
        bSum += min(255.0, Double(pixels[offset + 2]) / af)
        count += 1
      }
    }
    guard count > 0 else { return (168 / 255, 164 / 255, 156 / 255) }
    return (
      CGFloat(rSum / count / 255.0),
      CGFloat(gSum / count / 255.0),
      CGFloat(bSum / count / 255.0)
    )
  }

  private static func makeInkPalette(metalRGB: (CGFloat, CGFloat, CGFloat)) -> InkPalette {
    let (mr, mg, mb) = metalRGB
    // groove = mix(metal, black, 0.58)
    let gr = mr * 0.42
    let gg = mg * 0.42
    let gb = mb * 0.42
    // shadow = mix(groove, black, 0.45)
    let sr = gr * 0.55
    let sg = gg * 0.55
    let sb = gb * 0.55
    // edge = mix(metal, white, 0.38) @ 0.75 alpha
    let er = mr * 0.62 + 0.38
    let eg = mg * 0.62 + 0.38
    let eb = mb * 0.62 + 0.38
    return InkPalette(
      groove: UIColor(red: gr, green: gg, blue: gb, alpha: 0.94),
      shadow: UIColor(red: sr, green: sg, blue: sb, alpha: 0.95),
      edge: UIColor(red: er, green: eg, blue: eb, alpha: 0.75)
    )
  }

  private static func fitLayout(
    engraving: CommunityMedalEngraving,
    dialWidth: CGFloat,
    maxWidth: CGFloat,
    maxHeight: CGFloat,
    minFont: CGFloat
  ) -> (rows: [LayoutRow], gapRatio: CGFloat) {
    var rows: [LayoutRow] = [
      LayoutRow(
        kind: .title, text: engraving.title, fontSize: dialWidth * 0.125,
        weight: .semibold, tracking: 0.08, lineHeightRatio: 1.18)
    ]
    if let tierLine = engraving.tierLine, !tierLine.isEmpty {
      rows.append(
        LayoutRow(
          kind: .body, text: tierLine, fontSize: dialWidth * 0.062,
          weight: .medium, tracking: 0.02, lineHeightRatio: 1.18))
    }
    if let recipient = engraving.recipientLine, !recipient.isEmpty {
      rows.append(
        LayoutRow(
          kind: .body, text: recipient, fontSize: dialWidth * 0.060,
          weight: .medium, tracking: 0.02, lineHeightRatio: 1.18))
    }
    if let timeLine = engraving.timeLine, !timeLine.isEmpty {
      rows.append(
        LayoutRow(
          kind: .body, text: timeLine, fontSize: dialWidth * 0.058,
          weight: .medium, tracking: 0.02, lineHeightRatio: 1.18))
    }
    rows.append(
      LayoutRow(
        kind: .mark, text: engraving.makerMark, fontSize: dialWidth * 0.056,
        weight: .semibold, tracking: 0.12, lineHeightRatio: 1.18))

    var gapRatio: CGFloat = 1.24

    func fits() -> Bool {
      guard measureTotalHeight(rows: rows, gapRatio: gapRatio) <= maxHeight else { return false }
      return rows.allSatisfy { measureRowWidth($0) <= maxWidth }
    }

    if !fits() {
      gapRatio = 1.14
    }
    var guardSteps = 0
    while !fits() && guardSteps < 24 {
      guardSteps += 1
      if rows[0].fontSize > minFont * 1.7 {
        rows[0].fontSize *= 0.94
        continue
      }
      var shrunkBody = false
      for i in rows.indices where rows[i].kind == .body && rows[i].fontSize > minFont {
        rows[i].fontSize *= 0.94
        shrunkBody = true
      }
      if shrunkBody { continue }

      // 优先移除 time 行，再移除 recipient 行；title 与 makerMark 永不丢弃。
      if let time = engraving.timeLine,
        let idx = rows.firstIndex(where: { $0.kind == .body && $0.text == time })
      {
        rows.remove(at: idx)
        continue
      }
      if let recipient = engraving.recipientLine,
        let idx = rows.firstIndex(where: { $0.kind == .body && $0.text == recipient })
      {
        rows.remove(at: idx)
        continue
      }
      // 最后兜底等比缩放
      for i in rows.indices {
        rows[i].fontSize *= 0.92
      }
    }
    return (rows, gapRatio)
  }

  private static func measureTotalHeight(rows: [LayoutRow], gapRatio: CGFloat) -> CGFloat {
    var total: CGFloat = 0
    for (idx, row) in rows.enumerated() {
      total += row.fontSize * row.lineHeightRatio
      if idx < rows.count - 1 {
        total += row.fontSize * (gapRatio - 1.0)
      }
    }
    return total
  }

  private static func measureRowWidth(_ row: LayoutRow) -> CGFloat {
    let font = UIFont.systemFont(ofSize: row.fontSize, weight: row.weight)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .kern: row.fontSize * row.tracking,
    ]
    let textWidth = (row.text as NSString).size(withAttributes: attrs).width
    if row.kind == .mark {
      return textWidth + row.fontSize * 1.55
    }
    return textWidth
  }

  private static func drawCarvedText(
    text: String,
    centerX: CGFloat,
    centerY: CGFloat,
    fontSize: CGFloat,
    weight: UIFont.Weight,
    tracking: CGFloat,
    bevel: CGFloat,
    ink: InkPalette
  ) {
    let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
    let baseAttrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .kern: fontSize * tracking,
    ]
    let textSize = (text as NSString).size(withAttributes: baseAttrs)
    let originX = centerX - textSize.width * 0.5
    let originY = centerY - textSize.height * 0.5

    let passes: [(UIColor, CGFloat)] = [
      (ink.edge, bevel),
      (ink.shadow, 0),
      (ink.groove, bevel * 0.5),
    ]
    for (color, dy) in passes {
      var attrs = baseAttrs
      attrs[.foregroundColor] = color
      (text as NSString).draw(at: CGPoint(x: originX, y: originY + dy), withAttributes: attrs)
    }
  }

  /// 绘制底部 MoviePilot 开放六边形标志 + 品牌铭文（三遍凹雕）。
  private static func drawMakerMark(
    in cg: CGContext,
    text: String,
    centerX: CGFloat,
    centerY: CGFloat,
    fontSize: CGFloat,
    tracking: CGFloat,
    bevel: CGFloat,
    ink: InkPalette
  ) {
    let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
    let baseAttrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .kern: fontSize * tracking,
    ]
    let textSize = (text as NSString).size(withAttributes: baseAttrs)
    let iconSize = fontSize * 1.15
    let gap = fontSize * 0.40
    let totalW = iconSize + gap + textSize.width
    let startX = centerX - totalW * 0.5

    let passes: [(UIColor, CGFloat)] = [
      (ink.edge, bevel),
      (ink.shadow, 0),
      (ink.groove, bevel * 0.5),
    ]

    for (color, dy) in passes {
      drawOpenHexagonLogo(
        in: cg,
        rect: CGRect(
          x: startX, y: centerY - iconSize * 0.5 + dy, width: iconSize, height: iconSize),
        color: color
      )
      var attrs = baseAttrs
      attrs[.foregroundColor] = color
      (text as NSString).draw(
        at: CGPoint(x: startX + iconSize + gap, y: centerY - textSize.height * 0.5 + dy),
        withAttributes: attrs)
    }
  }

  private static func drawOpenHexagonLogo(in cg: CGContext, rect: CGRect, color: UIColor) {
    cg.saveGState()
    let cx = rect.midX
    let cy = rect.midY
    let r = min(rect.width, rect.height) * 0.44
    // 五段开放六边形（右上缺口）
    let angles: [CGFloat] = [30, 90, 150, 210, 270, 330].map { $0 * .pi / 180 }
    let pts = angles.map { CGPoint(x: cx + r * cos($0), y: cy + r * sin($0)) }
    cg.beginPath()
    cg.move(to: pts[0])
    for i in 1..<5 {
      cg.addLine(to: pts[i])
    }
    cg.setStrokeColor(color.cgColor)
    cg.setLineWidth(max(1.2, rect.width * 0.11))
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.strokePath()

    // 居中播放三角形
    let triR = r * 0.44
    cg.beginPath()
    cg.move(to: CGPoint(x: cx - triR * 0.55, y: cy - triR * 0.72))
    cg.addLine(to: CGPoint(x: cx + triR * 0.85, y: cy))
    cg.addLine(to: CGPoint(x: cx - triR * 0.55, y: cy + triR * 0.72))
    cg.closePath()
    cg.setFillColor(color.cgColor)
    cg.fillPath()
    cg.restoreGState()
  }
}

// MARK: - 法线 / 金属度贴图与主创外圈拆分

/// 单枚勋章 3D 渲染所需的预处理贴图与轮廓数据包。
final class CommunityMedalRenderBundle: @unchecked Sendable {
  let frontDiffuse: UIImage
  let frontNormal: UIImage?
  let frontMetalness: UIImage?
  let frontOuterDiffuse: UIImage?
  let frontOuterNormal: UIImage?
  let frontOuterMetalness: UIImage?
  let backDiffuse: UIImage
  let backNormal: UIImage?
  let backMetalness: UIImage?
  let frontOutline: CommunityMedalOutline?
  let edgeMetalColor: UIColor
  let spinConfig: CommunityMedalOutline.SpinConfig?

  init(
    frontDiffuse: UIImage,
    frontNormal: UIImage?,
    frontMetalness: UIImage?,
    frontOuterDiffuse: UIImage?,
    frontOuterNormal: UIImage?,
    frontOuterMetalness: UIImage?,
    backDiffuse: UIImage,
    backNormal: UIImage?,
    backMetalness: UIImage?,
    frontOutline: CommunityMedalOutline?,
    edgeMetalColor: UIColor,
    spinConfig: CommunityMedalOutline.SpinConfig?
  ) {
    self.frontDiffuse = frontDiffuse
    self.frontNormal = frontNormal
    self.frontMetalness = frontMetalness
    self.frontOuterDiffuse = frontOuterDiffuse
    self.frontOuterNormal = frontOuterNormal
    self.frontOuterMetalness = frontOuterMetalness
    self.backDiffuse = backDiffuse
    self.backNormal = backNormal
    self.backMetalness = backMetalness
    self.frontOutline = frontOutline
    self.edgeMetalColor = edgeMetalColor
    self.spinConfig = spinConfig
  }
}

/// 异步生成并缓存勋章法线贴图、金属度贴图、背面凹雕贴图与外圈旋转拆分贴图。
final class CommunityMedalRenderCache: @unchecked Sendable {
  static let shared = CommunityMedalRenderCache()

  private let lock = NSLock()
  private var bundles: [String: CommunityMedalRenderBundle] = [:]
  private var cachedStudioEnv: UIImage?

  func studioEnvironmentMap() -> UIImage {
    lock.lock()
    if let existing = cachedStudioEnv {
      lock.unlock()
      return existing
    }
    lock.unlock()

    let size = CGSize(width: 512, height: 256)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let cg = ctx.cgContext
      // 深影棚底色（复刻 Web #24282e 环境球）
      UIColor(red: 0.14, green: 0.16, blue: 0.19, alpha: 1).setFill()
      cg.fill(CGRect(origin: .zero, size: size))

      // 克制的影棚柔光条带，仅在拖动倾斜时呈现细腻柔和的金属光泽，不遮盖原画质感
      let strips: [(CGRect, UIColor)] = [
        (CGRect(x: 90, y: 14, width: 332, height: 42), UIColor(white: 1.0, alpha: 0.48)),
        (
          CGRect(x: 24, y: 68, width: 92, height: 118),
          UIColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 0.34)
        ),
        (
          CGRect(x: 396, y: 62, width: 92, height: 118),
          UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 0.32)
        ),
        (CGRect(x: 170, y: 82, width: 172, height: 34), UIColor(white: 0.96, alpha: 0.22)),
        (CGRect(x: 60, y: 196, width: 392, height: 28), UIColor(white: 0.55, alpha: 0.16)),
      ]
      for (rect, color) in strips {
        cg.saveGState()
        cg.setFillColor(color.cgColor)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.45)
        cg.addPath(path.cgPath)
        cg.fillPath()
        cg.restoreGState()
      }
    }

    // 柔化影棚条带以形成丝滑金属反光
    let finalEnv: UIImage
    if let ci = CIImage(image: image),
      let filter = CIFilter(name: "CIGaussianBlur")
    {
      filter.setValue(ci, forKey: kCIInputImageKey)
      filter.setValue(22.0, forKey: kCIInputRadiusKey)
      let ciContext = CIContext(options: nil)
      if let out = filter.outputImage?.cropped(to: ci.extent),
        let cgOut = ciContext.createCGImage(out, from: ci.extent)
      {
        finalEnv = UIImage(cgImage: cgOut)
      } else {
        finalEnv = image
      }
    } else {
      finalEnv = image
    }

    lock.lock()
    cachedStudioEnv = finalEnv
    lock.unlock()
    return finalEnv
  }

  func bundle(
    for record: CommunityMedalRecord,
    login: String?
  ) -> CommunityMedalRenderBundle? {
    let cacheKey =
      "\(record.key)|\(record.normalizedTier ?? 0)|\(login ?? "")|\(record.at ?? "")|\(record.specialty ?? "")"
    lock.lock()
    if let cached = bundles[cacheKey] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    let loader = CommunityMedalAssetLoader.shared
    let frontStem = CommunityMedalCatalog.frontAssetStem(for: record)
    let backStem = CommunityMedalCatalog.backAssetStem(for: record)
    guard let rawFront = loader.frontImage(for: record) else { return nil }
    let rawBack = loader.webpImage(named: backStem) ?? rawFront

    let frontOutline =
      loader.outline(named: frontStem) ?? loader.outline(named: "\(record.key)-front")
    let backOutline = loader.outline(named: backStem)

    let engraving = CommunityMedalCatalog.engraving(for: record, login: login)
    let engravedBack = CommunityMedalEngraver.engrave(
      backImage: rawBack, dial: backOutline?.dial, engraving: engraving)

    let frontHeight =
      loader.webpImage(named: "\(frontStem)-height")
      ?? loader.webpImage(named: "\(record.key)-front-height")
    let backHeight = loader.webpImage(named: "\(backStem)-height")

    let (frontNormal, frontMetal) = buildPBRMaps(from: frontHeight, strength: 2.5)
    let (backNormal, backMetal) = buildPBRMaps(from: backHeight, strength: 2.2)

    let fallbackTone = CommunityMedalColor.uiColor(hex: record.spec?.toneHex ?? "#9b7bff")
    let edgeColor = sampleEdgeMetalColor(
      frontImage: rawFront, outline: frontOutline, fallback: fallbackTone)

    var finalFrontDiffuse = rawFront
    var finalFrontNormal = frontNormal
    var finalFrontMetal = frontMetal
    var outerDiffuse: UIImage?
    var outerNormal: UIImage?
    var outerMetal: UIImage?

    if let spin = frontOutline?.spin {
      let splitDiffuse = splitRingImages(image: rawFront, spin: spin)
      finalFrontDiffuse = splitDiffuse.inner
      outerDiffuse = splitDiffuse.outer
      if let fn = frontNormal {
        let splitN = splitRingImages(image: fn, spin: spin)
        finalFrontNormal = splitN.inner
        outerNormal = splitN.outer
      }
      if let fm = frontMetal {
        let splitM = splitRingImages(image: fm, spin: spin)
        finalFrontMetal = splitM.inner
        outerMetal = splitM.outer
      }
    }

    let built = CommunityMedalRenderBundle(
      frontDiffuse: finalFrontDiffuse,
      frontNormal: finalFrontNormal,
      frontMetalness: finalFrontMetal,
      frontOuterDiffuse: outerDiffuse,
      frontOuterNormal: outerNormal,
      frontOuterMetalness: outerMetal,
      backDiffuse: engravedBack,
      backNormal: backNormal,
      backMetalness: backMetal,
      frontOutline: frontOutline,
      edgeMetalColor: edgeColor,
      spinConfig: frontOutline?.spin
    )

    lock.lock()
    if bundles.count > 8 {
      bundles.removeAll(keepingCapacity: true)
    }
    bundles[cacheKey] = built
    lock.unlock()
    return built
  }

  /// 从灰度高度图计算切线空间法线贴图与金属度贴图（区分高光金属边框与柔和珐琅内盘）。
  private func buildPBRMaps(
    from heightImage: UIImage?,
    strength: Float
  ) -> (normal: UIImage?, metalness: UIImage?) {
    guard let cg = heightImage?.cgImage else { return (nil, nil) }
    let dim = 512
    var gray = [UInt8](repeating: 0, count: dim * dim)
    guard
      let graySpace = CGColorSpace(name: CGColorSpace.linearGray),
      let ctx = CGContext(
        data: &gray,
        width: dim,
        height: dim,
        bitsPerComponent: 8,
        bytesPerRow: dim,
        space: graySpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else { return (nil, nil) }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dim, height: dim))

    var normalBytes = [UInt8](repeating: 255, count: dim * dim * 4)
    var metalBytes = [UInt8](repeating: 0, count: dim * dim)

    for y in 0..<dim {
      let y0 = max(0, y - 1)
      let y1 = min(dim - 1, y + 1)
      for x in 0..<dim {
        let x0 = max(0, x - 1)
        let x1 = min(dim - 1, x + 1)

        let hL = Float(gray[y * dim + x0]) / 255.0
        let hR = Float(gray[y * dim + x1]) / 255.0
        let hU = Float(gray[y0 * dim + x]) / 255.0
        let hD = Float(gray[y1 * dim + x]) / 255.0
        let hC = Float(gray[y * dim + x]) / 255.0

        let nx = -(hR - hL) * strength
        let ny = (hD - hU) * strength
        let nz: Float = 1.0
        let len = sqrt(nx * nx + ny * ny + nz * nz)

        let outIdx = (y * dim + x) * 4
        normalBytes[outIdx] = UInt8(max(0, min(255, ((nx / len) * 0.5 + 0.5) * 255.0)))
        normalBytes[outIdx + 1] = UInt8(max(0, min(255, ((ny / len) * 0.5 + 0.5) * 255.0)))
        normalBytes[outIdx + 2] = UInt8(max(0, min(255, ((nz / len) * 0.5 + 0.5) * 255.0)))
        normalBytes[outIdx + 3] = 255

        // 1:1 对齐 Web communityMedalRelief.ts：smoothstep(0.26, 0.45, h)，珐琅与铭牌严格为 0（零额外反光）
        let t = max(0, min(1, (hC - 0.26) / (0.45 - 0.26)))
        let smooth = t * t * (3.0 - 2.0 * t)
        metalBytes[y * dim + x] = UInt8(max(0, min(255, smooth * 255.0)))
      }
    }

    let normalImage: UIImage? = {
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let provider = CGDataProvider(data: Data(normalBytes) as CFData),
        let outCG = CGImage(
          width: dim, height: dim, bitsPerComponent: 8, bitsPerPixel: 32,
          bytesPerRow: dim * 4, space: space,
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
      else { return nil }
      return UIImage(cgImage: outCG)
    }()

    let metalImage: UIImage? = {
      guard let space = CGColorSpace(name: CGColorSpace.linearGray),
        let provider = CGDataProvider(data: Data(metalBytes) as CFData),
        let outCG = CGImage(
          width: dim, height: dim, bitsPerComponent: 8, bitsPerPixel: 8,
          bytesPerRow: dim, space: space,
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
      else { return nil }
      return UIImage(cgImage: outCG)
    }()

    return (normalImage, metalImage)
  }

  /// 采样正面向内 4% 金属唇缘颜色作为 3D 侧边厚度材质颜色。
  private func sampleEdgeMetalColor(
    frontImage: UIImage,
    outline: CommunityMedalOutline?,
    fallback: UIColor
  ) -> UIColor {
    guard let cg = frontImage.cgImage, let pts = outline?.outline, pts.count >= 8 else {
      return fallback
    }
    let w = cg.width
    let h = cg.height
    let bytesPerRow = w * 4
    var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return fallback }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    var cx: Double = 0
    var cy: Double = 0
    for p in pts where p.count >= 2 {
      cx += p[0]
      cy += p[1]
    }
    cx /= Double(pts.count)
    cy /= Double(pts.count)

    var rSum: Double = 0
    var gSum: Double = 0
    var bSum: Double = 0
    var count: Double = 0

    for p in pts where p.count >= 2 {
      for inset in [0.03, 0.05] {
        let u = p[0] + (cx - p[0]) * inset
        let v = p[1] + (cy - p[1]) * inset
        let x = min(w - 1, max(0, Int(u * Double(w))))
        let y = min(h - 1, max(0, Int(v * Double(h))))
        let offset = y * bytesPerRow + x * 4
        let a = pixels[offset + 3]
        guard a >= 220 else { continue }
        let af = Double(a) / 255.0
        rSum += min(255.0, Double(pixels[offset]) / af)
        gSum += min(255.0, Double(pixels[offset + 1]) / af)
        bSum += min(255.0, Double(pixels[offset + 2]) / af)
        count += 1
      }
    }
    guard count > 0 else { return fallback }
    return UIColor(
      red: CGFloat(rSum / count / 255.0 * 0.90),
      green: CGFloat(gSum / count / 255.0 * 0.90),
      blue: CGFloat(bSum / count / 255.0 * 0.90),
      alpha: 1
    )
  }

  /// 按 `spin` 圆环半径将主创勋章正面拆分为静止内盘与可步进旋转的外圈。
  private func splitRingImages(
    image: UIImage,
    spin: CommunityMedalOutline.SpinConfig
  ) -> (inner: UIImage, outer: UIImage) {
    guard let cg = image.cgImage else { return (image, image) }
    let w = cg.width
    let h = cg.height
    let size = CGSize(width: w, height: h)
    let center = CGPoint(x: CGFloat(spin.x) * size.width, y: CGFloat(spin.y) * size.height)
    let radius = CGFloat(spin.r) * size.width

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false

    let inner = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let cgCtx = ctx.cgContext
      cgCtx.addArc(
        center: center, radius: radius + 1.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
      cgCtx.clip()
      image.draw(in: CGRect(origin: .zero, size: size))
    }

    let outer = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let cgCtx = ctx.cgContext
      let path = UIBezierPath(rect: CGRect(origin: .zero, size: size))
      path.append(
        UIBezierPath(
          arcCenter: center, radius: max(1, radius - 1.5), startAngle: 0, endAngle: .pi * 2,
          clockwise: false))
      path.usesEvenOddFillRule = true
      cgCtx.addPath(path.cgPath)
      cgCtx.clip(using: .evenOdd)
      image.draw(in: CGRect(origin: .zero, size: size))
    }

    return (inner, outer)
  }
}

// MARK: - 原生 SceneKit 3D 动态勋章互动舞台

/// 复刻 Web `communityMedalRelief.ts` 物理手感的原生 SceneKit 3D 勋章舞台：
/// 真实金属挤出厚度边框、高度法线浮雕光照、背面凹雕铭文、主创外圈擒纵步进旋转、拖动倾斜回弹与轻点翻面。
struct NativeMedal3DStageView: UIViewRepresentable {
  let record: CommunityMedalRecord
  let login: String?
  let reducedMotion: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(reducedMotion: reducedMotion)
  }

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView(frame: .zero)
    view.backgroundColor = .clear
    view.isOpaque = false
    view.antialiasingMode = .multisampling4X
    view.autoenablesDefaultLighting = false
    view.allowsCameraControl = false
    view.preferredFramesPerSecond = 60
    view.isPlaying = true
    view.scene = context.coordinator.scene
    view.delegate = context.coordinator

    let pan = UIPanGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
    pan.maximumNumberOfTouches = 1
    let tap = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    view.addGestureRecognizer(pan)
    view.addGestureRecognizer(tap)

    context.coordinator.loadMedal(record: record, login: login)
    return view
  }

  func updateUIView(_ uiView: SCNView, context: Context) {
    context.coordinator.setReducedMotion(reducedMotion)
    context.coordinator.loadMedal(record: record, login: login)
  }

  private final class PhysicsBox: @unchecked Sendable {
    let lock = NSLock()
    let medalHolder: SCNNode
    var outerSpinNode: SCNNode?
    var spinConfig: CommunityMedalOutline.SpinConfig?
    var reducedMotion: Bool

    let yawLimit: Double = 0.65
    let pitchLimit: Double = 0.45
    var isDragging = false
    var dragYaw: Double = 0
    var dragPitch: Double = 0
    var targetFaceAngle: Double = 0
    var faceAngle: Double = 0
    var entranceElapsed: Double = 0
    let entranceDuration: Double = 1.1
    var lastUpdateTime: TimeInterval?
    var lastInputTime: TimeInterval = 0
    var idleStrength: Double = 0
    var spinElapsed: Double = 0

    init(medalHolder: SCNNode, reducedMotion: Bool) {
      self.medalHolder = medalHolder
      self.reducedMotion = reducedMotion
    }

    func resetForNewMedal() {
      lock.lock()
      defer { lock.unlock() }
      isDragging = false
      dragYaw = 0
      dragPitch = 0
      targetFaceAngle = 0
      faceAngle = 0
      entranceElapsed = reducedMotion ? entranceDuration : 0
      idleStrength = 0
      spinElapsed = 0
    }

    func setOuterSpin(node: SCNNode?, config: CommunityMedalOutline.SpinConfig?) {
      lock.lock()
      defer { lock.unlock() }
      outerSpinNode = node
      spinConfig = config
    }

    func setReducedMotion(_ value: Bool) {
      lock.lock()
      defer { lock.unlock() }
      reducedMotion = value
    }

    func updateDrag(began: Bool, dx: Double, dy: Double, ended: Bool, now: TimeInterval) {
      lock.lock()
      defer { lock.unlock() }
      if began {
        isDragging = true
        lastInputTime = now
      } else if ended {
        isDragging = false
        lastInputTime = now
      } else {
        isDragging = true
        dragYaw += dx * 0.01
        dragPitch += dy * 0.008
        lastInputTime = now
      }
    }

    func flip(now: TimeInterval) {
      lock.lock()
      defer { lock.unlock() }
      targetFaceAngle += Double.pi
      lastInputTime = now
    }

    func step(time: TimeInterval, now: TimeInterval) {
      lock.lock()
      let dt: Double
      if let last = lastUpdateTime {
        dt = min(max(time - last, 0), 0.05)
      } else {
        dt = 1.0 / 60.0
      }
      lastUpdateTime = time

      if !isDragging {
        let decay = exp(-dt * 5.0)
        dragYaw *= decay
        dragPitch *= decay
      }

      if reducedMotion {
        faceAngle = targetFaceAngle
      } else {
        faceAngle += (targetFaceAngle - faceAngle) * min(1.0, dt * 9.0)
      }

      var entranceScale: Double = 1.0
      var entranceYaw: Double = 0.0
      if !reducedMotion && entranceElapsed < entranceDuration {
        entranceElapsed = min(entranceDuration, entranceElapsed + dt)
        let t = entranceElapsed / entranceDuration
        let ease = 1.0 - pow(1.0 - t, 3.0)
        entranceScale = 0.82 + 0.18 * ease
        entranceYaw = -0.7 * (1.0 - ease)
      }

      let allowIdle = !reducedMotion && !isDragging && (now - lastInputTime > 2.5)
      if allowIdle {
        idleStrength = min(1.0, idleStrength + dt * 1.5)
      } else {
        idleStrength = max(0.0, idleStrength - dt * 3.0)
      }

      let clampedYaw = yawLimit * tanh(dragYaw / yawLimit)
      let clampedPitch = pitchLimit * tanh(dragPitch / pitchLimit)
      let idleYaw = idleStrength * sin(time * 0.45) * 0.15
      let idlePitch = idleStrength * sin(time * 0.30) * 0.06

      let totalYaw = clampedYaw + idleYaw + entranceYaw + faceAngle
      let totalPitch = clampedPitch + idlePitch

      let holder = medalHolder
      let outer = outerSpinNode
      let spin = spinConfig
      let spinDisabled = reducedMotion
      var spinAngle: Double?
      if outer != nil, let spin, !spinDisabled {
        spinElapsed += dt
        spinAngle = Self.computeSpinAngle(elapsed: spinElapsed, spin: spin)
      }
      lock.unlock()

      holder.eulerAngles = SCNVector3(Float(totalPitch), Float(totalYaw), 0)
      let s = Float(entranceScale)
      holder.scale = SCNVector3(s, s, s)
      if let outer, let spinAngle {
        outer.eulerAngles.z = Float(-spinAngle)
      }
    }

    private static func computeSpinAngle(elapsed: Double, spin: CommunityMedalOutline.SpinConfig)
      -> Double
    {
      if spin.mode == "continuous" {
        let period = max(spin.period ?? 180.0, 1.0)
        return (elapsed / period) * Double.pi * 2.0
      }
      let stepDeg = spin.step ?? 6.0
      let interval = max(spin.interval ?? 2.0, 0.4)
      let tickDuration = 0.35
      let overshoot = 0.4 / max(stepDeg, 1.0)
      let stepIndex = floor(elapsed / interval)
      let local = elapsed - stepIndex * interval
      let progress: Double
      if local >= tickDuration {
        progress = 1.0
      } else {
        let u = local / tickDuration
        if u < 0.7 {
          let p = u / 0.7
          let quad = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
          progress = quad * (1.0 + overshoot)
        } else {
          let p = (u - 0.7) / 0.3
          let quadOut = 1 - pow(1 - p, 2)
          progress = (1.0 + overshoot) - overshoot * quadOut
        }
      }
      return (stepIndex + progress) * stepDeg * Double.pi / 180.0
    }
  }

  @MainActor
  final class Coordinator: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    private let medalHolder = SCNNode()
    private let contentRoot = SCNNode()
    private var accentLightNode = SCNNode()
    private let physics: PhysicsBox

    private var currentToken = ""
    private var loadTask: Task<Void, Never>?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init(reducedMotion: Bool) {
      self.physics = PhysicsBox(medalHolder: medalHolder, reducedMotion: reducedMotion)
      super.init()
      setupScene()
    }

    func setReducedMotion(_ value: Bool) {
      physics.setReducedMotion(value)
    }

    private func setupScene() {
      scene.background.contents = UIColor.clear
      scene.lightingEnvironment.contents = CommunityMedalRenderCache.shared.studioEnvironmentMap()
      scene.lightingEnvironment.intensity = 0.36

      let cameraNode = SCNNode()
      let camera = SCNCamera()
      camera.fieldOfView = 28
      camera.zNear = 0.5
      camera.zFar = 30
      cameraNode.camera = camera
      cameraNode.position = SCNVector3(0, 0, 5.65)
      scene.rootNode.addChildNode(cameraNode)

      // 影棚主定向光（仅作用于 3D 金属侧壁；正反面采用对标 Web 的 .constant + 克制柔光着色器）
      let keyLight = SCNNode()
      keyLight.light = SCNLight()
      keyLight.light?.type = .directional
      keyLight.light?.intensity = 260
      keyLight.light?.color = UIColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 1)
      keyLight.position = SCNVector3(-3, 4, 5)
      keyLight.look(at: SCNVector3Zero)
      scene.rootNode.addChildNode(keyLight)

      // 右侧柔和轮廓补光（侧壁边缘）
      let rimLight = SCNNode()
      rimLight.light = SCNLight()
      rimLight.light?.type = .directional
      rimLight.light?.intensity = 100
      rimLight.light?.color = UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1)
      rimLight.position = SCNVector3(4, 1.5, 3)
      rimLight.look(at: SCNVector3Zero)
      scene.rootNode.addChildNode(rimLight)

      // 勋章主色微氛围补光（仅轻染金属侧壁）
      accentLightNode.light = SCNLight()
      accentLightNode.light?.type = .omni
      accentLightNode.light?.intensity = 32
      accentLightNode.position = SCNVector3(0, -2.5, 3.5)
      scene.rootNode.addChildNode(accentLightNode)

      // 柔和基础环境光
      let ambient = SCNNode()
      ambient.light = SCNLight()
      ambient.light?.type = .ambient
      ambient.light?.intensity = 90
      ambient.light?.color = UIColor(white: 0.92, alpha: 1)
      scene.rootNode.addChildNode(ambient)

      medalHolder.addChildNode(contentRoot)
      scene.rootNode.addChildNode(medalHolder)
    }

    func loadMedal(record: CommunityMedalRecord, login: String?) {
      let token = "\(record.key)|\(record.normalizedTier ?? 0)|\(login ?? "")|\(record.at ?? "")"
      guard token != currentToken else { return }
      currentToken = token
      loadTask?.cancel()

      // 切换勋章时重置为正面并播放丝滑入场动画
      physics.resetForNewMedal()

      let toneColor = CommunityMedalColor.uiColor(hex: record.spec?.toneHex ?? "#9b7bff")
      accentLightNode.light?.color = toneColor

      loadTask = Task.detached(priority: .userInitiated) { [weak self] in
        guard let bundle = CommunityMedalRenderCache.shared.bundle(for: record, login: login) else {
          return
        }
        guard !Task.isCancelled else { return }
        await MainActor.run {
          self?.applyBundle(bundle)
        }
      }
    }

    private func applyBundle(_ bundle: CommunityMedalRenderBundle) {
      for child in contentRoot.childNodes {
        child.removeFromParentNode()
      }
      physics.setOuterSpin(node: nil, config: bundle.spinConfig)

      let width: CGFloat = 2.4
      let thickness: CGFloat = 0.11

      // 1. 真实 3D 金属挤出侧边厚度
      if let outline = bundle.frontOutline,
        let rimPath = makeRimBezierPath(outline: outline, width: width)
      {
        let shape = SCNShape(path: rimPath, extrusionDepth: thickness - 0.008)
        shape.chamferRadius = 0.012
        shape.chamferMode = .both
        let sideMat = SCNMaterial()
        sideMat.lightingModel = .physicallyBased
        sideMat.diffuse.contents = bundle.edgeMetalColor
        sideMat.metalness.contents = NSNumber(value: 0.90)
        sideMat.roughness.contents = NSNumber(value: 0.48)
        shape.materials = [sideMat]
        let rimNode = SCNNode(geometry: shape)
        contentRoot.addChildNode(rimNode)
      }

      // 2. 正面浮雕主平面（对标 Web CapShader：零场景灯过曝，仅在倾斜时于金属棱线呈现极淡柔光）
      let frontPlane = SCNPlane(width: width, height: width)
      frontPlane.materials = [
        makeReliefMaterial(
          diffuse: bundle.frontDiffuse,
          normal: bundle.frontNormal,
          metalness: bundle.frontMetalness,
          accentColor: bundle.edgeMetalColor
        )
      ]
      let frontNode = SCNNode(geometry: frontPlane)
      frontNode.position = SCNVector3(0, 0, Float(thickness * 0.5))
      contentRoot.addChildNode(frontNode)

      // 3. 主创勋章外圈机械步进旋转环
      if let outerDiffuse = bundle.frontOuterDiffuse, let spin = bundle.spinConfig {
        let pivotX = CGFloat(spin.x - 0.5) * width
        let pivotY = CGFloat(0.5 - spin.y) * width
        let ringPivot = SCNNode()
        ringPivot.position = SCNVector3(
          Float(pivotX), Float(pivotY), Float(thickness * 0.5 + 0.002))

        let outerPlane = SCNPlane(width: width, height: width)
        outerPlane.materials = [
          makeReliefMaterial(
            diffuse: outerDiffuse,
            normal: bundle.frontOuterNormal,
            metalness: bundle.frontOuterMetalness,
            accentColor: bundle.edgeMetalColor
          )
        ]
        let outerNode = SCNNode(geometry: outerPlane)
        outerNode.position = SCNVector3(Float(-pivotX), Float(-pivotY), 0)
        ringPivot.addChildNode(outerNode)
        contentRoot.addChildNode(ringPivot)
        physics.setOuterSpin(node: ringPivot, config: spin)
      }

      // 4. 背面凹雕铭文平面（绕 Y 轴旋转 π）
      let backPlane = SCNPlane(width: width, height: width)
      backPlane.materials = [
        makeReliefMaterial(
          diffuse: bundle.backDiffuse,
          normal: bundle.backNormal,
          metalness: bundle.backMetalness,
          accentColor: bundle.edgeMetalColor
        )
      ]
      let backNode = SCNNode(geometry: backPlane)
      backNode.position = SCNVector3(0, 0, Float(-thickness * 0.5))
      backNode.eulerAngles = SCNVector3(0, Float.pi, 0)
      contentRoot.addChildNode(backNode)
    }

    private static let zeroMetalImage: UIImage = {
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { ctx in
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      }
    }()

    private static let capSurfaceShader = """
      #pragma arguments
      texture2d<float> uMetalMap;
      float3 uAccent;

      #pragma body
      constexpr sampler mpMedalSampler(filter::linear, address::clamp_to_edge);
      float metal = uMetalMap.sample(mpMedalSampler, _surface.diffuseTexcoord).r;
      float3 n = normalize(_surface.normal);
      float3 v = normalize(_surface.view);
      float3 r = reflect(-v, n);

      // 1:1 对齐 Web communityMedalRelief.ts CapShader：以原画自带金工光影为主，
      // 珐琅与铭牌（metal == 0）零反光，正对时几乎无光照叠加，仅在倾斜时于金属棱线浮现极淡柔光。
      float3 light = float3(0.0);
      light += float3(1.0) * smoothstep(0.2, 0.95, r.y) * 0.8;
      float rxL = (r.x + 0.6) / 0.35;
      float rxR = (r.x - 0.6) / 0.30;
      float rzMask = smoothstep(-0.6, 0.3, r.z);
      light += uAccent * exp(-(rxL * rxL)) * rzMask * 0.6;
      light += float3(1.0) * exp(-(rxR * rxR)) * rzMask * 0.45;

      float3 base = _surface.diffuse.rgb;
      float ndv = max(dot(n, v), 0.0);
      float fresnel = 0.2 + 0.8 * pow(1.0 - ndv, 3.0);
      float3 tint = mix(float3(1.0), base * 1.6, 0.7);
      float3 sheen = light * tint * fresnel;
      float shade = 0.93 + 0.12 * dot(n, normalize(float3(-0.4, 0.6, 0.7)));
      _surface.diffuse.rgb = base * mix(1.0, shade, metal * 0.5) + sheen * metal * 0.14;
      """

    private static let capFragmentShader = """
      float alpha = smoothstep(0.45, 0.85, _output.color.a);
      if (alpha <= 0.0) { discard_fragment(); }
      _output.color.a = alpha;
      """

    private func makeReliefMaterial(
      diffuse: UIImage,
      normal: UIImage?,
      metalness: UIImage?,
      accentColor: UIColor
    ) -> SCNMaterial {
      let mat = SCNMaterial()
      // 采用 .constant 彻底隔离外部场景灯与 IBL 过曝反光，完整还原原画写实金工与珐琅深邃质感
      mat.lightingModel = .constant
      mat.diffuse.contents = diffuse
      mat.diffuse.mipFilter = .linear
      mat.diffuse.minificationFilter = .linear
      mat.diffuse.magnificationFilter = .linear
      mat.diffuse.maxAnisotropy = 4
      if let normal {
        mat.normal.contents = normal
        mat.normal.intensity = 1.0
      }
      mat.isDoubleSided = false
      mat.writesToDepthBuffer = true
      mat.readsFromDepthBuffer = true

      var r: CGFloat = 0.8
      var g: CGFloat = 0.78
      var b: CGFloat = 0.72
      var a: CGFloat = 1.0
      accentColor.getRed(&r, green: &g, blue: &b, alpha: &a)
      // 转线性空间与 Metal shader 内线性漫反射一致
      let accentVec = SCNVector3(
        Float(pow(max(0, r), 2.2)),
        Float(pow(max(0, g), 2.2)),
        Float(pow(max(0, b), 2.2))
      )
      mat.setValue(SCNMaterialProperty(contents: metalness ?? Self.zeroMetalImage), forKey: "uMetalMap")
      mat.setValue(NSValue(scnVector3: accentVec), forKey: "uAccent")
      mat.shaderModifiers = [
        .surface: Self.capSurfaceShader,
        .fragment: Self.capFragmentShader,
      ]
      return mat
    }

    private func makeRimBezierPath(outline: CommunityMedalOutline, width: CGFloat) -> UIBezierPath?
    {
      let pts = outline.outline.filter { $0.count >= 2 }
      guard pts.count >= 3 else { return nil }
      var cx: CGFloat = 0
      var cy: CGFloat = 0
      let mapped: [CGPoint] = pts.map { p in
        let x = CGFloat(p[0] - 0.5) * width
        let y = CGFloat(0.5 - p[1]) * width
        cx += x
        cy += y
        return CGPoint(x: x, y: y)
      }
      cx /= CGFloat(mapped.count)
      cy /= CGFloat(mapped.count)

      // 轻微内缩 1.4%，令金属侧边紧贴正反两面轮廓而不露毛边
      let insetRatio: CGFloat = 0.986
      let path = UIBezierPath()
      for (idx, pt) in mapped.enumerated() {
        let p = CGPoint(x: cx + (pt.x - cx) * insetRatio, y: cy + (pt.y - cy) * insetRatio)
        if idx == 0 {
          path.move(to: p)
        } else {
          path.addLine(to: p)
        }
      }
      path.close()
      return path
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
      let translation = gesture.translation(in: gesture.view)
      gesture.setTranslation(.zero, in: gesture.view)
      let now = CACurrentMediaTime()

      switch gesture.state {
      case .began:
        physics.updateDrag(began: true, dx: 0, dy: 0, ended: false, now: now)
      case .changed:
        physics.updateDrag(
          began: false, dx: Double(translation.x), dy: Double(translation.y), ended: false, now: now
        )
      default:
        physics.updateDrag(began: false, dx: 0, dy: 0, ended: true, now: now)
      }
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard gesture.state == .ended else { return }
      physics.flip(now: CACurrentMediaTime())
      haptic.impactOccurred()
    }

    nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
      physics.step(time: time, now: CACurrentMediaTime())
    }
  }
}

// MARK: - 1080×1350 荣誉分享海报生成（复刻 Web communityMedalShare.ts）

/// 按 Web 端精确规格生成 1080×1350 社区勋章荣誉分享图。
enum CommunityMedalShareRenderer {
  static func renderPoster(
    record: CommunityMedalRecord,
    login: String?
  ) -> UIImage? {
    guard let frontImage = CommunityMedalAssetLoader.shared.frontImage(for: record) else {
      return nil
    }
    let size = CGSize(width: 1080, height: 1350)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let toneColor = CommunityMedalColor.uiColor(hex: record.spec?.toneHex ?? "#9b7bff")

    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let cg = ctx.cgContext
      // 深色纪念底幕 #0b0c0e
      UIColor(red: 11 / 255, green: 12 / 255, blue: 14 / 255, alpha: 1).setFill()
      cg.fill(CGRect(origin: .zero, size: size))

      // 勋章主色柔和径向光晕 (540, 560, r=620)
      let colors =
        [toneColor.withAlphaComponent(0.22).cgColor, toneColor.withAlphaComponent(0).cgColor]
        as CFArray
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
      {
        let center = CGPoint(x: 540, y: 560)
        cg.drawRadialGradient(
          gradient, startCenter: center, startRadius: 20, endCenter: center, endRadius: 620,
          options: [.drawsAfterEndLocation])
      }

      // 居中 900×900 正面勋章
      frontImage.draw(in: CGRect(x: 90, y: 110, width: 900, height: 900))

      // 标题 60pt Semibold #f2f3f5
      let title = record.spec?.name ?? record.key
      let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 60, weight: .semibold),
        .foregroundColor: UIColor(red: 242 / 255, green: 243 / 255, blue: 245 / 255, alpha: 1),
      ]
      let titleSize = (title as NSString).size(withAttributes: titleAttrs)
      (title as NSString).draw(
        at: CGPoint(x: (size.width - titleSize.width) * 0.5, y: 1052),
        withAttributes: titleAttrs)

      // 荣誉摘要行 #9a9fa6
      var metaParts: [String] = []
      if let tierLine = CommunityMedalCatalog.tierLine(for: record) {
        metaParts.append(tierLine)
      }
      if let login, !login.isEmpty {
        metaParts.append("授予 @\(login)")
      }
      if let timeLine = CommunityMedalCatalog.timeLine(for: record) {
        metaParts.append(timeLine)
      }
      let meta = metaParts.joined(separator: " · ")
      if !meta.isEmpty {
        let metaAttrs: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: 30, weight: .regular),
          .foregroundColor: UIColor(red: 154 / 255, green: 159 / 255, blue: 166 / 255, alpha: 1),
        ]
        let metaSize = (meta as NSString).size(withAttributes: metaAttrs)
        (meta as NSString).draw(
          at: CGPoint(x: (size.width - metaSize.width) * 0.5, y: 1144),
          withAttributes: metaAttrs)
      }

      // 页脚 MoviePilot #5f646b
      let footer = "MoviePilot"
      let footerAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
        .kern: 3.0,
        .foregroundColor: UIColor(red: 95 / 255, green: 100 / 255, blue: 107 / 255, alpha: 1),
      ]
      let footerSize = (footer as NSString).size(withAttributes: footerAttrs)
      (footer as NSString).draw(
        at: CGPoint(x: (size.width - footerSize.width) * 0.5, y: 1244),
        withAttributes: footerAttrs)
    }
  }
}
