import Charts
import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生站点管理页（五.2）：去除过滤与排序，右上角提供新增站点，支持完整新增/编辑/删除、单站连通检测与站点流量/做种历史数据查看。
@MainActor
struct NativeSitesPage: View {
  private enum TestState: Equatable {
    case testing
    case passed
    case failed
  }

  let session: NativeSession

  @State private var sites: [NativeSiteItem] = []
  @State private var userdataByDomain: [String: NativeSiteUserData] = [:]
  @State private var userdataByName: [String: NativeSiteUserData] = [:]
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var testStates: [Int: TestState] = [:]
  @State private var showsCreateSheet = false
  @State private var editingSite: NativeSiteItem?
  @State private var inspectingSite: NativeSiteItem?
  @State private var pendingDeleteSite: NativeSiteItem?
  @State private var feedback: (isError: Bool, text: String)?
  @State private var containerWidth: CGFloat = 0
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            CinematicPanel(padding: 11) {
              HStack(spacing: 8) {
                Image(
                  systemName: feedback.isError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.text).font(.caption.weight(.medium))
                Spacer()
              }
            }
          }

          if isLoading && sites.isEmpty {
            NativeCardListSkeletonView(count: 5, style: .iconRow)
              .transition(.opacity)
          } else if loadFailed && sites.isEmpty {
            failureCard
          } else if filteredSites.isEmpty {
            emptyCard
          } else {
            let columnCount = NativeDeviceLayout.cardGridCount(
              for: containerWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            let gridColumns = Array(
              repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columnCount)
            LazyVGrid(columns: gridColumns, spacing: 12) {
              ForEach(filteredSites) { site in
                siteCard(site)
              }
            }
          }
        }
        .frame(maxWidth: containerWidth >= 740 ? 1180 : 840)
        .padding(.horizontal, NativeDeviceLayout.horizontalMargin(for: containerWidth))
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .refreshable { await load(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-sites-scroll")
    }
    .navigationTitle(sites.isEmpty ? "站点管理" : "站点管理 (\(sites.count))")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .searchable(text: $searchText, prompt: "搜索站点名称或域名")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsCreateSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .tint(.primary)
        .accessibilityLabel("新增站点")
        .accessibilityIdentifier("native-sites-add")
      }
    }
    .sheet(isPresented: $showsCreateSheet) {
      NativeSiteEditorSheet(session: session, existing: nil) { message in
        feedback = (false, message)
        NativePageDataCache.shared.remove("sites|all", session: session)
        NativePageDataCache.shared.remove("settingsHub|overview.v2", session: session)
        attempt += 1
      }
    }
    .sheet(item: $editingSite) { target in
      NativeSiteEditorSheet(
        session: session,
        existing: target,
        onDelete: {
          editingSite = nil
          pendingDeleteSite = target
        }
      ) { message in
        feedback = (false, message)
        NativePageDataCache.shared.remove("sites|all", session: session)
        NativePageDataCache.shared.remove("settingsHub|overview.v2", session: session)
        attempt += 1
      }
    }
    .sheet(item: $inspectingSite) { target in
      NativeSiteDataSheet(
        session: session,
        site: target,
        onEdit: {
          inspectingSite = nil
          editingSite = target
        },
        onDelete: {
          inspectingSite = nil
          pendingDeleteSite = target
        }
      )
    }
    .alert(
      "删除站点",
      isPresented: Binding(
        get: { pendingDeleteSite != nil },
        set: { if !$0 { pendingDeleteSite = nil } }),
      presenting: pendingDeleteSite
    ) { target in
      Button("删除", role: .destructive) {
        Task { await deleteSite(target) }
      }
      Button("取消", role: .cancel) {}
    } message: { target in
      Text("确认删除站点「\(target.name)」吗？删除后将无法恢复。")
    }
    .task(id: attempt) { await load(forceRefresh: attempt > 0) }
  }

  private var filteredSites: [NativeSiteItem] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return sites }
    return sites.filter { site in
      site.name.lowercased().contains(trimmed)
        || (site.domain ?? "").lowercased().contains(trimmed)
    }
  }

  private func siteCard(_ site: NativeSiteItem) -> some View {
    let active = site.isActive ?? true
    let state = testStates[site.id]
    let stats = trafficStats(for: site)
    return CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 12) {
          NativeSiteIconView(session: session, siteID: site.id, size: 42, active: active)
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Text(site.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
              NativeAdaptiveBadge(
                active ? "已启用" : "已停用", tint: active ? NativeTheme.success : nil)
            }
            HStack(spacing: 8) {
              if let domain = site.domain, !domain.isEmpty {
                Text(domain)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              if let pri = site.pri {
                Text("优先级 \(pri)")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
            if let state {
              testResultBadge(state)
            }
          }
          Spacer(minLength: 4)
          Button {
            Task { await testSite(site) }
          } label: {
            HStack(spacing: 4) {
              if state == .testing {
                ProgressView().controlSize(.mini).tint(.primary)
              } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                  .font(.caption2.weight(.semibold))
              }
              Text(state == .testing ? "检测中" : "测试")
                .font(.caption.weight(.semibold))
            }
            .foregroundStyle(NativeTheme.chipText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
              Capsule()
                .fill(NativeTheme.chipFill)
                .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
            }
            .frame(minHeight: 34)
          }
          .buttonStyle(.plain)
          .disabled(state == .testing)
          .accessibilityIdentifier("native-site-test-\(site.id)")
        }

        if let stats {
          siteTrafficBar(stats)
        }
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: CinematicStyle.radius, style: .continuous))
    .accessibilityIdentifier("native-site-card-\(site.id)")
    .onTapGesture {
      inspectingSite = site
    }
    .contextMenu {
      Button {
        inspectingSite = site
      } label: {
        Label("查看站点数据", systemImage: "chart.bar.doc.horizontal")
      }
      Button {
        editingSite = site
      } label: {
        Label("编辑站点", systemImage: "pencil")
      }
      Button {
        Task { await testSite(site) }
      } label: {
        Label("测试连通性", systemImage: "antenna.radiowaves.left.and.right")
      }
      Divider()
      Button(role: .destructive) {
        pendingDeleteSite = site
      } label: {
        Label("删除站点", systemImage: "trash")
      }
    }
  }

  private func siteTrafficBar(_ stats: NativeSiteUserData) -> some View {
    let up = max(stats.upload, 0)
    let down = max(stats.download, 0)
    let total = max(up + down, 1)
    let upRatio = min(max(up / total, 0.04), 0.96)
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 12) {
        HStack(spacing: 4) {
          Image(systemName: "arrow.up")
            .font(.caption2.weight(.bold))
            .foregroundStyle(NativeTheme.success)
          Text(Self.formatBytes(up))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary.opacity(0.92))
        }
        HStack(spacing: 4) {
          Image(systemName: "arrow.down")
            .font(.caption2.weight(.bold))
            .foregroundStyle(NativeTheme.pink)
          Text(Self.formatBytes(down))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary.opacity(0.84))
        }
        Spacer(minLength: 4)
        if stats.ratio > 0 {
          Text(String(format: "分享率 %.2f", stats.ratio))
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(NativeTheme.brand)
        }
        if stats.seeding > 0 {
          Text("做种 \(stats.seeding)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      GeometryReader { bar in
        let width = max(bar.size.width, 1)
        HStack(spacing: 2) {
          Capsule()
            .fill(
              LinearGradient(
                colors: [NativeTheme.success, NativeTheme.brand],
                startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: up > 0 ? max(width * upRatio - 1, 6) : 0)
          Capsule()
            .fill(NativeTheme.pink.opacity(0.85))
            .frame(width: down > 0 ? max(width * (1 - upRatio) - 1, 6) : 0)
        }
      }
      .frame(height: 5)
    }
    .padding(.top, 2)
  }

  private func trafficStats(for site: NativeSiteItem) -> NativeSiteUserData? {
    if let domain = site.domain?.lowercased(), let matched = userdataByDomain[domain] {
      return matched
    }
    return userdataByName[site.name.lowercased()]
  }

  fileprivate static func formatBytes(_ bytes: Double) -> String {
    let value = Int64(exactly: min(max(0, bytes), Double(Int64.max - 1)).rounded(.towardZero)) ?? 0
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
  }

  @ViewBuilder
  private func testResultBadge(_ state: TestState) -> some View {
    switch state {
    case .testing:
      Text("正在测试站点连通性…").font(.caption2).foregroundStyle(.secondary)
    case .passed:
      Label("连接正常", systemImage: "checkmark.circle.fill")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(NativeTheme.success)
        .accessibilityIdentifier("native-site-test-passed")
    case .failed:
      Label("连接测试失败", systemImage: "exclamationmark.triangle.fill")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(NativeTheme.danger)
    }
  }

  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "globe")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
        Text("暂无站点，点击右上角「+」新增站点").font(.subheadline).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 140)
    }
  }

  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入站点清单", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-sites-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func load(forceRefresh: Bool = false) async {
    let cacheKey = "sites|all"
    if !forceRefresh,
      let cached:
        (
          sites: [NativeSiteItem],
          byDomain: [String: NativeSiteUserData],
          byName: [String: NativeSiteUserData]
        ) = NativePageDataCache.shared.get(cacheKey, session: session)
    {
      sites = cached.sites
      userdataByDomain = cached.byDomain
      userdataByName = cached.byName
      isLoading = false
      loadFailed = false
      return
    }
    if sites.isEmpty { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["site"], trailingSlash: true)
      async let sitesTask = session.request(endpoint, as: [NativeSiteItem].self).value
      async let trafficTask = loadLatestTraffic()
      let (loaded, traffic) = try await (sitesTask, trafficTask)
      try Task.checkCancellation()
      sites = loaded
      var byDomain: [String: NativeSiteUserData] = [:]
      var byName: [String: NativeSiteUserData] = [:]
      for row in traffic {
        if let d = row.domain?.lowercased(), !d.isEmpty { byDomain[d] = row }
        if let n = row.name?.lowercased(), !n.isEmpty { byName[n] = row }
      }
      userdataByDomain = byDomain
      userdataByName = byName
      NativePageDataCache.shared.set(
        (sites: loaded, byDomain: byDomain, byName: byName),
        for: cacheKey, session: session)
    } catch is CancellationError {
      return
    } catch {
      if sites.isEmpty { loadFailed = true }
    }
  }

  private func loadLatestTraffic() async -> [NativeSiteUserData] {
    do {
      let endpoint = try APIEndpoint(path: ["site", "userdata", "latest"])
      return try await session.request(endpoint, as: [NativeSiteUserData].self).value
    } catch {
      return []
    }
  }

  private func testSite(_ site: NativeSiteItem) async {
    testStates[site.id] = .testing
    do {
      let endpoint = try APIEndpoint(path: ["site", "test", String(site.id)], timeout: 30)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      testStates[site.id] = .passed
    } catch is CancellationError {
      testStates.removeValue(forKey: site.id)
    } catch {
      testStates[site.id] = .failed
    }
  }

  private func deleteSite(_ site: NativeSiteItem) async {
    do {
      let ep = try APIEndpoint(path: ["site", String(site.id)], method: .delete)
      try await session.perform(ep, requiring: .init(category: .admin))
      sites.removeAll { $0.id == site.id }
      NativePageDataCache.shared.remove("sites|all", session: session)
      NativePageDataCache.shared.remove("settingsHub|overview.v2", session: session)
      feedback = (false, "已删除站点「\(site.name)」。")
    } catch {
      feedback = (true, "删除站点失败，请稍后重试。")
    }
  }
}

