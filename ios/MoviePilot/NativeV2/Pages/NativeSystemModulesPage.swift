import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生系统专项设置页：覆盖目录存储、下载器与媒体服务器、通知渠道、过滤规则与识别词、刮削开关保存及网络连通性诊断，仅展示脱敏配置。
@MainActor
struct NativeSystemModulesPage: View {
  /// 八类设置对应的原生专项分区。
  enum Domain: String, CaseIterable, Identifiable {
    case siteScope = "站点范围"
    case directories = "目录与存储"
    case services = "下载与媒体服务"
    case notifications = "通知渠道"
    case rules = "规则与识别词"
    case scraping = "刮削开关"
    case nettest = "网络诊断"

    /// 稳定分区标识。
    var id: String { rawValue }

    /// SF Symbol 图标。
    var symbol: String {
      switch self {
      case .siteScope: "checklist"
      case .directories: "folder.badge.gearshape"
      case .services: "server.rack"
      case .notifications: "bell.badge"
      case .rules: "line.3.horizontal.decrease.circle"
      case .scraping: "sparkles.rectangle.stack"
      case .nettest: "network"
      }
    }
  }

  /// 站点范围切换：搜索站点（`IndexerSites`）与订阅站点（`RssSites`）。
  private enum SiteScopeKind: String, CaseIterable, Identifiable {
    case search = "搜索站点"
    case subscribe = "订阅站点"
    var id: String { rawValue }
    var settingKey: String { self == .search ? "IndexerSites" : "RssSites" }
  }

  let session: NativeSession
  let initialDomain: Domain

  @State private var domain: Domain
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0

  @State private var allSites: [NativeSiteScopeOption] = []
  @State private var siteScopeKind: SiteScopeKind = .search
  @State private var selectedSearchSites: Set<Int> = []
  @State private var originalSearchSites: Set<Int> = []
  @State private var selectedSubscribeSites: Set<Int> = []
  @State private var originalSubscribeSites: Set<Int> = []
  @State private var isSavingSiteScope = false
  @State private var directories: [NativeDirectoryConfig] = []
  @State private var storages: [NativeStorageConfig] = []
  @State private var downloaders: [NativeServiceConfig] = []
  @State private var mediaservers: [NativeServiceConfig] = []
  @State private var notifications: [NativeNotificationConfig] = []
  @State private var ruleGroups: [NativeFilterRuleGroup] = []
  @State private var customIdentifiers: [String] = []
  @State private var scrapingSwitches: [String: Bool] = [:]
  @State private var originalScrapingSwitches: [String: Bool] = [:]
  @State private var isSavingScraping = false
  @State private var netTargets: [NativeNetTestTarget] = []
  @State private var netResults: [String: NativeNetTestResult] = [:]
  @State private var testingTargetID: String?
  @State private var isTestingAllNet = false
  @State private var feedback: String?

  /// 指定初始进入的设置分区。
  init(session: NativeSession, initialDomain: Domain = .directories) {
    self.session = session
    self.initialDomain = initialDomain
    _domain = State(initialValue: initialDomain)
  }

