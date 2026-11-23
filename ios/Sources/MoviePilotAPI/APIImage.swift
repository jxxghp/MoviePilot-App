import Foundation

/// 由 MoviePilot 同源图片代理返回的受限图片数据，不保存源 URL 或缓存状态。
public struct APIImage: Equatable, Sendable {
  /// 单张媒体图片的最大响应大小，避免大图占用不受控内存。
  public static let maximumBytes = 8 * 1024 * 1024

  /// 已经通过长度限制的原始图片字节，可交由系统图片解码器处理。
  public let data: Data
  /// 服务端声明且经过 JPEG、PNG、WebP 白名单验证的 MIME 类型。
  public let mimeType: String

  /// 构造时重复执行传输约束，避免其它调用方伪造未校验的图片结果。
  public init(data: Data, mimeType: String) throws {
    guard !data.isEmpty, data.count <= Self.maximumBytes,
      ["image/jpeg", "image/png", "image/webp"].contains(mimeType.lowercased())
    else { throw APIError.invalidResponse }
    self.data = data
    self.mimeType = mimeType.lowercased()
  }
}
