import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import WebKit

/// 原生插件数据页：直连 `GET /api/v1/plugin/page/{id}` 递归原生渲染 Vuetify JSON 节点与图表；仅对 Vue 远程组件插件提供显式受控 Web 兼容容器。
@MainActor
struct NativePluginDataPageView: View {
  let session: NativeSession
  let pluginID: String
  let pluginName: String

  @State private var renderMode = "vuetify"
  @State private var nodes: [NativePluginJSONNode] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var showsCompatWeb = false
  @State private var actionFeedback: String?

  /// 深色紫玫瑰渐变背景、原生 JSON 树渲染与受控兼容容器入口。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let actionFeedback {
            CinematicPanel(padding: 11) {
              HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(NativeTheme.success)
                Text(actionFeedback).font(.subheadline).foregroundStyle(.primary.opacity(0.92))
                Spacer(minLength: 0)
              }
            }
          }
          if isLoading && nodes.isEmpty && renderMode != "vue" {
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
          } else if renderMode.lowercased() == "vue" {
            vueCompatCard
          } else if nodes.isEmpty {
            CinematicPanel {
              VStack(spacing: 10) {
                Image(systemName: "doc.plaintext")
                  .font(.largeTitle)
                  .foregroundStyle(.primary.opacity(0.55))
                Text("当前插件暂无展示数据").font(.headline)
              }
              .frame(maxWidth: .infinity, minHeight: 160)
            }
          } else {
            NativePluginJSONRenderer(
              session: session,
              nodes: nodes,
              onTriggerAPI: { path in
                Task { await triggerPluginAPI(path) }
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
    .navigationTitle(pluginName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .sheet(isPresented: $showsCompatWeb) {
      NativePluginCompatSheet(session: session, pluginID: pluginID, pluginName: pluginName)
    }
    .task(id: reloadToken) { await load() }
  }

  /// Vue 远程组件插件的显式受控兼容容器引导卡，默认不创建任何 WebView。
  private var vueCompatCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: "puzzlepiece.extension.fill")
            .foregroundStyle(Color(red: 0.80, green: 0.68, blue: 1.0))
          Text("Vue 远程组件插件").font(.headline)
        }
        Text("「\(pluginName)」使用前端模块联邦远程组件渲染。你可在同源隔离的受控兼容容器中打开，主体页面仍保持全原生运行。")
          .font(.subheadline)
          .foregroundStyle(.primary.opacity(0.76))
        Button {
          showsCompatWeb = true
        } label: {
          Label("在受控兼容容器中打开", systemImage: "safari")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
              Capsule()
                .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.78))
                .overlay { Capsule().strokeBorder(.primary.opacity(0.24), lineWidth: 0.6) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-plugin-open-compat")
      }
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
      var budget = 1500
      nodes = NativePluginJSONNode.parseArray(envelope.page ?? [], depth: 0, budget: &budget)
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 执行插件节点声明的同源 API 动作并刷新页面。
  private func triggerPluginAPI(_ rawPath: String) async {
    let cleaned = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let segments = cleaned.split(separator: "/").map(String.init)
    guard !segments.isEmpty else { return }
    let apiSegments: [String]
    if segments.count >= 3, segments[0] == "api", segments[1] == "v1" {
      apiSegments = Array(segments.dropFirst(2))
    } else {
      apiSegments = segments
    }
    do {
      let endpoint = try APIEndpoint(path: apiSegments, method: .get)
      try await session.perform(endpoint)
      actionFeedback = "插件动作已执行。"
      reloadToken += 1
    } catch {
      actionFeedback = "插件动作执行失败，请稍后重试。"
    }
  }
}

/// 递归原生渲染 MoviePilot 插件 JSON 节点树与图表，供插件数据页与仪表板卡片共用。
@MainActor
struct NativePluginJSONRenderer: View {
  let session: NativeSession
  let nodes: [NativePluginJSONNode]
  var onTriggerAPI: ((String) -> Void)?