// MARK: - 站点数据详情弹窗（`GET/POST /api/v1/site/userdata/{id}`）

@MainActor
private struct NativeSiteDataSheet: View {
  let session: NativeSession
  let site: NativeSiteItem
  let onEdit: () -> Void
  let onDelete: () -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var history: [NativeSiteUserData] = []
  @State private var isLoading = true
  @State private var isRefreshing = false
  @State private var message: String?
  @State private var selectedHistoryIndex: Int?
  @State private var selectedSeedingIndex: Int?

  private static let seedingPointLimit = 200

  /// 最新一天站点统计数据（按统计日期升序排列后取末位，与 Web 保持一致）。
  private var latestData: NativeSiteUserData? { history.last }

  /// 最近两次统计的增量差值。
  private var previousData: NativeSiteUserData? {
    history.count >= 2 ? history[history.count - 2] : nil
  }

  /// 流量历史折线面积图采样序列（单位：GB，按时间从旧到新）。
  private var trafficPoints: [NativeSiteTrafficPoint] {
    history.enumerated().map { idx, row in
      NativeSiteTrafficPoint(
        index: idx,
        rawDay: row.updatedDay ?? "记录 #\(idx + 1)",
        shortDay: Self.formatShortDate(row.updatedDay ?? "记录 #\(idx + 1)"),
        uploadGB: row.upload / 1_073_741_824.0,
        downloadGB: row.download / 1_073_741_824.0,
        uploadBytes: row.upload,
        downloadBytes: row.download
      )
    }
  }

