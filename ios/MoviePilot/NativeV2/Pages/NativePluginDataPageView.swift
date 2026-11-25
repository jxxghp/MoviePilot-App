import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotSession
import SwiftUI
import UIKit
import WebKit

/// 插件页面按钮声明的同源 API 动作（支持 `GET`/`POST`/`PUT`/`DELETE` 与 `params` 参数透传）。
struct NativePluginActionRequest: Sendable {
  let api: String
  let method: String
  let params: [String: JSONValue]?
}

/// 原生插件数据页：直连 `GET /api/v1/plugin/page/{id}` 递归原生渲染 Vuetify JSON 节点与图表；
/// 当插件声明 `render_mode == "vue"` 时，自动在免登隔离 WebView 中直接呈现纯插件内容（隐藏 Web 壳、自动注入会话令牌与资源 Cookie）。
/// 与 Web 端数据弹窗一致，右上角提供「插件设置」入口；原生无法完整还原的自定义样式页面可切换到网页样式查看。
@MainActor
struct NativePluginDataPageView: View {
  let session: NativeSession
  let pluginID: String
  let pluginName: String
  var navKey: String? = nil

  @State private var renderMode = "vuetify"
  @State private var nodes: [NativePluginJSONNode] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var actionFeedback: String?
  @State private var actionIsError = false
  @State private var showsVueSheet = false
  @State private var showsWebStyleSheet = false
  @State private var settingsPlugin: NativeInstalledPlugin?
  @State private var isSettingsPresented = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      CinematicBackground()
      if renderMode.lowercased() == "vue", let navKey {
        NativeVuePluginWebContainer(
          session: session,
          pluginID: pluginID,
          pluginName: pluginName,
          surface: .appPage(navKey: navKey)
        )
        .ignoresSafeArea(edges: .bottom)
      } else if renderMode.lowercased() == "vue" {
        VStack(spacing: 14) {
          ProgressView("正在打开插件弹窗…")
            .tint(.primary)
          Button("重新打开插件界面") {
            showsVueSheet = true
          }
          .buttonStyle(.borderedProminent)
          .tint(NativeTheme.brand)
        }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if let actionFeedback {
              CinematicPanel(padding: 11) {
                HStack(spacing: 8) {
                  Image(
                    systemName: actionIsError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                  )
                  .foregroundStyle(actionIsError ? NativeTheme.warning : NativeTheme.success)
                  Text(actionFeedback).font(.subheadline).foregroundStyle(.primary)
                  Spacer(minLength: 0)
                  Button {
                    self.actionFeedback = nil
                  } label: {
                    Image(systemName: "xmark")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
            if isLoading && nodes.isEmpty {
              NativeCardListSkeletonView(count: 3, style: .formPanel)
                .transition(.opacity)
            } else if loadFailed && nodes.isEmpty {
              CinematicPanel {
                VStack(alignment: .leading, spacing: 10) {
                  Label("暂时无法载入插件页面", systemImage: "exclamationmark.triangle").font(.headline)
                  Button("重试") { reloadToken += 1 }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("native-plugin-page-retry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            } else if nodes.isEmpty {
              CinematicPanel {
                VStack(spacing: 12) {
                  Image(systemName: "doc.plaintext")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                  Text("此插件没有详情页面").font(.headline)
                  Button {
                    openSettings()
                  } label: {
                    Label("打开插件设置", systemImage: "gearshape")
                  }
                  .buttonStyle(.borderedProminent)
                  .tint(NativeTheme.brand)
                  .accessibilityIdentifier("native-plugin-page-empty-settings")
                }
                .frame(maxWidth: .infinity, minHeight: 160)
              }
            } else {
              NativePluginJSONRenderer(
                session: session,
                nodes: nodes,
                onTriggerAction: { request in
                  Task { await triggerPluginAction(request) }
                })
            }
          }
          .frame(maxWidth: 880)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
        .modifier(NativeSoftTopScrollEdge())
        .accessibilityIdentifier("native-plugin-page-scroll")
      }
    }
    .navigationTitle(pluginName)
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      if navKey == nil, renderMode.lowercased() != "vue" {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            openSettings()
          } label: {
            Image(systemName: "gearshape")
          }
          .tint(.primary)
          .accessibilityLabel("插件设置")
          .accessibilityIdentifier("native-plugin-page-settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button {
              showsWebStyleSheet = true
            } label: {
              Label("网页样式查看", systemImage: "safari")
            }
            Button {
              reloadToken += 1
            } label: {
              Label("刷新", systemImage: "arrow.clockwise")
            }
          } label: {
            Image(systemName: "ellipsis")
          }
          .tint(.primary)
          .accessibilityLabel("更多操作")
          .accessibilityIdentifier("native-plugin-page-more")
        }
      }
    }
    .navigationDestination(isPresented: $isSettingsPresented) {
      if let settingsPlugin {
        NativePluginLazyFormDestination(session: session, plugin: settingsPlugin)
          .id(settingsPlugin.id)
      }
    }
    .onChange(of: isSettingsPresented) { presented in
      if !presented, settingsPlugin != nil {
        settingsPlugin = nil
        // 设置页可能已保存配置，返回后刷新数据页。
        reloadToken += 1
      }
    }
    .sheet(isPresented: $showsVueSheet, onDismiss: { dismiss() }) {
      NativeVuePluginSheet(
        session: session,
        pluginID: pluginID,
        pluginName: pluginName,
        surface: .dataPage
      )
    }
    .sheet(isPresented: $showsWebStyleSheet, onDismiss: { reloadToken += 1 }) {
      // 原生无法完整还原插件自定义样式（CSS 网格、状态矩阵等）时，以前端真实渲染的数据弹窗查看。
      NativeVuePluginSheet(
        session: session,
        pluginID: pluginID,
        pluginName: pluginName,
        surface: .dataPage
      )
    }
    .onChange(of: renderMode) { mode in
      if mode.lowercased() == "vue", navKey == nil {
        showsVueSheet = true
      }
    }
    .task(id: reloadToken) {
      if navKey != nil {
        renderMode = "vue"
        isLoading = false
        return
      }
      await load()
    }
  }

  /// 与 Web 数据弹窗的设置按钮一致：在当前导航栈打开插件原生配置表单。
  private func openSettings() {
    do {
      let target = try PluginFormTarget(physicalID: pluginID)
      settingsPlugin = NativeInstalledPlugin(target: target, name: pluginName, hasPage: true)
      isSettingsPresented = true
    } catch {
      actionIsError = true
      actionFeedback = "无法打开该插件的配置。"
    }
  }