  /// 深色紫玫瑰渐变背景与当前专项配置玻璃卡片（由系统设置主菜单直接进入，不再展示横向一级跳转条）。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            CinematicPanel(padding: 10) {
              HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(NativeTheme.success)
                Text(feedback).font(.subheadline).foregroundStyle(.primary.opacity(0.88))
                Spacer(minLength: 0)
              }
            }
            .accessibilityIdentifier("native-sysmod-feedback")
          }
          contentSection
        }
        .frame(maxWidth: 840)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-sysmod-scroll")
    }
    .navigationTitle(domain.rawValue)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if domain == .siteScope {
          Button {
            Task { await saveSiteScopes() }
          } label: {
            if isSavingSiteScope {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Text("保存").fontWeight(.semibold)
            }
          }
          .disabled(!isSiteScopeDirty || isSavingSiteScope)
          .accessibilityIdentifier("native-sysmod-sitescope-save")
        } else if domain == .scraping {
          Button {
            Task { await saveScrapingSwitches() }
          } label: {
            if isSavingScraping {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Text("保存").fontWeight(.semibold)
            }
          }
          .disabled(scrapingSwitches == originalScrapingSwitches || isSavingScraping)
          .accessibilityIdentifier("native-sysmod-scraping-save")
        } else if domain == .nettest {
          Button {
            Task { await runAllNetTests() }
          } label: {
            if isTestingAllNet {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Text("测试全部").fontWeight(.semibold)
            }
          }
          .disabled(isTestingAllNet || netTargets.isEmpty)
          .accessibilityIdentifier("native-sysmod-nettest-all")
        }
      }
    }
    .task(id: "\(domain.rawValue)|\(reloadToken)") { await load() }
  }

  /// 当前分区的具体渲染内容。
  @ViewBuilder
  private var contentSection: some View {
    if isLoading {
      ProgressView("正在读取\(domain.rawValue)…")
        .tint(.primary)
        .frame(maxWidth: .infinity, minHeight: 200)
    } else if loadFailed {
      CinematicPanel {
        VStack(alignment: .leading, spacing: 10) {
          Label("暂时无法读取\(domain.rawValue)", systemImage: "exclamationmark.triangle").font(.headline)
          Button("重试") { reloadToken += 1 }
            .frame(minHeight: 44)
            .accessibilityIdentifier("native-sysmod-retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      switch domain {
      case .siteScope:
        siteScopeContent
      case .directories:
        directoriesContent
      case .services:
        servicesContent
      case .notifications:
        notificationsContent
      case .rules:
        rulesContent
      case .scraping:
        scrapingContent
      case .nettest:
        nettestContent
      }
    }
  }

  /// 订阅和搜索站点范围是否有未保存变更。
  private var isSiteScopeDirty: Bool {
    selectedSearchSites != originalSearchSites || selectedSubscribeSites != originalSubscribeSites
  }

  /// 当前编辑模式对应的已选站点集合。
  private var activeSiteScopeSelection: Set<Int> {
    siteScopeKind == .search ? selectedSearchSites : selectedSubscribeSites
  }

  /// 订阅与搜索站点范围可视化选择视图（`IndexerSites` + `RssSites`）。
  private var siteScopeContent: some View {
    let activeSites = allSites.filter(\.isActive)
    let selected = activeSiteScopeSelection
    return VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        ForEach(SiteScopeKind.allCases) { kind in
          let isCurrent = siteScopeKind == kind
          let count =
            kind == .search ? selectedSearchSites.count : selectedSubscribeSites.count
          Button {
            siteScopeKind = kind
          } label: {
            Text("\(kind.rawValue) (\(count))")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(isCurrent ? Color.white : NativeTheme.chipText)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background {
                Capsule()
                  .fill(
                    isCurrent
                      ? Color(red: 0.56, green: 0.40, blue: 0.88).opacity(0.80)
                      : NativeTheme.chipFill
                  )
                  .overlay {
                    Capsule().strokeBorder(
                      .white.opacity(isCurrent ? 0.30 : 0.14), lineWidth: 0.6)
                  }
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-sysmod-sitescope-\(kind.rawValue)")
        }
        Spacer(minLength: 0)
      }

      CinematicPanel(padding: 12) {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text(siteScopeKind == .search ? "搜索站点范围" : "订阅站点范围")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
            Text(
              selected.isEmpty
                ? "未勾选特定站点时默认覆盖全部已启用站点"
                : "已选择 \(selected.count) / \(activeSites.count) 个已启用站点"
            )
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.68))
          }
          Spacer(minLength: 6)
          Button("全选") {
            let allIDs = Set(activeSites.map(\.id))
            if siteScopeKind == .search {
              selectedSearchSites = allIDs
            } else {
              selectedSubscribeSites = allIDs
            }
          }
          .font(.caption.weight(.semibold))
          .foregroundStyle(NativeTheme.brand)
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-sysmod-sitescope-all")

          Button("清空") {
            if siteScopeKind == .search {
              selectedSearchSites.removeAll()
            } else {
              selectedSubscribeSites.removeAll()
            }
          }
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary.opacity(0.72))
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-sysmod-sitescope-clear")
        }
      }

      if activeSites.isEmpty {
        emptyCard("暂无已启用站点")
      } else {
        CinematicPanel(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(activeSites.enumerated()), id: \.element.id) { index, site in
              let isOn = Binding<Bool>(
                get: {
                  siteScopeKind == .search
                    ? selectedSearchSites.contains(site.id)
                    : selectedSubscribeSites.contains(site.id)
                },
                set: { newValue in
                  if siteScopeKind == .search {
                    if newValue {
                      selectedSearchSites.insert(site.id)
                    } else {
                      selectedSearchSites.remove(site.id)
                    }
                  } else {
                    if newValue {
                      selectedSubscribeSites.insert(site.id)
                    } else {
                      selectedSubscribeSites.remove(site.id)
                    }
                  }
                }
              )
              Toggle(isOn: isOn) {
                HStack(spacing: 10) {
                  NativeSiteIconView(session: session, siteID: site.id, size: 30, active: true)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                      .font(.subheadline.weight(.medium))
                      .foregroundStyle(.primary)
                    if !site.domain.isEmpty {
                      Text(site.domain)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.primary.opacity(0.55))
                    }
                  }
                }
              }
              .tint(Color(red: 0.62, green: 0.48, blue: 0.94))
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .accessibilityIdentifier("native-sysmod-sitescope-toggle-\(site.id)")
              if index < activeSites.count - 1 {
                Divider().overlay(.primary.opacity(0.08))
              }
            }
          }
        }
      }
    }
  }

  /// 目录与存储配置视图。
  private var directoriesContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("刮削策略", count: 0)
      CinematicPanel(padding: 0) {
        NavigationLink {
          NativeSystemModulesPage(session: session, initialDomain: .scraping)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(NativeTheme.brand)
              .frame(width: 28, height: 28)
              .background(NativeTheme.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
              Text("刮削开关").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
              Text("配置电影、剧集、音乐 NFO 与图片刮削").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
          }
          .padding(.horizontal, 14).padding(.vertical, 11)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }

      sectionHeader("已配置存储", count: storages.count)
      if storages.isEmpty {
        emptyCard("暂无存储配置")
      } else {
        ForEach(storages) { storage in
          CinematicPanel(padding: 13) {
            HStack(spacing: 12) {
              NativeBrandIcon(kind: .storage, type: storage.type, size: 38, cornerRadius: 10)
              VStack(alignment: .leading, spacing: 3) {
                Text(storage.name).font(.headline).foregroundStyle(.primary)
                Text(storage.type).font(.caption.monospaced()).foregroundStyle(
                  .primary.opacity(0.65))
              }
              Spacer()
              statusTag("已挂载", active: true)
            }
          }
        }
      }

      sectionHeader("下载与媒体库目录", count: directories.count)
      if directories.isEmpty {
        emptyCard("暂无目录映射配置")
      } else {
        ForEach(directories) { dir in
          CinematicPanel(padding: 13) {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(dir.displayName).font(.headline).foregroundStyle(.primary)
                Spacer()
                if !dir.transferLabel.isEmpty {
                  statusTag(dir.transferLabel, active: true)
                }
              }
              if let src = dir.downloadPath, !src.isEmpty {
                Label(src, systemImage: "arrow.down.doc")
                  .font(.caption.monospaced())
                  .foregroundStyle(.primary.opacity(0.76))
                  .lineLimit(2)
              }
              if let dst = dir.libraryPath, !dst.isEmpty {
                Label(dst, systemImage: "folder.fill")
                  .font(.caption.monospaced())
                  .foregroundStyle(NativeTheme.brand)
                  .lineLimit(2)
              }
              HStack(spacing: 8) {
                if let mediaType = dir.mediaType, !mediaType.isEmpty {
                  miniChip(mediaType)
                }
                if let category = dir.mediaCategory, !category.isEmpty {
                  miniChip(category)
                }
                if let monitor = dir.monitorType, !monitor.isEmpty {
                  miniChip("监控: \(monitor)")
                }
              }
            }
          }
        }
      }
    }
  }

  /// 下载器与媒体服务器视图（严格脱敏，不展示密钥/密码）。
  private var servicesContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("下载器", count: downloaders.count)
      if downloaders.isEmpty {
        emptyCard("暂无已配置下载器")
      } else {
        ForEach(downloaders) { item in
          serviceRowCard(item, iconKind: .downloader)
        }
      }

      sectionHeader("媒体服务器", count: mediaservers.count)
      if mediaservers.isEmpty {
        emptyCard("暂无已配置媒体服务器")
      } else {
        ForEach(mediaservers) { item in
          serviceRowCard(item, iconKind: .mediaServer)
        }
      }
    }
  }

  /// 单条服务脱敏卡片（显示真实下载器与媒体服务器品牌图标）。
  private func serviceRowCard(
    _ item: NativeServiceConfig, iconKind: NativeBrandIconKind
  ) -> some View {
    CinematicPanel(padding: 13) {
      HStack(spacing: 12) {
        NativeBrandIcon(kind: iconKind, type: item.type, size: 40, cornerRadius: 11)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(item.name).font(.headline).foregroundStyle(.primary)
            if item.isDefault {
              miniChip("默认")
            }
          }
          Text(item.type).font(.caption.monospaced()).foregroundStyle(.primary.opacity(0.66))
        }
        Spacer()
        statusTag(item.enabled ? "已启用" : "已停用", active: item.enabled)
      }
    }
  }

  /// 通知渠道视图（脱敏显示真实渠道品牌图标、名称、类型与订阅场景）。
  private var notificationsContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("通知渠道", count: notifications.count)
      if notifications.isEmpty {
        emptyCard("暂无已配置通知渠道")
      } else {
        ForEach(notifications) { item in
          CinematicPanel(padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 12) {
                NativeBrandIcon(kind: .notification, type: item.type, size: 40, cornerRadius: 11)
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.name).font(.headline).foregroundStyle(.primary)
                  Text(item.type).font(.caption.monospaced()).foregroundStyle(
                    .primary.opacity(0.66))
                }
                Spacer()
                statusTag(item.enabled ? "已启用" : "已停用", active: item.enabled)
              }
              if !item.switchs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 6) {
                    ForEach(item.switchs.prefix(6), id: \.self) { scene in
                      miniChip(scene)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  /// 过滤规则组与自定义识别词视图。
  private var rulesContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("优先级规则组", count: ruleGroups.count)
      if ruleGroups.isEmpty {
        emptyCard("暂无自定义过滤规则组")
      } else {
        ForEach(ruleGroups) { group in
          CinematicPanel(padding: 13) {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(group.name).font(.headline).foregroundStyle(.primary)
                Spacer()
                if let mediaType = group.mediaType, !mediaType.isEmpty {
                  miniChip(mediaType)
                }
              }
              if !group.ruleString.isEmpty {
                Text(group.ruleString)
                  .font(.caption.monospaced())
                  .foregroundStyle(.primary.opacity(0.76))
                  .lineLimit(3)
              }
            }
          }
        }
      }

      sectionHeader("自定义识别词", count: customIdentifiers.count)
      if customIdentifiers.isEmpty {
        emptyCard("暂无自定义识别词")
      } else {
        CinematicPanel(padding: 13) {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(customIdentifiers.prefix(30).enumerated()), id: \.offset) { idx, line in
              if idx > 0 { Divider().overlay(.primary.opacity(0.08)) }
              Text(line)
                .font(.caption.monospaced())
                .foregroundStyle(.primary.opacity(0.86))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
    }
  }

  /// 媒体刮削开关交互编辑视图（支持单次保存 `POST /api/v1/system/setting/ScrapingSwitchs`）。
  private var scrapingContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("刮削元数据开关", count: Self.scrapingLabels.count)
      CinematicPanel(padding: 14) {
        VStack(spacing: 12) {
          ForEach(Array(Self.scrapingLabels.enumerated()), id: \.element.key) { index, item in
            if index > 0 { Divider().overlay(.primary.opacity(0.08)) }
            Toggle(
              item.label,
              isOn: Binding(
                get: { scrapingSwitches[item.key] ?? true },
                set: { scrapingSwitches[item.key] = $0 }
              )
            )
            .font(.subheadline)
            .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
            .accessibilityIdentifier("native-sysmod-scrape-\(item.key)")
          }
        }
      }
    }
  }

  /// 网络连通性诊断视图（`GET /api/v1/system/nettest/targets` + 单目标测速）。
  private var nettestContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("网络连通性测试", count: netTargets.count)
      if netTargets.isEmpty {
        emptyCard("暂无可用网络测试目标")
      } else {
        ForEach(netTargets) { target in
          let result = netResults[target.id]
          let isTesting = testingTargetID == target.id
          CinematicPanel(padding: 13) {
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 3) {
                Text(target.name).font(.headline).foregroundStyle(.primary)
                Text(target.address)
                  .font(.caption.monospaced())
                  .foregroundStyle(.primary.opacity(0.64))
                  .lineLimit(1)
                if let result {
                  Text(result.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                      result.success
                        ? NativeTheme.success
                        : NativeTheme.danger)
                }
              }
              Spacer(minLength: 6)
              Button {
                Task { await runNetTest(target) }
              } label: {
                HStack(spacing: 4) {
                  if isTesting {
                    ProgressView().controlSize(.mini).tint(.primary)
                  } else {
                    Image(systemName: "bolt.horizontal.circle").font(.caption)
                  }
                  Text("测速").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                  Capsule()
                    .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.76))
                    .overlay { Capsule().strokeBorder(.primary.opacity(0.22), lineWidth: 0.6) }
                }
                .frame(minHeight: 34)
              }
              .buttonStyle(.plain)
              .disabled(testingTargetID != nil)
              .accessibilityIdentifier("native-sysmod-nettest-\(target.id)")
            }
          }
        }
      }
    }
  }

  private func sectionHeader(_ title: String, count: Int) -> some View {
    HStack {
      Text(title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.isHeader)
      Spacer()
      Text("\(count) 项")
        .font(.caption2)
        .foregroundStyle(.secondary.opacity(0.85))
    }
    .padding(.horizontal, 2)
  }

  private func statusTag(_ text: String, active: Bool) -> some View {
    let tint: Color = active ? Color(red: 0.48, green: 0.86, blue: 0.64) : .secondary
    return Text(text)
      .font(.caption2.weight(.medium))
      .foregroundStyle(tint)
      .padding(.horizontal, 7)
      .padding(.vertical, 2.5)
      .background {
        Capsule()
          .fill(.primary.opacity(0.07))
          .overlay { Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6) }
      }
  }

  private func miniChip(_ text: String) -> some View {
    Text(text)
      .font(.caption2.weight(.medium))
      .foregroundStyle(NativeTheme.brand)
      .padding(.horizontal, 7)
      .padding(.vertical, 2.5)
      .background { Capsule().fill(.primary.opacity(0.09)) }
  }

  private func emptyCard(_ text: String) -> some View {
    CinematicPanel {
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.primary.opacity(0.70))
        .frame(maxWidth: .infinity, minHeight: 80)
    }
  }

  /// 按当前分区并发读取后端 `GET /api/v1/system/setting/{key}` 或网络测试目标。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      switch domain {
      case .siteScope:
        let sitesEndpoint = try APIEndpoint(path: ["site"], trailingSlash: true)
        async let sitesTask = session.request(
          sitesEndpoint, as: [NativeSiteScopeOption].self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        async let indexerTask: [Int]? = readSetting("IndexerSites")
        async let rssTask: [Int]? = readSetting("RssSites")
        allSites = try await sitesTask
        let idx = Set(await indexerTask ?? [])
        let rss = Set(await rssTask ?? [])
        selectedSearchSites = idx
        originalSearchSites = idx
        selectedSubscribeSites = rss
        originalSubscribeSites = rss
      case .directories:
        async let dirsTask: [NativeDirectoryConfig]? = readSetting("Directories")
        async let storTask: [NativeStorageConfig]? = readSetting("Storages")
        directories = await dirsTask ?? []
        storages = await storTask ?? []
      case .services:
        async let dlTask: [NativeServiceConfig]? = readSetting("Downloaders")
        async let msTask: [NativeServiceConfig]? = readSetting("MediaServers")
        downloaders = await dlTask ?? []
        mediaservers = await msTask ?? []
      case .notifications:
        notifications = await readSetting("Notifications") ?? []
      case .rules:
        async let grpTask: [NativeFilterRuleGroup]? = readSetting("UserFilterRuleGroups")
        async let idTask: [String]? = readSetting("CustomIdentifiers")
        ruleGroups = await grpTask ?? []
        customIdentifiers = await idTask ?? []
      case .scraping:
        let raw: [String: Bool] = await readSetting("ScrapingSwitchs") ?? [:]
        var merged: [String: Bool] = [:]
        for item in Self.scrapingLabels {
          merged[item.key] = raw[item.key] ?? true
        }
        scrapingSwitches = merged
        originalScrapingSwitches = merged
      case .nettest:
        let endpoint = try APIEndpoint(path: ["system", "nettest", "targets"])
        netTargets = try await session.request(
          endpoint, as: [NativeNetTestTarget].self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        if netResults.isEmpty && !netTargets.isEmpty {
          isLoading = false
          await runAllNetTests()
        }
      }
      try Task.checkCancellation()
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 读取单键系统配置并解包 `{value: T}`。
  private func readSetting<T: Decodable & Sendable>(_ key: String) async -> T? {
    do {
      let endpoint = try APIEndpoint(path: ["system", "setting", key])
      let wrapper = try await session.request(
        endpoint, as: NativeSettingValueWrapper<T>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      return wrapper.value
    } catch {
      return nil
    }
  }

  /// 单次保存搜索站点范围（`IndexerSites`）与订阅站点范围（`RssSites`）。
  private func saveSiteScopes() async {
    guard !isSavingSiteScope else { return }
    isSavingSiteScope = true
    defer { isSavingSiteScope = false }
    do {
      if selectedSearchSites != originalSearchSites {
        let body = try JSONEncoder().encode(selectedSearchSites.sorted())
        let ep = try APIEndpoint(
          path: ["system", "setting", "IndexerSites"], method: .post, body: body)
        try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
        originalSearchSites = selectedSearchSites
      }
      if selectedSubscribeSites != originalSubscribeSites {
        let body = try JSONEncoder().encode(selectedSubscribeSites.sorted())
        let ep = try APIEndpoint(
          path: ["system", "setting", "RssSites"], method: .post, body: body)
        try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
        originalSubscribeSites = selectedSubscribeSites
      }
      try Task.checkCancellation()
      feedback = "搜索与订阅站点范围已保存。"
    } catch is CancellationError {
      return
    } catch {
      feedback = "保存站点范围失败，请稍后重试。"
    }
  }

  /// 单次保存刮削开关配置至 `POST /api/v1/system/setting/ScrapingSwitchs`。
  private func saveScrapingSwitches() async {
    guard !isSavingScraping else { return }
    isSavingScraping = true
    defer { isSavingScraping = false }
    do {
      let body = try JSONEncoder().encode(scrapingSwitches)
      let endpoint = try APIEndpoint(
        path: ["system", "setting", "ScrapingSwitchs"], method: .post, body: body)
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      originalScrapingSwitches = scrapingSwitches
      feedback = "刮削开关配置已保存。"
    } catch is CancellationError {
      return
    } catch {
      feedback = "保存刮削开关失败，请稍后重试。"
    }
  }

  /// 顺序自动测试全部网络目标（用于页面加载完成及右上角「测试全部」）。
  private func runAllNetTests() async {
    guard !isTestingAllNet, !netTargets.isEmpty else { return }
    isTestingAllNet = true
    defer { isTestingAllNet = false }
    let snapshot = netTargets
    for target in snapshot {
      if Task.isCancelled { break }
      await runNetTest(target)
    }
  }

  /// 执行单个内置目标网络连通性测速。
  private func runNetTest(_ target: NativeNetTestTarget) async {
    testingTargetID = target.id
    defer { testingTargetID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["system", "nettest"],
        query: [URLQueryItem(name: "target_id", value: target.id)])
      let data = try await session.request(
        endpoint, as: NativeNetTestTimePayload.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      let ms = data.time.map { "\(Int($0.rounded())) ms" } ?? "连通正常"
      netResults[target.id] = NativeNetTestResult(success: true, summary: "连通正常 · \(ms)")
    } catch {
      netResults[target.id] = NativeNetTestResult(success: false, summary: "连接超时或不可达")
    }
  }

  private static let scrapingLabels: [(key: String, label: String)] = [
    ("movie_nfo", "电影 NFO 元数据"),
    ("movie_poster", "电影海报"),
    ("movie_backdrop", "电影背景图"),
    ("tv_nfo", "剧集 NFO 元数据"),
    ("tv_poster", "剧集海报"),
    ("tv_backdrop", "剧集背景图"),
    ("season_nfo", "分季 NFO 元数据"),
    ("episode_nfo", "分集 NFO 元数据"),
  ]
}

private struct NativeSettingValueWrapper<Value: Decodable & Sendable>: Decodable, Sendable {
  let value: Value?
}

private struct NativeDirectoryConfig: Decodable, Sendable, Identifiable {
  let name: String?
  let storage: String?
  let downloadPath: String?
  let libraryPath: String?
  let mediaType: String?
  let mediaCategory: String?
  let transferType: String?
  let monitorType: String?

  var id: String { "\(name ?? "")|\(downloadPath ?? "")|\(libraryPath ?? "")" }
  var displayName: String { (name?.isEmpty == false ? name : nil) ?? storage ?? "媒体目录" }
  var transferLabel: String {
    switch (transferType ?? "").lowercased() {
    case "link": "硬链接"
    case "softlink": "软链接"
    case "copy": "复制"
    case "move": "移动"
    default: transferType ?? ""
    }
  }

  private enum CodingKeys: String, CodingKey {
    case name, storage
    case downloadPath = "download_path"
    case libraryPath = "library_path"
    case mediaType = "media_type"
    case mediaCategory = "media_category"
    case transferType = "transfer_type"
    case monitorType = "monitor_type"
  }
}

private struct NativeStorageConfig: Decodable, Sendable, Identifiable {
  let name: String
  let type: String
  var id: String { "\(type)-\(name)" }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "存储"
    type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "local"
  }

  private enum CodingKeys: String, CodingKey { case name, type }
}