  /// 逐节点渲染当前层级的全部组件。
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(nodes) { node in
        renderNode(node)
      }
    }
  }

  /// 按 Vuetify 组件名映射至对应原生深色紫玫瑰玻璃视图。
  @ViewBuilder
  private func renderNode(_ node: NativePluginJSONNode) -> some View {
    let name = node.component.lowercased()
    switch name {
    case "style", "script":
      EmptyView()
    case "vspacer":
      Spacer(minLength: 4)
    case "vrow", "vwindow", "vwindowitem":
      VStack(alignment: .leading, spacing: 10) {
        if !node.text.isEmpty {
          Text(node.text).font(.subheadline).foregroundStyle(.primary.opacity(0.92))
        }
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
    case "vcol", "div", "span", "a", "p", "h1", "h2", "h3", "h4", "strong", "b":
      VStack(alignment: .leading, spacing: 6) {
        if !node.text.isEmpty {
          Text(node.text)
            .font(name.hasPrefix("h") ? .headline : .subheadline)
            .foregroundStyle(
              name == "a" ? NativeTheme.brand : Color.primary.opacity(0.90))
        }
        if !node.children.isEmpty {
          ForEach(node.children) { child in AnyView(renderNode(child)) }
        }
      }
    case "vcard":
      CinematicPanel(padding: 13) {
        VStack(alignment: .leading, spacing: 8) {
          if let title = node.stringProp("title"), !title.isEmpty {
            Text(title).font(.headline).foregroundStyle(.primary)
          }
          if let subtitle = node.stringProp("subtitle"), !subtitle.isEmpty {
            Text(subtitle).font(.caption).foregroundStyle(.primary.opacity(0.65))
          }
          if !node.text.isEmpty {
            Text(node.text).font(.subheadline).foregroundStyle(.primary.opacity(0.90))
          }
          ForEach(node.children) { child in AnyView(renderNode(child)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    case "vcardtitle":
      Text(node.combinedText)
        .font(.headline.weight(.bold))
        .foregroundStyle(.primary)
    case "vcardsubtitle":
      Text(node.combinedText)
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary.opacity(0.66))
    case "vcardtext":
      VStack(alignment: .leading, spacing: 8) {
        if !node.text.isEmpty {
          Text(node.text).font(.subheadline).foregroundStyle(.primary.opacity(0.88))
        }
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
    case "valert":
      alertView(node)
    case "vchip":
      Text(node.combinedText.isEmpty ? (node.stringProp("text") ?? "") : node.combinedText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Self.tintColor(node.stringProp("color")))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
          Capsule()
            .fill(.primary.opacity(0.11))
            .overlay {
              Capsule().strokeBorder(
                Self.tintColor(node.stringProp("color")).opacity(0.35), lineWidth: 0.6)
            }
        }
    case "vtable":
      tableView(node)
    case "vlist":
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
            AnyView(renderNode(child))
            if index < node.children.count - 1 {
              Divider().overlay(.primary.opacity(0.08))
            }
          }
        }
      }
    case "vlistitem":
      VStack(alignment: .leading, spacing: 4) {
        if let title = node.stringProp("title"), !title.isEmpty {
          Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        }
        if let subtitle = node.stringProp("subtitle"), !subtitle.isEmpty {
          Text(subtitle).font(.caption).foregroundStyle(.primary.opacity(0.66))
        }
        if !node.text.isEmpty {
          Text(node.text).font(.subheadline).foregroundStyle(.primary.opacity(0.90))
        }
        ForEach(node.children) { child in AnyView(renderNode(child)) }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
    case "vlistitemtitle":
      Text(node.combinedText).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
    case "vlistitemsubtitle":
      Text(node.combinedText).font(.caption).foregroundStyle(.primary.opacity(0.65))
    case "vprogresslinear":
      progressView(node)
    case "vimg", "img":
      imageView(node)
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
          .background { Circle().fill(.primary.opacity(0.14)) }
      }
    case "vapexchart":
      NativePluginApexChartView(props: node.props)
    case "vbtn":
      buttonView(node)
    default:
      if !node.text.isEmpty || !node.children.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          if !node.text.isEmpty {
            Text(node.text).font(.subheadline).foregroundStyle(.primary.opacity(0.88))
          }
          ForEach(node.children) { child in AnyView(renderNode(child)) }
        }
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
    let bodyText = node.stringProp("text") ?? node.combinedText
    return CinematicPanel(padding: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: symbol).foregroundStyle(tint)
        VStack(alignment: .leading, spacing: 4) {
          if let title = node.stringProp("title"), !title.isEmpty {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
          }
          if !bodyText.isEmpty {
            Text(bodyText).font(.caption).foregroundStyle(.primary.opacity(0.86))
          }
        }
        Spacer(minLength: 0)
      }
    }
  }

  /// 原生可横滑透色玻璃表格（解析 `thead/tbody/tr/th/td`）。
  private func tableView(_ node: NativePluginJSONNode) -> some View {
    let parsed = node.extractTable()
    return CinematicPanel(padding: 0) {
      if parsed.headers.isEmpty && parsed.rows.isEmpty {
        Text("暂无表格数据")
          .font(.caption)
          .foregroundStyle(.primary.opacity(0.60))
          .padding(14)
      } else {
        ScrollView(.horizontal) {
          VStack(alignment: .leading, spacing: 0) {
            if !parsed.headers.isEmpty {
              HStack(spacing: 12) {
                ForEach(Array(parsed.headers.enumerated()), id: \.offset) { _, header in
                  Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.76))
                    .frame(minWidth: 88, alignment: .leading)
                }
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .background(.white.opacity(0.06))
            }
            ForEach(Array(parsed.rows.enumerated()), id: \.offset) { rowIdx, row in
              Divider().overlay(.primary.opacity(0.08))
              HStack(spacing: 12) {
                ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                  Text(cell)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.92))
                    .frame(minWidth: 88, alignment: .leading)
                    .lineLimit(3)
                }
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 9)
              .background(rowIdx % 2 == 1 ? .white.opacity(0.03) : .clear)
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
    return GeometryReader { bar in
      ZStack(alignment: .leading) {
        Capsule().fill(.primary.opacity(0.14))
        Capsule()
          .fill(Color(red: 0.68, green: 0.52, blue: 0.96))
          .frame(width: max(bar.size.width * fraction, 4))
      }
    }
    .frame(height: 6)
  }

  /// 通过同源图片代理渲染插件图片，拒绝非法方案。
  @ViewBuilder
  private func imageView(_ node: NativePluginJSONNode) -> some View {
    if let src = node.stringProp("src"), !src.isEmpty {
      NativeMediaArtwork(session: session, reference: src, role: .poster, maximumWidth: 420)
        .frame(maxWidth: 260, minHeight: 120, maxHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  /// 按钮动作渲染（仅允许同源 API 动作，不执行任意 JS）。
  private func buttonView(_ node: NativePluginJSONNode) -> some View {
    let label = node.combinedText.isEmpty ? (node.stringProp("text") ?? "执行") : node.combinedText
    let apiPath = node.clickAPIPath
    return Button {
      if let apiPath { onTriggerAPI?(apiPath) }
    } label: {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
          Capsule()
            .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(apiPath == nil ? 0.35 : 0.75))
            .overlay { Capsule().strokeBorder(.primary.opacity(0.22), lineWidth: 0.6) }
        }
    }
    .buttonStyle(.plain)
    .disabled(apiPath == nil)
  }

  /// 语义色彩映射到暗紫玫瑰柔和色板。
  private static func tintColor(_ raw: String?) -> Color {
    switch (raw ?? "").lowercased() {
    case "success", "green": NativeTheme.success
    case "warning", "orange", "amber": Color(red: 0.98, green: 0.78, blue: 0.44)
    case "error", "red": NativeTheme.danger
    case "primary", "purple": Color(red: 0.82, green: 0.70, blue: 1.0)
    default: Color(red: 0.66, green: 0.84, blue: 1.0)
    }
  }
}

/// 原生 SwiftUI `VApexChart` 渲染器：支持饼/环形图与柱状/折线系列，零 WebView 与 JS。
@MainActor
struct NativePluginApexChartView: View {
  let props: [String: JSONValue]

  /// 标题、原生环形图或横向柱状图及色点图例。
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
            .foregroundStyle(.primary.opacity(0.56))
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
                    .foregroundStyle(.primary.opacity(0.86))
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
                    .foregroundStyle(.primary.opacity(0.84))
                    .lineLimit(1)
                  Spacer()
                  Text(slice.formattedValue)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                }
                GeometryReader { bar in
                  ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
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

  /// 纯 SwiftUI 多段环形比例图。
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
      Circle().stroke(.white.opacity(0.10), lineWidth: 16)
      ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
        Circle()
          .trim(from: CGFloat(seg.start), to: CGFloat(seg.end))
          .stroke(seg.color, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
          .rotationEffect(.degrees(-90))
      }
      Text(String(format: "%.1f", total))
        .font(.caption.monospacedDigit().bold())
        .foregroundStyle(.primary.opacity(0.88))
    }
  }

  private static let palette: [Color] = [
    Color(red: 0.66, green: 0.50, blue: 0.96),
    Color(red: 0.92, green: 0.52, blue: 0.68),
    Color(red: 0.44, green: 0.84, blue: 0.72),
    Color(red: 0.52, green: 0.78, blue: 1.0),
    Color(red: 0.98, green: 0.76, blue: 0.44),
    Color(red: 0.80, green: 0.64, blue: 0.98),
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

/// 受控隔离的 Vue 远程插件兼容容器：仅在用户显式打开 `render_mode == "vue"` 插件时创建，锁死当前实例同源且使用非持久化数据存储。
@MainActor
private struct NativePluginCompatSheet: View {
  let session: NativeSession
  let pluginID: String
  let pluginName: String
  @Environment(\.dismiss) private var dismiss

  /// 同源兼容视图与顶部原生退出条。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        if let targetURL = resolvedURL {
          NativePluginCompatWebView(url: targetURL, origin: session.instance.address)
            .ignoresSafeArea(edges: .bottom)
        } else {
          Text("无法构造受控插件兼容地址").foregroundStyle(.primary)
        }
      }
      .navigationTitle("\(pluginName)（兼容）")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityIdentifier("native-plugin-compat-close")
        }
      }
    }
    .nativeAppearanceRoot()
  }

  /// 严格基于当前实例同源地址构造受控插件兼容路径。
  private var resolvedURL: URL? {
    let url = session.instance.address.url
      .appendingPathComponent("plugins", isDirectory: false)
    guard session.instance.address.contains(url) else { return nil }
    return url
  }
}

