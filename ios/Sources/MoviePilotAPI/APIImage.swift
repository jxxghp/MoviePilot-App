import Foundation

/// 由 MoviePilot 同源图片代理返回的受限图片数据，不保存源 URL 或缓存状态。
public struct APIImage: Equatable, Sendable {
  /// 单张媒体图片的最大响应大小，避免大图占用不受控内存。
  public static let maximumBytes = 8 * 1024 * 1024

  /// 校验 MIME 类型是否属于允许解码的位图/动图格式（放行 image/avif、image/webp、image/jpeg、image/png、image/gif、image/heic 等，严格拒绝可执行脚本载体 image/svg+xml）。
  public static func isSupportedMIMEType(_ rawMIMEType: String) -> Bool {
    let base = rawMIMEType
      .split(separator: ";", maxSplits: 1)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    guard base.hasPrefix("image/") else { return false }
    return base != "image/svg+xml" && base != "image/svg"
  }

  /// 规范化 MIME 类型（去除分号后的参数并转为小写）。
  public static func normalizedMIMEType(_ rawMIMEType: String) -> String {
    rawMIMEType
      .split(separator: ";", maxSplits: 1)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
  }

  /// 已经通过长度限制的原始图片字节，可交由系统图片解码器处理。
  public let data: Data
  /// 服务端声明且经过安全图片类型验证的 MIME 类型。
  public let mimeType: String

  /// 构造时重复执行传输约束，避免其它调用方伪造未校验的图片结果。
  public init(data: Data, mimeType: String) throws {
    let normalized = Self.normalizedMIMEType(mimeType)
    guard !data.isEmpty, data.count <= Self.maximumBytes,
      Self.isSupportedMIMEType(normalized)
    else { throw APIError.invalidResponse }
    self.data = data
    self.mimeType = normalized
  }
}
