import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotSession
import SwiftUI

/// 原生插件市场与生命周期管理页：支持市场检索/筛选/安装/更新与已安装插件的配置、重置和卸载，仅超级管理员可见。
@MainActor
struct NativePluginMarketPage: View {
  /// 顶部两大视图模式。
  enum Mode: String, CaseIterable, Identifiable {
    case market = "插件市场"
    case installed = "已安装管理"

    /// 稳定模式标识。
    var id: String { rawValue }
  }

  /// 市场子筛选。
  enum MarketFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case updatable = "可更新"
    case notInstalled = "未安装"

    /// 稳定筛选标识。
    var id: String { rawValue }
  }

  let session: NativeSession

  @State private var mode: Mode = .market
  @State private var marketFilter: MarketFilter = .all
  @State private var marketPlugins: [NativeMarketPluginRecord] = []
  @State private var installedPlugins: [NativeMarketPluginRecord] = []
  @State private var marketPage = 1
  @State private var marketHasMore = true
  @State private var isLoadingMore = false
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var mutatingID: String?
  @State private var pendingInstall: NativeMarketPluginRecord?
  @State private var pendingReset: NativeMarketPluginRecord?
  @State private var pendingUninstall: NativeMarketPluginRecord?
  @State private var feedback: NativePluginMarketFeedback?
  @State private var formSelection: FormSelection?

  /// 复用既有 `NativePluginFormView` 打开已安装插件配置。
  private struct FormSelection {
    let plugin: NativeInstalledPlugin
    let form: NativePluginForm
  }

  /// 连续紫玫瑰深色渐变、模式切换胶囊、筛选条与插件玻璃卡片列表。
  var body: some View {
    mainContent
      .navigationTitle(mode == .market ? "插件市场" : "插件管理")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .searchable(text: $searchText, prompt: "搜索插件名称、作者或标签")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            reloadToken += 1
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .accessibilityLabel("刷新插件列表")
          .accessibilityIdentifier("native-plugin-market-refresh")
        }
      }
      .navigationDestination(
        isPresented: Binding(
          get: { formSelection != nil }, set: { if !$0 { formSelection = nil } })
      ) {
        if let formSelection {
          NativePluginFormView(plugin: formSelection.plugin, form: formSelection.form)
        }
      }
      .task(id: "\(mode.rawValue)|\(reloadToken)") { await load(forceMarket: false) }
      .alert(
        pendingInstall?.hasUpdate == true ? "更新插件" : "安装插件",
        isPresented: Binding(
          get: { pendingInstall != nil }, set: { if !$0 { pendingInstall = nil } }),
        presenting: pendingInstall
      ) { plugin in
        Button(plugin.hasUpdate ? "确认更新" : "确认安装") {
          Task { await installPlugin(plugin) }
        }
        Button("取消", role: .cancel) {}
      } message: { plugin in
        Text("确认从插件仓库安装「\(plugin.displayName)」v\(plugin.version) 吗？")
      }
      .alert(
        "重置插件",
        isPresented: Binding(get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } }),
        presenting: pendingReset
      ) { plugin in
        Button("确认重置", role: .destructive) {
          Task { await resetPlugin(plugin) }
        }
        Button("取消", role: .cancel) {}
      } message: { plugin in
        Text("重置将清空「\(plugin.displayName)」的配置与本地数据，确认继续吗？")
      }
      .alert(
        "卸载插件",
        isPresented: Binding(
          get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
        presenting: pendingUninstall
      ) { plugin in
        Button("确认卸载", role: .destructive) {
          Task { await uninstallPlugin(plugin) }
        }
        Button("取消", role: .cancel) {}
      } message: { plugin in
        Text("确认卸载插件「\(plugin.displayName)」吗？卸载后将停止相关后台任务。")
      }
  }

  /// 主滚动内容区。
  private var mainContent: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          modeBar
          if mode == .market {
            marketFilterBar
          }
          if let feedback {
            feedbackBanner(feedback)
          }
          listSection
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load(forceMarket: mode == .market) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-plugin-market-scroll")
    }
  }

  /// 加载态、失败态、空态或插件卡片列表。
  @ViewBuilder
  private var listSection: some View {
    if isLoading && activeItems.isEmpty {
      ProgressView(mode == .market ? "正在载入插件市场…" : "正在载入已安装插件…")
        .tint(.white)
        .frame(maxWidth: .infinity, minHeight: 220)
    } else if loadFailed && activeItems.isEmpty {
      failureCard
    } else if filteredItems.isEmpty {
      emptyCard
    } else {
      LazyVStack(spacing: 12) {
        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, plugin in
          pluginCard(plugin)
            .onAppear {
              if mode == .market && marketHasMore && !isLoadingMore
                && index >= max(0, filteredItems.count - 8)
              {
                Task { await loadMoreMarket() }
              }
            }
        }
        if mode == .market && isLoadingMore {
          ProgressView().tint(.white).padding(.vertical, 10)
        }
      }
    }
  }

  /// 当前视图对应的全量插件数组。
  private var activeItems: [NativeMarketPluginRecord] {
    mode == .market ? marketPlugins : installedPlugins
  }

  /// 按筛选与关键词过滤后的插件列表。
  private var filteredItems: [NativeMarketPluginRecord] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return activeItems.filter { plugin in
      if mode == .market {
        switch marketFilter {
        case .all: break
        case .updatable: guard plugin.hasUpdate else { return false }
        case .notInstalled: guard !plugin.installed else { return false }
        }
      }
      guard !trimmed.isEmpty else { return true }
      return plugin.displayName.lowercased().contains(trimmed)
        || plugin.summary.lowercased().contains(trimmed)
        || plugin.author.lowercased().contains(trimmed)
        || plugin.labels.contains(where: { $0.lowercased().contains(trimmed) })
    }
  }

  /// 顶部模式切换胶囊。
  private var modeBar: some View {
    HStack(spacing: 8) {
      ForEach(Mode.allCases) { option in
        let active = mode == option
        Button {
          mode = option
        } label: {
          Text(option.rawValue)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? .white : .white.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
              Capsule()
                .fill(
                  active
                    ? Color(red: 0.58, green: 0.42, blue: 0.88).opacity(0.78)
                    : .white.opacity(0.08)
                )
                .overlay {
                  Capsule().strokeBorder(.white.opacity(active ? 0.32 : 0.14), lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-plugin-mode-\(option.rawValue)")
      }
      Spacer(minLength: 0)
    }
  }

  /// 插件市场状态过滤胶囊。
  private var marketFilterBar: some View {
    HStack(spacing: 8) {
      ForEach(MarketFilter.allCases) { option in
        let active = marketFilter == option
        Button {
          marketFilter = option
        } label: {
          Text(option.rawValue)
            .font(.caption.weight(active ? .semibold : .medium))
            .foregroundStyle(active ? .white : .white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
              Capsule()
                .fill(.white.opacity(active ? 0.20 : 0.08))
                .overlay {
                  Capsule().strokeBorder(.white.opacity(active ? 0.28 : 0.12), lineWidth: 0.6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-plugin-market-filter-\(option.rawValue)")
      }
      Spacer(minLength: 0)
    }
  }

  /// 单张插件透色玻璃卡片。
  private func pluginCard(_ plugin: NativeMarketPluginRecord) -> some View {
    let isMutating = mutatingID == plugin.id
    return CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(
                plugin.isRunning
                  ? Color(red: 0.48, green: 0.34, blue: 0.78).opacity(0.60)
                  : .white.opacity(0.11))
            Image(systemName: "puzzlepiece.extension.fill")
              .font(.title3.weight(.semibold))
              .foregroundStyle(.white.opacity(0.92))
          }
          .frame(width: 44, height: 44)

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Text(plugin.displayName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
              if !plugin.version.isEmpty {
                Text("v\(plugin.version)")
                  .font(.caption2.monospacedDigit().weight(.semibold))
                  .foregroundStyle(.white.opacity(0.72))
              }
              Spacer(minLength: 4)
              statusBadge(plugin)
            }
            if !plugin.summary.isEmpty {
              Text(plugin.summary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
            }
            HStack(spacing: 8) {
              if !plugin.author.isEmpty {
                Text(plugin.author)
                  .font(.caption2)
                  .foregroundStyle(.white.opacity(0.58))
              }
              if plugin.installCount > 0 {
                Label("\(plugin.installCount)", systemImage: "arrow.down.circle")
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.white.opacity(0.58))
              }
              ForEach(plugin.labels.prefix(3), id: \.self) { label in
                Text(label)
                  .font(.caption2)
                  .foregroundStyle(Color(red: 0.84, green: 0.74, blue: 1.0))
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background { Capsule().fill(.white.opacity(0.08)) }
              }
            }
          }
        }

        HStack(spacing: 8) {
          if mode == .market {
            if !plugin.installed || plugin.hasUpdate {
              Button {
                pendingInstall = plugin
              } label: {
                HStack(spacing: 5) {
                  if isMutating {
                    ProgressView().controlSize(.mini).tint(.white)
                  } else {
                    Image(
                      systemName: plugin.hasUpdate
                        ? "arrow.triangle.2.circlepath" : "arrow.down.to.line"
                    )
                    .font(.caption2.weight(.semibold))
                  }
                  Text(plugin.hasUpdate ? "更新" : "安装").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                  Capsule()
                    .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.75))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.6) }
                }
                .frame(minHeight: 32)
              }
              .buttonStyle(.plain)
              .disabled(mutatingID != nil)
              .accessibilityIdentifier("native-market-install-\(plugin.id)")
            }
          } else {
            if plugin.hasPage {
              NavigationLink {
                NativePluginDataPageView(
                  session: session, pluginID: plugin.id, pluginName: plugin.displayName)
              } label: {
                HStack(spacing: 4) {
                  Image(systemName: "doc.text.magnifyingglass").font(.caption2.weight(.semibold))
                  Text("数据页").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                  Capsule()
                    .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.75))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.6) }
                }
                .frame(minHeight: 32)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-installed-page-\(plugin.id)")
            }

            Button {
              openForm(for: plugin)
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3").font(.caption2.weight(.semibold))
                Text("配置").font(.caption.weight(.semibold))
              }
              .foregroundStyle(.white)
              .padding(.horizontal, 11)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(.white.opacity(0.14))
                  .overlay { Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.6) }
              }
              .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(mutatingID != nil)
            .accessibilityIdentifier("native-installed-config-\(plugin.id)")

            Button {
              pendingReset = plugin
            } label: {
              Text("重置")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                  Capsule()
                    .fill(.white.opacity(0.09))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6) }
                }
                .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(mutatingID != nil)
            .accessibilityIdentifier("native-installed-reset-\(plugin.id)")

            Button(role: .destructive) {
              pendingUninstall = plugin
            } label: {
              Image(systemName: "trash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.58))
                .frame(minWidth: 32, minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(mutatingID != nil)
            .accessibilityLabel("卸载 \(plugin.displayName)")
            .accessibilityIdentifier("native-installed-uninstall-\(plugin.id)")
          }
          Spacer()
        }
      }
    }
  }

  /// 插件安装/更新/运行状态徽标。
  @ViewBuilder
  private func statusBadge(_ plugin: NativeMarketPluginRecord) -> some View {
    if plugin.hasUpdate {
      badgePill("有更新", tint: Color(red: 0.98, green: 0.78, blue: 0.44))
    } else if mode == .market && plugin.installed {
      badgePill("已安装", tint: Color(red: 0.56, green: 0.92, blue: 0.72))
    } else if mode == .installed {
      badgePill(
        plugin.isRunning ? "运行中" : "未启用",
        tint: plugin.isRunning ? Color(red: 0.56, green: 0.92, blue: 0.72) : .white.opacity(0.58))
    }
  }

  /// 紧凑胶囊徽标。
  private func badgePill(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background {
        Capsule()
          .fill(.white.opacity(0.10))
          .overlay { Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6) }
      }
  }

  /// 操作反馈横幅。
  private func feedbackBanner(_ feedback: NativePluginMarketFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : Color(red: 0.56, green: 0.92, blue: 0.72))
        Text(feedback.message).font(.subheadline).foregroundStyle(.white.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65)).frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-plugin-market-feedback")
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "puzzlepiece.extension")
          .font(.largeTitle)
          .foregroundStyle(.white.opacity(0.55))
        Text("暂无匹配的插件").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 失败重试卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入插件列表", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { reloadToken += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-plugin-market-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 按模式读取 `GET /api/v1/plugin/?state=market|installed`；市场分页拉取每页 60 条提升首屏速度。
  private func load(forceMarket: Bool) async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    let stateValue = mode == .market ? "market" : "installed"
    var query = [URLQueryItem(name: "state", value: stateValue)]
    if mode == .market {
      marketPage = 1
      marketHasMore = true
      query.append(URLQueryItem(name: "page", value: "1"))
      query.append(URLQueryItem(name: "count", value: "60"))
      if forceMarket { query.append(URLQueryItem(name: "force", value: "true")) }
    }
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin"],
        query: query,
        maximumResponseBytes: 8 * 1024 * 1024,
        trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeMarketPluginRecord].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      try Task.checkCancellation()
      let valid = loaded.filter { !$0.id.isEmpty }
      if mode == .market {
        marketPlugins = valid
        marketHasMore = valid.count >= 60
      } else {
        installedPlugins = valid
      }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 滚动至市场底部时自动加载下一页插件。
  private func loadMoreMarket() async {
    guard mode == .market, marketHasMore, !isLoadingMore, !isLoading else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    let nextPage = marketPage + 1
    let query = [
      URLQueryItem(name: "state", value: "market"),
      URLQueryItem(name: "page", value: String(nextPage)),
      URLQueryItem(name: "count", value: "60"),
    ]
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin"], query: query, maximumResponseBytes: 8 * 1024 * 1024, trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeMarketPluginRecord].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      try Task.checkCancellation()
      let valid = loaded.filter { !$0.id.isEmpty }
      if valid.isEmpty {
        marketHasMore = false
        return
      }
      var seen = Set(marketPlugins.map(\.id))
      let appended = valid.filter { seen.insert($0.id).inserted }
      marketPlugins.append(contentsOf: appended)
      marketPage = nextPage
      marketHasMore = valid.count >= 60 && !appended.isEmpty
    } catch {
      return
    }
  }

  /// 打开现有原生 JSON 插件配置表单。
  private func openForm(for record: NativeMarketPluginRecord) {
    do {
      let payload = try JSONEncoder().encode(record)
      let installed = try JSONDecoder().decode(NativeInstalledPlugin.self, from: payload)
      let form = try NativePluginForm(
        session: session, target: installed.target, validator: NativeFormValidator())
      formSelection = FormSelection(plugin: installed, form: form)
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "无法打开该插件的原生配置。")
    }
  }

  /// 单次请求安装或更新插件（`GET /api/v1/plugin/install/{id}`）。
  private func installPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    var query = [URLQueryItem(name: "force", value: "true")]
    if let repo = plugin.repoURL, !repo.isEmpty {
      query.append(URLQueryItem(name: "repo_url", value: repo))
    }
    do {
      let endpoint = try APIEndpoint(path: ["plugin", "install", plugin.id], query: query)
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      if let idx = marketPlugins.firstIndex(where: { $0.id == plugin.id }) {
        marketPlugins[idx].installed = true
        marketPlugins[idx].hasUpdate = false
      }
      feedback = NativePluginMarketFeedback(
        isError: false, message: "「\(plugin.displayName)」安装/更新已完成。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "安装插件失败，请检查仓库连通性后重试。")
    }
  }

  /// 确认后单次重置插件配置及数据（`GET /api/v1/plugin/reset/{id}`）。
  private func resetPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(path: ["plugin", "reset", plugin.id])
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      feedback = NativePluginMarketFeedback(isError: false, message: "已重置「\(plugin.displayName)」。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "重置插件失败，请稍后重试。")
    }
  }

  /// 确认后单次卸载插件（`DELETE /api/v1/plugin/{id}`）。
  private func uninstallPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(path: ["plugin", plugin.id], method: .delete)
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      installedPlugins.removeAll { $0.id == plugin.id }
      feedback = NativePluginMarketFeedback(isError: false, message: "已卸载「\(plugin.displayName)」。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "卸载插件失败，请先移除关联分身或稍后重试。")
    }
  }
}

