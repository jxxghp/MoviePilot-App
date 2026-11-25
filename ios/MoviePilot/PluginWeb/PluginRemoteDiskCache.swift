import Foundation
import MoviePilotCore

/// Vue 联邦插件远程产物磁盘缓存（按实例源 SHA-256 / 插件 ID / 版本或产物哈希三级隔离，上限 50MB LRU）。
actor PluginRemoteDiskCache {
  static let shared = PluginRemoteDiskCache()

  private let maxBytes: Int64 = 50 * 1024 * 1024
  private let rootURL: URL

  private struct Meta: Codable {
    let contentType: String
  }

  init(rootURL: URL? = nil) {
    if let rootURL {
      self.rootURL = rootURL
    } else {
      let base =
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      self.rootURL = base.appendingPathComponent("plugin-remote-cache", isDirectory: true)
    }
  }

  /// 读取已缓存的插件远程资源，命中时刷新修改时间用于 LRU 淘汰。
  func read(
    instanceOrigin: String,
    pluginId: String,
    versionTag: String,
    assetRelPath: String
  ) -> (data: Data, contentType: String)? {
    guard
      let fileURL = resolvedFileURL(
        instanceOrigin: instanceOrigin,
        pluginId: pluginId,
        versionTag: versionTag,
        assetRelPath: assetRelPath
      )
    else { return nil }
    let fm = FileManager.default
    guard fm.fileExists(atPath: fileURL.path), let data = try? Data(contentsOf: fileURL) else {
      return nil
    }
    try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    let metaURL = metaFileURL(for: fileURL)
    let contentType: String
    if let metaData = try? Data(contentsOf: metaURL),
      let meta = try? JSONDecoder().decode(Meta.self, from: metaData),
      !meta.contentType.isEmpty
    {
      contentType = meta.contentType
    } else {
      contentType = PluginRemoteRuntime.mimeType(forPath: assetRelPath)
    }
    return (data, contentType)
  }

  /// 原子写入远程插件资产并自动清理同插件旧版本及超限 LRU 文件。
  func write(
    data: Data,
    contentType: String,
    instanceOrigin: String,
    pluginId: String,
    versionTag: String,
    assetRelPath: String
  ) {
    guard
      let fileURL = resolvedFileURL(
        instanceOrigin: instanceOrigin,
        pluginId: pluginId,
        versionTag: versionTag,
        assetRelPath: assetRelPath
      )
    else { return }
    let fm = FileManager.default
    do {
      try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: fileURL, options: [.atomic])
      let meta = Meta(contentType: contentType)
      if let encoded = try? JSONEncoder().encode(meta) {
        try encoded.write(to: metaFileURL(for: fileURL), options: [.atomic])
      }
      pruneOlderVersions(
        instanceOrigin: instanceOrigin,
        pluginId: pluginId,
        keepingVersion: versionTag
      )
      enforceBudgetIfNeeded()
    } catch {
      // 磁盘写入失败不影响当次内存响应
    }
  }

  /// 计算当前插件远程缓存占用字节数。
  func diskUsageBytes() -> Int64 {
    let fm = FileManager.default
    guard
      let enumerator = fm.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else { return 0 }
    var total: Int64 = 0
    for case let url as URL in enumerator {
      if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
        values.isRegularFile == true,
        let size = values.fileSize
      {
        total += Int64(size)
      }
    }
    return total
  }

  /// 清空指定实例的插件远程缓存。
  func clear(instanceOrigin: String) {
    let key = PluginRemoteRuntime.buildCacheKey(
      instanceOrigin: instanceOrigin, pluginId: "x", versionOrHash: "x")
    let dir = rootURL.appendingPathComponent(key.instanceHash, isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
  }

  /// 清空所有实例的插件远程缓存。
  func clearAll() {
    try? FileManager.default.removeItem(at: rootURL)
  }

  private func resolvedFileURL(
    instanceOrigin: String,
    pluginId: String,
    versionTag: String,
    assetRelPath: String
  ) -> URL? {
    let key = PluginRemoteRuntime.buildCacheKey(
      instanceOrigin: instanceOrigin,
      pluginId: pluginId,
      versionOrHash: versionTag
    )
    let baseDir = rootURL.appendingPathComponent(key.relativeDir, isDirectory: true).standardizedFileURL
    let candidate = baseDir.appendingPathComponent(assetRelPath, isDirectory: false).standardizedFileURL
    guard candidate.path.hasPrefix(baseDir.path + "/") else { return nil }
    return candidate
  }

  private func metaFileURL(for fileURL: URL) -> URL {
    fileURL.appendingPathExtension("meta.json")
  }

  private func pruneOlderVersions(
    instanceOrigin: String,
    pluginId: String,
    keepingVersion: String
  ) {
    let key = PluginRemoteRuntime.buildCacheKey(
      instanceOrigin: instanceOrigin,
      pluginId: pluginId,
      versionOrHash: keepingVersion
    )
    let pluginDir =
      rootURL
      .appendingPathComponent(key.instanceHash, isDirectory: true)
      .appendingPathComponent(key.pluginIdLower, isDirectory: true)
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(at: pluginDir, includingPropertiesForKeys: nil)
    else { return }
    for entry in entries where entry.lastPathComponent != key.versionSegment {
      try? fm.removeItem(at: entry)
    }
  }

  private func enforceBudgetIfNeeded() {
    let fm = FileManager.default
    guard
      let enumerator = fm.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else { return }
    var files: [(url: URL, size: Int64, modified: Date)] = []
    var total: Int64 = 0
    for case let url as URL in enumerator {
      guard !url.lastPathComponent.hasSuffix(".meta.json") else { continue }
      guard
        let values = try? url.resourceValues(
          forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
        values.isRegularFile == true,
        let size = values.fileSize
      else { continue }
      let s = Int64(size)
      total += s
      files.append((url, s, values.contentModificationDate ?? .distantPast))
    }
    guard total > maxBytes else { return }
    files.sort { $0.modified < $1.modified }
    let target = (maxBytes * 4) / 5
    for item in files {
      if total <= target { break }
      try? fm.removeItem(at: item.url)
      try? fm.removeItem(at: metaFileURL(for: item.url))
      total -= item.size
    }
  }
}
