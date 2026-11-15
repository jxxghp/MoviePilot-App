import Foundation
import Testing

@testable import MoviePilotCore

/// 语言缓存使用独立偏好域；只验证共享设置边界，不读取真实服务、账号或系统语言。
struct AppLanguageTests {
  /// 地区和脚本映射与前端一致，未支持语言继续尝试后续偏好。
  @Test func resolvesSystemLanguages() {
    for value in ["zh-TW", "zh_HK", "zh-MO", "zh-Hant-US"] {
      #expect(AppLanguage.preferred(in: [value]) == .traditionalChinese)
    }
    #expect(AppLanguage.preferred(in: ["zh-Hans-HK"]) == .simplifiedChinese)
    #expect(AppLanguage.preferred(in: ["fr-FR", "en-GB"]) == .english)
    #expect(AppLanguage.preferred(in: ["fr-FR", "zh-Hant"]) == .traditionalChinese)
    #expect(AppLanguage.preferred(in: ["de-DE"]) == .simplifiedChinese)
  }

  /// 连接页选择只绑定下一实例，旧缓存和迟到网页不能覆盖尚未确认的新选择。
  @Test func sharesPreferencesWithoutCrossingInstances() throws {
    let suite = "moviepilot-language-tests-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = LanguagePreferences(defaults: defaults)
    let first = UUID()
    let second = UUID()
    #expect(store.receive(.traditionalChinese, for: first))
    #expect(store.receive(.english, for: second))
    store.activate(first)
    #expect(defaults.string(forKey: AppLanguage.preferenceKey) == "zh-TW")
    #expect(store.pending(for: first) == nil)
    store.select(.english)
    store.activate(first)
    #expect(store.pending(for: first) == .english)
    #expect(!store.receive(.traditionalChinese, for: first))
    #expect(store.pending(for: first) == .english)
    #expect(store.receive(.english, for: first))
    #expect(store.pending(for: first) == nil)
    store.select(.simplifiedChinese, instanceID: first)
    // 重建存储相当于网络失败后重启；尚未同步的选择仍然存在。
    let restored = LanguagePreferences(defaults: defaults)
    restored.activate(second)
    #expect(defaults.string(forKey: AppLanguage.preferenceKey) == "en-US")
    #expect(restored.pending(for: first) == .simplifiedChinese)
    restored.forget(first)
    #expect(restored.cached(for: first) == nil)
    #expect(restored.pending(for: first) == nil)
    #expect(restored.cached(for: second) == .english)
  }

  /// 所有资源键和参数保持相同，防止发布时缺翻译或格式化参数错位。
  @Test func translationsAreCompleteAndKeepPlaceholders() throws {
    var tables: [[String: String]] = []
    for language in AppLanguage.allCases {
      let bundle = try #require(L10n.bundle(for: language))
      let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
      let table = try #require(
        PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
          as? [String: String])
      tables.append(table)
      #expect(L10n.text("语言", language: language) == table["语言"])
      #expect(L10n.text("not-a-translation-key", language: language) == "not-a-translation-key")
    }
    let reference = try #require(tables.first)
    #expect(reference.count > 250)
    for table in tables {
      #expect(Set(table.keys) == Set(reference.keys))
      for (key, value) in table {
        #expect(!value.isEmpty)
        #expect(placeholders(key) == placeholders(value), "\(key)")
      }
    }
    #expect(L10n.text("连接与显示", language: .english) == "Connection & Display")
    #expect(L10n.text("连接服务", language: .traditionalChinese) == "連接服務")
    #expect(L10n.text("主导航", language: .english) == "Main navigation")
  }

  /// 仅比较实际格式参数，普通百分号和标点不影响翻译完整性。
  private func placeholders(_ value: String) -> [String] {
    value.matches(of: /%[@d]/).map { String($0.output) }.sorted()
  }
}
