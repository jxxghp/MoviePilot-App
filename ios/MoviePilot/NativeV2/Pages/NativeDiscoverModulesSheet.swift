import Foundation
import MoviePilotAPI
import SwiftUI

/// 发现页可编排模块的受控标识：兼容内置 10 大发现区块与插件通过 `RecommendSource` 动态注册的推荐榜单模块。
struct NativeDiscoverModuleID: RawRepresentable, Hashable, Codable, Identifiable, Sendable {
  static let pluginPrefix = "plugin_recommend:"

  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  static let continueWatching = NativeDiscoverModuleID(rawValue: "continueWatching")
  static let movies = NativeDiscoverModuleID(rawValue: "movies")
  static let television = NativeDiscoverModuleID(rawValue: "television")
  static let trending = NativeDiscoverModuleID(rawValue: "trending")
  static let doubanMusic = NativeDiscoverModuleID(rawValue: "doubanMusic")
  static let doubanShowing = NativeDiscoverModuleID(rawValue: "doubanShowing")
  static let doubanTop250 = NativeDiscoverModuleID(rawValue: "doubanTop250")
  static let latest = NativeDiscoverModuleID(rawValue: "latest")
  static let mediaLibrary = NativeDiscoverModuleID(rawValue: "mediaLibrary")
  static let categories = NativeDiscoverModuleID(rawValue: "categories")

  /// 内置 10 大默认模块顺序。
  static let allCases: [NativeDiscoverModuleID] = [
    .continueWatching,
    .movies,
    .television,
    .trending,
    .doubanMusic,
    .doubanShowing,
    .doubanTop250,
    .latest,
    .mediaLibrary,
    .categories,
  ]

  /// 构造插件动态推荐榜单模块标识（`plugin_recommend:<api_path>`）。
  static func pluginRecommend(_ apiPath: String) -> NativeDiscoverModuleID {
    NativeDiscoverModuleID(rawValue: "\(pluginPrefix)\(apiPath)")
  }

  /// 稳定模块键。
  var id: String { rawValue }

  /// 是否为插件动态注册的推荐榜单模块。
  var isPluginRecommend: Bool { rawValue.hasPrefix(Self.pluginPrefix) }

  /// 提取插件推荐榜单的相对 `api_path`。
  var pluginAPIPath: String? {
    guard isPluginRecommend else { return nil }
    let sub = String(rawValue.dropFirst(Self.pluginPrefix.count))
    return sub.isEmpty ? nil : sub
  }

  /// 模块默认中文标题（插件动态模块优先使用 `NativeDiscoverModuleItem.displayTitle`）。
  var title: String {
    switch rawValue {
    case Self.continueWatching.rawValue: "继续观看"
    case Self.movies.rawValue: "热门电影"
    case Self.television.rawValue: "热门剧集"
    case Self.trending.rawValue: "本周趋势"
    case Self.doubanMusic.rawValue: "热门音乐"
    case Self.doubanShowing.rawValue: "豆瓣热映"
    case Self.doubanTop250.rawValue: "豆瓣 Top250"
    case Self.latest.rawValue: "最新入库"
    case Self.mediaLibrary.rawValue: "媒体库"
    case Self.categories.rawValue: "分类浏览"
    default:
      pluginAPIPath ?? rawValue
    }
  }

  /// 模块列表前置 SF Symbol。
  var symbol: String {
    switch rawValue {
    case Self.continueWatching.rawValue: "play.circle"
    case Self.movies.rawValue: "film"
    case Self.television.rawValue: "tv"
    case Self.trending.rawValue: "flame"
    case Self.doubanMusic.rawValue: "music.note.list"
    case Self.doubanShowing.rawValue: "ticket"
    case Self.doubanTop250.rawValue: "star.circle"
    case Self.latest.rawValue: "clock.arrow.circlepath"
    case Self.mediaLibrary.rawValue: "rectangle.stack"
    case Self.categories.rawValue: "square.grid.2x2"
    default: "sparkles.rectangle.stack"
    }
  }