  /// 最新一天的做种分布散点（最多等距采样 200 个点并保留首尾，与 Web 保持一致）。
  private var seedingPoints: [NativeSiteSeedingPoint] {
    guard let source = latestData?.seedingInfo, !source.isEmpty else { return [] }
    let limit = Self.seedingPointLimit
    let sampled: [(Int, Double)]
    if source.count <= limit {
      sampled = source
    } else {
      sampled = (0..<limit).map { idx in
        let pos = Int(
          (Double(idx) * Double(source.count - 1) / Double(max(limit - 1, 1))).rounded())
        return source[min(max(pos, 0), source.count - 1)]
      }
    }
    return sampled.enumerated().map { idx, pair in
      NativeSiteSeedingPoint(
        index: idx,
        count: pair.0,
        volumeGB: pair.1 / 1_073_741_824.0,
        sizeBytes: pair.1
      )
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            // 站点头部
            CinematicPanel(padding: 15) {
              HStack(spacing: 12) {
                NativeSiteIconView(
                  session: session, siteID: site.id, size: 46, active: site.isActive ?? true)
                VStack(alignment: .leading, spacing: 3) {
                  Text(site.name).font(.headline)
                  Text(site.url ?? site.domain ?? "").font(.caption.monospaced())
                    .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                  Task { await refreshLiveData() }
                } label: {
                  HStack(spacing: 4) {
                    if isRefreshing {
                      ProgressView().controlSize(.mini).tint(.white)
                    } else {
                      Image(systemName: "arrow.clockwise").font(.caption2.weight(.semibold))
                    }
                    Text("刷新数据").font(.caption.weight(.semibold))
                  }
                  .foregroundStyle(.white)
                  .padding(.horizontal, 12).padding(.vertical, 7)
                  .background(appearance.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
              }
            }

            if let message {
              CinematicPanel(padding: 11) {
                Text(message).font(.caption).foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }

            if isLoading {
              NativeCardListSkeletonView(count: 2, style: .formPanel)
                .transition(.opacity)
            } else if let latest = latestData {
              LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
              ) {
                metricTile(
                  "上传量",
                  value: NativeSitesPage.formatBytes(latest.upload),
                  delta: previousData.map { Self.formatSignedBytes(latest.upload - $0.upload) },
                  deltaPositive: previousData.map { latest.upload >= $0.upload },
                  tint: NativeTheme.success)
                metricTile(
                  "下载量",
                  value: NativeSitesPage.formatBytes(latest.download),
                  delta: previousData.map { Self.formatSignedBytes(latest.download - $0.download) },
                  deltaPositive: previousData.map { latest.download >= $0.download },
                  tint: NativeTheme.warning)
                metricTile(
                  "分享率",
                  value: latest.download == 0 && latest.ratio == 0
                    ? "∞" : String(format: "%.2f", latest.ratio),
                  delta: previousData.map { Self.formatSignedDouble(latest.ratio - $0.ratio) },
                  deltaPositive: previousData.map { latest.ratio >= $0.ratio },
                  tint: NativeTheme.info)
                metricTile(
                  "做种数 / 体积",
                  value: "\(latest.seeding) · \(NativeSitesPage.formatBytes(latest.seedingSize))",
                  delta: previousData.map {
                    Self.formatSignedInt(latest.seeding - $0.seeding)
                  },
                  deltaPositive: previousData.map { latest.seeding >= $0.seeding },
                  tint: NativeTheme.brand)
                metricTile(
                  "魔力 / 积分",
                  value: String(format: "%.1f", latest.bonus),
                  delta: previousData.map { Self.formatSignedDouble(latest.bonus - $0.bonus) },
                  deltaPositive: previousData.map { latest.bonus >= $0.bonus },
                  tint: NativeTheme.warning)
                metricTile(
                  "用户等级", value: latest.userLevel?.isEmpty == false ? latest.userLevel! : "-",
                  tint: NativeTheme.cyan)
              }

              // 流量历史面积折线图（对标 Web 上传量/下载量 GB 双曲线趋势图）
              if !trafficPoints.isEmpty {
                trafficHistoryChartCard
              }

              // 做种分布散点图（对标 Web 做种数 × 做种体积 GB 散点图）
              if !seedingPoints.isEmpty {
                seedingDistributionChartCard(totalCount: latest.seedingInfo.count)
              }

              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  if let username = latest.username, !username.isEmpty {
                    kvRow("站点账号", value: username)
                    CinematicFormDivider()
                  }
                  if let joinAt = latest.joinAt, !joinAt.isEmpty {
                    kvRow("加入时间", value: joinAt)
                    CinematicFormDivider()
                  }
                  if let updated = latest.updatedDay, !updated.isEmpty {
                    kvRow("统计日期", value: updated)
                    CinematicFormDivider()
                  }
                  kvRow("未读消息", value: "\(latest.messageUnread)")
                }
              }
            } else {
              CinematicPanel(padding: 16) {
                Text("暂无该站点的流量统计记录，可点击上方「刷新数据」实时抓取。")
                  .font(.subheadline).foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, minHeight: 80)
              }
            }

            // 快捷操作
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                Button(action: onEdit) {
                  HStack {
                    Image(systemName: "pencil").foregroundStyle(.primary)
                    Text("编辑站点配置").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                  }
                  .padding(.horizontal, 15).padding(.vertical, 12)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                CinematicFormDivider()
                Button(role: .destructive, action: onDelete) {
                  HStack {
                    Image(systemName: "trash").foregroundStyle(NativeTheme.danger)
                    Text("删除此站点").font(.subheadline.weight(.medium)).foregroundStyle(
                      NativeTheme.danger)
                    Spacer()
                  }
                  .padding(.horizontal, 15).padding(.vertical, 12)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("native-site-data-scroll")
      }
      .navigationTitle("站点数据")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-site-data-close")
        }
      }
      .task { await loadUserData() }
    }
    .nativeGlassSheet()
    .nativeAdaptiveSheetSizing()
  }

  /// 历史流量双曲线面积图（上传量绿色 + 下载量琥珀色，支持手指滑动查看每日明细）。
  private var trafficHistoryChartCard: some View {
    let points = trafficPoints
    let activePoint: NativeSiteTrafficPoint? =
      selectedHistoryIndex.flatMap { idx in
        points.indices.contains(idx) ? points[idx] : nil
      }
    let xStride = max(1, points.count / 4)
    let xTicks = points.indices.filter {
      $0 == 0 || $0 == points.count - 1 || $0 % xStride == 0
    }
    return CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 8) {
          Image(systemName: "chart.xyaxis.line")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text("历史流量趋势")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Text("最近 \(points.count) 天 · GB")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        if let active = activePoint {
          HStack(spacing: 12) {
            Text(active.rawDay)
              .font(.caption2.monospacedDigit().weight(.semibold))
              .foregroundStyle(.primary)
            Spacer()
            Text("↑ \(NativeSitesPage.formatBytes(active.uploadBytes))")
              .font(.caption2.monospacedDigit().weight(.semibold))
              .foregroundStyle(NativeTheme.success)
            Text("↓ \(NativeSitesPage.formatBytes(active.downloadBytes))")
              .font(.caption2.monospacedDigit().weight(.semibold))
              .foregroundStyle(NativeTheme.warning)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(
            NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        Chart {
          ForEach(points) { pt in
            AreaMark(
              x: .value("日期", pt.index),
              y: .value("上传量", pt.uploadGB),
              series: .value("类型", "上传量"),
              stacking: .unstacked
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
              LinearGradient(
                colors: [NativeTheme.success.opacity(0.32), NativeTheme.success.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            LineMark(
              x: .value("日期", pt.index),
              y: .value("上传量", pt.uploadGB),
              series: .value("类型", "上传量")
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .foregroundStyle(NativeTheme.success)

            AreaMark(
              x: .value("日期", pt.index),
              y: .value("下载量", pt.downloadGB),
              series: .value("类型", "下载量"),
              stacking: .unstacked
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
              LinearGradient(
                colors: [NativeTheme.warning.opacity(0.30), NativeTheme.warning.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            LineMark(
              x: .value("日期", pt.index),
              y: .value("下载量", pt.downloadGB),
              series: .value("类型", "下载量")
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .foregroundStyle(NativeTheme.warning)
          }

          if let active = activePoint {
            RuleMark(x: .value("选中", active.index))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
              .foregroundStyle(.primary.opacity(0.35))
            PointMark(
              x: .value("日期", active.index),
              y: .value("上传量", active.uploadGB)
            )
            .symbolSize(46)
            .foregroundStyle(NativeTheme.success)
            PointMark(
              x: .value("日期", active.index),
              y: .value("下载量", active.downloadGB)
            )
            .symbolSize(46)
            .foregroundStyle(NativeTheme.warning)
          }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(points.count - 1, 1))
        .chartXAxis {
          AxisMarks(values: xTicks) { value in
            if let idx = value.as(Int.self), points.indices.contains(idx) {
              AxisValueLabel {
                Text(points[idx].shortDay)
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .chartYAxis {
          AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
              .foregroundStyle(NativeTheme.divider)
            AxisValueLabel {
              if let gb = value.as(Double.self) {
                Text(Self.formatCompactGB(gb))
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .chartOverlay { proxy in
          GeometryReader { geo in
            Rectangle()
              .fill(.clear)
              .contentShape(Rectangle())
              .gesture(
                DragGesture(minimumDistance: 12)
                  .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                      return
                    }
                    let origin = geo[proxy.plotAreaFrame].origin
                    let xPos = value.location.x - origin.x
                    if let rawIndex: Double = proxy.value(atX: xPos) {
                      let clamped = min(max(Int(rawIndex.rounded()), 0), points.count - 1)
                      selectedHistoryIndex = clamped
                    }
                  }
                  .onEnded { _ in
                    selectedHistoryIndex = nil
                  }
              )
          }
        }
        .frame(height: 196)

        HStack(spacing: 16) {
          HStack(spacing: 6) {
            Circle().fill(NativeTheme.success).frame(width: 8, height: 8)
            Text("上传量").font(.caption2).foregroundStyle(.secondary)
          }
          HStack(spacing: 6) {
            Circle().fill(NativeTheme.warning).frame(width: 8, height: 8)
            Text("下载量").font(.caption2).foregroundStyle(.secondary)
          }
          Spacer()
          Text("按住图表滑动查看每日数值")
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.75))
        }
      }
    }
  }

  /// 做种分布散点图（横轴做种数、纵轴做种体积 GB，与 Web `seeding_info` 图表对齐）。
  private func seedingDistributionChartCard(totalCount: Int) -> some View {
    let points = seedingPoints
    let activePoint: NativeSiteSeedingPoint? =
      selectedSeedingIndex.flatMap { idx in
        points.indices.contains(idx) ? points[idx] : nil
      }
    return CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 8) {
          Image(systemName: "chart.dots.scatter")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text("做种分布")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Text("GB")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        if let active = activePoint {
          HStack(spacing: 10) {
            Text("做种数 \(active.count)")
              .font(.caption2.monospacedDigit().weight(.semibold))
            Spacer()
            Text("体积 \(NativeSitesPage.formatBytes(active.sizeBytes))")
              .font(.caption2.monospacedDigit().weight(.semibold))
              .foregroundStyle(appearance.accentColor)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(
            NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        Chart(points) { pt in
          PointMark(
            x: .value("做种数", pt.count),
            y: .value("体积", pt.volumeGB)
          )
          .symbolSize(activePoint?.id == pt.id ? 64 : 34)
          .foregroundStyle(
            activePoint?.id == pt.id
              ? appearance.accentColor
              : appearance.accentColor.opacity(0.72)
          )
        }
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 5)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
              .foregroundStyle(NativeTheme.divider)
            AxisValueLabel {
              if let count = value.as(Int.self) {
                Text("\(count)")
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .chartYAxis {
          AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
              .foregroundStyle(NativeTheme.divider)
            AxisValueLabel {
              if let gb = value.as(Double.self) {
                Text(Self.formatCompactGB(gb))
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .chartOverlay { proxy in
          GeometryReader { geo in
            Rectangle()
              .fill(.clear)
              .contentShape(Rectangle())
              .gesture(
                DragGesture(minimumDistance: 12)
                  .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                      return
                    }
                    let origin = geo[proxy.plotAreaFrame].origin
                    let xPos = value.location.x - origin.x
                    if let targetX: Double = proxy.value(atX: xPos) {
                      selectedSeedingIndex =
                        points.enumerated().min {
                          abs(Double($0.element.count) - targetX)
                            < abs(Double($1.element.count) - targetX)
                        }?.offset
                    }
                  }
                  .onEnded { _ in
                    selectedSeedingIndex = nil
                  }
              )
          }
        }
        .frame(height: 176)

        HStack(spacing: 12) {
          HStack(spacing: 6) {
            Circle().fill(appearance.accentColor).frame(width: 8, height: 8)
            Text("做种体积（横轴：做种数）").font(.caption2).foregroundStyle(.secondary)
          }
          Spacer()
          if totalCount > Self.seedingPointLimit {
            Text("采样 \(Self.seedingPointLimit) / \(totalCount) 点")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func metricTile(
    _ title: String,
    value: String,
    delta: String? = nil,
    deltaPositive: Bool? = nil,
    tint: Color
  ) -> some View {
    CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 4) {
          Text(title).font(.caption2).foregroundStyle(.secondary)
          Spacer(minLength: 2)
          if let delta, !delta.isEmpty, delta != "0" {
            Text(delta)
              .font(.caption2.monospacedDigit().weight(.medium))
              .foregroundStyle(
                deltaPositive == false ? NativeTheme.danger : NativeTheme.success
              )
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }
        Text(value)
          .font(.subheadline.monospacedDigit().weight(.bold))
          .foregroundStyle(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private static func formatShortDate(_ raw: String) -> String {
    let clean = raw.split(separator: " ").first.map(String.init) ?? raw
    let parts = clean.split(separator: "-")
    if parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) {
      return "\(m)/\(d)"
    }
    return clean
  }

  private static func formatCompactGB(_ gb: Double) -> String {
    let rounded = Int(gb.rounded())
    if rounded >= 10_000 {
      return String(format: "%.1fT", gb / 1024.0)
    }
    return "\(rounded)"
  }

  private static func formatSignedBytes(_ diff: Double) -> String {
    if abs(diff) < 1 { return "0" }
    let sign = diff > 0 ? "+" : "-"
    return "\(sign)\(NativeSitesPage.formatBytes(abs(diff)))"
  }

  private static func formatSignedDouble(_ diff: Double) -> String {
    if abs(diff) < 0.01 { return "0" }
    return String(format: "%+.1f", diff)
  }

  private static func formatSignedInt(_ diff: Int) -> String {
    if diff == 0 { return "0" }
    return diff > 0 ? "+\(diff)" : "\(diff)"
  }

  private func kvRow(_ k: String, value: String) -> some View {
    HStack {
      Text(k).font(.subheadline).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }

  private func loadUserData() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let ep = try APIEndpoint(
        path: ["site", "userdata", String(site.id)],
        query: [
          URLQueryItem(name: "page", value: "1"),
          URLQueryItem(name: "count", value: "90"),
          URLQueryItem(name: "latest_seeding_only", value: "true"),
        ],
        responseContract: .payload)
      let reply = try await session.request(
        ep, as: NativeSiteUserDataEnvelope.self, requiring: .init(category: .admin)
      ).value
      let sorted = (reply.data ?? []).sorted {
        ($0.updatedDay ?? "") < ($1.updatedDay ?? "")
      }
      history = Array(sorted.suffix(90))
    } catch {
      history = []
    }
  }

  private func refreshLiveData() async {
    isRefreshing = true
    message = nil
    defer { isRefreshing = false }
    do {
      let ep = try APIEndpoint(
        path: ["site", "userdata", String(site.id)], method: .post, timeout: 45)
      try await session.perform(ep, requiring: .init(category: .admin))
      message = "已刷新最新站点流量与做种统计。"
      await loadUserData()
    } catch {
      message = "实时刷新失败，请检查站点 Cookie 或代理状态。"
    }
  }
}

// MARK: - 站点新增 / 编辑弹窗（iOS 原生分组列表风格）

@MainActor
private struct NativeSiteEditorSheet: View {
  let session: NativeSession
  let existing: NativeSiteItem?
  var onDelete: (() -> Void)? = nil
  let onSaved: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var name = ""
  @State private var url = ""
  @State private var pri = 1
  @State private var rss = ""
  @State private var cookie = ""
  @State private var ua = ""
  @State private var apiKey = ""
  @State private var token = ""
  @State private var timeout = 15
  @State private var proxy = false
  @State private var render = false
  @State private var isActive = true
  @State private var downloader = ""
  @State private var filter = ""
  @State private var isSubmitting = false
  @State private var errorMsg: String?

  private var isCreate: Bool { existing == nil }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if let errorMsg {
              CinematicPanel(padding: 11) {
                Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                  .font(.caption).foregroundStyle(NativeTheme.danger)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }

            // 基本信息
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("站点名称", placeholder: "必填，如 M-Team", text: $name)
                CinematicFormDivider()
                rowField("站点地址", placeholder: "https://example.com", text: $url)
                CinematicFormDivider()
                Stepper("搜索优先级：\(pri)", value: $pri, in: 0...999)
                  .font(.subheadline)
                  .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                Toggle("启用站点", isOn: $isActive)
                  .font(.subheadline).tint(appearance.accentColor)
                  .padding(.horizontal, 15).padding(.vertical, 10)
              }
            }

            // 认证凭据与 RSS
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("RSS 地址", placeholder: "可选", text: $rss)
                CinematicFormDivider()
                rowField("Cookie", placeholder: isCreate ? "可选" : "留空保留原值", text: $cookie)
                CinematicFormDivider()
                rowField("User-Agent", placeholder: "可选", text: $ua)
                CinematicFormDivider()
                rowField("API Key", placeholder: "可选", text: $apiKey)
                CinematicFormDivider()
                rowField("Token", placeholder: "可选", text: $token)
              }
            }

            // 请求与下载选项
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                Toggle("使用代理访问", isOn: $proxy)
                  .font(.subheadline).tint(appearance.accentColor)
                  .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                Toggle("浏览器仿真渲染", isOn: $render)
                  .font(.subheadline).tint(appearance.accentColor)
                  .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                Stepper("请求超时：\(timeout) 秒", value: $timeout, in: 5...120, step: 5)
                  .font(.subheadline)
                  .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                rowField("指定下载器", placeholder: "留空使用默认", text: $downloader)
                CinematicFormDivider()
                rowField("过滤规则", placeholder: "可选正则", text: $filter)
              }
            }

            if let onDelete {
              CinematicPanel(padding: 0) {
                Button(role: .destructive, action: onDelete) {
                  Text("删除此站点")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NativeTheme.danger)
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
              }
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
      }
      .navigationTitle(isCreate ? "新增站点" : "编辑站点")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await submit() }
          } label: {
            if isSubmitting {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Text("保存").fontWeight(.semibold)
            }
          }
          .tint(.primary)
          .disabled(
            isSubmitting
              || name.trimmingCharacters(in: .whitespaces).isEmpty
              || url.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear {
        if let existing {
          name = existing.name
          url = existing.url ?? (existing.domain.map { "https://\($0)" } ?? "")
          pri = existing.pri ?? 1
          rss = existing.rss ?? ""
          ua = existing.ua ?? ""
          timeout = existing.timeout ?? 15
          proxy = (existing.proxy ?? 0) != 0
          render = (existing.render ?? 0) != 0
          isActive = existing.isActive ?? true
          downloader = existing.downloader ?? ""
          filter = existing.filter ?? ""
        }
      }
    }
    .nativeGlassSheet()
    .nativeAdaptiveSheetSizing()
  }

  private func rowField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
    HStack(spacing: 12) {
      Text(label).font(.subheadline).frame(width: 86, alignment: .leading)
      TextField(placeholder, text: text)
        .font(.subheadline).multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }

  private func submit() async {
    isSubmitting = true
    errorMsg = nil
    defer { isSubmitting = false }
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    var payload: [String: JSONValue] = [
      "name": .string(trimmedName),
      "url": .string(trimmedURL),
      "pri": .number(Double(pri)),
      "timeout": .number(Double(timeout)),
      "proxy": .number(proxy ? 1 : 0),
      "render": .number(render ? 1 : 0),
      "is_active": .bool(isActive),
    ]
    if let existing {
      payload["id"] = .number(Double(existing.id))
      if let domain = existing.domain, !domain.isEmpty { payload["domain"] = .string(domain) }
    }
    if !rss.trimmingCharacters(in: .whitespaces).isEmpty {
      payload["rss"] = .string(rss.trimmingCharacters(in: .whitespaces))
    }
    if !cookie.trimmingCharacters(in: .whitespaces).isEmpty {
      payload["cookie"] = .string(cookie.trimmingCharacters(in: .whitespaces))
    }
    if !ua.trimmingCharacters(in: .whitespaces).isEmpty {
      payload["ua"] = .string(ua.trimmingCharacters(in: .whitespaces))
    }
    if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
      payload["apikey"] = .string(apiKey.trimmingCharacters(in: .whitespaces))
    }
    if !token.trimmingCharacters(in: .whitespaces).isEmpty {
      payload["token"] = .string(token.trimmingCharacters(in: .whitespaces))
    }
    if !downloader.trimmingCharacters(in: .whitespaces).isEmpty {
      payload["downloader"] = .string(downloader.trimmingCharacters(in: .whitespaces))
    }
    if !filter.trimmingCharacters(in: .whitespaces).isEmpty {
      payload["filter"] = .string(filter.trimmingCharacters(in: .whitespaces))
    }

    do {
      let body = try JSONEncoder().encode(payload)
      let ep = try APIEndpoint(
        path: ["site"], method: isCreate ? .post : .put, body: body, trailingSlash: true)
      try await session.perform(ep, requiring: .init(category: .admin))
      onSaved(isCreate ? "已新增站点「\(trimmedName)」。" : "已更新站点「\(trimmedName)」。")
      dismiss()
    } catch {
      errorMsg = "保存站点失败，请检查站点地址与格式。"
    }
  }
}

// MARK: - 站点解码模型

private struct NativeSiteItem: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let domain: String?
  let url: String?
  let isActive: Bool?
  let pri: Int?
  let rss: String?
  let ua: String?
  let proxy: Int?
  let render: Int?
  let timeout: Int?
  let downloader: String?
  let filter: String?

  private enum CodingKeys: String, CodingKey {
    case id, name, domain, url, pri, rss, ua, proxy, render, timeout, downloader, filter
    case isActive = "is_active"
  }
}

private struct NativeSiteUserDataEnvelope: Decodable, Sendable {
  let success: Bool?
  let data: [NativeSiteUserData]?
}

private struct NativeSiteTrafficPoint: Identifiable {
  let index: Int
  let rawDay: String
  let shortDay: String
  let uploadGB: Double
  let downloadGB: Double
  let uploadBytes: Double
  let downloadBytes: Double

  var id: Int { index }
}

private struct NativeSiteSeedingPoint: Identifiable {
  let index: Int
  let count: Int
  let volumeGB: Double
  let sizeBytes: Double

  var id: Int { index }
}

private struct NativeSiteUserData: Decodable, Sendable {
  let domain: String?
  let name: String?
  let username: String?
  let userLevel: String?
  let joinAt: String?
  let updatedDay: String?
  let upload: Double
  let download: Double
  let ratio: Double
  let seeding: Int
  let seedingSize: Double
  let seedingInfo: [(Int, Double)]
  let bonus: Double
  let messageUnread: Int

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    domain = try? c.decodeIfPresent(String.self, forKey: .domain)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    username = try? c.decodeIfPresent(String.self, forKey: .username)
    userLevel = try? c.decodeIfPresent(String.self, forKey: .userLevel)
    joinAt = try? c.decodeIfPresent(String.self, forKey: .joinAt)
    updatedDay = try? c.decodeIfPresent(String.self, forKey: .updatedDay)
    upload = (try? c.decodeIfPresent(Double.self, forKey: .upload)) ?? 0
    download = (try? c.decodeIfPresent(Double.self, forKey: .download)) ?? 0
    ratio = (try? c.decodeIfPresent(Double.self, forKey: .ratio)) ?? 0
    seeding = (try? c.decodeIfPresent(Int.self, forKey: .seeding)) ?? 0
    seedingSize = (try? c.decodeIfPresent(Double.self, forKey: .seedingSize)) ?? 0
    if let rawPairs = try? c.decodeIfPresent([[Double]].self, forKey: .seedingInfo) {
      seedingInfo = rawPairs.compactMap { pair in
        guard pair.count >= 2 else { return nil }
        return (Int(pair[0].rounded()), pair[1])
      }
    } else {
      seedingInfo = []
    }
    bonus = (try? c.decodeIfPresent(Double.self, forKey: .bonus)) ?? 0
    messageUnread = (try? c.decodeIfPresent(Int.self, forKey: .messageUnread)) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case domain, name, username, upload, download, ratio, seeding, bonus
    case userLevel = "user_level"
    case joinAt = "join_at"
    case updatedDay = "updated_day"
    case seedingSize = "seeding_size"
    case seedingInfo = "seeding_info"
    case messageUnread = "message_unread"
  }
}
