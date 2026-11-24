import Foundation
import SwiftUI

/// 发现页可编排模块的受控标识，与 MoviePilot 发现轨道和媒体服务器区块一一对应。
enum NativeDiscoverModuleID: String, CaseIterable, Codable, Identifiable, Sendable {
  case continueWatching
  case movies
  case television
  case trending
  case doubanMusic
  case doubanShowing
  case doubanTop250
  case latest
  case mediaLibrary
  case categories

  /// 稳定模块键。
  var id: String { rawValue }

  /// 模块中文标题。
  var title: String {
    switch self {
    case .continueWatching: "继续观看"
    case .movies: "热门电影"
    case .television: "热门剧集"
    case .trending: "本周趋势"
    case .doubanMusic: "热门音乐"
    case .doubanShowing: "豆瓣热映"
    case .doubanTop250: "豆瓣 Top250"
    case .latest: "最新入库"
    case .mediaLibrary: "媒体库"
    case .categories: "分类浏览"
    }
  }

  /// 模块列表前置 SF Symbol。
  var symbol: String {
    switch self {
    case .continueWatching: "play.circle"
    case .movies: "film"
    case .television: "tv"
    case .trending: "flame"
    case .doubanMusic: "music.note.list"
    case .doubanShowing: "sparkles"
    case .doubanTop250: "star.circle"
    case .latest: "clock.arrow.circlepath"
    case .mediaLibrary: "rectangle.stack"
    case .categories: "square.grid.2x2"
    }
  }

  /// 默认是否开启，保持首屏加载轻快的同时允许随时开启额外榜单。
  var defaultEnabled: Bool {
    switch self {
    case .doubanShowing, .doubanTop250: false
    default: true
    }
  }
}

/// 单条可持久化的发现模块显隐与顺序配置。
struct NativeDiscoverModuleItem: Identifiable, Codable, Equatable, Sendable {
  let id: NativeDiscoverModuleID
  var enabled: Bool

  /// 生成完整默认模块顺序。
  static var defaults: [NativeDiscoverModuleItem] {
    NativeDiscoverModuleID.allCases.map {
      NativeDiscoverModuleItem(id: $0, enabled: $0.defaultEnabled)
    }
  }

  /// 合并服务端保存的配置与新增默认模块，确保不丢失未知未来模块且不重复。
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
                Text(item.id.title)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(.primary)
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
