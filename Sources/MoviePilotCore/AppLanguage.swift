import Foundation

/// 与前端 MP_LOCALE 共用稳定标识，系统地区和文字脚本仅参与首次语言选择。
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
  case simplifiedChinese = "zh-CN"
  case traditionalChinese = "zh-TW"
  case english = "en-US"

  public static let preferenceKey = "moviepilot.language.v1"

  /// 原生尚无选择时沿用与前端相同的语言族回退，不把香港中文误判为简体。
  public static func preferred(in languages: [String]) -> Self {
    for value in languages {
      let parts = value.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
      if parts.first == "en" { return .english }
      guard parts.first == "zh" else { continue }
      if parts.contains("hant") { return .traditionalChinese }
      if parts.contains("hans") { return .simplifiedChinese }
      return parts.contains(where: { ["tw", "hk", "mo"].contains($0) })
        ? .traditionalChinese : .simplifiedChinese
    }
    return .simplifiedChinese
  }

  /// 当前原生文案只读取非敏感偏好；测试可直接向翻译函数传入语言而无需修改全局。
  public static var current: Self {
    UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:))
      ?? shared.flatMap(Self.init(rawValue:))
      ?? preferred(in: Locale.preferredLanguages)
  }

  /// 扩展只读取签名声明的共享语言，不探测主 App 沙箱或默认账户数据。
  private static var shared: String? {
    guard let group = WidgetSharedStorage.groupIdentifier,
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
    else { return nil }
    return UserDefaults(suiteName: group)?.string(forKey: preferenceKey)
  }

  /// 选项始终使用语言自身名称，便于误选后找回。
  public var title: String {
    switch self {
    case .simplifiedChinese: "简体中文"
    case .traditionalChinese: "繁體中文"
    case .english: "English"
    }
  }

  /// Apple 资源目录采用脚本标识，协议与持久化仍使用前端地区标识。
  public var resourceName: String {
    switch self {
    case .simplifiedChinese: "zh-Hans"
    case .traditionalChinese: "zh-Hant"
    case .english: "en"
    }
  }
}

/// 固定原生文案的共享资源入口，业务及服务器返回文字仍由原有来源负责翻译。
public enum L10n {
  /// 明确指定资源语言，运行时切换无需修改系统 AppleLanguages 或重新启动 App。
  public static func text(_ key: String, language: AppLanguage = .current) -> String {
    guard let bundle = bundle(for: language) else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
  }

  /// 使用同一目录读取翻译和校验资源，避免依赖宿主的系统语言。
  static func bundle(for language: AppLanguage) -> Bundle? {
    guard
      let url = Bundle.module.resourceURL?.appendingPathComponent(
        "\(language.resourceName).lproj", isDirectory: true),
      FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return Bundle(url: url)
  }

  /// 变量通过占位符传入，允许英语和中文调整语序，不把用户内容当翻译键。
  public static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(
      format: text(key), locale: Locale(identifier: AppLanguage.current.rawValue),
      arguments: arguments)
  }
}

/// 实例缓存只负责首帧；网页 MP_LOCALE 是连接后的来源，显式选择在确认保存前保留。
public struct LanguagePreferences {
  private let defaults: UserDefaults
  private let nextKey = "moviepilot.language.next.v1"

  /// 测试使用独立 suite，不访问真实实例或设备偏好。
  public init(defaults: UserDefaults) { self.defaults = defaults }

  /// 连接页选择只应用于下一次连接，已连接时只覆盖当前实例。
  public func select(_ language: AppLanguage, instanceID: UUID? = nil) {
    saveGlobal(language)
    defaults.set(language.rawValue, forKey: instanceID.map(pendingKey) ?? nextKey)
  }

  /// 进入实例时先绑定明确选择；否则恢复该实例最近由网页确认的语言。
  public func activate(_ instanceID: UUID) {
    if let next = defaults.string(forKey: nextKey), let language = AppLanguage(rawValue: next) {
      select(language, instanceID: instanceID)
      defaults.removeObject(forKey: nextKey)
    } else if let language = pending(for: instanceID) ?? cached(for: instanceID) {
      saveGlobal(language)
    }
  }

  /// 仅显式未同步选择允许覆盖网页存储；普通缓存绝不覆盖既有 MP_LOCALE。
  public func pending(for instanceID: UUID) -> AppLanguage? {
    defaults.string(forKey: pendingKey(instanceID)).flatMap(AppLanguage.init(rawValue:))
  }

  /// 缓存按实例 UUID 分隔，不把账号、地址或认证信息加入键名。
  public func cached(for instanceID: UUID) -> AppLanguage? {
    defaults.string(forKey: cacheKey(instanceID)).flatMap(AppLanguage.init(rawValue:))
  }

  /// 当前可信主文档确认保存后才能清理对应待同步选择；迟到旧值不能覆盖新选择。
  @discardableResult
  public func receive(_ language: AppLanguage, for instanceID: UUID) -> Bool {
    if let pending = pending(for: instanceID), pending != language { return false }
    defaults.set(language.rawValue, forKey: cacheKey(instanceID))
    saveGlobal(language)
    defaults.removeObject(forKey: pendingKey(instanceID))
    return true
  }

  /// 删除实例时一并删除缓存与未同步选择。
  public func forget(_ instanceID: UUID) {
    defaults.removeObject(forKey: cacheKey(instanceID))
    defaults.removeObject(forKey: pendingKey(instanceID))
  }

  /// 独立版本键允许后续迁移偏好而不影响 WebKit 的 MP_LOCALE。
  private func cacheKey(_ id: UUID) -> String { "moviepilot.language.\(id.uuidString).v1" }

  /// 同步至签名实际声明的 App Group；本机测试及未授权环境只保留标准偏好。
  private func saveGlobal(_ language: AppLanguage) {
    defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
    guard defaults === UserDefaults.standard, let group = WidgetSharedStorage.groupIdentifier,
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
    else { return }
    UserDefaults(suiteName: group)?.set(language.rawValue, forKey: AppLanguage.preferenceKey)
  }

  /// 待同步值与首帧缓存分开，页面失败或进程重启后仍可完成用户选择。
  private func pendingKey(_ id: UUID) -> String {
    "moviepilot.language.pending.\(id.uuidString).v1"
  }
}