/// 插件市场操作提示载体。
private struct NativePluginMarketFeedback {
  let isError: Bool
  let message: String
}

/// 插件市场与已安装插件统一编解码模型。
private struct NativeMarketPluginRecord: Codable, Sendable, Identifiable {
  let id: String
  let pluginName: String?
  let pluginDesc: String?
  let pluginVersion: String?
  let pluginLabel: String?
  let pluginAuthor: String?
  var installed: Bool
  var hasUpdate: Bool
  let hasPage: Bool
  let state: Bool?
  let repoURL: String?
  let installCount: Int

  /// 显示名称回退至插件 ID。
  var displayName: String {
    if let pluginName, !pluginName.isEmpty { return pluginName }
    return id
  }

  /// 插件简介。
  var summary: String { pluginDesc ?? "" }

  /// 插件版本。
  var version: String { pluginVersion ?? "" }

  /// 作者名。
  var author: String { pluginAuthor ?? "" }

  /// 运行状态。
  var isRunning: Bool { state ?? false }

  /// 拆分逗号分隔标签。
  var labels: [String] {
    (pluginLabel ?? "")
      .split(whereSeparator: { $0 == "," || $0 == "，" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// 解码后端 `_SchemaPlugin` 非敏感元数据。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
    pluginName = try? container.decodeIfPresent(String.self, forKey: .pluginName)
    pluginDesc = try? container.decodeIfPresent(String.self, forKey: .pluginDesc)
    pluginVersion = try? container.decodeIfPresent(String.self, forKey: .pluginVersion)
    pluginLabel = try? container.decodeIfPresent(String.self, forKey: .pluginLabel)
    pluginAuthor = try? container.decodeIfPresent(String.self, forKey: .pluginAuthor)
    installed = (try? container.decodeIfPresent(Bool.self, forKey: .installed)) ?? false
    hasUpdate = (try? container.decodeIfPresent(Bool.self, forKey: .hasUpdate)) ?? false
    hasPage = (try? container.decodeIfPresent(Bool.self, forKey: .hasPage)) ?? false
    state = try? container.decodeIfPresent(Bool.self, forKey: .state)
    repoURL = try? container.decodeIfPresent(String.self, forKey: .repoURL)
    installCount = (try? container.decodeIfPresent(Int.self, forKey: .installCount)) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case pluginName = "plugin_name"
    case pluginDesc = "plugin_desc"
    case pluginVersion = "plugin_version"
    case pluginLabel = "plugin_label"
    case pluginAuthor = "plugin_author"
    case installed
    case hasUpdate = "has_update"
    case hasPage = "has_page"
    case state
    case repoURL = "repo_url"
    case installCount = "install_count"
  }
}