  /// 读取 `GET /api/v1/plugin/page/{pluginID}` 并有界解析节点树。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["plugin", "page", pluginID])
      let envelope = try await session.request(
        endpoint, as: NativePluginPageEnvelope.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      try Task.checkCancellation()
      renderMode = envelope.renderMode ?? "vuetify"
      if renderMode.lowercased() != "vue" {
        var budget = 8000
        nodes = NativePluginJSONNode.parseArray(envelope.page ?? [], depth: 0, budget: &budget)
      }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 执行插件节点声明的同源 API 动作（支持 method 与 params），完成后自动刷新页面。
  private func triggerPluginAction(_ request: NativePluginActionRequest) async {
    let cleaned = request.api.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let segments = cleaned.split(separator: "/").map(String.init)
    guard !segments.isEmpty else { return }
    let apiSegments: [String]
    if segments.count >= 3, segments[0] == "api", segments[1] == "v1" {
      apiSegments = Array(segments.dropFirst(2))
    } else {
      apiSegments = segments
    }
    let httpMethod: APIMethod =
      switch request.method.uppercased() {
      case "POST": .post
      case "PUT": .put
      case "DELETE": .delete
      default: .get
      }
    do {
      var queryItems: [URLQueryItem] = []
      var bodyData: Data?
      if let params = request.params, !params.isEmpty {
        if httpMethod == .get || httpMethod == .delete {
          for key in params.keys.sorted() {
            if let str = Self.stringifyParam(params[key]) {
              queryItems.append(URLQueryItem(name: key, value: str))
            }
          }
        } else {
          bodyData = try JSONEncoder().encode(params)
        }
      }
      let endpoint = try APIEndpoint(
        path: apiSegments,
        method: httpMethod,
        query: queryItems,
        body: bodyData,
        responseContract: .payload,
        timeout: 45)
      let response = try await session.request(
        endpoint, as: NativePluginActionResponse.self
      ).value
      if response.success == false {
        actionIsError = true
        actionFeedback =
          response.message?.isEmpty == false ? response.message! : "插件动作执行失败。"
      } else {
        actionIsError = false
        actionFeedback =
          response.message?.isEmpty == false ? response.message! : "插件动作已执行。"
        reloadToken += 1
      }
    } catch {
      actionIsError = true
      actionFeedback = "插件动作执行失败：\(error.localizedDescription)"
    }
  }

  private static func stringifyParam(_ value: JSONValue?) -> String? {
    guard let value else { return nil }
    if let s = value.stringValue { return s }
    if let b = value.boolValue { return b ? "true" : "false" }
    if let n = value.numberValue {
      return n.rounded() == n ? String(Int64(n)) : String(n)
    }
    return nil
  }
}

/// 递归原生渲染 MoviePilot 插件 JSON 节点树与图表，供插件数据页与仪表板卡片共用。
@MainActor
struct NativePluginJSONRenderer: View {
  let session: NativeSession
  let nodes: [NativePluginJSONNode]
  var onTriggerAPI: ((String) -> Void)?
  var onTriggerAction: ((NativePluginActionRequest) -> Void)?

  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      let grouped = Self.coalesceTabsAndWindows(nodes)
      ForEach(Array(grouped.enumerated()), id: \.offset) { _, item in
        switch item {
        case .node(let node):
          renderNode(node)
        case .tabs(let tabTitles, let panels):
          NativePluginJSONTabsView(
            session: session,
            titles: tabTitles,
            panels: panels,
            onTriggerAPI: onTriggerAPI,
            onTriggerAction: onTriggerAction)
        }
      }
    }
  }

  /// 按 Vuetify 组件名映射至对应原生自适应主题视图。
  @ViewBuilder
  private func renderNode(_ node: NativePluginJSONNode) -> some View {
    let name = node.component.lowercased()
    switch name {
    case "style", "script", "vdialogclosebtn":
      EmptyView()
    case "vspacer":
      Spacer(minLength: 4)
    case "vdivider":
      Divider().overlay(NativeTheme.divider)
    case "br":
      Spacer().frame(height: 4)
    case "vrow", "vcontainer", "vwindow", "vwindowitem", "vtabs", "vtab", "vmenu":
      VStack(alignment: .leading, spacing: 10) {
        if !node.displayText.isEmpty {
          Text(node.displayText).font(.subheadline).foregroundStyle(.primary)
        }
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
    case "vsheet":
      CinematicPanel(padding: 12) {
        VStack(alignment: .leading, spacing: 8) {
          if !node.displayText.isEmpty {
            Text(node.displayText).font(.subheadline).foregroundStyle(.primary)
          }
          ForEach(node.children) { child in AnyView(renderNode(child)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    case "vexpansionpanels":
      VStack(alignment: .leading, spacing: 10) {
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
    case "vexpansionpanel":
      NativePluginExpansionPanelView(
        session: session,
        node: node,
        onTriggerAPI: onTriggerAPI,
        onTriggerAction: onTriggerAction)
    case "vcarousel":
      carouselView(node)
    case "vcarouselitem":
      VStack(alignment: .leading, spacing: 8) {
        if let src = node.stringProp("src"), !src.isEmpty {
          imageView(node)
        }
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
    case "vchipgroup":
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          ForEach(node.children) { child in AnyView(renderNode(child)) }
        }
      }
    case "a":
      linkView(node)
    case "div":
      containerView(node)
    case "vcol", "span", "p", "h1", "h2", "h3", "h4", "h5", "h6", "strong", "b", "em", "i",
      "u", "small", "code", "pre", "vlabel":
      VStack(alignment: .leading, spacing: 6) {
        if !node.displayText.isEmpty {
          textElement(node.displayText, tag: name)
        }
        if !node.children.isEmpty {
          ForEach(node.children) { child in AnyView(renderNode(child)) }
        }
      }
    case "vcard", "vdialog":
      CinematicPanel(padding: 13) {
        VStack(alignment: .leading, spacing: 8) {
          if let title = node.stringProp("title"), !title.isEmpty {
            Text(title).font(.headline).foregroundStyle(.primary)
          }
          if let subtitle = node.stringProp("subtitle"), !subtitle.isEmpty {
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
          }
          if !node.displayText.isEmpty {
            Text(node.displayText).font(.subheadline).foregroundStyle(.primary)
          }
          ForEach(node.children) { child in AnyView(renderNode(child)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    case "vcarditem":
      VStack(alignment: .leading, spacing: 4) {
        if let title = node.stringProp("title"), !title.isEmpty {
          Text(title).font(.headline).foregroundStyle(.primary)
        }
        if let subtitle = node.stringProp("subtitle"), !subtitle.isEmpty {
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
    case "vcardtitle":
      Text(node.combinedText)
        .font(.headline.weight(.bold))
        .foregroundStyle(.primary)
    case "vcardsubtitle":
      Text(node.combinedText)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    case "vcardtext":
      VStack(alignment: .leading, spacing: 8) {
        if !node.displayText.isEmpty {
          Text(node.displayText).font(.subheadline).foregroundStyle(.primary)
        }
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
    case "vcardactions":
      HStack(spacing: 10) {
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
    case "valert":
      alertView(node)
    case "vchip":
      chipView(node)
    case "vtable", "vdatatable", "vdatatablevirtual":
      tableView(node)
    case "vlist":
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
            AnyView(renderNode(child))
            if index < node.children.count - 1 {
              Divider().overlay(NativeTheme.divider)
            }
          }
        }
      }
    case "vlistsubheader":
      Text(node.combinedText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    case "vlistitem":
      VStack(alignment: .leading, spacing: 4) {
        if let title = node.stringProp("title"), !title.isEmpty {
          Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        }
        if let subtitle = node.stringProp("subtitle"), !subtitle.isEmpty {
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        if !node.displayText.isEmpty {
          Text(node.displayText).font(.subheadline).foregroundStyle(.primary)
        }
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
    case "vlistitemtitle":
      Text(node.combinedText).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
    case "vlistitemsubtitle":
      Text(node.combinedText).font(.caption).foregroundStyle(.secondary)
    case "vprogresslinear":
      progressView(node)
    case "vprogresscircular":
      ProgressView()
        .tint(Self.tintColor(node.stringProp("color")))
    case "vimg", "img":
      imageView(node)
    case "vicon", "v-icon":
      let iconName = node.iconName
      Image(systemName: Self.sfSymbol(forMDI: iconName))
        .font(.subheadline)
        .foregroundStyle(
          node.stringProp("color").map { Self.tintColor($0) } ?? Self.semanticTint(forMDI: iconName)
        )
    case "vavatar":
      if let img = node.children.first(where: {
        ["vimg", "img"].contains($0.component.lowercased())
      }) {
        imageView(img).frame(width: 40, height: 40).clipShape(Circle())
      } else if !node.combinedText.isEmpty {
        Text(node.combinedText)
          .font(.caption.bold())
          .foregroundStyle(.primary)
          .frame(width: 36, height: 36)
          .background { Circle().fill(NativeTheme.chipFill) }
      }
    case "vapexchart":
      NativePluginApexChartView(props: node.props)
    case "vbtn":
      buttonView(node)
    default:
      if !node.displayText.isEmpty || !node.children.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          if !node.displayText.isEmpty {
            Text(node.displayText).font(.subheadline).foregroundStyle(.primary)
          }
          ForEach(node.children) { child in AnyView(renderNode(child)) }
        }
      }
    }
  }

  private func textElement(_ text: String, tag: String) -> some View {
    let base: Font =
      switch tag {
      case "h1": .title2.bold()
      case "h2": .title3.bold()
      case "h3", "h4": .headline
      case "strong", "b": .subheadline.weight(.semibold)
      case "code", "pre": .caption.monospaced()
      case "small": .caption
      default: .subheadline
      }
    return Text(text)
      .font(base)
      .underline(tag == "u")
      .italic(tag == "em" || tag == "i")
      .foregroundStyle(tag == "small" ? .secondary : .primary)
  }

  @ViewBuilder
  private func linkView(_ node: NativePluginJSONNode) -> some View {
    let label = node.combinedText.isEmpty ? (node.stringProp("href") ?? "打开链接") : node.combinedText
    if let href = node.stringProp("href"), let url = URL(string: href),
      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
    {
      Button {
        openURL(url)
      } label: {
        HStack(spacing: 4) {
          Text(label)
            .font(.subheadline.weight(.medium))
            .underline()
          Image(systemName: "arrow.up.right")
            .font(.caption2)
        }
        .foregroundStyle(NativeTheme.brand)
      }
      .buttonStyle(.plain)
    } else if !label.isEmpty {
      Text(label).font(.subheadline).foregroundStyle(NativeTheme.brand)
    }
  }

  /// `div` 按插件声明的布局意图映射：含 `VSpacer` 的标题行横向排列，网格/概要类样式自适应多列，
  /// 卡片类样式套用玻璃面板，其余保持纵向堆叠。
  @ViewBuilder
  private func containerView(_ node: NativePluginJSONNode) -> some View {
    let tokens = node.classTokens
    let children = node.children.filter {
      !["style", "script"].contains($0.component.lowercased())
    }
    if children.contains(where: { $0.component.lowercased() == "vspacer" }) {
      HStack(alignment: .center, spacing: 8) {
        if !node.displayText.isEmpty {
          Text(node.displayText).font(.subheadline).foregroundStyle(.primary)
        }
        ForEach(children) { child in AnyView(renderNode(child)) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else if tokens.contains(where: { $0.contains("grid") || $0.hasSuffix("summary") }) {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)],
        alignment: .leading, spacing: 10
      ) {
        ForEach(children) { child in AnyView(renderNode(child)) }
      }
    } else if tokens.contains(where: { $0.contains("card") }) {
      CinematicPanel(padding: 12) {
        VStack(alignment: .leading, spacing: 6) {
          if !node.displayText.isEmpty {
            Text(node.displayText).font(.subheadline).foregroundStyle(.primary)
          }
          ForEach(children) { child in AnyView(renderNode(child)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      VStack(alignment: .leading, spacing: 6) {
        if !node.displayText.isEmpty {
          textElement(node.displayText, tag: "div")
        }
        ForEach(children) { child in AnyView(renderNode(child)) }
      }
    }
  }

  private func chipView(_ node: NativePluginJSONNode) -> some View {
    let tint = Self.tintColor(node.stringProp("color"))
    let label = node.combinedText.isEmpty ? (node.stringProp("text") ?? "") : node.combinedText
    let icon = node.stringProp("prepend-icon") ?? node.stringProp("prependIcon")
    return HStack(spacing: 4) {
      if let icon, !icon.isEmpty {
        Image(systemName: Self.sfSymbol(forMDI: icon)).font(.caption2)
      }
      if !label.isEmpty {
        Text(label).lineLimit(1)
      }
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(tint)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background {
      Capsule()
        .fill(tint.opacity(0.14))
        .overlay {
          Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6)
        }
    }
  }

  /// 语义提示卡片（info/success/warning/error）。
  private func alertView(_ node: NativePluginJSONNode) -> some View {
    let alertType = (node.stringProp("type") ?? node.stringProp("color") ?? "info").lowercased()
    let tint = Self.tintColor(alertType)
    let symbol: String =
      switch alertType {
      case "success": "checkmark.circle.fill"
      case "warning": "exclamationmark.triangle.fill"
      case "error": "xmark.octagon.fill"
      default: "info.circle.fill"
      }
    let bodyText = node.stringProp("text") ?? node.displayText
    return CinematicPanel(padding: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: symbol).foregroundStyle(tint)
        VStack(alignment: .leading, spacing: 4) {
          if let title = node.stringProp("title"), !title.isEmpty {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
          }
          if !bodyText.isEmpty {
            Text(bodyText).font(.caption).foregroundStyle(.primary)
          }
          if !node.children.isEmpty && node.stringProp("text") == nil {
            ForEach(node.children) { child in AnyView(renderNode(child)) }
          }
        }
        Spacer(minLength: 0)
      }
    }
  }

  /// 横向轮播组件渲染。
  private func carouselView(_ node: NativePluginJSONNode) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(node.children) { child in
          AnyView(renderNode(child))
            .frame(width: 280)
        }
      }
    }
  }

  /// 原生可横滑自适应玻璃表格（同时支持 HTML `thead/tbody/tr/th/td` 与 Vuetify `VDataTable` `headers`/`items`）。
  /// 含徽标、图标或按钮的单元格按原生控件渲染，避免把图标名当作文字展示。
  private func tableView(_ node: NativePluginJSONNode) -> some View {
    let parsed = node.extractTableCells()
    return CinematicPanel(padding: 0) {
      if parsed.headers.isEmpty && parsed.rows.isEmpty {
        Text(node.stringProp("no-data-text") ?? "暂无表格数据")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(14)
      } else {
        ScrollView(.horizontal) {
          VStack(alignment: .leading, spacing: 0) {
            if !parsed.headers.isEmpty {
              HStack(spacing: 12) {
                ForEach(Array(parsed.headers.enumerated()), id: \.offset) { _, header in
                  Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 88, alignment: .leading)
                }
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .background(NativeTheme.chipFill)
            }
            ForEach(Array(parsed.rows.enumerated()), id: \.offset) { rowIdx, row in
              Divider().overlay(NativeTheme.divider)
              HStack(spacing: 12) {
                ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                  tableCell(cell)
                    .frame(minWidth: 88, alignment: .leading)
                }
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 9)
              .background(rowIdx % 2 == 1 ? NativeTheme.chipFill.opacity(0.45) : .clear)
            }
          }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("native-plugin-json-table")
      }
    }
  }

  /// 单元格：纯文本保持紧凑三行；富内容逐个子节点以原生控件横向排列。
  @ViewBuilder
  private func tableCell(_ cell: NativePluginTableCell) -> some View {
    if let content = cell.node, content.containsRichContent {
      HStack(spacing: 6) {
        ForEach(content.children) { child in AnyView(renderNode(child)) }
      }
    } else {
      Text(cell.text)
        .font(.caption)
        .foregroundStyle(.primary)
        .lineLimit(3)
    }
  }

  /// 进度条渲染。
  private func progressView(_ node: NativePluginJSONNode) -> some View {
    let raw = node.doubleProp("modelValue") ?? node.doubleProp("value") ?? 0
    let fraction = min(max(raw > 1 ? raw / 100.0 : raw, 0), 1)
    let tint = Self.tintColor(node.stringProp("color"))
    return GeometryReader { bar in
      ZStack(alignment: .leading) {
        Capsule().fill(NativeTheme.chipFill)
        Capsule()
          .fill(tint)
          .frame(width: max(bar.size.width * fraction, 4))
      }
    }
    .frame(height: 6)
  }

  /// 通过同源图片代理渲染插件图片，拒绝非法方案。
  @ViewBuilder
  private func imageView(_ node: NativePluginJSONNode) -> some View {
    if let src = node.stringProp("src"), !src.isEmpty {
      NativeMediaArtwork(session: session, reference: src, role: .poster, maximumWidth: 480)
        .frame(maxWidth: 280, minHeight: 120, maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  /// 按钮动作渲染：支持外链 `href` 与声明式同源 API（完整透传 method 与 params）。
  private func buttonView(_ node: NativePluginJSONNode) -> some View {
    let label = node.combinedText.isEmpty ? (node.stringProp("text") ?? "执行") : node.combinedText
    let action = node.clickAction
    let hrefURL: URL? = node.stringProp("href").flatMap { raw in
      guard let url = URL(string: raw),
        let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
      else { return nil }
      return url
    }
    let tint = Self.tintColor(node.stringProp("color") ?? "primary")
    let enabled = action != nil || hrefURL != nil
    return Button {
      if let hrefURL {
        openURL(hrefURL)
      } else if let action {
        if let onTriggerAction {
          onTriggerAction(action)
        } else {
          onTriggerAPI?(action.api)
        }
      }
    } label: {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(enabled ? tint : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
          Capsule()
            .fill(enabled ? tint.opacity(0.16) : NativeTheme.chipFill)
            .overlay {
              Capsule().strokeBorder(
                enabled ? tint.opacity(0.36) : NativeTheme.chipBorder, lineWidth: 0.6)
            }
        }
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }

  /// 语义色彩映射到全局自适应色板。
  static func tintColor(_ raw: String?) -> Color {
    switch (raw ?? "").lowercased() {
    case "success", "green": NativeTheme.success
    case "warning", "orange", "amber": NativeTheme.warning
    case "error", "red": NativeTheme.danger
    case "primary", "purple", "indigo": NativeTheme.brand
    case "grey", "gray": Color.secondary
    default: NativeTheme.info
    }
  }

  /// 未声明颜色的状态图标按图标语义着色（插件常依赖 CSS 类为状态点上色，原生无法读取样式表）。
  static func semanticTint(forMDI raw: String) -> Color {
    let icon = raw.lowercased()
    if icon.contains("cookie") || icon.contains("alert") || icon.contains("close")
      || icon.contains("cancel") || icon.contains("error")
    {
      return NativeTheme.danger
    }
    if icon.contains("check") { return NativeTheme.success }
    if icon.contains("refresh") || icon.contains("sync") || icon.contains("clock") {
      return NativeTheme.warning
    }
    if icon.contains("minus") || icon.contains("help") { return Color.secondary }
    return NativeTheme.info
  }

  /// 常见 MDI 图标名称映射为原生 SF Symbol。
  static func sfSymbol(forMDI raw: String) -> String {
    let icon = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if icon.contains("calendar") { return "calendar" }
    if icon.contains("cookie") { return "exclamationmark.octagon.fill" }
    if icon.contains("check") { return "checkmark.circle.fill" }
    if icon.contains("alert") || icon.contains("warning") { return "exclamationmark.triangle.fill" }
    if icon.contains("close") || icon.contains("cancel") { return "xmark.circle.fill" }
    if icon.contains("delete") || icon.contains("trash") { return "trash" }
    if icon.contains("refresh") || icon.contains("reload") || icon.contains("sync") {
      return "arrow.triangle.2.circlepath"
    }
    if icon.contains("download") { return "arrow.down.circle" }
    if icon.contains("upload") { return "arrow.up.circle" }
    if icon.contains("play") { return "play.fill" }
    if icon.contains("pause") { return "pause.fill" }
    if icon.contains("stop") { return "stop.fill" }
    if icon.contains("cog") || icon.contains("setting") { return "gearshape" }
    if icon.contains("star") { return "star.fill" }
    if icon.contains("heart") { return "heart.fill" }
    if icon.contains("folder") { return "folder.fill" }
    if icon.contains("file") || icon.contains("doc") { return "doc.text" }
    if icon.contains("link") || icon.contains("open") { return "link" }
    if icon.contains("search") || icon.contains("magnify") { return "magnifyingglass" }
    if icon.contains("movie") || icon.contains("film") { return "film" }
    if icon.contains("television") || icon.contains("tv") { return "tv" }
    if icon.contains("music") { return "music.note" }
    if icon.contains("clock") || icon.contains("time") || icon.contains("history") {
      return "clock"
    }
    if icon.contains("qrcode") { return "qrcode" }
    if icon.contains("send") { return "paperplane.fill" }
    if icon.contains("plus") || icon.contains("add") { return "plus" }
    if icon.contains("minus") { return "minus.circle" }
    if icon.contains("help") { return "questionmark.circle" }
    if icon.contains("information") || icon.contains("info") { return "info.circle" }
    if icon.contains("login") || icon.contains("account") { return "person.crop.circle" }
    return "circle.grid.2x2"
  }

  /// 将相邻的 `VTabs` 与 `VWindow` 配对为可切换的原生分段标签页。
  private enum CoalescedNode {
    case node(NativePluginJSONNode)
    case tabs(titles: [String], panels: [NativePluginJSONNode])
  }

  private static func coalesceTabsAndWindows(_ nodes: [NativePluginJSONNode]) -> [CoalescedNode] {
    var result: [CoalescedNode] = []
    var i = 0
    while i < nodes.count {
      let current = nodes[i]
      if current.component.lowercased() == "vtabs",
        i + 1 < nodes.count,
        nodes[i + 1].component.lowercased() == "vwindow"
      {
        let titles = current.children.map { tab in
          tab.combinedText.isEmpty ? (tab.stringProp("text") ?? "标签") : tab.combinedText
        }
        let panels = nodes[i + 1].children
        if !titles.isEmpty && !panels.isEmpty {
          result.append(.tabs(titles: titles, panels: panels))
          i += 2
          continue
        }
      }
      result.append(.node(current))
      i += 1
    }
    return result
  }
}

/// 插件 JSON 数据页可切换标签容器（`VTabs` + `VWindow`）。
@MainActor
private struct NativePluginJSONTabsView: View {
  let session: NativeSession
  let titles: [String]
  let panels: [NativePluginJSONNode]
  let onTriggerAPI: ((String) -> Void)?
  let onTriggerAction: ((NativePluginActionRequest) -> Void)?

  @State private var selectedIndex = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
            Button {
              selectedIndex = index
            } label: {
              NativeAdaptivePill(title, isSelected: selectedIndex == index)
            }
            .buttonStyle(.plain)
          }
        }
      }
      if selectedIndex < panels.count {
        NativePluginJSONRenderer(
          session: session,
          nodes: panels[selectedIndex].children,
          onTriggerAPI: onTriggerAPI,
          onTriggerAction: onTriggerAction)
      }
    }
  }
}

/// 插件 JSON 数据页折叠卡片（`VExpansionPanel`）。
@MainActor
private struct NativePluginExpansionPanelView: View {
  let session: NativeSession
  let node: NativePluginJSONNode
  let onTriggerAPI: ((String) -> Void)?
  let onTriggerAction: ((NativePluginActionRequest) -> Void)?

  @State private var isExpanded = false

  var body: some View {
    let titleNode = node.children.first { $0.component.lowercased() == "vexpansionpaneltitle" }
    let titleText = titleNode?.combinedText ?? node.stringProp("title") ?? "展开详情"
    let bodyNodes: [NativePluginJSONNode] = node.children.flatMap {
      child -> [NativePluginJSONNode] in
      let lower = child.component.lowercased()
      if lower == "vexpansionpaneltitle" { return [] }
      if lower == "vexpansionpaneltext" { return child.children }
      return [child]
    }
    return CinematicPanel(padding: 13) {
      DisclosureGroup(isExpanded: $isExpanded) {
        VStack(alignment: .leading, spacing: 10) {
          NativePluginJSONRenderer(
            session: session,
            nodes: bodyNodes,
            onTriggerAPI: onTriggerAPI,
            onTriggerAction: onTriggerAction)
        }
        .padding(.top, 10)
      } label: {
        Text(titleText)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
      }
      .tint(NativeTheme.brand)
    }
  }
}

/// 原生 SwiftUI `VApexChart` 渲染器：支持饼/环形图与柱状/折线系列，零 WebView 与 JS。
@MainActor
struct NativePluginApexChartView: View {
  let props: [String: JSONValue]

  var body: some View {
    let spec = NativeApexChartSpec(props: props)
    return CinematicPanel(padding: 14) {
      VStack(alignment: .leading, spacing: 12) {
        if !spec.title.isEmpty {
          Text(spec.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
        }
        if spec.slices.isEmpty {
          Text(spec.noDataText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72)
        } else if spec.isCircular {
          HStack(spacing: 18) {
            donutChart(slices: spec.slices)
              .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 7) {
              ForEach(Array(spec.slices.prefix(8).enumerated()), id: \.offset) { index, slice in
                HStack(spacing: 7) {
                  Circle()
                    .fill(Self.palette[index % Self.palette.count])
                    .frame(width: 8, height: 8)
                  Text(slice.label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                  Spacer(minLength: 4)
                  Text(slice.formattedValue)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          let maxVal = max(spec.slices.map(\.value).max() ?? 1, 0.001)
          VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(spec.slices.prefix(10).enumerated()), id: \.offset) { index, slice in
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(slice.label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                  Spacer()
                  Text(slice.formattedValue)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                }
                GeometryReader { bar in
                  ZStack(alignment: .leading) {
                    Capsule().fill(NativeTheme.chipFill)
                    Capsule()
                      .fill(Self.palette[index % Self.palette.count])
                      .frame(width: max(bar.size.width * CGFloat(slice.value / maxVal), 6))
                  }
                }
                .frame(height: 6)
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func donutChart(slices: [NativeApexChartSpec.Slice]) -> some View {
    let total = max(slices.reduce(0) { $0 + $1.value }, 0.0001)
    var cumulative = 0.0
    let segments: [(start: Double, end: Double, color: Color)] = slices.enumerated().map {
      idx, slice in
      let start = cumulative / total
      cumulative += slice.value
      let end = cumulative / total
      return (start, end, Self.palette[idx % Self.palette.count])
    }
    return ZStack {
      Circle().stroke(NativeTheme.chipFill, lineWidth: 16)
      ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
        Circle()
          .trim(from: CGFloat(seg.start), to: CGFloat(seg.end))
          .stroke(seg.color, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
          .rotationEffect(.degrees(-90))
      }
      Text(String(format: "%.1f", total))
        .font(.caption.monospacedDigit().bold())
        .foregroundStyle(.primary)
    }
  }

  private static let palette: [Color] = [
    Color(red: 0.54, green: 0.36, blue: 0.90),
    Color(red: 0.86, green: 0.38, blue: 0.58),
    Color(red: 0.24, green: 0.72, blue: 0.56),
    Color(red: 0.28, green: 0.60, blue: 0.94),
    Color(red: 0.90, green: 0.62, blue: 0.22),
    Color(red: 0.68, green: 0.48, blue: 0.92),
  ]
}

/// 从 ApexCharts `options` 与 `series` 提取原生渲染数据。
private struct NativeApexChartSpec {
  struct Slice {
    let label: String
    let value: Double
    var formattedValue: String {
      abs(value.rounded() - value) < 0.01
        ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }
  }

  let title: String
  let noDataText: String
  let isCircular: Bool
  let slices: [Slice]

  init(props: [String: JSONValue]) {
    let options = props["options"]?.objectValue ?? [:]
    let chartObj = options["chart"]?.objectValue ?? [:]
    let chartType = (chartObj["type"]?.stringValue ?? "bar").lowercased()
    isCircular = ["pie", "donut", "radialbar"].contains(chartType)
    title = options["title"]?.objectValue?["text"]?.stringValue ?? ""
    noDataText = options["noData"]?.objectValue?["text"]?.stringValue ?? "暂无图表数据"

    let labels: [String] =
      (options["labels"]?.arrayValue ?? options["xaxis"]?.objectValue?["categories"]?.arrayValue
      ?? [])
      .compactMap { $0.stringValue ?? $0.numberValue.map { String(Int($0)) } }

    var parsed: [Slice] = []
    if let seriesArray = props["series"]?.arrayValue {
      if seriesArray.allSatisfy({ $0.numberValue != nil }) {
        for (idx, item) in seriesArray.enumerated() {
          let val = max(item.numberValue ?? 0, 0)
          let label = idx < labels.count ? labels[idx] : "项 \(idx + 1)"
          parsed.append(Slice(label: label, value: val))
        }
      } else if let firstObj = seriesArray.first?.objectValue,
        let dataArr = firstObj["data"]?.arrayValue
      {
        for (idx, item) in dataArr.enumerated() {
          let val = max(item.numberValue ?? 0, 0)
          let label = idx < labels.count ? labels[idx] : "项 \(idx + 1)"
          parsed.append(Slice(label: label, value: val))
        }
      }
    }
    slices = parsed
  }
}

/// 前端 `presentation.sheet.actions` 声明、并投影到原生 Sheet 导航栏的标题栏按钮。
struct NativeVueSheetAction: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let icon: String?
  let enabled: Bool

  /// 将前端声明的语义图标（或 Material Design Icon 名称）映射为原生 SF Symbol。
  var sfSymbol: String {
    let raw = (icon ?? "").lowercased()
    if raw.contains("cog") || raw.contains("tune") || raw.contains("setting") { return "gearshape" }
    if raw.contains("refresh") || raw.contains("reload") || raw.contains("sync") {
      return "arrow.clockwise"
    }
    if raw.contains("save") || raw.contains("content-save") || raw.contains("check") {
      return "checkmark"
    }
    if raw.contains("delete") || raw.contains("trash") { return "trash" }
    if raw.contains("plus") || raw.contains("add") { return "plus" }
    if raw.contains("undo") || raw.contains("restore") || raw.contains("reset") {
      return "arrow.counterclockwise"
    }
    if raw.contains("information") || raw.contains("info") || raw.contains("help") {
      return "info.circle"
    }
    if raw.contains("file") || raw.contains("text") || raw.contains("list") || raw.contains("page")
      || raw.contains("view") || raw.contains("chart")
    {
      return "doc.text"
    }
    if raw.contains("download") { return "arrow.down.circle" }
    if raw.contains("upload") { return "arrow.up.circle" }
    if raw.contains("play") { return "play.fill" }
    if raw.contains("stop") { return "stop.fill" }
    if raw.contains("search") || raw.contains("magnify") { return "magnifyingglass" }
    if raw.contains("link") || raw.contains("open-in-new") { return "arrow.up.right" }
    if raw.contains("history") || raw.contains("clock") { return "clock" }
    if raw.contains("bell") { return "bell" }
    if raw.contains("pencil") || raw.contains("edit") { return "pencil" }
    return "ellipsis.circle"
  }
}

/// 前端 `presentation.confirmation` 声明的确认框；原生 Alert 只回传确认结果，业务回调仍留在网页。
struct NativeVueSheetConfirmation: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let message: String
  let confirmText: String
  let cancelText: String
  let confirmEnabled: Bool
  let cancelEnabled: Bool
  let destructive: Bool
}

/// Vue 插件原生 Sheet 的展示状态：标题、按钮与确认框全部来自前端原生容器协议的快照。
@MainActor
final class NativeVueSheetBridge: ObservableObject {
  @Published var title: String
  @Published var actions: [NativeVueSheetAction] = []
  @Published var isReady = false
  @Published var shouldDismiss = false
  @Published var confirmation: NativeVueSheetConfirmation?
  @Published var failureMessage: String?
  /// 当前 WebView 文档的协议宿主；WebView 销毁后自动失效，旧文档不能再接收命令。
  weak var host: NativeVuePluginChromeHost?
  /// 本地预热联邦运行时（v2）回调覆盖，启用本地运行时后优先接管导航栏按钮与确认框。
  var localInvokeAction: ((String) -> Void)?
  var localRequestClose: (() -> Bool)?
  var localRespondConfirmation: ((String, Bool) -> Void)?

  init(defaultTitle: String) {
    self.title = defaultTitle
  }

  /// 非 Sheet（AppPage 全页）容器使用的占位状态，永不发布变化。
  static let detached = NativeVueSheetBridge(defaultTitle: "")

  /// 原生栏按钮只回传前端声明的按钮标识，由前端复核后点击当前弹窗内的真实按钮。
  func invokeAction(id: String) {
    if let localInvokeAction {
      localInvokeAction(id)
      return
    }
    host?.invokeSheetAction(id)
  }

  /// 原生关闭：可关闭的网页弹窗先交回前端关闭（嵌套弹窗只关闭最上层）；返回 false 表示应直接关闭整个 Sheet。
  func requestClose() -> Bool {
    if let localRequestClose {
      return localRequestClose()
    }
    return host?.requestCloseCurrentSheet() ?? false
  }

  /// 原生 Alert 结算后把确认/取消交回前端原组件，不重复执行业务逻辑。
  func respondConfirmation(_ confirmed: Bool) {
    guard let current = confirmation else { return }
    confirmation = nil
    if let localRespondConfirmation {
      localRespondConfirmation(current.id, confirmed)
      return
    }
    host?.respondConfirmation(id: current.id, confirmed: confirmed)
  }
}

/// V1 风格原生 Modal Sheet 容器：专用于 `render_mode == "vue"` 的插件数据页 / 配置弹窗，
/// 以及原生无法完整呈现的 JSON 插件兼容视图。网页侧由前端原生容器协议只展示当前插件弹窗内容，
/// 弹窗标题、标题栏按钮与关闭按钮注册到原生 Sheet 导航栏。
@MainActor
struct NativeVuePluginSheet: View {
  let session: NativeSession
  let pluginID: String
  let pluginName: String
  let surface: NativeVuePluginWebContainer.Surface
  /// 插件是否带详情页：配置入口需先经由详情弹窗的设置按钮切换。
  let pluginHasPage: Bool

  @Environment(\.dismiss) private var dismiss
  @StateObject private var bridge: NativeVueSheetBridge

  init(
    session: NativeSession,
    pluginID: String,
    pluginName: String,
    surface: NativeVuePluginWebContainer.Surface,
    pluginHasPage: Bool = true
  ) {
    self.session = session
    self.pluginID = pluginID
    self.pluginName = pluginName
    self.surface = surface
    self.pluginHasPage = pluginHasPage
    _bridge = StateObject(wrappedValue: NativeVueSheetBridge(defaultTitle: pluginName))
  }

  var body: some View {
    NavigationStack {
      NativeVuePluginWebContainer(
        session: session,
        pluginID: pluginID,
        pluginName: pluginName,
        surface: surface,
        sheetBridge: bridge,
        pluginHasPage: pluginHasPage
      )
      .navigationTitle(bridge.title.isEmpty ? pluginName : bridge.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        if !bridge.actions.isEmpty {
          ToolbarItem(placement: .topBarLeading) {
            Menu {
              ForEach(bridge.actions) { action in
                Button {
                  bridge.invokeAction(id: action.id)
                } label: {
                  Label(action.title, systemImage: action.sfSymbol)
                }
                .disabled(!action.enabled)
              }
            } label: {
              Image(systemName: "ellipsis")
            }
            .tint(.primary)
            .accessibilityLabel("弹窗操作")
            .accessibilityIdentifier("native-sheet-menu")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            if !bridge.requestClose() { dismiss() }
          } label: {
            Image(systemName: "xmark")
              .font(.body.weight(.semibold))
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-vue-plugin-sheet-close")
        }
      }
      .alert(
        bridge.confirmation?.title ?? "",
        isPresented: Binding(
          get: { bridge.confirmation != nil },
          set: { presented in
            if !presented, bridge.confirmation != nil { bridge.respondConfirmation(false) }
          }),
        presenting: bridge.confirmation
      ) { confirmation in
        Button(confirmation.cancelText, role: .cancel) {
          bridge.respondConfirmation(false)
        }
        .disabled(!confirmation.cancelEnabled)
        Button(confirmation.confirmText, role: confirmation.destructive ? .destructive : nil) {
          bridge.respondConfirmation(true)
        }
        .disabled(!confirmation.confirmEnabled)
      } message: { confirmation in
        Text(confirmation.message)
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .onChange(of: bridge.shouldDismiss) { closed in
      if closed { dismiss() }
    }
    .nativeGlassSheet()
  }
}

/// 免登自动渲染的 Vue 远程插件容器：
/// 1. 首帧前向同源 `localStorage` 写入 Pinia `auth` / `user` 会话、界面语言与主题皮肤（彻底免登）；
/// 2. 向非持久化 `WKHTTPCookieStore` 写入当前实例资源 Cookie，确保远程联邦脚本与图片代理直通；
/// 3. Sheet 模式下注入 `MoviePilotNative` 传输门面，与前端完成 `moviepilot.chrome` v1 + `sheets.v1` 协商，
///    由前端自身隔离当前插件弹窗并声明标题/按钮，原生只承载导航栏，不再扫描或改写业务 DOM。
@MainActor
struct NativeVuePluginWebContainer: View {
  enum Surface: Equatable {
    case dataPage
    case config
    case appPage(navKey: String)
  }

  let session: NativeSession
  let pluginID: String
  let pluginName: String
  let surface: Surface
  let sheetBridge: NativeVueSheetBridge?
  let pluginHasPage: Bool
  /// 必须订阅 Sheet 协议状态：前端确认接管（`isReady`）或失败后才会重新计算加载层，
  /// 只持有普通引用时 SwiftUI 不会刷新本视图，WebView 会一直停在透明加载态。
  @ObservedObject private var observedBridge: NativeVueSheetBridge

  init(
    session: NativeSession,
    pluginID: String,
    pluginName: String,
    surface: Surface,
    sheetBridge: NativeVueSheetBridge? = nil,
    pluginHasPage: Bool = true
  ) {
    self.session = session
    self.pluginID = pluginID
    self.pluginName = pluginName
    self.surface = surface
    self.sheetBridge = sheetBridge
    self.pluginHasPage = pluginHasPage
    _observedBridge = ObservedObject(wrappedValue: sheetBridge ?? NativeVueSheetBridge.detached)
  }

  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @AppStorage(PluginRuntimePreferences.useLegacyWebContainerKey)
  private var useLegacyWebContainer = false
  @State private var fallbackToLegacy = false
  @State private var launchConfig: VuePluginLaunchConfig?
  @State private var isWebLoading = true
  @State private var loadError: String?

  private var prefersLocalRuntime: Bool {
    !useLegacyWebContainer && !fallbackToLegacy
  }

  private var showsLoader: Bool {
    if let sheetBridge {
      return !sheetBridge.isReady && sheetBridge.failureMessage == nil
    }
    return isWebLoading
  }

  var body: some View {
    if prefersLocalRuntime {
      NativePluginLocalRuntimeView(
        session: session,
        pluginID: pluginID,
        pluginName: pluginName,
        surface: surface,
        sheetBridge: sheetBridge,
        pluginHasPage: pluginHasPage,
        onFallbackToLegacy: {
          fallbackToLegacy = true
        }
      )
    } else {
      legacyWebBody
    }
  }

  private var legacyWebBody: some View {
    ZStack {
      CinematicBackground()
      if let launchConfig {
        NativeVuePluginWebView(
          config: launchConfig,
          isLoading: $isWebLoading,
          sheetBridge: sheetBridge
        )
        .opacity(sheetBridge != nil && (showsLoader || sheetBridge?.failureMessage != nil) ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: showsLoader)
        if let failure = sheetBridge?.failureMessage {
          failurePanel(failure)
        } else if showsLoader {
          ScrollView {
            NativeCardListSkeletonView(count: 3, style: .formPanel)
              .frame(maxWidth: 880)
              .padding(.horizontal, CinematicStyle.margin)
              .padding(.vertical, 16)
              .frame(maxWidth: .infinity)
          }
          .scrollIndicators(.hidden)
          .transition(.opacity)
        }
      } else if let loadError {
        failurePanel(loadError)
      } else {
        ScrollView {
          NativeCardListSkeletonView(count: 3, style: .formPanel)
            .frame(maxWidth: 880)
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity)
      }
    }
    .accessibilityIdentifier(
      sheetBridge.map {
        $0.isReady ? "native-vue-plugin-sheet-ready" : "native-vue-plugin-sheet-loading"
      } ?? "native-vue-plugin-web-content"
    )
    .task(
      id:
        "\(pluginID)|\(colorScheme)|\(AppLanguage.current.rawValue)|\(NativeAppearanceStore.hexString(from: appearance.accentColor))"
    ) {
      await prepareLaunch()
    }
  }

  /// 失败提示与重试共用同一块玻璃面板；重试会重建 WebView 文档与协议会话。
  private func failurePanel(_ message: String) -> some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle")
          .font(.title2)
          .foregroundStyle(NativeTheme.warning)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
        Button("重试") {
          sheetBridge?.failureMessage = nil
          sheetBridge?.isReady = false
          launchConfig = nil
          Task { await prepareLaunch() }
        }
        .buttonStyle(.borderedProminent)
        .tint(NativeTheme.brand)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    }
    .padding(.horizontal, CinematicStyle.margin)
  }

  private func prepareLaunch() async {
    loadError = nil
    isWebLoading = true
    do {
      let auth = try session.playbackAuthorization()
      let resourceCookie = try? await session.resolveResourceCookie()
      guard let frontend = await resolveFrontendAddress(api: auth.address) else {
        loadError = "当前服务器地址没有提供 MoviePilot 网页前端，无法显示该插件界面。请确认前端端口（默认 3000）可以访问。"
        return
      }
      try Task.checkCancellation()
      guard let targetURL = buildTargetURL(frontend: frontend) else {
        loadError = "无法构造受控插件页面地址。"
        return
      }
      let authPayload: [String: Any] = [
        "token": auth.accessToken,
        "remember": true,
        "originalPath": NSNull(),
      ]
      let user = session.user
      let userPayload: [String: Any] = [
        "superUser": user.isSuperuser,
        "userID": user.id,
        "userName": user.name,
        "avatar": user.avatar,
        "level": user.level,
        "permissions": [
          "discovery": user.allows(.init(category: .discovery)),
          "search": user.allows(.init(category: .search)),
          "subscribe": user.allows(.init(category: .subscribe)),
          "manage": user.allows(.init(category: .manage)),
          "admin": user.allows(.init(category: .admin)),
          "features": [String: Bool](),
        ],
      ]
      let authData = try JSONSerialization.data(withJSONObject: authPayload)
      let userData = try JSONSerialization.data(withJSONObject: userPayload)
      guard let authJSON = String(data: authData, encoding: .utf8),
        let userJSON = String(data: userData, encoding: .utf8)
      else {
        loadError = "会话初始化失败。"
        return
      }
      let preferDark: Bool
      switch appearance.mode {
      case .dark: preferDark = true
      case .light: preferDark = false
      case .system: preferDark = (colorScheme == .dark)
      }
      let accentHex = NativeAppearanceStore.hexString(from: appearance.accentColor)
      let locale = AppLanguage.current.rawValue
      let containingFolder: String?
      switch surface {
      case .appPage:
        containingFolder = nil
      case .dataPage, .config:
        containingFolder = await resolveContainingFolder(for: pluginID)
      }
      launchConfig = VuePluginLaunchConfig(
        url: targetURL,
        origin: frontend,
        authJSON: authJSON,
        userJSON: userJSON,
        resourceCookie: resourceCookie,
        preferDark: preferDark,
        accentHex: accentHex,
        locale: locale,
        surface: surface,
        switchesToConfig: surface == .config && pluginHasPage,
        containingFolder: containingFolder)
    } catch is CancellationError {
      return
    } catch {
      loadError = "当前登录会话不可用，无法打开插件页面。"
    }
  }

  /// 已确认的前端入口缓存（按实例地址），避免每次打开插件都重新探测。
  private static var frontendCache: [String: ServerAddress] = [:]

  /// 找到真正提供前端页面的入口：实例地址本身是前端时直接使用；
  /// 若连接的是后端 API 端口，再按系统配置中的前端端口与访问域名依次探测。
  private func resolveFrontendAddress(api: ServerAddress) async -> ServerAddress? {
    let key = api.url.absoluteString
    if let cached = Self.frontendCache[key] { return cached }
    if await Self.probeFrontend(api) {
      Self.frontendCache[key] = api
      return api
    }
    var frontendPort: Int?
    var appDomain: String?
    if let endpoint = try? APIEndpoint(path: ["system", "env"], responseContract: .payload),
      let data = try? await session.requestPayload(
        endpoint, requiring: PermissionRequirement(category: .admin)
      ).value,
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    {
      let env = (object["data"] as? [String: Any]) ?? object
      frontendPort =
        (env["NGINX_PORT"] as? NSNumber)?.intValue
        ?? (env["NGINX_PORT"] as? String).flatMap { Int($0) }
      appDomain = env["APP_DOMAIN"] as? String
    }
    // 读取不到系统配置（非管理员或旧后端）时按官方默认前端端口探测。
    let candidates = PluginWebFrontend.candidates(
      api: api, frontendPort: frontendPort ?? 3000, appDomain: appDomain)
    for candidate in candidates.dropFirst() where await Self.probeFrontend(candidate) {
      Self.frontendCache[key] = candidate
      return candidate
    }
    return nil
  }

  /// 无凭据 GET 候选入口，只确认其返回 MoviePilot 前端 `index.html`。
  private static func probeFrontend(_ address: ServerAddress) async -> Bool {
    var request = URLRequest(url: address.url, timeoutInterval: 6)
    request.setValue("text/html", forHTTPHeaderField: "Accept")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    let urlSession = URLSession(configuration: configuration)
    defer { urlSession.finishTasksAndInvalidate() }
    guard let (data, response) = try? await urlSession.data(for: request),
      let http = response as? HTTPURLResponse
    else { return false }
    return PluginWebFrontend.isFrontendDocument(
      statusCode: http.statusCode,
      contentType: http.value(forHTTPHeaderField: "Content-Type"),
      body: data)
  }

  /// 查询插件是否归属于某个 Web 插件文件夹；若在文件夹内，前端主列表默认隐藏其卡片，需自动展开对应文件夹后触发弹窗。
  private func resolveContainingFolder(for targetPluginID: String) async -> String? {
    guard let endpoint = try? APIEndpoint(path: ["plugin", "folders"], responseContract: .payload),
      let data = try? await session.requestPayload(
        endpoint, requiring: PermissionRequirement(category: .admin)
      ).value,
      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    for (folderName, entry) in obj {
      if let list = entry as? [String], list.contains(targetPluginID) {
        return folderName
      }
      if let dict = entry as? [String: Any],
        let list = dict["plugins"] as? [String],
        list.contains(targetPluginID)
      {
        return folderName
      }
    }
    return nil
  }

  /// 基于 Vue Hash Router 构造同源插件入口：AppPage 直达 `/#/plugin-app/{id}/{navKey}`，数据/配置页直达 `/#/plugins?id={id}`。
  private func buildTargetURL(frontend: ServerAddress) -> URL? {
    var baseString = frontend.url.absoluteString
    if !baseString.hasSuffix("/") { baseString += "/" }
    let encodedID =
      pluginID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pluginID
    let hashPath: String
    switch surface {
    case .appPage(let navKey):
      let encodedNav =
        navKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? navKey
      hashPath = "#/plugin-app/\(encodedID)/\(encodedNav)"
    case .dataPage, .config:
      let encodedQueryID =
        pluginID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pluginID
      hashPath = "#/plugins?id=\(encodedQueryID)&tab=installed"
    }
    guard let url = URL(string: baseString + hashPath), frontend.contains(url) else { return nil }
    return url
  }
}

/// Vue 插件 WebView 启动参数（共享认证态、资源 Cookie、当前界面语言与主题/强调色设置）。
private struct VuePluginLaunchConfig: Equatable {
  let url: URL
  let origin: ServerAddress
  let authJSON: String
  let userJSON: String
  let resourceCookie: APIExportedResourceCookie?
  let preferDark: Bool
  let accentHex: String
  let locale: String
  let surface: NativeVuePluginWebContainer.Surface
  /// 配置入口且插件带详情页：前端深链先打开详情弹窗，需要切换到配置弹窗后再接管。
  let switchesToConfig: Bool
  /// 插件所在的文件夹名（若已归入插件文件夹）。
  let containingFolder: String?

  static func == (lhs: VuePluginLaunchConfig, rhs: VuePluginLaunchConfig) -> Bool {
    lhs.url == rhs.url && lhs.preferDark == rhs.preferDark && lhs.accentHex == rhs.accentHex
      && lhs.locale == rhs.locale && lhs.surface == rhs.surface
      && lhs.switchesToConfig == rhs.switchesToConfig
      && lhs.containingFolder == rhs.containingFolder
  }
}

/// 弱引用消息代理，避免 `WKUserContentController` 与协议宿主形成循环引用。
private final class WeakVueSheetScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: (any WKScriptMessageHandler)?
  init(_ target: any WKScriptMessageHandler) { self.target = target }
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}

/// 同源免登隔离 `WKWebView`：首帧前写入 Pinia 会话、语言与主题皮肤以及资源 Cookie；
/// 传入 `sheetBridge` 时注入前端原生容器传输门面，由 `NativeVuePluginChromeHost` 完成弹窗接管协商。
private struct NativeVuePluginWebView: UIViewRepresentable {
  let config: VuePluginLaunchConfig
  @Binding var isLoading: Bool
  let sheetBridge: NativeVueSheetBridge?

  func makeCoordinator() -> NativeVuePluginChromeHost {
    NativeVuePluginChromeHost(
      origin: config.origin,
      isLoading: $isLoading,
      sheetBridge: sheetBridge,
      switchesToConfig: config.switchesToConfig,
      containingFolder: config.containingFolder)
  }

  func makeUIView(context: Context) -> WKWebView {
    let wkConfig = WKWebViewConfiguration()
    wkConfig.websiteDataStore = .nonPersistent()
    wkConfig.allowsInlineMediaPlayback = true
    wkConfig.mediaTypesRequiringUserActionForPlayback = []
    if UIDevice.current.userInterfaceIdiom == .phone {
      wkConfig.defaultWebpagePreferences.preferredContentMode = .mobile
    }

    let contentController = wkConfig.userContentController
    contentController.addUserScript(
      WKUserScript(
        source: makeSessionScript(config),
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true))
    if sheetBridge != nil {
      contentController.add(
        WeakVueSheetScriptHandler(context.coordinator),
        name: NativeVuePluginChromeHost.messageHandlerName)
      contentController.addUserScript(
        WKUserScript(
          source: NativeVuePluginChromeHost.transportScript,
          injectionTime: .atDocumentStart,
          forMainFrameOnly: true))
    }

    let screenBounds = UIScreen.main.bounds
    let initialFrame =
      screenBounds.width > 0 && screenBounds.height > 0
      ? screenBounds
      : CGRect(x: 0, y: 0, width: 390, height: 844)
    let webView = WKWebView(frame: initialFrame, configuration: wkConfig)
    webView.navigationDelegate = context.coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    // Sheet 模式由前端按原生量测的底部安全区留白，避免与 UIKit 自动内边距重复叠加。
    webView.scrollView.contentInsetAdjustmentBehavior = sheetBridge != nil ? .never : .automatic
    webView.overrideUserInterfaceStyle = config.preferDark ? .dark : .light
    context.coordinator.attach(webView)

    var request = URLRequest(url: config.url)
    request.setValue(config.locale, forHTTPHeaderField: "Accept-Language")
    request.setValue(config.locale, forHTTPHeaderField: "X-MoviePilot-Locale")

    // 先写入同源资源 Cookie，再触发首次导航，确保远程联邦 JS 模块和图片代理零 401。
    if let cookieInfo = config.resourceCookie,
      let cookie = makeHTTPCookie(from: cookieInfo, targetURL: config.url)
    {
      wkConfig.websiteDataStore.httpCookieStore.setCookie(cookie) {
        DispatchQueue.main.async {
          webView.load(request)
        }
      }
    } else {
      webView.load(request)
    }
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    uiView.overrideUserInterfaceStyle = config.preferDark ? .dark : .light
    context.coordinator.layoutChanged()
  }

  static func dismantleUIView(_ uiView: WKWebView, coordinator: NativeVuePluginChromeHost) {
    uiView.configuration.userContentController.removeScriptMessageHandler(
      forName: NativeVuePluginChromeHost.messageHandlerName)
    coordinator.stop()
  }

  private func makeHTTPCookie(
    from info: APIExportedResourceCookie, targetURL: URL
  ) -> HTTPCookie? {
    var props: [HTTPCookiePropertyKey: Any] = [
      .name: info.name,
      .value: info.value,
      // 前端入口可能与 API 地址不同主机（访问域名），Cookie 始终写给实际加载的前端主机。
      .domain: targetURL.host ?? info.domain,
      .path: info.path.isEmpty ? "/" : info.path,
    ]
    if info.isSecure || targetURL.scheme?.lowercased() == "https" {
      props[.secure] = "TRUE"
    }
    return HTTPCookie(properties: props)
  }

  /// 构造首帧前注入脚本：同步登录态、语言（`MP_LOCALE`）、主题皮肤与强调色，并隐藏网页外壳导航；
  /// Sheet 接管成功后前端协议同样隐藏外壳，降级展示网页时也不会露出完整站点导航。
  private func makeSessionScript(_ cfg: VuePluginLaunchConfig) -> String {
    let authLiteral = Self.jsStringLiteral(cfg.authJSON)
    let userLiteral = Self.jsStringLiteral(cfg.userJSON)
    let themeName = cfg.preferDark ? "dark" : "light"
    let localeLiteral = Self.jsStringLiteral(cfg.locale)
    let accentLiteral = Self.jsStringLiteral(cfg.accentHex)
    let customizerDict: [String: Any] = [
      "theme": themeName,
      "primaryColor": cfg.accentHex,
    ]
    let customizerJSON =
      (try? JSONSerialization.data(withJSONObject: customizerDict)).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "{}"
    let customizerLiteral = Self.jsStringLiteral(customizerJSON)

    return """
      (function() {
        if (window.top !== window) return;
        try {
          window.localStorage.setItem('auth', \(authLiteral));
          window.localStorage.setItem('user', \(userLiteral));
          window.localStorage.setItem('MP_LOCALE', \(localeLiteral));
          window.localStorage.setItem('theme', '\(themeName)');
          window.localStorage.setItem('materio-initial-resolved-theme', '\(themeName)');
          window.localStorage.setItem('materio-initial-loader-color', \(accentLiteral));
          window.localStorage.setItem('moviepilot-theme-customizer', \(customizerLiteral));
        } catch (e) {}

        function applyNativePluginChrome() {
          try {
            var root = document.documentElement;
            if (!root) return;
            root.lang = \(localeLiteral);
            if (document.getElementById('mp-native-vue-plugin-style')) return;
            var style = document.createElement('style');
            style.id = 'mp-native-vue-plugin-style';
            style.textContent = [
              '.layout-navbar, .layout-vertical-nav, .layout-overlay, .layout-footer,',
              '.footer-content-container, .mobile-dock, .v-bottom-navigation,',
              '.app-customizer-toggler, .agent-pet-container, .floating-agent-btn,',
              '[data-native-page-title], [data-native-page-heading], [data-native-page-actions] {',
              '  display: none !important;',
              '}',
              '.layout-content-wrapper { padding-inline-start: 0 !important; }',
              '.layout-page-content { padding-block-start: 8px !important; padding-block-end: 12px !important; }'
            ].join('\\n');
            (document.head || root).appendChild(style);
          } catch (e) {}
        }

        applyNativePluginChrome();
        document.addEventListener('DOMContentLoaded', applyNativePluginChrome, { once: true });
      })();
      """
  }

  /// 通过 JSON 序列化生成安全的 JS 字符串字面量，防止任何引号/换行转义问题。
  private static func jsStringLiteral(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
      let json = String(data: data, encoding: .utf8),
      json.count >= 2
    else { return "\"\"" }
    return String(json.dropFirst().dropLast())
  }
}

/// Vue 插件容器的前端原生容器协议宿主（`moviepilot.chrome` v1，与 V1 App 一致）：
/// - `web.ready` → `host.configure`，随后以 `chrome.prepare` 提交布局，前端隐藏自身导航外壳；
/// - 前端快照中的 `presentation.sheet` 是当前最上层插件弹窗：原生先 `presentation.attach` 让前端
///   只显示该弹窗内容，再把标题与标题栏按钮注册到原生 Sheet 导航栏；
/// - 按钮点击回传 `presentation.action`，确认框通过 `confirmation.respond` 交回原组件；
/// - 协商失败或旧前端不支持时释放接管，直接展示网页内容，不留下空白页面。
@MainActor
final class NativeVuePluginChromeHost: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  static let messageHandlerName = "mpVuePluginChrome"

  /// 只声明本容器真实实现的能力：传输、业务弹窗接管与系统确认框。
  static let transportScript = """
    (function () {
      'use strict';
      if (window.top !== window || window.MoviePilotNative) return;
      var handler = window.webkit && window.webkit.messageHandlers
        && window.webkit.messageHandlers.\(messageHandlerName);
      if (!handler) return;
      Object.defineProperty(window, 'MoviePilotNative', {
        value: Object.freeze({
          transportVersion: 1,
          sheetsVersion: 1,
          confirmationsVersion: 1,
          postMessage: function (message) { handler.postMessage(message); },
          authenticationRequired: function () {
            handler.postMessage({ kind: 'authentication.required' });
          }
        }),
        configurable: false,
        writable: false
      });
      function extractMdi(el) {
        var iconEl = el.querySelector('[class*="mdi-"]')
          || (el.className && String(el.className).indexOf('mdi-') >= 0 ? el : null);
        if (iconEl) {
          var m = String(iconEl.className || '').match(/mdi-[a-z0-9-]+/i);
          if (m) return m[0].toLowerCase();
        }
        var vIcon = el.querySelector('.v-icon');
        if (vIcon) {
          var t = (vIcon.textContent || '').trim().toLowerCase();
          if (t.indexOf('mdi-') === 0) return t;
        }
        return '';
      }

      function labelForIcon(icon) {
        if (!icon) return '';
        if (icon.indexOf('cog') >= 0 || icon.indexOf('tune') >= 0) return '设置';
        if (icon.indexOf('refresh') >= 0 || icon.indexOf('sync') >= 0 || icon.indexOf('reload') >= 0) return '刷新';
        if (icon.indexOf('save') >= 0 || icon === 'mdi-check') return '保存';
        if (icon.indexOf('plus') >= 0 || icon.indexOf('add') >= 0) return '添加';
        if (icon.indexOf('delete') >= 0 || icon.indexOf('trash') >= 0) return '删除';
        if (icon.indexOf('history') >= 0 || icon.indexOf('clock') >= 0) return '历史';
        if (icon.indexOf('undo') >= 0 || icon.indexOf('restore') >= 0) return '重置';
        if (icon.indexOf('info') >= 0 || icon.indexOf('help') >= 0) return '详情';
        return '';
      }

      function isCloseLike(btn, icon, rawText, aria) {
        return btn.classList.contains('v-dialog-close-btn')
          || icon === 'mdi-close' || icon === 'mdi-close-circle' || icon === 'mdi-close-circle-outline'
          || rawText === '关闭' || rawText === 'Close' || aria === '关闭' || aria === 'Close';
      }

      function buttonFacts(btn) {
        return {
          icon: extractMdi(btn),
          text: (btn.textContent || '').replace(/mdi-[a-z0-9-]+/gi, '').trim(),
          aria: (btn.getAttribute('aria-label') || '').trim()
        };
      }

      // 联邦插件常用自定义 <header>/「*-header」作为弹窗标题栏：只认弹窗内容顶部、带关闭按钮且不含输入控件的那一个，
      // 避免把正文里的卡片标题误当成标题栏隐藏。
      function findCustomHeader(root) {
        var content = root.querySelector(':scope > .v-overlay__content') || root;
        var top = content.getBoundingClientRect().top;
        var candidates = content.querySelectorAll('header, [class*="header"], [class*="toolbar"]');
        for (var i = 0; i < candidates.length && i < 40; i++) {
          var el = candidates[i];
          if (el.closest('[data-native-dialog-content]')) continue;
          if (el.querySelector('input, select, textarea, [role="tablist"]')) continue;
          if (el.getBoundingClientRect().top - top > 160) continue;
          var buttons = el.querySelectorAll('button');
          for (var b = 0; b < buttons.length; b++) {
            var f = buttonFacts(buttons[b]);
            if (isCloseLike(buttons[b], f.icon, f.text, f.aria)) return el;
          }
        }
        return null;
      }

      function findDialogHeader(root) {
        return root.querySelector('[data-native-dialog-header]')
          || root.querySelector(
            ':scope > .v-overlay__content > .v-card > .v-card-item, :scope > .v-overlay__content > .v-card > .v-toolbar, :scope > .v-overlay__content > .v-card > .v-card-title'
          )
          || findCustomHeader(root)
          || root.querySelector('.v-card-item, .v-toolbar');
      }

      // 联邦 Vue 插件自身的标题栏常使用纯图标按钮、自定义 header 或未声明 data-native-dialog-close 的关闭按钮，
      // 补齐语义属性后交给前端 NativeSheetAdapter 统一采集标题、动作与关闭能力；原生 Sheet 接管后标题栏由原生导航栏替代。
      function normalizeVueDialogHeaders() {
        var dialogs = document.querySelectorAll('.v-overlay--active.v-dialog');
        for (var d = 0; d < dialogs.length; d++) {
          var root = dialogs[d];
          var header = findDialogHeader(root);
          if (!header || header.closest('[data-native-dialog-content]')) continue;
          if (!header.hasAttribute('data-native-dialog-header')
            && !header.matches('.v-card-item, .v-toolbar, .v-card-title')) {
            header.setAttribute('data-native-dialog-header', '');
          }
          if (!root.querySelector('[data-native-dialog-title]')) {
            var heading = header.querySelector('.v-card-title, .v-toolbar-title, h1, h2, h3');
            if (heading && !heading.querySelector('button')) heading.setAttribute('data-native-dialog-title', '');
          }
          var hasClose = Boolean(root.querySelector('[data-native-dialog-close]'));
          var buttons = header.querySelectorAll('button');
          for (var i = 0; i < buttons.length; i++) {
            var btn = buttons[i];
            // 当前布局下不显示的按钮（插件桌面端专用、移动端另有底部操作）不投影为原生按钮。
            var rendered = btn.getClientRects().length > 0;
            if (!rendered) {
              if (!btn.hasAttribute('aria-hidden')) {
                btn.setAttribute('aria-hidden', 'true');
                btn.setAttribute('data-mp-native-hidden', '');
              }
              continue;
            }
            if (btn.hasAttribute('data-mp-native-hidden')) {
              btn.removeAttribute('aria-hidden');
              btn.removeAttribute('data-mp-native-hidden');
            }
            if (btn.hasAttribute('data-native-dialog-close') || btn.hasAttribute('data-mp-native-duplicate-close')) continue;
            var f = buttonFacts(btn);
            if (isCloseLike(btn, f.icon, f.text, f.aria)) {
              if (!hasClose) {
                btn.setAttribute('data-native-dialog-close', '');
                hasClose = true;
              } else {
                // 重复的关闭入口由原生关闭按钮统一承担。
                btn.setAttribute('aria-hidden', 'true');
                btn.setAttribute('data-mp-native-duplicate-close', '');
              }
              continue;
            }
            if (f.icon && !btn.hasAttribute('data-native-sheet-action') && !header.hasAttribute('data-native-sheet-actions')) {
              btn.setAttribute('data-native-sheet-action', f.icon);
            }
            if (!f.aria && !btn.getAttribute('title') && !f.text) {
              var fallback = labelForIcon(f.icon);
              if (fallback) btn.setAttribute('aria-label', fallback);
            }
          }
        }
      }

      function installHeaderObserver() {
        if (!document.body) return;
        normalizeVueDialogHeaders();
        new MutationObserver(function (records) {
          for (var i = 0; i < records.length; i++) {
            if (records[i].type === 'childList') {
              normalizeVueDialogHeaders();
              break;
            }
          }
        }).observe(document.body, { childList: true, subtree: true });
      }
      if (document.body) installHeaderObserver();
      else document.addEventListener('DOMContentLoaded', installHeaderObserver, { once: true });

      // 若目标插件被用户归入了插件文件夹，主列表默认不挂载其卡片；展开对应文件夹即可触发自动打开。
      window.__mpNativeOpenPluginFolder = function (folderName) {
        if (!folderName) return false;
        var cards = document.querySelectorAll('.plugin-folder-card');
        for (var i = 0; i < cards.length; i++) {
          var card = cards[i];
          var txt = (card.textContent || '').trim();
          if (txt === folderName || txt.indexOf(folderName) >= 0) {
            card.click();
            return true;
          }
        }
        return false;
      };

      // 配置入口：前端深链先打开详情弹窗时，点击其中的「设置/前往配置」按钮切换到配置弹窗。
      window.__mpNativeSwitchToConfig = function () {
        var dialogs = Array.prototype.slice.call(document.querySelectorAll('.v-overlay--active.v-dialog'));
        if (!dialogs.length) return false;
        dialogs.sort(function (a, b) {
          return (parseInt(getComputedStyle(a).zIndex || '0', 10) || 0)
            - (parseInt(getComputedStyle(b).zIndex || '0', 10) || 0);
        });
        var buttons = dialogs[dialogs.length - 1].querySelectorAll('button, .v-btn');
        for (var i = 0; i < buttons.length; i++) {
          var button = buttons[i];
          var icon = extractMdi(button);
          var text = (button.textContent || '').replace(/mdi-[a-z0-9-]+/gi, '').trim();
          var label = (button.getAttribute('aria-label') || '').trim();
          if (icon === 'mdi-cog' || icon === 'mdi-cog-outline' || icon === 'mdi-tune'
            || text === '设置' || text === '配置' || text.indexOf('前往配置') >= 0 || text.indexOf('切换配置') >= 0
            || label === '设置' || label === 'Settings' || label === '切换配置') {
            button.click();
            return true;
          }
        }
        return false;
      };
    })();
    """

  private enum Phase { case waiting, configured, preparing, active, released }

  let origin: ServerAddress
  @Binding var isLoading: Bool
  weak var sheetBridge: NativeVueSheetBridge?
  private let switchesToConfig: Bool
  private let containingFolder: String?
  private weak var webView: WKWebView?
  private var phase: Phase = .waiting
  private var sessionId: String?
  private var routeRevision = 0
  private var stateRevision = 0
  private var sequence = 0
  private var layoutRevision = 0
  private var lastLayoutSize: CGSize = .zero
  private var latestSnapshot: [String: Any]?
  private var currentSheetID: String?
  private var currentSheetCanDismiss = false
  private var closeRequested = false
  private var attachedSheetID: String?
  private var attachingSheetID: String?
  private var attachAttempts: [String: Int] = [:]
  private var hasPresentedSheet = false
  private var folderOpenDone = false
  private var folderOpenAttempts = 0
  private var configSwitchDone = false
  private var configSwitchAttempts = 0
  private var confirmationID: String?
  private var pendingCommands: [String: (Bool) -> Void] = [:]
  private var dismissTask: Task<Void, Never>?
  private var fallbackTask: Task<Void, Never>?
  private var folderOpenTask: Task<Void, Never>?
  private var configSwitchTask: Task<Void, Never>?

  init(
    origin: ServerAddress,
    isLoading: Binding<Bool>,
    sheetBridge: NativeVueSheetBridge?,
    switchesToConfig: Bool,
    containingFolder: String?
  ) {
    self.origin = origin
    _isLoading = isLoading
    self.sheetBridge = sheetBridge
    self.switchesToConfig = switchesToConfig
    self.containingFolder = containingFolder
    super.init()
  }

  /// 绑定当前 WebView 文档；Sheet 栏的按钮命令只发往这一份文档。
  func attach(_ webView: WKWebView) {
    self.webView = webView
    sheetBridge?.host = self
  }

  /// WebView 拆除时撤销全部计时与待确认命令，迟到的回包不再改变界面。
  func stop() {
    phase = .released
    dismissTask?.cancel()
    fallbackTask?.cancel()
    folderOpenTask?.cancel()
    configSwitchTask?.cancel()
    pendingCommands.removeAll()
    if sheetBridge?.host === self { sheetBridge?.host = nil }
  }

  /// 接管完成后容器尺寸变化（旋转、分屏）时同步布局，前端据此重算底部安全区。
  func layoutChanged() {
    guard phase == .active, let size = webView?.bounds.size, size.width > 0, size.height > 0,
      size != lastLayoutSize
    else { return }
    send("host.layout", payload: layoutPayload())
  }

  /// 原生栏按钮：只作用于当前快照里的最上层弹窗，前端会再次核对弹窗与按钮是否仍有效。
  func invokeSheetAction(_ actionID: String) {
    guard phase == .active, let sheetID = currentSheetID else { return }
    sendCommand("presentation.action", payload: ["id": sheetID, "actionId": actionID]) { _ in }
  }

  /// 原生关闭按钮：当前弹窗可关闭时交给前端点击其真实关闭按钮，嵌套弹窗关闭后回到下层弹窗；
  /// 最上层已无弹窗或前端拒绝时由原生直接关闭整个 Sheet。返回 false 表示调用方应立即关闭。
  func requestCloseCurrentSheet() -> Bool {
    guard phase == .active, let sheetID = currentSheetID, currentSheetCanDismiss else {
      return false
    }
    closeRequested = true
    sendCommand("presentation.dismiss", payload: ["id": sheetID]) { [weak self] accepted in
      guard let self, !accepted else { return }
      self.sheetBridge?.shouldDismiss = true
    }
    // 前端迟迟未关闭（业务弹窗拦截关闭）时不让用户停在原地。
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard let self, self.closeRequested, self.currentSheetID == sheetID else { return }
      self.sheetBridge?.shouldDismiss = true
    }
    return true
  }

  /// 原生确认框结果交回前端原确认组件。
  func respondConfirmation(id: String, confirmed: Bool) {
    guard phase == .active else { return }
    sendCommand("confirmation.respond", payload: ["id": id, "confirmed": confirmed]) { _ in }
  }

  // MARK: - 消息接收

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard message.name == Self.messageHandlerName, message.frameInfo.isMainFrame,
      let webView, message.webView === webView,
      let documentURL = webView.url, origin.contains(documentURL),
      let body = message.body as? [String: Any]
    else { return }
    if body["kind"] as? String == "authentication.required" {
      handleAuthenticationRequired()
      return
    }
    guard body["protocol"] as? String == "moviepilot.chrome",
      (body["major"] as? NSNumber)?.intValue == 1,
      let type = body["type"] as? String,
      let payload = body["payload"] as? [String: Any]
    else { return }
    if type != "web.ready" {
      guard let sessionId, body["sessionId"] as? String == sessionId else { return }
    }
    if let route = (body["routeRevision"] as? NSNumber)?.intValue, route >= 0 {
      routeRevision = route
    }
    if let state = (body["stateRevision"] as? NSNumber)?.intValue, state >= 0 {
      stateRevision = state
    }
    handle(type: type, payload: payload)
  }

  /// 封闭分派表：未知消息直接忽略，不成为通用原生调用入口。
  private func handle(type: String, payload: [String: Any]) {
    switch type {
    case "web.ready":
      // 网页（重新）就绪：开启新的协商会话，旧会话的命令与弹窗标识全部作废。
      let id = "ios-" + UUID().uuidString
      sessionId = id
      phase = .configured
      resetPresentationState()
      send(
        "host.configure",
        payload: [
          "sessionId": id, "major": 1,
          "capabilities": ["actions.v1", "layout.v1", "menu.v1", "navigation.v1"],
        ])
    case "navigation.state":
      latestSnapshot = payload
      if phase == .configured {
        phase = .preparing
        send("chrome.prepare", payload: layoutPayload())
      } else if phase == .active {
        apply(snapshot: payload)
      }
    case "chrome.accepted":
      guard phase == .preparing else { return }
      phase = .active
      if let latestSnapshot { apply(snapshot: latestSnapshot) }
    case "command.result":
      guard let requestID = payload["requestId"] as? String,
        let completion = pendingCommands.removeValue(forKey: requestID)
      else { return }
      completion((payload["accepted"] as? Bool) == true)
    case "session.state":
      // 网页身份或权限变化：轮换会话标识，旧命令全部失效后由前端重新发布快照。
      guard phase == .active, let previous = sessionId else { return }
      let next = "ios-" + UUID().uuidString
      failPendingCommands()
      send("host.rekey", payload: ["sessionId": next], sessionOverride: previous)
      sessionId = next
    case "chrome.failed":
      releaseToWebContent()
    default:
      break
    }
  }

  // MARK: - 弹窗接管

  /// 读取前端快照中的当前最上层弹窗与确认框，驱动原生 Sheet 标题、按钮与生命周期。
  private func apply(snapshot: [String: Any]) {
    let presentation = snapshot["presentation"] as? [String: Any]
    updateConfirmation(presentation?["confirmation"] as? [String: Any])
    guard let sheet = presentation?["sheet"] as? [String: Any],
      let sheetID = sheet["id"] as? String, !sheetID.isEmpty
    else {
      currentSheetID = nil
      currentSheetCanDismiss = false
      if closeRequested {
        // 用户通过原生关闭按钮关闭了最后一层弹窗：立即关闭 Sheet，不再等待切换窗口。
        sheetBridge?.shouldDismiss = true
      } else if hasPresentedSheet {
        scheduleDismiss()
      } else if let folder = containingFolder, !folder.isEmpty, !folderOpenDone {
        openContainingFolder(folder)
      }
      return
    }
    folderOpenTask?.cancel()
    folderOpenDone = true
    dismissTask?.cancel()
    if sheetID != currentSheetID { closeRequested = false }
    currentSheetID = sheetID
    currentSheetCanDismiss = (sheet["canDismiss"] as? Bool) == true
    let route = snapshot["route"] as? [String: Any]
    updateSheetChrome(sheet, pageTitle: route?["title"] as? String)
    if sheetID == attachedSheetID || sheetID == attachingSheetID { return }
    if switchesToConfig && !configSwitchDone {
      switchToConfig()
      return
    }
    attachSheet(sheetID)
  }

  /// 标题与按钮完全采用前端声明（已过滤关闭按钮、不可表达的控件与超量按钮）；
  /// 弹窗未声明标题时前端会回退为页面标题，此时保留插件名称而不显示「插件」等页面名。
  private func updateSheetChrome(_ sheet: [String: Any], pageTitle: String?) {
    guard let sheetBridge else { return }
    if let title = sheet["title"] as? String, !title.isEmpty, title != "MoviePilot",
      title != pageTitle
    {
      sheetBridge.title = title
    }
    let rawActions = sheet["actions"] as? [[String: Any]] ?? []
    sheetBridge.actions = rawActions.compactMap { item in
      guard let id = item["id"] as? String, !id.isEmpty,
        let title = item["title"] as? String, !title.isEmpty
      else { return nil }
      return NativeVueSheetAction(
        id: id, title: title, icon: item["icon"] as? String,
        enabled: (item["enabled"] as? Bool) ?? true)
    }
  }

  /// 请求前端只显示指定弹窗；前端在真正绘制后才确认，原生据此揭开 WebView，避免闪出底页。
  private func attachSheet(_ sheetID: String) {
    let attempts = (attachAttempts[sheetID] ?? 0) + 1
    attachAttempts[sheetID] = attempts
    guard attempts <= 5 else {
      releaseToWebContent()
      return
    }
    attachingSheetID = sheetID
    sendCommand("presentation.attach", payload: ["id": sheetID]) { [weak self] accepted in
      guard let self, self.attachingSheetID == sheetID else { return }
      self.attachingSheetID = nil
      guard accepted else { return }
      self.attachedSheetID = sheetID
      self.hasPresentedSheet = true
      self.reveal()
    }
  }

  /// 插件被归入插件文件夹时，主列表不挂载其卡片；待文件夹卡片渲染后自动点开一次以触发目标弹窗。
  private func openContainingFolder(_ folderName: String) {
    guard folderOpenTask == nil, let webView else { return }
    folderOpenAttempts += 1
    folderOpenTask = Task { @MainActor [weak self, weak webView] in
      guard let webView else { return }
      let opened: Bool
      do {
        let result = try await webView.callAsyncJavaScript(
          "return window.__mpNativeOpenPluginFolder ? window.__mpNativeOpenPluginFolder(folder) : false;",
          arguments: ["folder": folderName], in: nil, contentWorld: .page)
        opened = (result as? Bool) == true
      } catch {
        opened = false
      }
      guard let self, !Task.isCancelled, self.phase == .active else { return }
      if opened || self.folderOpenAttempts >= 16 {
        self.folderOpenDone = true
        self.folderOpenTask = nil
        return
      }
      try? await Task.sleep(nanoseconds: 300_000_000)
      self.folderOpenTask = nil
      guard !Task.isCancelled, self.phase == .active else { return }
      if let snapshot = self.latestSnapshot { self.apply(snapshot: snapshot) }
    }
  }

  /// 配置入口：详情弹窗出现后点击其「设置」按钮切换到配置弹窗；联邦组件可能稍后加载，短暂重试。
  private func switchToConfig() {
    guard configSwitchTask == nil, let webView else { return }
    configSwitchAttempts += 1
    configSwitchTask = Task { @MainActor [weak self, weak webView] in
      guard let webView else { return }
      let switched: Bool
      do {
        let result = try await webView.callAsyncJavaScript(
          "return window.__mpNativeSwitchToConfig ? window.__mpNativeSwitchToConfig() : false;",
          arguments: [:], in: nil, contentWorld: .page)
        switched = (result as? Bool) == true
      } catch {
        switched = false
      }
      guard let self, !Task.isCancelled, self.phase == .active else { return }
      if switched || self.configSwitchAttempts >= 12 {
        self.configSwitchDone = true
        self.configSwitchTask = nil
        if !switched, let current = self.currentSheetID { self.attachSheet(current) }
        return
      }
      try? await Task.sleep(nanoseconds: 250_000_000)
      self.configSwitchTask = nil
      guard !Task.isCancelled, self.phase == .active else { return }
      if let snapshot = self.latestSnapshot { self.apply(snapshot: snapshot) }
    }
  }

  /// 弹窗关闭后短暂等待：详情与配置互相切换时会先关闭旧弹窗再打开新弹窗。
  private func scheduleDismiss() {
    dismissTask?.cancel()
    dismissTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      guard let self, !Task.isCancelled, self.currentSheetID == nil, self.hasPresentedSheet
      else { return }
      self.sheetBridge?.shouldDismiss = true
    }
  }

  /// 确认框按标识去重，只在新出现时弹出原生 Alert。
  private func updateConfirmation(_ raw: [String: Any]?) {
    guard let raw, let id = raw["id"] as? String, !id.isEmpty else {
      confirmationID = nil
      if sheetBridge?.confirmation != nil { sheetBridge?.confirmation = nil }
      return
    }
    guard id != confirmationID else { return }
    confirmationID = id
    sheetBridge?.confirmation = NativeVueSheetConfirmation(
      id: id,
      title: (raw["title"] as? String) ?? "MoviePilot",
      message: (raw["message"] as? String) ?? "",
      confirmText: (raw["confirmText"] as? String) ?? "确认",
      cancelText: (raw["cancelText"] as? String) ?? "取消",
      confirmEnabled: (raw["confirmEnabled"] as? Bool) ?? true,
      cancelEnabled: (raw["cancelEnabled"] as? Bool) ?? true,
      destructive: (raw["destructive"] as? Bool) ?? false)
  }

  // MARK: - 降级与可见性

  private func reveal() {
    fallbackTask?.cancel()
    isLoading = false
    sheetBridge?.isReady = true
  }

  /// 协商失败、超时或旧前端：释放接管恢复网页原弹窗，再展示内容，保证不会停在空白页。
  private func releaseToWebContent() {
    guard phase != .released else { return }
    if sessionId != nil, phase == .active || phase == .preparing {
      send("chrome.release", payload: [:])
    }
    phase = .released
    failPendingCommands()
    reveal()
  }

  private func handleAuthenticationRequired() {
    fallbackTask?.cancel()
    isLoading = false
    sheetBridge?.failureMessage = "登录状态已失效，请重新登录 App 后再打开插件。"
  }

  private func resetPresentationState() {
    latestSnapshot = nil
    currentSheetID = nil
    attachedSheetID = nil
    attachingSheetID = nil
    attachAttempts.removeAll()
    folderOpenTask?.cancel()
    folderOpenTask = nil
    configSwitchTask?.cancel()
    configSwitchTask = nil
    failPendingCommands()
  }

  // MARK: - 消息发送

  /// 需要前端确认的命令：重复 requestId 不会重放，超时视为拒绝。
  private func sendCommand(
    _ type: String, payload: [String: Any], completion: @escaping (Bool) -> Void
  ) {
    guard sessionId != nil else {
      completion(false)
      return
    }
    sequence += 1
    let requestID = "ios-cmd-\(sequence)"
    pendingCommands[requestID] = completion
    send(type, payload: payload, requestID: requestID)
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard let self, let pending = self.pendingCommands.removeValue(forKey: requestID) else {
        return
      }
      pending(false)
    }
  }

  private func failPendingCommands() {
    let pending = pendingCommands.values
    pendingCommands.removeAll()
    for completion in pending { completion(false) }
  }

  /// 固定 JS 入口以参数传递完整消息，不把任何载荷拼接为可执行代码。
  private func send(
    _ type: String, payload: [String: Any], requestID: String? = nil,
    sessionOverride: String? = nil
  ) {
    guard let webView else { return }
    let resolvedRequestID: String
    if let requestID {
      resolvedRequestID = requestID
    } else {
      sequence += 1
      resolvedRequestID = "ios-msg-\(sequence)"
    }
    var envelope: [String: Any] = [
      "protocol": "moviepilot.chrome",
      "major": 1,
      "type": type,
      "requestId": resolvedRequestID,
      "payload": payload,
    ]
    if let id = sessionOverride ?? sessionId {
      envelope["sessionId"] = id
      envelope["routeRevision"] = routeRevision
      envelope["stateRevision"] = stateRevision
    }
    webView.callAsyncJavaScript(
      "window.dispatchEvent(new CustomEvent('moviepilot:native-message', { detail: message })); return true;",
      arguments: ["message": envelope], in: nil, in: .page, completionHandler: nil)
  }

  /// 原生 point 量测：与 V1 `NativeWebSheetController` 一致，WebView 已对齐 Sheet 安全区（排除顶部导航栏与底部 Home Indicator），
  /// `consumedByNativeFrame: true` 使网页弹窗填满安全区且底部操作栏不被遮挡。
  private func layoutPayload() -> [String: Any] {
    layoutRevision += 1
    let size = webView?.bounds.size ?? .zero
    lastLayoutSize = size
    let width = size.width > 0 ? Double(size.width) : 390
    let height = size.height > 0 ? Double(size.height) : 844
    let zero: [String: Any] = ["top": 0, "left": 0, "bottom": 0, "right": 0]
    return [
      "layoutRevision": layoutRevision,
      "viewportPoints": ["width": width, "height": height],
      "contentInsets": zero,
      "systemSafeArea": zero,
      "chromeOcclusion": zero,
      "keyboardOcclusion": 0,
      "consumedByNativeFrame": true,
    ]
  }

  // MARK: - 导航策略

  /// 严格拦截跨域主文档导航：外链交由系统打开，同源导航放行。
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    guard let target = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    if origin.contains(target) || target.scheme == "about" || target.scheme == "blob" {
      decisionHandler(.allow)
    } else if navigationAction.navigationType == .linkActivated,
      let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https"
    {
      UIApplication.shared.open(target)
      decisionHandler(.cancel)
    } else {
      decisionHandler(.cancel)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard sheetBridge != nil else {
      Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 350_000_000)
        self?.isLoading = false
      }
      return
    }
    // 前端需完成登录态恢复与目录加载后才发起协商；长时间未接管时降级展示网页内容。
    fallbackTask?.cancel()
    fallbackTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 15_000_000_000)
      guard let self, !Task.isCancelled, self.sheetBridge?.isReady != true else { return }
      self.releaseToWebContent()
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    reveal()
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    // 策略拦截外链或主动取消产生的失败不代表插件页面不可用。
    let nsError = error as NSError
    if nsError.code == NSURLErrorCancelled
      || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
    {
      return
    }
    if sheetBridge != nil, sheetBridge?.isReady != true {
      fallbackTask?.cancel()
      isLoading = false
      sheetBridge?.failureMessage = "无法连接插件页面，请检查服务器连接后重试。"
    } else {
      isLoading = false
    }
  }
}

/// `GET /api/v1/plugin/page/{id}` 响应结构。
private struct NativePluginPageEnvelope: Decodable, Sendable {
  let renderMode: String?
  let page: [JSONValue]?

  private enum CodingKeys: String, CodingKey {
    case renderMode = "render_mode"
    case page
  }
}

/// 插件动作响应信封。
private struct NativePluginActionResponse: Decodable, Sendable {
  let success: Bool?
  let message: String?
}

/// 插件表格单元格：纯文本或保留原节点的富内容（徽标、状态图标等）。
struct NativePluginTableCell: Sendable {
  let text: String
  let node: NativePluginJSONNode?
}

/// 有界解码的插件 UI 节点。
struct NativePluginJSONNode: Identifiable, Sendable {
  let id: String
  let component: String
  let text: String
  let html: String
  let props: [String: JSONValue]
  let events: [String: JSONValue]
  let children: [NativePluginJSONNode]

  /// 有界递归解析插件 JSON 数组（深度上限 32、节点总数上限 8000）。
  /// 状态矩阵类页面（站点 × 日期）单页即可达数千节点，预算过小会静默截断后半部分内容。
  static func parseArray(_ raw: [JSONValue], depth: Int, budget: inout Int)
    -> [NativePluginJSONNode]
  {
    guard depth < 32, budget > 0 else { return [] }
    var output: [NativePluginJSONNode] = []
    for (idx, item) in raw.enumerated() {
      guard budget > 0, let obj = item.objectValue else { continue }
      budget -= 1
      let component = obj["component"]?.stringValue ?? "div"
      let text = obj["text"]?.stringValue ?? ""
      let html = obj["html"]?.stringValue ?? ""
      let props = obj["props"]?.objectValue ?? [:]
      let events = obj["events"]?.objectValue ?? [:]
      var rawChildren: [JSONValue] = []
      if let contentArr = obj["content"]?.arrayValue {
        rawChildren.append(contentsOf: contentArr)
      }
      if let childArr = obj["children"]?.arrayValue {
        rawChildren.append(contentsOf: childArr)
      }
      let children = parseArray(rawChildren, depth: depth + 1, budget: &budget)
      output.append(
        NativePluginJSONNode(
          id: "\(depth)-\(idx)-\(budget)-\(component)",
          component: component,
          text: text,
          html: html,
          props: props,
          events: events,
          children: children
        ))
    }
    return output
  }

  func stringProp(_ key: String) -> String? { props[key]?.stringValue }

  func doubleProp(_ key: String) -> Double? { props[key]?.numberValue }

  /// `VIcon` 的 `text` / `icon` 是 MDI 图标名，不是可读文字，不能混入标题、徽标或表格文本。
  var isIcon: Bool {
    let name = component.lowercased()
    return name == "vicon" || name == "v-icon"
  }

  /// 图标名优先取 `icon` 属性，其次为节点文本（插件常用 `{'component': 'VIcon', 'text': 'mdi-xxx'}`）。
  var iconName: String {
    let raw = stringProp("icon") ?? (text.isEmpty ? displayTextIgnoringIcon : text)
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// `class` 属性拆分后的小写样式名，用于识别卡片、网格等布局意图。
  var classTokens: [String] {
    (stringProp("class") ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
  }

  /// 子树是否包含需要原生控件呈现的元素（徽标、图标、按钮、链接、图片），决定表格单元格的渲染方式。
  var containsRichContent: Bool {
    let name = component.lowercased()
    if ["vchip", "vicon", "v-icon", "vbtn", "a", "vimg", "img", "vavatar", "vprogresslinear"]
      .contains(name)
    {
      return true
    }
    return children.contains { $0.containsRichContent }
  }

  /// 文本展示优先级：`text` -> 剥离 HTML 标签后的 `html` / `props.innerHTML`；图标节点不产生文字。
  var displayText: String {
    if isIcon { return "" }
    return displayTextIgnoringIcon
  }

  private var displayTextIgnoringIcon: String {
    if !text.isEmpty { return text }
    if !html.isEmpty { return Self.stripHTML(html) }
    if let inner = props["innerHTML"]?.stringValue, !inner.isEmpty {
      return Self.stripHTML(inner)
    }
    return ""
  }

  /// 聚合当前节点及后代纯文本，用于标题、徽标和表格单元格展示（跳过样式、脚本与图标名）。
  var combinedText: String {
    if isIcon { return "" }
    var parts: [String] = []
    let own = displayText
    if !own.isEmpty { parts.append(own) }
    for child in children where !["style", "script"].contains(child.component.lowercased()) {
      let sub = child.combinedText
      if !sub.isEmpty { parts.append(sub) }
    }
    return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 提取 `events.click` 声明的完整同源 API 动作（api、method、params）。
  var clickAction: NativePluginActionRequest? {
    guard let click = events["click"]?.objectValue,
      let api = click["api"]?.stringValue ?? click["path"]?.stringValue,
      !api.isEmpty
    else { return nil }
    let method = click["method"]?.stringValue ?? "GET"
    let params = click["params"]?.objectValue
    return NativePluginActionRequest(api: api, method: method, params: params)
  }

  /// 从 `VTable` / `VDataTable` / `VDataTableVirtual` 提取表头与行单元格；
  /// HTML 表格保留单元格节点，便于徽标与状态图标按原生控件呈现。
  func extractTableCells() -> (headers: [String], rows: [[NativePluginTableCell]]) {
    if let rawHeaders = props["headers"]?.arrayValue,
      let rawItems = props["items"]?.arrayValue
    {
      let cols: [(title: String, key: String)] = rawHeaders.compactMap { item in
        guard let obj = item.objectValue else { return nil }
        let key = obj["key"]?.stringValue ?? obj["value"]?.stringValue ?? ""
        let title = obj["title"]?.stringValue ?? obj["text"]?.stringValue ?? key
        return key.isEmpty ? nil : (title, key)
      }
      let rows: [[NativePluginTableCell]] = rawItems.compactMap { row in
        guard let obj = row.objectValue else { return nil }
        return cols.map { NativePluginTableCell(text: Self.formatCell(obj[$0.key]), node: nil) }
      }
      return (cols.map(\.title), rows)
    }
    var headers: [String] = []
    var rows: [[NativePluginTableCell]] = []
    func walk(_ node: NativePluginJSONNode, inHead: Bool) {
      let name = node.component.lowercased()
      if name == "thead" {
        for c in node.children { walk(c, inHead: true) }
      } else if name == "tbody" {
        for c in node.children { walk(c, inHead: false) }
      } else if name == "tr" {
        if inHead || node.children.allSatisfy({ $0.component.lowercased() == "th" }) {
          if headers.isEmpty { headers = node.children.map(\.combinedText) }
        } else if !node.children.isEmpty {
          rows.append(
            node.children.map { NativePluginTableCell(text: $0.combinedText, node: $0) })
        }
      } else {
        for c in node.children { walk(c, inHead: inHead) }
      }
    }
    walk(self, inHead: false)
    return (headers, rows)
  }

  private static func formatCell(_ value: JSONValue?) -> String {
    guard let value else { return "" }
    if let s = value.stringValue { return s }
    if let b = value.boolValue { return b ? "是" : "否" }
    if let n = value.numberValue {
      return n.rounded() == n ? String(Int64(n)) : String(format: "%.2f", n)
    }
    return ""
  }

  private static func stripHTML(_ html: String) -> String {
    var text =
      html
      .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
      .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities: [(String, String)] = [
      ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
      ("&quot;", "\""), ("&#39;", "'"),
    ]
    for (k, v) in entities { text = text.replacingOccurrences(of: k, with: v) }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// `JSONValue` 便捷读取扩展，供插件 JSON 节点解析使用。
extension JSONValue {
  fileprivate var objectValue: [String: JSONValue]? {
    if case .object(let dict) = self { return dict }
    return nil
  }

  fileprivate var arrayValue: [JSONValue]? {
    if case .array(let list) = self { return list }
    return nil
  }

  fileprivate var stringValue: String? {
    if case .string(let text) = self { return text }
    return nil
  }

  fileprivate var numberValue: Double? {
    if case .number(let num) = self { return num }
    return nil
  }

  fileprivate var boolValue: Bool? {
    if case .bool(let flag) = self { return flag }
    return nil
  }
}
