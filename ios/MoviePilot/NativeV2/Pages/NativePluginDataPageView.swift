import Foundation
import MoviePilotAPI
import MoviePilotCore
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
              ProgressView("正在载入插件页面…")
                .tint(.primary)
                .frame(maxWidth: .infinity, minHeight: 220)
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
                VStack(spacing: 10) {
                  Image(systemName: "doc.plaintext")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                  Text("当前插件暂无展示数据").font(.headline)
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
    .toolbarBackground(.hidden, for: .navigationBar)
    .sheet(isPresented: $showsVueSheet, onDismiss: { dismiss() }) {
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
        var budget = 2000
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
    case "vcol", "div", "span", "p", "h1", "h2", "h3", "h4", "h5", "h6", "strong", "b", "em", "i",
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
      Image(systemName: Self.sfSymbol(forMDI: node.stringProp("icon") ?? node.combinedText))
        .font(.subheadline)
        .foregroundStyle(Self.tintColor(node.stringProp("color")))
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

  private func chipView(_ node: NativePluginJSONNode) -> some View {
    let tint = Self.tintColor(node.stringProp("color"))
    let label = node.combinedText.isEmpty ? (node.stringProp("text") ?? "") : node.combinedText
    return Text(label)
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
  private func tableView(_ node: NativePluginJSONNode) -> some View {
    let parsed = node.extractTable()
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
                  Text(cell)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 88, alignment: .leading)
                    .lineLimit(3)
                }
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 9)
              .background(rowIdx % 2 == 1 ? NativeTheme.chipFill.opacity(0.45) : .clear)
            }
          }
        }
        .scrollIndicators(.hidden)
      }
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
    default: NativeTheme.info
    }
  }

  /// 常见 MDI 图标名称映射为原生 SF Symbol。
  static func sfSymbol(forMDI raw: String) -> String {
    let icon = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

/// 从 Vue 插件弹出页顶部栏提取并投影到原生 Sheet 导航栏的动作按钮。
struct NativeVueSheetAction: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let icon: String?
  let enabled: Bool

  /// 将 Material Design Icon 名称映射为原生 SF Symbol。
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

/// Vue 插件原生 Sheet 接管桥接器：参考 V1 原生弹层方案，接管弹窗标题、顶部操作按钮与关闭按钮。
@MainActor
final class NativeVueSheetBridge: ObservableObject {
  @Published var title: String
  @Published var actions: [NativeVueSheetAction] = []
  @Published var isReady = false
  @Published var shouldDismiss = false
  weak var webView: WKWebView?

  init(defaultTitle: String) {
    self.title = defaultTitle
  }

  func invokeAction(id: String) {
    let escaped = Self.jsString(id)
    webView?.evaluateJavaScript(
      "window.__mpNativeSheetInvoke && window.__mpNativeSheetInvoke(\(escaped));",
      completionHandler: nil)
  }

  func requestWebDismiss() {
    webView?.evaluateJavaScript(
      "window.__mpNativeSheetDismiss && window.__mpNativeSheetDismiss();",
      completionHandler: nil)
  }

  private static func jsString(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
      let json = String(data: data, encoding: .utf8), json.count >= 2
    else { return "\"\"" }
    return String(json.dropFirst().dropLast())
  }
}

/// V1 风格原生 Modal Sheet 接管容器：专用于 `render_mode == "vue"` 的插件数据页与配置弹窗。
/// 自动隔离 Web 端 `.v-overlay--active.v-dialog`，把弹窗标题、公共按钮与关闭按钮接管到原生 Sheet 导航栏。
@MainActor
struct NativeVuePluginSheet: View {
  let session: NativeSession
  let pluginID: String
  let pluginName: String
  let surface: NativeVuePluginWebContainer.Surface

  @Environment(\.dismiss) private var dismiss
  @StateObject private var bridge: NativeVueSheetBridge

  init(
    session: NativeSession,
    pluginID: String,
    pluginName: String,
    surface: NativeVuePluginWebContainer.Surface
  ) {
    self.session = session
    self.pluginID = pluginID
    self.pluginName = pluginName
    self.surface = surface
    _bridge = StateObject(wrappedValue: NativeVueSheetBridge(defaultTitle: pluginName))
  }

  var body: some View {
    NavigationStack {
      NativeVuePluginWebContainer(
        session: session,
        pluginID: pluginID,
        pluginName: pluginName,
        surface: surface,
        sheetBridge: bridge
      )
      .ignoresSafeArea(edges: .bottom)
      .navigationTitle(bridge.title.isEmpty ? pluginName : bridge.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        if !bridge.actions.isEmpty {
          ToolbarItemGroup(placement: .topBarLeading) {
            if bridge.actions.count <= 2 {
              ForEach(bridge.actions) { action in
                Button {
                  bridge.invokeAction(id: action.id)
                } label: {
                  if let icon = action.icon, !icon.isEmpty {
                    Image(systemName: action.sfSymbol)
                  } else {
                    Text(action.title)
                  }
                }
                .disabled(!action.enabled)
                .accessibilityLabel(action.title)
              }
            } else {
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
                Image(systemName: "ellipsis.circle")
              }
              .accessibilityLabel("更多操作")
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            bridge.requestWebDismiss()
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.body.weight(.semibold))
          }
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-vue-plugin-sheet-close")
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .onChange(of: bridge.shouldDismiss) { closed in
      if closed { dismiss() }
    }
    .nativeAppearanceRoot()
  }
}

/// 免登自动渲染的 Vue 远程插件容器：
/// 1. 首帧前向同源 `localStorage` 写入 Pinia `auth` 与 `user` 会话（彻底免登）；
/// 2. 向非持久化 `WKHTTPCookieStore` 写入当前实例资源 Cookie，确保远程联邦脚本与图片代理直通；
/// 3. 在 Sheet 接管模式下仅隔离当前最顶层 `.v-overlay--active.v-dialog`，将标题、顶部按钮和关闭按钮投影给原生导航栏。
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
  var sheetBridge: NativeVueSheetBridge? = nil

  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var launchConfig: VuePluginLaunchConfig?
  @State private var isWebLoading = true
  @State private var loadError: String?

  private var showsLoader: Bool {
    if let sheetBridge {
      return !sheetBridge.isReady
    }
    return isWebLoading
  }

  var body: some View {
    ZStack {
      CinematicBackground()
      if let launchConfig {
        NativeVuePluginWebView(
          config: launchConfig,
          isLoading: $isWebLoading,
          sheetBridge: sheetBridge
        )
        .opacity(sheetBridge != nil && showsLoader ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: showsLoader)
        if showsLoader {
          VStack(spacing: 10) {
            ProgressView()
              .controlSize(.regular)
              .tint(NativeTheme.brand)
            Text("正在加载 \(pluginName)…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 16)
          .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(.ultraThinMaterial)
          }
        }
      } else if let loadError {
        CinematicPanel {
          VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
              .font(.title2)
              .foregroundStyle(NativeTheme.warning)
            Text(loadError)
              .font(.subheadline)
              .foregroundStyle(.primary)
              .multilineTextAlignment(.center)
            Button("重试") {
              Task { await prepareLaunch() }
            }
            .buttonStyle(.borderedProminent)
            .tint(NativeTheme.brand)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
        }
        .padding(.horizontal, CinematicStyle.margin)
      } else {
        ProgressView("正在准备插件环境…")
          .tint(.primary)
      }
    }
    .task(
      id:
        "\(pluginID)|\(colorScheme)|\(AppLanguage.current.rawValue)|\(NativeAppearanceStore.hexString(from: appearance.accentColor))"
    ) {
      await prepareLaunch()
    }
  }

  private func prepareLaunch() async {
    loadError = nil
    isWebLoading = true
    do {
      let auth = try session.playbackAuthorization()
      let resourceCookie = try? await session.resolveResourceCookie()
      guard let targetURL = buildTargetURL(baseURL: auth.address.url) else {
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
      launchConfig = VuePluginLaunchConfig(
        url: targetURL,
        origin: auth.address,
        authJSON: authJSON,
        userJSON: userJSON,
        resourceCookie: resourceCookie,
        preferDark: preferDark,
        accentHex: accentHex,
        locale: locale,
        surface: surface)
    } catch {
      loadError = "当前登录会话不可用，无法打开 Vue 插件。"
    }
  }

  /// 基于 Vue Hash Router 构造同源插件入口：AppPage 直达 `/#/plugin-app/{id}/{navKey}`，数据/配置页直达 `/#/plugins?id={id}`。
  private func buildTargetURL(baseURL: URL) -> URL? {
    var baseString = baseURL.absoluteString
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
    guard let url = URL(string: baseString + hashPath),
      session.instance.address.contains(url)
    else { return nil }
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

  static func == (lhs: VuePluginLaunchConfig, rhs: VuePluginLaunchConfig) -> Bool {
    lhs.url == rhs.url && lhs.preferDark == rhs.preferDark && lhs.accentHex == rhs.accentHex
      && lhs.locale == rhs.locale && lhs.surface == rhs.surface
  }
}

/// 弱引用消息代理，避免 `WKUserContentController` 与 `Coordinator` 形成循环引用。
private final class WeakVueSheetScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: (any WKScriptMessageHandler)?
  init(_ target: any WKScriptMessageHandler) { self.target = target }
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}

/// 同源免登隔离 `WKWebView`：在首帧前写入 Pinia 会话与资源 Cookie；
/// 传入 `sheetBridge` 时采用 V1 风格弹窗接管，隔离最顶层 `.v-dialog` 并将标题/顶部按钮/关闭按钮投影到原生 Sheet 栏。
private struct NativeVuePluginWebView: UIViewRepresentable {
  let config: VuePluginLaunchConfig
  @Binding var isLoading: Bool
  let sheetBridge: NativeVueSheetBridge?

  func makeCoordinator() -> Coordinator {
    Coordinator(origin: config.origin, isLoading: $isLoading, sheetBridge: sheetBridge)
  }

  func makeUIView(context: Context) -> WKWebView {
    let wkConfig = WKWebViewConfiguration()
    wkConfig.websiteDataStore = .nonPersistent()
    wkConfig.allowsInlineMediaPlayback = true

    if sheetBridge != nil {
      wkConfig.userContentController.add(
        WeakVueSheetScriptHandler(context.coordinator), name: "mpVuePluginSheet")
    }

    let bootstrapScript = makeBootstrapScript(config, sheetTakeover: sheetBridge != nil)
    wkConfig.userContentController.addUserScript(
      WKUserScript(
        source: bootstrapScript,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true))

    let webView = WKWebView(frame: .zero, configuration: wkConfig)
    webView.navigationDelegate = context.coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.contentInsetAdjustmentBehavior = .automatic
    webView.overrideUserInterfaceStyle = config.preferDark ? .dark : .light
    sheetBridge?.webView = webView

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
    sheetBridge?.webView = uiView
  }

  static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
    uiView.configuration.userContentController.removeScriptMessageHandler(
      forName: "mpVuePluginSheet")
  }

  private func makeHTTPCookie(
    from info: APIExportedResourceCookie, targetURL: URL
  ) -> HTTPCookie? {
    var props: [HTTPCookiePropertyKey: Any] = [
      .name: info.name,
      .value: info.value,
      .domain: info.domain.isEmpty ? (targetURL.host ?? "") : info.domain,
      .path: info.path.isEmpty ? "/" : info.path,
    ]
    if info.isSecure || targetURL.scheme?.lowercased() == "https" {
      props[.secure] = "TRUE"
    }
    return HTTPCookie(properties: props)
  }

  /// 构造首帧前注入脚本：同步登录态、语言（`MP_LOCALE`）、主题与强调色以及 V1 风格 `.v-dialog` 隔离与顶栏投影。
  private func makeBootstrapScript(_ cfg: VuePluginLaunchConfig, sheetTakeover: Bool) -> String {
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
    let wantsConfigSwitch = (cfg.surface == .config) ? "true" : "false"
    let isSheetTakeover = sheetTakeover ? "true" : "false"

    return """
      (function() {
        try {
          window.localStorage.setItem('auth', \(authLiteral));
          window.localStorage.setItem('user', \(userLiteral));
          window.localStorage.setItem('MP_LOCALE', \(localeLiteral));
          window.localStorage.setItem('theme', '\(themeName)');
          window.localStorage.setItem('materio-initial-resolved-theme', '\(themeName)');
          window.localStorage.setItem('materio-initial-loader-color', \(accentLiteral));
          window.localStorage.setItem('moviepilot-theme-customizer', \(customizerLiteral));
        } catch (e) {}

        var isSheetTakeover = \(isSheetTakeover);
        var wantsConfigSwitch = \(wantsConfigSwitch);

        function applyNativePluginChrome() {
          try {
            var root = document.documentElement;
            if (!root) return;
            root.lang = \(localeLiteral);
            root.dataset.nativeChrome = 'active';
            if (isSheetTakeover) {
              root.dataset.nativeSheet = 'active';
            }
            root.style.setProperty('--native-top', '0px');
            root.style.setProperty('--native-bottom', '0px');
            root.style.setProperty('--native-left', '0px');
            root.style.setProperty('--native-right', '0px');

            if (!document.getElementById('mp-native-vue-plugin-style')) {
              var style = document.createElement('style');
              style.id = 'mp-native-vue-plugin-style';
              var rules = [
                '.layout-navbar, .layout-vertical-nav, .layout-overlay, .layout-footer,',
                '.footer-content-container, .mobile-dock, .v-bottom-navigation,',
                '.app-customizer-toggler, .agent-pet-container, .floating-agent-btn,',
                '[data-native-page-title], [data-native-page-heading], [data-native-page-actions] {',
                '  display: none !important;',
                '}',
                '.layout-content-wrapper { padding-inline-start: 0 !important; }',
                '.layout-page-content { padding-block-start: 8px !important; padding-block-end: 12px !important; }'
              ];
              if (isSheetTakeover) {
                rules.push(
                  'html[data-native-sheet="active"] body { overflow: hidden !important; background: transparent !important; }',
                  'html[data-native-sheet="active"] #app { visibility: hidden !important; pointer-events: none !important; }',
                  '[data-native-sheet-background="true"] { visibility: hidden !important; pointer-events: none !important; }',
                  '[data-native-sheet-current="true"] { position: fixed !important; inset: 0 !important; visibility: visible !important; pointer-events: auto !important; }',
                  '[data-native-sheet-current="true"] > .v-overlay__scrim { display: none !important; }',
                  '[data-native-sheet-current="true"] > .v-overlay__content {',
                  '  margin: 0 !important; padding: 0 !important; inset: 0 !important;',
                  '  width: 100vw !important; max-width: 100vw !important;',
                  '  height: 100dvh !important; max-height: 100dvh !important;',
                  '  border-radius: 0 !important; box-shadow: none !important; transform: none !important;',
                  '}',
                  '[data-native-sheet-current="true"] > .v-overlay__content > .v-card,',
                  '[data-native-sheet-current="true"] > .v-overlay__content > .v-sheet {',
                  '  border-radius: 0 !important; box-shadow: none !important;',
                  '  min-height: 100dvh !important; max-height: 100dvh !important;',
                  '  display: flex !important; flex-direction: column !important;',
                  '}',
                  '[data-native-sheet-current="true"] > .v-overlay__content > .v-card > .v-card-text {',
                  '  flex: 1 1 auto !important; overflow-y: auto !important; -webkit-overflow-scrolling: touch;',
                  '}',
                  '[data-native-sheet-current="true"] [data-native-sheet-header="true"],',
                  '[data-native-sheet-current="true"] [data-native-sheet-heading="true"],',
                  '[data-native-sheet-current="true"] [data-native-dialog-close],',
                  '[data-native-sheet-current="true"] .v-dialog-close-btn {',
                  '  display: none !important;',
                  '}'
                );
              }
              style.textContent = rules.join('\\n');
              (document.head || root).appendChild(style);
            }
          } catch (e) {}
        }

        applyNativePluginChrome();
        document.addEventListener('DOMContentLoaded', applyNativePluginChrome, { once: true });

        if (!isSheetTakeover) { return; }

        function postSheetMessage(payload) {
          try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mpVuePluginSheet) {
              window.webkit.messageHandlers.mpVuePluginSheet.postMessage(payload);
            }
          } catch (e) {}
        }

        function extractMdiIcon(el) {
          var iconEl = el.querySelector('[class*="mdi-"]') || (el.className && String(el.className).indexOf('mdi-') >= 0 ? el : null);
          if (!iconEl) return '';
          var cls = String(iconEl.className || '');
          var m = cls.match(/mdi-[a-z0-9-]+/i);
          return m ? m[0] : '';
        }

        function isCloseButton(btn) {
          if (btn.hasAttribute('data-native-dialog-close') || btn.classList.contains('v-dialog-close-btn')) return true;
          var icon = extractMdiIcon(btn).toLowerCase();
          if (icon === 'mdi-close' || icon === 'mdi-close-circle' || icon === 'mdi-close-circle-outline') return true;
          var text = (btn.textContent || '').trim();
          var aria = (btn.getAttribute('aria-label') || '').trim();
          return text === '关闭' || text === 'Close' || aria === '关闭' || aria === 'Close';
        }

        var hadActiveDialog = false;
        var switchedToConfig = false;
        var configSwitchAttempts = 0;
        var lastSignature = '';
        var scheduled = false;

        window.__mpNativeSheetInvoke = function(actionId) {
          var target = document.querySelector('[data-mp-sheet-action-id="' + actionId + '"]');
          if (target) { target.click(); }
        };

        window.__mpNativeSheetDismiss = function() {
          var current = document.querySelector('[data-native-sheet-current="true"]');
          if (!current) return;
          var closeEl = current.querySelector('[data-native-dialog-close], .v-dialog-close-btn');
          if (!closeEl) {
            var btns = current.querySelectorAll('button, .v-btn');
            for (var i = 0; i < btns.length; i++) {
              if (isCloseButton(btns[i])) { closeEl = btns[i]; break; }
            }
          }
          if (closeEl) { closeEl.click(); }
        };

        function syncNativeSheet() {
          scheduled = false;
          var dialogs = Array.prototype.slice.call(
            document.querySelectorAll('.v-overlay--active.v-dialog')
          );

          var allOverlays = document.querySelectorAll('.v-overlay');
          for (var k = 0; k < allOverlays.length; k++) {
            allOverlays[k].removeAttribute('data-native-sheet-current');
            allOverlays[k].removeAttribute('data-native-sheet-background');
          }

          if (dialogs.length === 0) {
            if (hadActiveDialog) {
              hadActiveDialog = false;
              postSheetMessage({ type: 'sheet.closed' });
            }
            return;
          }

          dialogs.sort(function(a, b) {
            var za = parseInt(getComputedStyle(a).zIndex || '0', 10) || 0;
            var zb = parseInt(getComputedStyle(b).zIndex || '0', 10) || 0;
            return za - zb;
          });
          var topDialog = dialogs[dialogs.length - 1];
          for (var j = 0; j < dialogs.length - 1; j++) {
            dialogs[j].setAttribute('data-native-sheet-background', 'true');
          }
          topDialog.setAttribute('data-native-sheet-current', 'true');
          hadActiveDialog = true;

          // 如果目标是配置弹窗而前端默认先打开了数据弹窗，则自动触发一次「设置/配置」按钮
          if (wantsConfigSwitch && !switchedToConfig && configSwitchAttempts < 12) {
            configSwitchAttempts++;
            var allBtns = topDialog.querySelectorAll('button, .v-btn');
            for (var bi = 0; bi < allBtns.length; bi++) {
              var b = allBtns[bi];
              var txt = (b.textContent || '').trim();
              var ico = extractMdiIcon(b).toLowerCase();
              if (ico === 'mdi-cog' || ico === 'mdi-cog-outline' || ico === 'mdi-tune' || txt === '设置' || txt === '配置') {
                switchedToConfig = true;
                b.click();
                return;
              }
            }
          }

          var card = topDialog.querySelector('.v-overlay__content > .v-card, .v-overlay__content > .v-sheet') || topDialog;
          var headerEl = card.querySelector('[data-native-sheet-header]')
            || card.querySelector(':scope > .v-toolbar')
            || card.querySelector(':scope > .v-card-item')
            || card.querySelector(':scope > .v-card-title');

          var titleText = '';
          var actions = [];
          if (headerEl) {
            headerEl.setAttribute('data-native-sheet-header', 'true');
            var headingEl = headerEl.querySelector('[data-native-sheet-heading], .v-toolbar-title, .v-card-title, h1, h2, h3, h4, span');
            if (headingEl) {
              var clone = headingEl.cloneNode(true);
              var junk = clone.querySelectorAll('button, .v-btn, .v-icon, svg');
              for (var ji = 0; ji < junk.length; ji++) junk[ji].remove();
              titleText = (clone.textContent || '').replace(/\\s+/g, ' ').trim();
            }
            if (!titleText) {
              var hClone = headerEl.cloneNode(true);
              var hJunk = hClone.querySelectorAll('button, .v-btn, .v-icon, svg');
              for (var hi = 0; hi < hJunk.length; hi++) hJunk[hi].remove();
              titleText = (hClone.textContent || '').replace(/\\s+/g, ' ').trim();
            }

            var headerBtns = headerEl.querySelectorAll('button, .v-btn');
            var actionIdx = 0;
            for (var i = 0; i < headerBtns.length; i++) {
              var btn = headerBtns[i];
              if (btn.hidden || getComputedStyle(btn).display === 'none') continue;
              if (isCloseButton(btn)) continue;
              var actionId = 'mp_act_' + actionIdx++;
              btn.setAttribute('data-mp-sheet-action-id', actionId);
              var iconName = extractMdiIcon(btn);
              var btnTitle = (btn.getAttribute('aria-label') || btn.getAttribute('title') || btn.textContent || '').replace(/\\s+/g, ' ').trim();
              if (!btnTitle) {
                if (iconName.indexOf('cog') >= 0 || iconName.indexOf('tune') >= 0) btnTitle = '设置';
                else if (iconName.indexOf('refresh') >= 0 || iconName.indexOf('sync') >= 0) btnTitle = '刷新';
                else if (iconName.indexOf('save') >= 0) btnTitle = '保存';
                else btnTitle = '操作';
              }
              var disabled = btn.disabled || btn.getAttribute('aria-disabled') === 'true' || btn.classList.contains('v-btn--disabled');
              actions.push({ id: actionId, title: btnTitle, icon: iconName, enabled: !disabled });
            }
          }

          var signature = JSON.stringify({ title: titleText, actions: actions });
          if (signature !== lastSignature) {
            lastSignature = signature;
            postSheetMessage({
              type: 'sheet.state',
              ready: true,
              title: titleText,
              actions: actions
            });
          }
        }

        function scheduleSync() {
          if (scheduled) return;
          scheduled = true;
          requestAnimationFrame(syncNativeSheet);
        }

        var observer = new MutationObserver(scheduleSync);
        function startObserver() {
          if (document.body) {
            observer.observe(document.body, {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: ['class', 'style', 'disabled', 'aria-disabled', 'hidden']
            });
            scheduleSync();
          }
        }
        if (document.body) {
          startObserver();
        } else {
          document.addEventListener('DOMContentLoaded', startObserver, { once: true });
        }
        // 安全兜底：即使插件未使用 .v-dialog 渲染，6 秒后也展示内容避免永久白屏
        setTimeout(function() {
          if (!hadActiveDialog) {
            postSheetMessage({ type: 'sheet.state', ready: true, title: '', actions: [] });
          }
        }, 6000);
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

  /// 严格拦截跨域主文档导航（外链交由系统 Safari 打开，同源导航放行），并接收 Sheet 接管消息。
  final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let origin: ServerAddress
    @Binding var isLoading: Bool
    weak var sheetBridge: NativeVueSheetBridge?

    init(
      origin: ServerAddress,
      isLoading: Binding<Bool>,
      sheetBridge: NativeVueSheetBridge?
    ) {
      self.origin = origin
      _isLoading = isLoading
      self.sheetBridge = sheetBridge
    }

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      guard message.name == "mpVuePluginSheet",
        let body = message.body as? [String: Any],
        let type = body["type"] as? String
      else { return }
      DispatchQueue.main.async { [weak self] in
        guard let bridge = self?.sheetBridge else { return }
        if type == "sheet.closed" {
          bridge.shouldDismiss = true
          return
        }
        if type == "sheet.state" {
          if let title = body["title"] as? String, !title.isEmpty {
            bridge.title = title
          }
          if let rawActions = body["actions"] as? [[String: Any]] {
            bridge.actions = rawActions.compactMap { dict in
              guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
              let title = (dict["title"] as? String) ?? "操作"
              let icon = dict["icon"] as? String
              let enabled = (dict["enabled"] as? Bool) ?? true
              return NativeVueSheetAction(id: id, title: title, icon: icon, enabled: enabled)
            }
          }
          if (body["ready"] as? Bool) == true {
            bridge.isReady = true
            self?.isLoading = false
          }
        }
      }
    }

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
      if sheetBridge == nil {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          self.isLoading = false
        }
      }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      DispatchQueue.main.async {
        self.isLoading = false
        self.sheetBridge?.isReady = true
      }
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

/// 有界解码的插件 UI 节点。
struct NativePluginJSONNode: Identifiable, Sendable {
  let id: String
  let component: String
  let text: String
  let html: String
  let props: [String: JSONValue]
  let events: [String: JSONValue]
  let children: [NativePluginJSONNode]

  /// 有界递归解析插件 JSON 数组（深度上限 24、节点总数上限 2000）。
  static func parseArray(_ raw: [JSONValue], depth: Int, budget: inout Int)
    -> [NativePluginJSONNode]
  {
    guard depth < 24, budget > 0 else { return [] }
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

  /// 文本展示优先级：`text` -> 剥离 HTML 标签后的 `html` / `props.innerHTML`。
  var displayText: String {
    if !text.isEmpty { return text }
    if !html.isEmpty { return Self.stripHTML(html) }
    if let inner = props["innerHTML"]?.stringValue, !inner.isEmpty {
      return Self.stripHTML(inner)
    }
    return ""
  }

  /// 聚合当前节点及后代纯文本，用于标题、徽标和表格单元格展示。
  var combinedText: String {
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

  /// 从 `VTable` / `VDataTable` / `VDataTableVirtual` 提取表头与行数据。
  func extractTable() -> (headers: [String], rows: [[String]]) {
    if let rawHeaders = props["headers"]?.arrayValue,
      let rawItems = props["items"]?.arrayValue
    {
      let cols: [(title: String, key: String)] = rawHeaders.compactMap { item in
        guard let obj = item.objectValue else { return nil }
        let key = obj["key"]?.stringValue ?? obj["value"]?.stringValue ?? ""
        let title = obj["title"]?.stringValue ?? obj["text"]?.stringValue ?? key
        return key.isEmpty ? nil : (title, key)
      }
      let rows: [[String]] = rawItems.compactMap { row in
        guard let obj = row.objectValue else { return nil }
        return cols.map { Self.formatCell(obj[$0.key]) }
      }
      return (cols.map(\.title), rows)
    }
    var headers: [String] = []
    var rows: [[String]] = []
    func walk(_ node: NativePluginJSONNode, inHead: Bool) {
      let name = node.component.lowercased()
      if name == "thead" {
        for c in node.children { walk(c, inHead: true) }
      } else if name == "tbody" {
        for c in node.children { walk(c, inHead: false) }
      } else if name == "tr" {
        let cells = node.children.map(\.combinedText)
        if inHead || node.children.allSatisfy({ $0.component.lowercased() == "th" }) {
          if headers.isEmpty { headers = cells }
        } else if !cells.isEmpty {
          rows.append(cells)
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