/// 隔离非持久化 `WKWebView`，仅允许访问当前实例同源页面。
private struct NativePluginCompatWebView: UIViewRepresentable {
  let url: URL
  let origin: ServerAddress

  func makeCoordinator() -> Coordinator { Coordinator(origin: origin) }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = context.coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}

  /// 严格拦截跨域跳转，防止远程插件跳出当前实例边界。
  final class Coordinator: NSObject, WKNavigationDelegate {
    let origin: ServerAddress
    init(origin: ServerAddress) { self.origin = origin }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
      if let target = navigationAction.request.url, origin.contains(target) {
        decisionHandler(.allow)
      } else {
        decisionHandler(.cancel)
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

/// 有界解码的插件 UI 节点。
struct NativePluginJSONNode: Identifiable, Sendable {
  let id: String
  let component: String
  let text: String
  let props: [String: JSONValue]
  let events: [String: JSONValue]
  let children: [NativePluginJSONNode]

  /// 有界递归解析插件 JSON 数组（深度上限 24、节点总数上限 1500）。
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
          props: props,
          events: events,
          children: children
        ))
    }
    return output
  }

  /// 读取字符串属性。
  func stringProp(_ key: String) -> String? { props[key]?.stringValue }

  /// 读取数值属性。
  func doubleProp(_ key: String) -> Double? { props[key]?.numberValue }

  /// 聚合当前节点及后代纯文本，用于标题、徽标和表格单元格展示。
  var combinedText: String {
    var parts: [String] = []
    if !text.isEmpty { parts.append(text) }
    for child in children where !["style", "script"].contains(child.component.lowercased()) {
      let sub = child.combinedText
      if !sub.isEmpty { parts.append(sub) }
    }
    return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 提取 `events.click` 声明的同源 API 路径。
  var clickAPIPath: String? {
    guard let click = events["click"]?.objectValue else { return nil }
    return click["api"]?.stringValue ?? click["path"]?.stringValue
  }

  /// 从 `VTable` 子树提取表头与行数据。
  func extractTable() -> (headers: [String], rows: [[String]]) {
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
}

/// `JSONValue` 便捷读取扩展，供插件 JSON 节点解析使用。
extension JSONValue {
  /// 读取对象字典。
  fileprivate var objectValue: [String: JSONValue]? {
    if case .object(let dict) = self { return dict }
    return nil
  }

  /// 读取数组。
  fileprivate var arrayValue: [JSONValue]? {
    if case .array(let list) = self { return list }
    return nil
  }

  /// 读取字符串。
  fileprivate var stringValue: String? {
    if case .string(let text) = self { return text }
    return nil
  }

  /// 读取浮点数值。
  fileprivate var numberValue: Double? {
    if case .number(let num) = self { return num }
    return nil
  }
}