  /// 默认是否开启：保持内置豆瓣扩展默认按需开启，同时让已启用插件注册的榜单立即可见。
  var defaultEnabled: Bool {
    switch rawValue {
    case Self.doubanShowing.rawValue, Self.doubanTop250.rawValue: false
    default: true
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.rawValue = try container.decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// 单条可持久化的发现模块显隐与顺序配置（兼容内置模块与插件动态推荐榜单模块）。
struct NativeDiscoverModuleItem: Identifiable, Codable, Equatable, Sendable {
  let id: NativeDiscoverModuleID
  var enabled: Bool
  var customTitle: String?
  var customCategory: String?

  init(
    id: NativeDiscoverModuleID,
    enabled: Bool,
    customTitle: String? = nil,
    customCategory: String? = nil
  ) {
    self.id = id
    self.enabled = enabled
    self.customTitle = customTitle
    self.customCategory = customCategory
  }

  /// 用于「管理发现模块」列表展示的标题。
  var displayTitle: String {
    if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return customTitle
    }
    return id.title
  }

  enum CodingKeys: String, CodingKey {
    case id
    case enabled
    case customTitle = "title"
    case customCategory = "category"
  }

  /// 生成完整默认模块顺序。
  static var defaults: [NativeDiscoverModuleItem] {
    NativeDiscoverModuleID.allCases.map {
      NativeDiscoverModuleItem(id: $0, enabled: $0.defaultEnabled)
    }
  }

  /// 合并服务端保存的配置与内置默认模块。
  static func normalized(_ raw: [NativeDiscoverModuleItem]?) -> [NativeDiscoverModuleItem] {
    guard let raw, !raw.isEmpty else { return defaults }
    var seen: Set<NativeDiscoverModuleID> = []
    var result: [NativeDiscoverModuleItem] = []
    for item in raw where seen.insert(item.id).inserted {
      result.append(item)
    }
    for fallback in defaults where seen.insert(fallback.id).inserted {
      if fallback.id == .categories,
        let mediaIdx = result.firstIndex(where: { $0.id == .mediaLibrary })
      {
        result.insert(fallback, at: mediaIdx + 1)
      } else {
        result.append(fallback)
      }
    }
    return result
  }

  /// 将持久化模块配置与 `GET /api/v1/recommend/source` 返回的插件推荐榜单动态合并：
  /// - 保留用户已保存的显隐开关与排序位置；
  /// - 新发现的插件推荐榜单默认开启并插入到「媒体库 / 分类浏览」之前；
  /// - 已卸载或停用插件撤销的推荐源自动从当前可见列表中剔除。
  static func merged(
    saved: [NativeDiscoverModuleItem]?,
    extraSources: [RecommendSource]
  ) -> [NativeDiscoverModuleItem] {
    let base = normalized(saved)
    let extraByID: [NativeDiscoverModuleID: RecommendSource] = Dictionary(
      uniqueKeysWithValues: extraSources.map {
        (NativeDiscoverModuleID.pluginRecommend($0.apiPath), $0)
      }
    )

    var seen: Set<NativeDiscoverModuleID> = []
    var result: [NativeDiscoverModuleItem] = []

    for var item in base {
      if item.id.isPluginRecommend {
        guard let matched = extraByID[item.id] else {
          continue
        }
        item.customTitle = matched.name
        item.customCategory = matched.type
      }
      if seen.insert(item.id).inserted {
        result.append(item)
      }
    }

    for source in extraSources {
      let modID = NativeDiscoverModuleID.pluginRecommend(source.apiPath)
      guard seen.insert(modID).inserted else { continue }
      let newItem = NativeDiscoverModuleItem(
        id: modID,
        enabled: true,
        customTitle: source.name,
        customCategory: source.type
      )
      if let anchorIdx = result.firstIndex(where: { $0.id == .mediaLibrary || $0.id == .categories })
      {
        result.insert(newItem, at: anchorIdx)
      } else {
        result.append(newItem)
      }
    }

    return result
  }
}

/// 参照视觉参考 10 的原生“管理模块”编排弹层：支持原生开关控制显隐、右侧手柄拖拽排序与单次服务端持久化。
@MainActor
struct NativeDiscoverModulesSheet: View {
  let initialModules: [NativeDiscoverModuleItem]
  let onSave: ([NativeDiscoverModuleItem]) async -> Bool

  @State private var modules: [NativeDiscoverModuleItem]
  @State private var editMode: EditMode = .active
  @State private var isSaving = false
  @State private var saveError = false
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  /// 以当前已载入的模块顺序初始化可编辑草稿。
  init(
    initialModules: [NativeDiscoverModuleItem],
    onSave: @escaping ([NativeDiscoverModuleItem]) async -> Bool
  ) {
    self.initialModules = initialModules
    self.onSave = onSave
    _modules = State(initialValue: initialModules)
  }

  /// 与「编辑仪表盘组件」完全统一的原生列表编排弹层：主题色图标与开关、无框透明行与充裕右侧留白，避免拖拽手柄溢出。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        List {
          if saveError {
            Section {
              HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(NativeTheme.warning)
                Text("保存模块顺序失败，请稍后重试。")
                  .font(.subheadline)
                  .foregroundStyle(.primary)
                Spacer(minLength: 0)
              }
              .listRowBackground(Color.clear)
              .accessibilityIdentifier("native-modules-error")
            }
          }

          Section {
            ForEach($modules) { $item in
              HStack(spacing: 12) {
                Image(systemName: item.id.symbol)
                  .font(.body.weight(.medium))
                  .foregroundStyle(appearance.accentColor)
                  .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                  Text(item.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                  if item.id.isPluginRecommend {
                    Text(
                      (item.customCategory?.isEmpty == false)
                        ? "插件推荐 · \(item.customCategory!)"
                        : "插件推荐榜单"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                  }
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $item.enabled)
                  .labelsHidden()
                  .tint(appearance.accentColor)
                  .accessibilityIdentifier("native-module-toggle-\(item.id.rawValue)")
              }
              .listRowBackground(Color.clear)
              .deleteDisabled(true)
            }
            .onMove { source, destination in
              modules.move(fromOffsets: source, toOffset: destination)
            }
          } header: {
            Text("开启或拖动调整模块顺序")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } footer: {
            Text("隐藏的模块不会在「发现」页中显示，可随时重新开启。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .accessibilityIdentifier("native-modules-list")
      }
      .navigationTitle("编辑发现模块")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") {
            editMode = .inactive
            dismiss()
          }
          .tint(.primary)
          .accessibilityIdentifier("native-modules-cancel")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task {
              isSaving = true
              saveError = false
              let ok = await onSave(modules)
              isSaving = false
              if ok {
                editMode = .inactive
                dismiss()
              } else {
                saveError = true
              }
            }
          } label: {
            Text(isSaving ? "保存中…" : "保存").fontWeight(.semibold)
          }
          .tint(.primary)
          .disabled(isSaving)
          .accessibilityIdentifier("native-modules-save")
        }
      }
    }
    .nativeGlassSheet()
  }
}
