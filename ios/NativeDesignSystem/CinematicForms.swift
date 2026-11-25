import SwiftUI

/// Cinematic 表单的原生分组行；输入控件保留自身焦点、辅助功能与自动填充语义。
@MainActor
struct CinematicFormRow<Content: View>: View {
  @ScaledMetric(relativeTo: .body) private var symbolWidth = 24.0
  private let symbol: String?
  private let content: Content

  /// 图标只提供视觉定位，朗读名称由实际字段或动作承担。
  init(symbol: String? = nil, @ViewBuilder content: () -> Content) {
    self.symbol = symbol
    self.content = content()
  }

  /// 不固定行高，大字号、多行地址和表单提示可以自然撑开材质面板。
  var body: some View {
    HStack(spacing: 14) {
      if let symbol {
        Image(systemName: symbol)
          .font(.body.weight(.medium)).foregroundStyle(.secondary)
          .frame(width: symbolWidth).accessibilityHidden(true)
      }
      HStack(spacing: 8) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 44)
    .padding(.horizontal, 18).padding(.vertical, 8)
  }
}

/// 分组内的细分隔保持连续玻璃表面，不给每个输入框再叠一层材质。
@MainActor
struct CinematicFormDivider: View {
  @Environment(\.colorSchemeContrast) private var contrast

  /// 提高对比度与深浅色主题时自动适配分隔线透明度。
  var body: some View {
    Rectangle().fill(.primary.opacity(contrast == .increased ? 0.28 : 0.085))
      .frame(height: contrast == .increased ? 1 : 0.5).padding(.horizontal, 18)
      .accessibilityHidden(true)
  }
}

/// Form/List 中的单块玻璃表单；外层仍使用原生滚动、键盘避让与分组语义。
@MainActor
struct CinematicFormSection<Content: View>: View {
  private let title: String?
  private let footer: String?
  private let content: Content

  /// 调用方显式传入本地化文本，组件不引入业务或语言存储依赖。
  init(
    _ title: String? = nil, footer: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.footer = footer
    self.content = content()
  }

  /// 原生 Section 持有标题/说明，只有内容共享半透明背景（Form 单元格自身会裁切外延阴影，故禁用阴影避免切边）。
  var body: some View {
    Section {
      CinematicPanel(padding: 0, showsShadow: false) {
        VStack(alignment: .leading, spacing: 0) { content }
          .buttonStyle(.borderless)
      }
      .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
    } header: {
      if let title {
        Text(title)
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
          .textCase(nil)
      }
    } footer: {
      if let footer {
        Text(footer)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}
