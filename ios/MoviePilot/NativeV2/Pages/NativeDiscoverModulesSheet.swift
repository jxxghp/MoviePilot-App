import Foundation
import SwiftUI

/// 发现页可编排模块的受控标识，与 MoviePilot 发现轨道和媒体服务器区块一一对应。
enum NativeDiscoverModuleID: String, CaseIterable, Codable, Identifiable, Sendable {
  case continueWatching
  case movies
  case television
  case trending
  case doubanShowing
  case doubanTop250
  case latest
  case mediaLibrary

  /// 稳定模块键。
  var id: String { rawValue }

  /// 模块中文标题。
  var title: String {
    switch self {
    case .continueWatching: "继续观看"
    case .movies: "热门电影"
    case .television: "热门剧集"
    case .trending: "本周趋势"
    case .doubanShowing: "豆瓣热映"
    case .doubanTop250: "豆瓣 Top250"
    case .latest: "最新入库"
    case .mediaLibrary: "媒体库与分类"
    }
  }

  /// 模块列表前置 SF Symbol。
  var symbol: String {
    switch self {
    case .continueWatching: "play.circle"
    case .movies: "film"
    case .television: "tv"
    case .trending: "flame"
    case .doubanShowing: "sparkles"
    case .doubanTop250: "star.circle"
    case .latest: "clock.arrow.circlepath"
    case .mediaLibrary: "square.grid.2x2"
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
      result.append(fallback)
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

  /// 以当前已载入的模块顺序初始化可编辑草稿。
  init(
    initialModules: [NativeDiscoverModuleItem],
    onSave: @escaping ([NativeDiscoverModuleItem]) async -> Bool
  ) {
    self.initialModules = initialModules
    self.onSave = onSave
    _modules = State(initialValue: initialModules)
  }

  /// 紫玫瑰深色渐变底色、大圆角透色玻璃列表卡片、开关 + 原生拖拽手柄及底部说明。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        VStack(alignment: .leading, spacing: 14) {
          if saveError {
            CinematicPanel(padding: 11) {
              HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("保存模块顺序失败，请稍后重试。").font(.subheadline)
                Spacer(minLength: 0)
              }
            }
            .padding(.horizontal, CinematicStyle.margin)
            .accessibilityIdentifier("native-modules-error")
          }
          List {
            ForEach($modules) { $item in
              HStack(spacing: 12) {
                Image(systemName: item.id.symbol)
                  .font(.body.weight(.medium))
                  .foregroundStyle(.primary.opacity(0.68))
                  .frame(width: 24)
                Toggle(item.id.title, isOn: $item.enabled)
                  .font(.body.weight(.medium))
                  .foregroundStyle(.primary)
                  .tint(Color(red: 0.24, green: 0.84, blue: 0.48))
                  .accessibilityIdentifier("native-module-toggle-\(item.id.rawValue)")
              }
              .padding(.vertical, 5)
              .listRowBackground(Color.clear)
              .listRowSeparatorTint(.white.opacity(0.10))
              .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 14))
              .deleteDisabled(true)
            }
            .onMove { source, destination in
              modules.move(fromOffsets: source, toOffset: destination)
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .environment(\.editMode, $editMode)
          .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                  .fill(Color(red: 62 / 255, green: 44 / 255, blue: 76 / 255).opacity(0.36))
              }
              .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                  .strokeBorder(.primary.opacity(0.15), lineWidth: 0.65)
              }
          }
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
          .padding(.horizontal, CinematicStyle.margin)
          .frame(height: min(CGFloat(modules.count) * 56 + 14, 520))
          .accessibilityIdentifier("native-modules-list")

          Text("关闭的模块不在「发现」页显示，可拖动右侧手柄调整展示顺序。")
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.58))
            .padding(.horizontal, CinematicStyle.margin + 4)
          Spacer(minLength: 0)
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
      }
      .navigationTitle("管理模块")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            editMode = .inactive
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("关闭")
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
          .disabled(isSaving)
          .accessibilityIdentifier("native-modules-save")
        }
      }
    }
    .nativeAppearanceRoot()
  }
}