private struct NativeServiceConfig: Decodable, Sendable, Identifiable {
  let name: String
  let type: String
  let enabled: Bool
  let isDefault: Bool
  var id: String { "\(type)-\(name)" }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "服务"
    type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
    enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
    isDefault = (try? c.decodeIfPresent(Bool.self, forKey: .isDefault)) ?? false
  }

  private enum CodingKeys: String, CodingKey {
    case name, type, enabled
    case isDefault = "default"
  }
}

private struct NativeNotificationConfig: Decodable, Sendable, Identifiable {
  let name: String
  let type: String
  let enabled: Bool
  let switchs: [String]
  var id: String { "\(type)-\(name)" }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "通知渠道"
    type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
    enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
    switchs = (try? c.decodeIfPresent([String].self, forKey: .switchs)) ?? []
  }

  private enum CodingKeys: String, CodingKey { case name, type, enabled, switchs }
}

private struct NativeFilterRuleGroup: Decodable, Sendable, Identifiable {
  let name: String
  let ruleString: String
  let mediaType: String?
  var id: String { name }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "规则组"
    ruleString = (try? c.decodeIfPresent(String.self, forKey: .ruleString)) ?? ""
    mediaType = try? c.decodeIfPresent(String.self, forKey: .mediaType)
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case ruleString = "rule_string"
    case mediaType = "media_type"
  }
}

private struct NativeNetTestTarget: Decodable, Sendable, Identifiable {
  let id: String
  let name: String
  let address: String
}

private struct NativeNetTestTimePayload: Decodable, Sendable {
  let time: Double?
}

private struct NativeNetTestResult {
  let success: Bool
  let summary: String
}

/// 站点范围选择项轻量解码模型。
private struct NativeSiteScopeOption: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let domain: String
  let isActive: Bool

  private enum CodingKeys: String, CodingKey {
    case id, name, domain
    case isActive = "is_active"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(Int.self, forKey: .id)) ?? 0
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "站点 #\(id)"
    domain = (try? c.decodeIfPresent(String.self, forKey: .domain)) ?? ""
    isActive = (try? c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true
  }
}
