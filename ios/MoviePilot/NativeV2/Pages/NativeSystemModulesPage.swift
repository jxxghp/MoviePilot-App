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
  @State private var feedbackIsError = false
  @State private var editingNotificationIndex: Int?
  @State private var showsNotificationCreate = false
  @State private var pendingDeleteNotificationIndex: Int?
  @State private var editingDirectoryIndex: Int?
  @State private var showsDirectoryCreate = false
  @State private var pendingDeleteDirectoryIndex: Int?

  /// 指定初始进入的设置分区。
  init(session: NativeSession, initialDomain: Domain = .directories) {
    self.session = session
    self.initialDomain = initialDomain
    _domain = State(initialValue: initialDomain)
  }

  /// 深色紫玫瑰渐变背景与当前专项配置玻璃卡片（由系统设置主菜单直接进入，不再展示横向一级跳转条）。
  var body: some View {
    mainWithModals
  }

  private var mainWithModals: some View {
    basePage
      .sheet(isPresented: $showsNotificationCreate) {
        NativeNotificationEditorSheet(initial: nil) { created in
          Task { await saveNotification(created, replaceAt: nil) }
        }
      }
      .sheet(
        isPresented: Binding(
          get: { editingNotificationIndex != nil },
          set: { if !$0 { editingNotificationIndex = nil } })
      ) {
        if let idx = editingNotificationIndex, notifications.indices.contains(idx) {
          NativeNotificationEditorSheet(
            initial: notifications[idx],
            onDelete: {
              editingNotificationIndex = nil
              pendingDeleteNotificationIndex = idx
            }
          ) { updated in
            Task { await saveNotification(updated, replaceAt: idx) }
          }
        }
      }
      .sheet(isPresented: $showsDirectoryCreate) {
        NativeDirectoryEditorSheet(initial: nil, storages: storages) { created in
          Task { await saveDirectory(created, replaceAt: nil) }
        }
      }
      .sheet(
        isPresented: Binding(
          get: { editingDirectoryIndex != nil },
          set: { if !$0 { editingDirectoryIndex = nil } })
      ) {
        if let idx = editingDirectoryIndex, directories.indices.contains(idx) {
          NativeDirectoryEditorSheet(
            initial: directories[idx],
            storages: storages,
            onDelete: {
              editingDirectoryIndex = nil
              pendingDeleteDirectoryIndex = idx
            }
          ) { updated in
            Task { await saveDirectory(updated, replaceAt: idx) }
          }
        }
      }
      .alert(
        "删除通知渠道",
        isPresented: Binding(
          get: { pendingDeleteNotificationIndex != nil },
          set: { if !$0 { pendingDeleteNotificationIndex = nil } })
      ) {
        Button("删除", role: .destructive) {
          if let idx = pendingDeleteNotificationIndex, notifications.indices.contains(idx) {
            Task { await deleteNotification(at: idx) }
          }
        }
        Button("取消", role: .cancel) {}
      } message: {
        Text("确认删除该服务端通知渠道吗？")
      }
      .alert(
        "删除整理目录",
        isPresented: Binding(
          get: { pendingDeleteDirectoryIndex != nil },
          set: { if !$0 { pendingDeleteDirectoryIndex = nil } })
      ) {
        Button("删除", role: .destructive) {
          if let idx = pendingDeleteDirectoryIndex, directories.indices.contains(idx) {
            Task { await deleteDirectory(at: idx) }
          }
        }
        Button("取消", role: .cancel) {}
      } message: {
        Text("确认删除该整理目录配置吗？")
      }
  }

  private var basePage: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let feedback {
            CinematicPanel(padding: 12) {
              HStack(spacing: 8) {
                Image(
                  systemName: feedbackIsError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedbackIsError ? NativeTheme.warning : NativeTheme.success)
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
        .padding(.vertical, 16)
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
        Group {
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
          } else if domain == .notifications {
            Button {
              showsNotificationCreate = true
            } label: {
              Image(systemName: "plus")
            }
            .accessibilityLabel("新增通知渠道")
            .accessibilityIdentifier("native-sysmod-notification-add")
          } else if domain == .directories {
            Button {
              showsDirectoryCreate = true
            } label: {
              Image(systemName: "plus")
            }
            .accessibilityLabel("新增整理目录")
            .accessibilityIdentifier("native-sysmod-directory-add")
          }
        }
        .tint(.primary)
      }
    }
    .task(id: "\(domain.rawValue)|\(reloadToken)") { await load() }
  }

  /// 当前分区的具体渲染内容。
  @ViewBuilder
  private var contentSection: some View {
    if isLoading {
      NativeCardListSkeletonView(count: 4, style: .iconRow)
        .transition(.opacity)
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

  /// 目录与存储配置视图（支持新增、编辑、优先级调整、删除整理目录，以及跳转刮削开关）。
  private var directoriesContent: some View {
    VStack(alignment: .leading, spacing: 18) {
      sectionHeader("刮削策略", count: 0)
      CinematicPanel(padding: 0) {
        NavigationLink {
          NativeSystemModulesPage(session: session, initialDomain: .scraping)
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
              .font(.system(size: 18, weight: .medium))
              .foregroundStyle(.primary)
              .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
              Text("刮削开关").font(.body.weight(.medium)).foregroundStyle(.primary)
              Text("配置电影、剧集、音乐 NFO 与图片刮削").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
              .foregroundStyle(.secondary.opacity(0.55))
          }
          .padding(.horizontal, 16).padding(.vertical, 14)
          .frame(minHeight: 58)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }

      sectionHeader("下载与媒体库整理目录", count: directories.count)
      if directories.isEmpty {
        emptyCard("暂无目录映射配置，点击右上角「+」新增整理目录。")
      } else {
        ForEach(Array(directories.enumerated()), id: \.offset) { idx, dir in
          Button {
            editingDirectoryIndex = idx
          } label: {
            CinematicPanel(padding: 15) {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                  Text("#\(idx + 1)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(NativeTheme.brand)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(NativeTheme.brand.opacity(0.14), in: Capsule())
                  Text(dir.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                  Spacer()
                  if !dir.transferLabel.isEmpty {
                    statusTag(dir.transferLabel, active: true)
                  }
                  Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.55))
                }

                VStack(alignment: .leading, spacing: 7) {
                  if let src = dir.downloadPath, !src.isEmpty {
                    HStack(spacing: 8) {
                      NativeBrandIcon(
                        kind: .storage, type: dir.storage ?? "local", size: 22, cornerRadius: 6)
                      Text(src)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary.opacity(0.82))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    }
                  }
                  if let dst = dir.libraryPath, !dst.isEmpty {
                    HStack(spacing: 8) {
                      NativeBrandIcon(
                        kind: .storage, type: dir.libraryStorage ?? "local", size: 22,
                        cornerRadius: 6)
                      Text(dst)
                        .font(.caption.monospaced())
                        .foregroundStyle(NativeTheme.brand)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    }
                  }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 6) {
                    if let mediaType = dir.mediaType, !mediaType.isEmpty {
                      miniChip(mediaType)
                    }
                    if let category = dir.mediaCategory, !category.isEmpty {
                      miniChip(category)
                    }
                    if !dir.monitorLabel.isEmpty {
                      miniChip(dir.monitorLabel)
                    }
                    if dir.renaming == true {
                      miniChip("智能重命名")
                    }
                    if dir.scraping == true {
                      miniChip("自动刮削")
                    }
                    if dir.notify == true {
                      miniChip("通知")
                    }
                  }
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button {
              editingDirectoryIndex = idx
            } label: {
              Label("编辑目录", systemImage: "pencil")
            }
            if idx > 0 {
              Button {
                Task { await moveDirectory(from: idx, to: idx - 1) }
              } label: {
                Label("提高优先级", systemImage: "arrow.up")
              }
            }
            if idx < directories.count - 1 {
              Button {
                Task { await moveDirectory(from: idx, to: idx + 1) }
              } label: {
                Label("降低优先级", systemImage: "arrow.down")
              }
            }
            Divider()
            Button(role: .destructive) {
              pendingDeleteDirectoryIndex = idx
            } label: {
              Label("删除目录", systemImage: "trash")
            }
          }
        }
      }

      sectionHeader("已挂载存储", count: storages.count)
      if storages.isEmpty {
        emptyCard("暂无存储配置")
      } else {
        CinematicPanel(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(storages.enumerated()), id: \.element.id) { idx, storage in
              if idx > 0 { CinematicFormDivider() }
              HStack(spacing: 13) {
                NativeBrandIcon(kind: .storage, type: storage.type, size: 38, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 3) {
                  Text(storage.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                  Text(storage.type).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                statusTag("已挂载", active: true)
              }
              .padding(.horizontal, 16).padding(.vertical, 13)
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

  /// 通知渠道视图（支持点击编辑、长按启停/排序/删除及右上角「+」新增渠道）。
  private var notificationsContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("通知渠道", count: notifications.count)
      if notifications.isEmpty {
        emptyCard("暂无已配置通知渠道，点击右上角「+」新增推送渠道。")
      } else {
        ForEach(Array(notifications.enumerated()), id: \.offset) { idx, item in
          Button {
            editingNotificationIndex = idx
          } label: {
            CinematicPanel(padding: 15) {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 13) {
                  NativeBrandIcon(
                    kind: .notification, type: item.type, size: 42, cornerRadius: 11)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text("\(NativeNotificationConfig.displayTypeName(item.type)) · \(item.type)")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                  Spacer()
                  statusTag(item.enabled ? "已启用" : "已停用", active: item.enabled)
                  Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.55))
                }
                if !item.switchs.isEmpty {
                  ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                      ForEach(item.switchs.prefix(8), id: \.self) { scene in
                        miniChip(scene)
                      }
                    }
                  }
                }
              }
            }
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button {
              editingNotificationIndex = idx
            } label: {
              Label("编辑配置", systemImage: "pencil")
            }
            Button {
              Task { await toggleNotificationEnabled(at: idx) }
            } label: {
              Label(
                item.enabled ? "停用渠道" : "启用渠道",
                systemImage: item.enabled ? "pause.circle" : "play.circle")
            }
            if idx > 0 {
              Button {
                Task { await moveNotification(from: idx, to: idx - 1) }
              } label: {
                Label("上移", systemImage: "arrow.up")
              }
            }
            if idx < notifications.count - 1 {
              Button {
                Task { await moveNotification(from: idx, to: idx + 1) }
              } label: {
                Label("下移", systemImage: "arrow.down")
              }
            }
            Divider()
            Button(role: .destructive) {
              pendingDeleteNotificationIndex = idx
            } label: {
              Label("删除渠道", systemImage: "trash")
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

  // MARK: - 通知渠道 CRUD 持久化

  private func saveNotification(_ item: NativeNotificationConfig, replaceAt index: Int?) async {
    var next = notifications
    if let index, next.indices.contains(index) {
      next[index] = item
    } else {
      next.append(item)
    }
    await persistNotifications(
      next,
      successMessage: index == nil ? "已新增通知渠道「\(item.name)」。" : "已保存通知渠道「\(item.name)」。")
  }

  private func toggleNotificationEnabled(at index: Int) async {
    guard notifications.indices.contains(index) else { return }
    var next = notifications
    next[index].enabled.toggle()
    let stateLabel = next[index].enabled ? "已启用" : "已停用"
    await persistNotifications(next, successMessage: "\(stateLabel)通知渠道「\(next[index].name)」。")
  }

  private func moveNotification(from source: Int, to destination: Int) async {
    guard notifications.indices.contains(source), notifications.indices.contains(destination) else {
      return
    }
    var next = notifications
    let item = next.remove(at: source)
    next.insert(item, at: destination)
    await persistNotifications(next, successMessage: "已调整通知渠道顺序。")
  }

  private func deleteNotification(at index: Int) async {
    guard notifications.indices.contains(index) else { return }
    var next = notifications
    let removed = next.remove(at: index)
    await persistNotifications(next, successMessage: "已删除通知渠道「\(removed.name)」。")
  }

  private func persistNotifications(
    _ next: [NativeNotificationConfig], successMessage: String
  ) async {
    do {
      let body = try JSONEncoder().encode(next)
      let ep = try APIEndpoint(
        path: ["system", "setting", "Notifications"], method: .post, body: body)
      try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
      notifications = next
      feedbackIsError = false
      feedback = successMessage
    } catch {
      feedbackIsError = true
      feedback = "保存通知渠道配置失败，请稍后重试。"
    }
  }

  // MARK: - 整理目录 CRUD 持久化

  private func saveDirectory(_ item: NativeDirectoryConfig, replaceAt index: Int?) async {
    var next = directories
    if let index, next.indices.contains(index) {
      next[index] = item
    } else {
      next.append(item)
    }
    await persistDirectories(
      next,
      successMessage: index == nil
        ? "已新增整理目录「\(item.displayName)」。" : "已保存整理目录「\(item.displayName)」。")
  }

  private func moveDirectory(from source: Int, to destination: Int) async {
    guard directories.indices.contains(source), directories.indices.contains(destination) else {
      return
    }
    var next = directories
    let item = next.remove(at: source)
    next.insert(item, at: destination)
    await persistDirectories(next, successMessage: "已更新整理目录优先级。")
  }

  private func deleteDirectory(at index: Int) async {
    guard directories.indices.contains(index) else { return }
    var next = directories
    let removed = next.remove(at: index)
    await persistDirectories(next, successMessage: "已删除整理目录「\(removed.displayName)」。")
  }

  private func persistDirectories(
    _ rawNext: [NativeDirectoryConfig], successMessage: String
  ) async {
    var normalized = rawNext
    for i in normalized.indices {
      normalized[i].priority = i
    }
    do {
      let body = try JSONEncoder().encode(normalized)
      let ep = try APIEndpoint(
        path: ["system", "setting", "Directories"], method: .post, body: body)
      try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
      directories = normalized
      feedbackIsError = false
      feedback = successMessage
    } catch {
      feedbackIsError = true
      feedback = "保存整理目录配置失败，请稍后重试。"
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

private struct NativeDirectoryConfig: Codable, Sendable, Identifiable {
  var name: String?
  var priority: Int?
  var storage: String?
  var downloadPath: String?
  var mediaType: String?
  var mediaCategory: String?
  var mediaCategoryID: String?
  var downloadTypeFolder: Bool?
  var downloadCategoryFolder: Bool?
  var monitorType: String?
  var monitorMode: String?
  var transferType: String?
  var overwriteMode: String?
  var libraryPath: String?
  var libraryStorage: String?
  var renaming: Bool?
  var scraping: Bool?
  var notify: Bool?
  var libraryTypeFolder: Bool?
  var libraryCategoryFolder: Bool?

  var id: String { "\(priority ?? 0)|\(name ?? "")|\(downloadPath ?? "")|\(libraryPath ?? "")" }
  var displayName: String { (name?.isEmpty == false ? name : nil) ?? storage ?? "媒体目录" }

  var transferLabel: String {
    switch (transferType ?? "").lowercased() {
    case "link": "硬链接"
    case "softlink": "软链接"
    case "copy": "复制"
    case "move": "移动"
    case "reflink": "Reflink"
    case "": ""
    default: transferType ?? ""
    }
  }

  var monitorLabel: String {
    switch (monitorType ?? "").lowercased() {
    case "downloader": "下载器监控"
    case "monitor": "目录监控"
    case "": ""
    default: monitorType ?? ""
    }
  }

  private enum CodingKeys: String, CodingKey {
    case name, priority, storage, renaming, scraping, notify
    case downloadPath = "download_path"
    case mediaType = "media_type"
    case mediaCategory = "media_category"
    case mediaCategoryID = "media_category_id"
    case downloadTypeFolder = "download_type_folder"
    case downloadCategoryFolder = "download_category_folder"
    case monitorType = "monitor_type"
    case monitorMode = "monitor_mode"
    case transferType = "transfer_type"
    case overwriteMode = "overwrite_mode"
    case libraryPath = "library_path"
    case libraryStorage = "library_storage"
    case libraryTypeFolder = "library_type_folder"
    case libraryCategoryFolder = "library_category_folder"
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

private struct NativeNotificationConfig: Codable, Sendable, Identifiable {
  var id: String
  var name: String
  var type: String
  var enabled: Bool
  var switchs: [String]
  var config: [String: JSONValue]

  func configString(_ key: String) -> String {
    if case .string(let s) = config[key] { return s }
    if case .number(let n) = config[key] {
      return n.rounded() == n ? String(Int64(n)) : String(n)
    }
    return ""
  }

  static func displayTypeName(_ type: String) -> String {
    switch type.lowercased() {
    case "wechat": "企业微信"
    case "wechatclawbot": "微信客服"
    case "telegram": "Telegram"
    case "feishu": "飞书"
    case "qqbot": "QQ 机器人"
    case "slack": "Slack"
    case "discord": "Discord"
    case "dingtalk": "钉钉"
    case "vocechat": "VoceChat"
    case "synologychat": "Synology Chat"
    case "webpush": "WebPush"
    case "apppush": "AppPush"
    default: type.isEmpty ? "自定义" : type
    }
  }

  init(
    id: String = UUID().uuidString,
    name: String,
    type: String,
    enabled: Bool,
    switchs: [String],
    config: [String: JSONValue]
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.enabled = enabled
    self.switchs = switchs
    self.config = config
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "通知渠道"
    type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
    enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
    switchs = (try? c.decodeIfPresent([String].self, forKey: .switchs)) ?? []
    config = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .config)) ?? [:]
  }

  private enum CodingKeys: String, CodingKey { case id, name, type, enabled, switchs, config }
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

// MARK: - 通知渠道新增/编辑弹窗

@MainActor
private struct NativeNotificationEditorSheet: View {
  let initial: NativeNotificationConfig?
  var onDelete: (() -> Void)? = nil
  let onSave: (NativeNotificationConfig) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  @State private var name: String
  @State private var type: String
  @State private var enabled: Bool
  @State private var selectedScenes: Set<String>
  @State private var configValues: [String: String]
  @State private var baseConfig: [String: JSONValue]

  private struct FieldSpec: Identifiable {
    let key: String
    let label: String
    let placeholder: String
    var isSecret: Bool = false
    var isNumber: Bool = false
    var id: String { key }
  }

  private static let allScenes: [String] = [
    "资源下载", "整理入库", "订阅", "站点", "媒体服务器", "手动处理", "插件", "智能体", "其它",
  ]

  private static let channelChoices: [NativeBrandChoiceItem] = [
    .init(id: "wechat", title: "企业微信"),
    .init(id: "wechatclawbot", title: "微信客服"),
    .init(id: "telegram", title: "Telegram"),
    .init(id: "feishu", title: "飞书"),
    .init(id: "qqbot", title: "QQ 机器人"),
    .init(id: "slack", title: "Slack"),
    .init(id: "discord", title: "Discord"),
    .init(id: "dingtalk", title: "钉钉"),
    .init(id: "vocechat", title: "VoceChat"),
    .init(id: "synologychat", title: "Synology"),
    .init(id: "apppush", title: "AppPush"),
    .init(id: "webpush", title: "WebPush"),
  ]

  init(
    initial: NativeNotificationConfig?,
    onDelete: (() -> Void)? = nil,
    onSave: @escaping (NativeNotificationConfig) -> Void
  ) {
    self.initial = initial
    self.onDelete = onDelete
    self.onSave = onSave
    let startType = initial?.type.isEmpty == false ? initial!.type : "wechat"
    _name = State(initialValue: initial?.name ?? "")
    _type = State(initialValue: startType)
    _enabled = State(initialValue: initial?.enabled ?? true)
    _selectedScenes = State(initialValue: Set(initial?.switchs ?? Self.allScenes))
    var values: [String: String] = [:]
    if let cfg = initial?.config {
      for (k, v) in cfg {
        switch v {
        case .string(let s): values[k] = s
        case .number(let n):
          values[k] = n.rounded() == n ? String(Int64(n)) : String(n)
        default: break
        }
      }
    }
    if startType == "wechat" && (values["WECHAT_MODE"] ?? "").isEmpty {
      values["WECHAT_MODE"] = "app"
    }
    _configValues = State(initialValue: values)
    _baseConfig = State(initialValue: initial?.config ?? [:])
  }

  private var wechatMode: String {
    let raw = (configValues["WECHAT_MODE"] ?? "app").lowercased()
    return raw == "bot" ? "bot" : "app"
  }

  private var activeFields: [FieldSpec] {
    switch type.lowercased() {
    case "wechat":
      if wechatMode == "bot" {
        return [
          .init(key: "WECHAT_BOT_ID", label: "机器人 ID", placeholder: "WECHAT_BOT_ID"),
          .init(
            key: "WECHAT_BOT_SECRET", label: "机器人密钥", placeholder: "WECHAT_BOT_SECRET",
            isSecret: true),
          .init(key: "WECHAT_BOT_CHAT_ID", label: "默认会话 ID", placeholder: "可选，单聊/群聊 ID"),
          .init(
            key: "WECHAT_BOT_WS_URL", label: "WebSocket 地址",
            placeholder: "wss://openws.work.weixin.qq.com"),
        ]
      }
      return [
        .init(key: "WECHAT_CORPID", label: "企业 ID", placeholder: "WECHAT_CORPID"),
        .init(key: "WECHAT_APP_ID", label: "应用 AgentId", placeholder: "WECHAT_APP_ID"),
        .init(
          key: "WECHAT_APP_SECRET", label: "应用 Secret", placeholder: "WECHAT_APP_SECRET",
          isSecret: true),
        .init(key: "WECHAT_PROXY", label: "代理地址", placeholder: "默认 https://qyapi.weixin.qq.com"),
        .init(key: "WECHAT_TOKEN", label: "回调 Token", placeholder: "可选"),
        .init(
          key: "WECHAT_ENCODING_AESKEY", label: "EncodingAESKey", placeholder: "可选", isSecret: true),
      ]
    case "wechatclawbot":
      return [
        .init(
          key: "WECHATCLAWBOT_BASE_URL", label: "服务地址", placeholder: "https://ilinkai.weixin.qq.com"
        ),
        .init(key: "WECHATCLAWBOT_DEFAULT_TARGET", label: "默认接收目标", placeholder: "可选"),
        .init(
          key: "WECHATCLAWBOT_POLL_TIMEOUT", label: "轮询超时 (秒)", placeholder: "25", isNumber: true),
      ]
    case "telegram":
      return [
        .init(
          key: "TELEGRAM_TOKEN", label: "Bot Token", placeholder: "123456:ABC-DEF...",
          isSecret: true),
        .init(key: "TELEGRAM_CHAT_ID", label: "Chat ID", placeholder: "接收用户或群组 ID"),
        .init(key: "TELEGRAM_TOPIC_ID", label: "Topic ID", placeholder: "可选，超级群主题 ID"),
        .init(key: "API_URL", label: "自定义 API 地址", placeholder: "默认 https://api.telegram.org"),
      ]
    case "feishu":
      return [
        .init(key: "FEISHU_APP_ID", label: "App ID", placeholder: "cli_xxx"),
        .init(key: "FEISHU_APP_SECRET", label: "App Secret", placeholder: "应用密钥", isSecret: true),
        .init(key: "FEISHU_OPEN_ID", label: "用户 Open ID", placeholder: "可选"),
        .init(key: "FEISHU_CHAT_ID", label: "群组 Chat ID", placeholder: "可选"),
        .init(key: "FEISHU_VERIFICATION_TOKEN", label: "Verification Token", placeholder: "可选"),
        .init(key: "FEISHU_ENCRYPT_KEY", label: "Encrypt Key", placeholder: "可选", isSecret: true),
      ]
    case "slack":
      return [
        .init(
          key: "SLACK_OAUTH_TOKEN", label: "Bot OAuth Token", placeholder: "xoxb-...",
          isSecret: true),
        .init(
          key: "SLACK_APP_TOKEN", label: "App-Level Token", placeholder: "xapp-...", isSecret: true),
        .init(key: "SLACK_CHANNEL", label: "频道名称", placeholder: "如 全体 / general"),
      ]
    case "discord":
      return [
        .init(
          key: "DISCORD_BOT_TOKEN", label: "Bot Token", placeholder: "Discord 机器人令牌", isSecret: true
        ),
        .init(key: "DISCORD_GUILD_ID", label: "服务器 Guild ID", placeholder: "可选"),
        .init(key: "DISCORD_CHANNEL_ID", label: "频道 Channel ID", placeholder: "目标频道 ID"),
      ]
    case "dingtalk":
      return [
        .init(
          key: "DINGTALK_WEBHOOK", label: "Webhook 地址",
          placeholder: "https://oapi.dingtalk.com/robot/send?..."),
        .init(key: "DINGTALK_SECRET", label: "加签密钥", placeholder: "SEC...", isSecret: true),
      ]
    case "vocechat":
      return [
        .init(key: "VOCECHAT_HOST", label: "服务器地址", placeholder: "https://chat.example.com"),
        .init(key: "VOCECHAT_API_KEY", label: "API Key", placeholder: "机器人密钥", isSecret: true),
        .init(key: "VOCECHAT_CHANNEL_ID", label: "频道 ID", placeholder: "数字频道 ID"),
      ]
    case "synologychat":
      return [
        .init(
          key: "SYNOLOGYCHAT_WEBHOOK", label: "Webhook 地址", placeholder: "群晖 Chat Incoming Webhook"),
        .init(key: "SYNOLOGYCHAT_TOKEN", label: "Token", placeholder: "可选", isSecret: true),
      ]
    case "qqbot":
      return [
        .init(key: "QQ_APP_ID", label: "App ID", placeholder: "QQ 开放平台 AppID"),
        .init(key: "QQ_APP_SECRET", label: "App Secret", placeholder: "QQ 开放平台密钥", isSecret: true),
        .init(key: "QQ_OPENID", label: "单聊 OpenID", placeholder: "可选"),
        .init(key: "QQ_GROUP_OPENID", label: "群聊 Group OpenID", placeholder: "可选"),
      ]
    case "apppush":
      return [
        .init(key: "PUSH_SERVER_URL", label: "推送中继地址", placeholder: "https://..."),
        .init(key: "PUSH_RELAY_KEY", label: "中继密钥", placeholder: "Relay Key", isSecret: true),
      ]
    case "webpush":
      return [
        .init(key: "WEBPUSH_USERNAME", label: "目标用户名", placeholder: "留空则向所有已订阅浏览器推送")
      ]
    default:
      return []
    }
  }

  private var canSubmit: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !type.isEmpty
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            channelTypeSection
            basicInfoSection
            configFieldsSection
            sceneSwitchesSection
            if let onDelete {
              Button(role: .destructive) {
                dismiss()
                onDelete()
              } label: {
                Label("删除该通知渠道", systemImage: "trash")
                  .font(.body.weight(.semibold))
                  .foregroundStyle(NativeTheme.danger)
                  .frame(maxWidth: .infinity, minHeight: 50)
                  .background(
                    NativeTheme.danger.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle(initial == nil ? "新增通知渠道" : "编辑通知渠道")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { commitSave() }
            .fontWeight(.semibold)
            .tint(.primary)
            .disabled(!canSubmit)
        }
      }
    }
    .nativeGlassSheet()
  }

  private var channelTypeSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("渠道类型")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      NativeBrandOptionGrid(
        kind: .notification,
        items: Self.channelChoices,
        selection: $type,
        columns: 3
      )
      .onChange(of: type) { next in
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          name = NativeNotificationConfig.displayTypeName(next)
        }
        if next == "wechat" && (configValues["WECHAT_MODE"] ?? "").isEmpty {
          configValues["WECHAT_MODE"] = "app"
        }
      }
    }
  }

  private var basicInfoSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("基本设置")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          HStack(spacing: 12) {
            Text("渠道名称")
              .font(.body)
              .foregroundStyle(.primary)
            TextField("例如：家庭 Telegram", text: $name)
              .multilineTextAlignment(.trailing)
              .font(.body)
          }
          .padding(.horizontal, 16)
          .frame(minHeight: 54)
          CinematicFormDivider()
          Toggle("启用此渠道", isOn: $enabled)
            .font(.body)
            .tint(appearance.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
        }
      }
    }
  }

  @ViewBuilder
  private var configFieldsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("连接参数")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          if type.lowercased() == "wechat" {
            HStack {
              Text("接入方式")
                .font(.body)
                .foregroundStyle(.primary)
              Spacer()
              Picker(
                "接入方式",
                selection: Binding(
                  get: { wechatMode },
                  set: { configValues["WECHAT_MODE"] = $0 }
                )
              ) {
                Text("自建应用").tag("app")
                Text("智能机器人").tag("bot")
              }
              .pickerStyle(.segmented)
              .frame(maxWidth: 190)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            CinematicFormDivider()
          }
          if activeFields.isEmpty {
            Text("该渠道无需额外连接参数，或保留原配置不变。")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(16)
          } else {
            ForEach(Array(activeFields.enumerated()), id: \.element.id) { idx, spec in
              if idx > 0 { CinematicFormDivider() }
              VStack(alignment: .leading, spacing: 6) {
                Text(spec.label)
                  .font(.footnote.weight(.medium))
                  .foregroundStyle(.secondary)
                if spec.isSecret {
                  SecureField(
                    spec.placeholder,
                    text: Binding(
                      get: { configValues[spec.key] ?? "" },
                      set: { configValues[spec.key] = $0 }
                    )
                  )
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .font(.body)
                } else {
                  TextField(
                    spec.placeholder,
                    text: Binding(
                      get: { configValues[spec.key] ?? "" },
                      set: { configValues[spec.key] = $0 }
                    )
                  )
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .keyboardType(spec.isNumber ? .numberPad : .default)
                  .font(.body)
                }
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
            }
          }
        }
      }
    }
  }

  private var sceneSwitchesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("推送场景")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer()
        Button(selectedScenes.count == Self.allScenes.count ? "清空" : "全选") {
          if selectedScenes.count == Self.allScenes.count {
            selectedScenes.removeAll()
          } else {
            selectedScenes = Set(Self.allScenes)
          }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(appearance.accentColor)
      }
      .padding(.horizontal, 4)

      CinematicPanel(padding: 14) {
        let cols = [GridItem(.adaptive(minimum: 92), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
          ForEach(Self.allScenes, id: \.self) { scene in
            let active = selectedScenes.contains(scene)
            Button {
              if active {
                selectedScenes.remove(scene)
              } else {
                selectedScenes.insert(scene)
              }
            } label: {
              Text(scene)
                .font(.footnote.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? appearance.accentColor : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 8)
                .background {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? appearance.accentColor.opacity(0.15) : NativeTheme.chipFill)
                    .overlay {
                      RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                          active ? appearance.accentColor.opacity(0.6) : NativeTheme.chipBorder,
                          lineWidth: active ? 1.1 : 0.6)
                    }
                }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func commitSave() {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    var mergedConfig = baseConfig
    if type.lowercased() == "wechat" {
      mergedConfig["WECHAT_MODE"] = .string(wechatMode)
    }
    for spec in activeFields {
      let val = (configValues[spec.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if val.isEmpty {
        mergedConfig.removeValue(forKey: spec.key)
      } else if spec.isNumber, let num = Double(val) {
        mergedConfig[spec.key] = .number(num)
      } else {
        mergedConfig[spec.key] = .string(val)
      }
    }
    let orderedScenes = Self.allScenes.filter { selectedScenes.contains($0) }
    let record = NativeNotificationConfig(
      id: initial?.id ?? UUID().uuidString,
      name: trimmedName,
      type: type,
      enabled: enabled,
      switchs: orderedScenes,
      config: mergedConfig
    )
    onSave(record)
    dismiss()
  }
}

// MARK: - 整理目录新增/编辑弹窗

@MainActor
private struct NativeDirectoryEditorSheet: View {
  let initial: NativeDirectoryConfig?
  let storages: [NativeStorageConfig]
  var onDelete: (() -> Void)? = nil
  let onSave: (NativeDirectoryConfig) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  @State private var name: String
  @State private var storage: String
  @State private var downloadPath: String
  @State private var mediaType: String
  @State private var mediaCategory: String
  @State private var downloadTypeFolder: Bool
  @State private var downloadCategoryFolder: Bool
  @State private var monitorType: String
  @State private var monitorMode: String
  @State private var transferType: String
  @State private var overwriteMode: String
  @State private var libraryStorage: String
  @State private var libraryPath: String
  @State private var libraryTypeFolder: Bool
  @State private var libraryCategoryFolder: Bool
  @State private var renaming: Bool
  @State private var scraping: Bool
  @State private var notify: Bool

  init(
    initial: NativeDirectoryConfig?,
    storages: [NativeStorageConfig],
    onDelete: (() -> Void)? = nil,
    onSave: @escaping (NativeDirectoryConfig) -> Void
  ) {
    self.initial = initial
    self.storages = storages
    self.onDelete = onDelete
    self.onSave = onSave
    _name = State(initialValue: initial?.name ?? "")
    _storage = State(initialValue: initial?.storage ?? "local")
    _downloadPath = State(initialValue: initial?.downloadPath ?? "")
    _mediaType = State(initialValue: initial?.mediaType ?? "")
    _mediaCategory = State(initialValue: initial?.mediaCategory ?? "")
    _downloadTypeFolder = State(initialValue: initial?.downloadTypeFolder ?? false)
    _downloadCategoryFolder = State(initialValue: initial?.downloadCategoryFolder ?? false)
    _monitorType = State(initialValue: initial?.monitorType ?? "downloader")
    _monitorMode = State(initialValue: initial?.monitorMode ?? "fast")
    _transferType = State(initialValue: initial?.transferType ?? "link")
    _overwriteMode = State(initialValue: initial?.overwriteMode ?? "size")
    _libraryStorage = State(initialValue: initial?.libraryStorage ?? "local")
    _libraryPath = State(initialValue: initial?.libraryPath ?? "")
    _libraryTypeFolder = State(initialValue: initial?.libraryTypeFolder ?? false)
    _libraryCategoryFolder = State(initialValue: initial?.libraryCategoryFolder ?? false)
    _renaming = State(initialValue: initial?.renaming ?? true)
    _scraping = State(initialValue: initial?.scraping ?? false)
    _notify = State(initialValue: initial?.notify ?? true)
  }

  private var storageChoices: [NativeBrandChoiceItem] {
    if !storages.isEmpty {
      return storages.map {
        NativeBrandChoiceItem(id: $0.type, title: $0.name, iconType: $0.type)
      }
    }
    return [
      .init(id: "local", title: "本地存储"),
      .init(id: "alipan", title: "阿里云盘"),
      .init(id: "u115", title: "115 网盘"),
      .init(id: "rclone", title: "Rclone"),
      .init(id: "alist", title: "Alist"),
      .init(id: "smb", title: "SMB"),
    ]
  }

  private var canSubmit: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !downloadPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !libraryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            basicSection
            sourceStorageSection
            transferRuleSection
            targetLibrarySection
            behaviorSwitchesSection
            if let onDelete {
              Button(role: .destructive) {
                dismiss()
                onDelete()
              } label: {
                Label("删除该整理目录", systemImage: "trash")
                  .font(.body.weight(.semibold))
                  .foregroundStyle(NativeTheme.danger)
                  .frame(maxWidth: .infinity, minHeight: 50)
                  .background(
                    NativeTheme.danger.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle(initial == nil ? "新增整理目录" : "编辑整理目录")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { commitSave() }
            .fontWeight(.semibold)
            .tint(.primary)
            .disabled(!canSubmit)
        }
      }
    }
    .nativeGlassSheet()
  }

  private var basicSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("目录标识与适用范围")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          HStack(spacing: 12) {
            Text("别名")
              .font(.body)
            TextField("例如：电影主目录", text: $name)
              .multilineTextAlignment(.trailing)
              .font(.body)
          }
          .padding(.horizontal, 16)
          .frame(minHeight: 54)
          CinematicFormDivider()
          HStack {
            Text("媒体类型")
              .font(.body)
            Spacer()
            Picker("媒体类型", selection: $mediaType) {
              Text("全部").tag("")
              Text("电影").tag("电影")
              Text("电视剧").tag("电视剧")
              Text("音乐").tag("音乐")
            }
            .tint(appearance.accentColor)
          }
          .padding(.horizontal, 16)
          .frame(minHeight: 54)
          CinematicFormDivider()
          HStack(spacing: 12) {
            Text("媒体分类")
              .font(.body)
            TextField("留空表示全部类别", text: $mediaCategory)
              .multilineTextAlignment(.trailing)
              .font(.body)
          }
          .padding(.horizontal, 16)
          .frame(minHeight: 54)
        }
      }
    }
  }

  private var sourceStorageSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("源目录与存储")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      NativeBrandOptionGrid(
        kind: .storage,
        items: storageChoices,
        selection: $storage,
        columns: 3
      )
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 6) {
            Text("源目录路径（下载目录）")
              .font(.footnote.weight(.medium))
              .foregroundStyle(.secondary)
            TextField("/downloads", text: $downloadPath)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .font(.body.monospaced())
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          CinematicFormDivider()
          Toggle("按媒体类型建子目录", isOn: $downloadTypeFolder)
            .font(.body)
            .tint(appearance.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
          CinematicFormDivider()
          Toggle("按媒体分类建子目录", isOn: $downloadCategoryFolder)
            .font(.body)
            .tint(appearance.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
      }
    }
  }

  private var transferRuleSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("监控与整理方式")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          HStack {
            Text("监控方式")
              .font(.body)
            Spacer()
            Picker("监控方式", selection: $monitorType) {
              Text("不监控").tag("")
              Text("下载器监控").tag("downloader")
              Text("目录监控").tag("monitor")
            }
            .tint(appearance.accentColor)
          }
          .padding(.horizontal, 16)
          .frame(minHeight: 54)
          if monitorType == "monitor" {
            CinematicFormDivider()
            HStack {
              Text("监控模式")
                .font(.body)
              Spacer()
              Picker("监控模式", selection: $monitorMode) {
                Text("性能模式").tag("fast")
                Text("兼容模式").tag("compatibility")
              }
              .tint(appearance.accentColor)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
          }
          CinematicFormDivider()
          HStack {
            Text("整理方式")
              .font(.body)
            Spacer()
            Picker("整理方式", selection: $transferType) {
              Text("不整理").tag("")
              Text("硬链接").tag("link")
              Text("软链接").tag("softlink")
              Text("移动").tag("move")
              Text("复制").tag("copy")
              Text("Reflink").tag("reflink")
            }
            .tint(appearance.accentColor)
          }
          .padding(.horizontal, 16)
          .frame(minHeight: 54)
          CinematicFormDivider()
          HStack {
            Text("覆盖模式")
              .font(.body)
            Spacer()
            Picker("覆盖模式", selection: $overwriteMode) {
              Text("从不覆盖").tag("never")
              Text("总是覆盖").tag("always")
              Text("按文件大小覆盖").tag("size")
              Text("仅保留最新版本").tag("latest")
            }
            .tint(appearance.accentColor)
          }
          .padding(.horizontal, 16)
          .frame(minHeight: 54)
        }
      }
    }
  }

  private var targetLibrarySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("目标媒体库目录")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      NativeBrandOptionGrid(
        kind: .storage,
        items: storageChoices,
        selection: $libraryStorage,
        columns: 3
      )
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 6) {
            Text("媒体库路径")
              .font(.footnote.weight(.medium))
              .foregroundStyle(.secondary)
            TextField("/media", text: $libraryPath)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .font(.body.monospaced())
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          CinematicFormDivider()
          Toggle("按媒体类型建子目录", isOn: $libraryTypeFolder)
            .font(.body)
            .tint(appearance.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
          CinematicFormDivider()
          Toggle("按媒体分类建子目录", isOn: $libraryCategoryFolder)
            .font(.body)
            .tint(appearance.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
      }
    }
  }

  private var behaviorSwitchesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("入库处理选项")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          Toggle("智能重命名", isOn: $renaming)
            .font(.body)
            .tint(appearance.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
          CinematicFormDivider()
          Toggle("自动刮削元数据", isOn: $scraping)
            .font(.body)
            .tint(appearance.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
          CinematicFormDivider()
          Toggle("入库完成后发送通知", isOn: $notify)
            .font(.body)
            .tint(appearance.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
      }
    }
  }

  private func commitSave() {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDownload = downloadPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedLibrary = libraryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedCategory = mediaCategory.trimmingCharacters(in: .whitespacesAndNewlines)
    let record = NativeDirectoryConfig(
      name: trimmedName.isEmpty ? nil : trimmedName,
      priority: initial?.priority,
      storage: storage.isEmpty ? "local" : storage,
      downloadPath: trimmedDownload.isEmpty ? nil : trimmedDownload,
      mediaType: mediaType.isEmpty ? nil : mediaType,
      mediaCategory: trimmedCategory.isEmpty ? nil : trimmedCategory,
      mediaCategoryID: initial?.mediaCategoryID,
      downloadTypeFolder: downloadTypeFolder,
      downloadCategoryFolder: downloadCategoryFolder,
      monitorType: monitorType.isEmpty ? nil : monitorType,
      monitorMode: monitorType == "monitor" ? monitorMode : initial?.monitorMode,
      transferType: transferType.isEmpty ? nil : transferType,
      overwriteMode: overwriteMode,
      libraryPath: trimmedLibrary.isEmpty ? nil : trimmedLibrary,
      libraryStorage: libraryStorage.isEmpty ? "local" : libraryStorage,
      renaming: renaming,
      scraping: scraping,
      notify: notify,
      libraryTypeFolder: libraryTypeFolder,
      libraryCategoryFolder: libraryCategoryFolder
    )
    onSave(record)
    dismiss()
  }
}
