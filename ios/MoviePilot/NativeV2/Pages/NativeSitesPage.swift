import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生站点管理页：展示站点列表、状态筛选与单站实时连通检测，绝不展示 Cookie/API Key/Passkey 敏感信息。
@MainActor
struct NativeSitesPage: View {
  /// 站点启用状态过滤。
  private enum Filter: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "已启用"
    case inactive = "已停用"

    /// 固定标签作为标识。
    var id: String { rawValue }
  }

  /// 单站连通测试实时状态。
  private enum TestState: Equatable {
    case testing
    case passed
    case failed
  }

  let session: NativeSession

  @State private var sites: [NativeSiteItem] = []
  @State private var userdataByDomain: [String: NativeSiteUserData] = [:]
  @State private var userdataByName: [String: NativeSiteUserData] = [:]
  @State private var filter: Filter = .all
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var testStates: [Int: TestState] = [:]

  /// 连续深色紫玫瑰渐变背景、站点筛选胶囊与透色玻璃站点卡。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          filterBar
          if isLoading && sites.isEmpty {
            ProgressView("正在载入站点清单…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 220)
          } else if loadFailed && sites.isEmpty {
            failureCard
          } else if filteredSites.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 12) {
              ForEach(filteredSites) { site in
                siteCard(site)
              }
            }
          }
        }
        .frame(maxWidth: 840)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-sites-scroll")
    }
    .navigationTitle(sites.isEmpty ? "站点管理" : "站点管理 (\(sites.count))")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .searchable(text: $searchText, prompt: "按站点名或域名筛选")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button {
            attempt += 1
          } label: {
            Label("刷新站点与流量", systemImage: "arrow.clockwise")
          }
          Divider()
          ForEach(Filter.allCases) { option in
            Button {
              filter = option
            } label: {
              if filter == option {
                Label(option.rawValue, systemImage: "checkmark")
              } else {
                Text(option.rawValue)
              }
            }
          }
        } label: {
          Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多站点操作")
        .accessibilityIdentifier("native-sites-refresh")
      }
    }
    .task(id: attempt) { await load() }
  }

  /// 按启用状态与关键字筛选后的站点清单。
  private var filteredSites: [NativeSiteItem] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return sites.filter { site in
      let matchesFilter: Bool =
        switch filter {
        case .all: true
        case .active: site.isActive ?? true
        case .inactive: !(site.isActive ?? true)
        }
      guard matchesFilter else { return false }
      guard !trimmed.isEmpty else { return true }
      return site.name.lowercased().contains(trimmed)
        || (site.domain ?? "").lowercased().contains(trimmed)
    }
  }

  /// 顶部分类胶囊栏，实时显示各状态站点数。
  private var filterBar: some View {
    HStack(spacing: 8) {
      ForEach(Filter.allCases) { option in
        let count = countFor(option)
        let selected = filter == option
        Button {
          filter = option
        } label: {
          Text(count > 0 ? "\(option.rawValue) \(count)" : option.rawValue)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(.white.opacity(selected ? 0.98 : 0.78))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
              Capsule()
                .fill(.white.opacity(selected ? 0.22 : 0.08))
                .overlay {
                  Capsule().strokeBorder(.white.opacity(selected ? 0.28 : 0.14), lineWidth: 0.6)
                }
            }
            .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-sites-filter-\(option.rawValue)")
      }
      Spacer()
    }
  }

  /// 计算单个状态下的站点数量。
  private func countFor(_ option: Filter) -> Int {
    switch option {
    case .all: sites.count
    case .active: sites.filter { $0.isActive ?? true }.count
    case .inactive: sites.filter { !($0.isActive ?? true) }.count
    }
  }

  /// 单站透色玻璃卡片：站名、域名、启用徽标、上下行流量比例图示与一键连通测试。
  private func siteCard(_ site: NativeSiteItem) -> some View {
    let active = site.isActive ?? true
    let state = testStates[site.id]
    let stats = trafficStats(for: site)
    return CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 12) {
          ZStack {
            Circle()
              .fill(
                active
                  ? Color(red: 0.44, green: 0.34, blue: 0.68).opacity(0.55) : .white.opacity(0.08))
            Image(systemName: active ? "globe" : "globe.badge.chevron.backward")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white.opacity(active ? 0.95 : 0.48))
          }
          .frame(width: 40, height: 40)
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Text(site.name)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
              Text(active ? "已启用" : "已停用")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                  active ? Color(red: 0.56, green: 0.92, blue: 0.72) : .white.opacity(0.50)
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background { Capsule().fill(.white.opacity(0.10)) }
            }
            HStack(spacing: 8) {
              if let domain = site.domain, !domain.isEmpty {
                Text(domain)
                  .font(.caption)
                  .foregroundStyle(.white.opacity(0.65))
                  .lineLimit(1)
              }
              if let pri = site.pri {
                Text("优先级 \(pri)")
                  .font(.caption2)
                  .foregroundStyle(.white.opacity(0.52))
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
                ProgressView().controlSize(.mini).tint(.white)
              } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                  .font(.caption2.weight(.semibold))
              }
              Text(state == .testing ? "检测中" : "测试")
                .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
              Capsule()
                .fill(.white.opacity(0.14))
                .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6) }
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
    .contextMenu {
      Button {
        Task { await testSite(site) }
      } label: {
        Label("测试站点连通性", systemImage: "antenna.radiowaves.left.and.right")
      }
      Button {
        attempt += 1
      } label: {
        Label("刷新站点流量数据", systemImage: "arrow.clockwise")
      }
    }
  }

  /// 站点上传 / 下载流量双向比例彩条图示与分享率摘要。
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
            .foregroundStyle(Color(red: 0.50, green: 0.90, blue: 0.76))
          Text(Self.formatBytes(up))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
        }
        HStack(spacing: 4) {
          Image(systemName: "arrow.down")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color(red: 0.94, green: 0.54, blue: 0.72))
          Text(Self.formatBytes(down))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.84))
        }
        Spacer(minLength: 4)
        if stats.ratio > 0 {
          Text(String(format: "分享率 %.2f", stats.ratio))
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(Color(red: 0.84, green: 0.74, blue: 1.0))
        }
        if stats.seeding > 0 {
          Text("做种 \(stats.seeding)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))
        }
      }
      GeometryReader { bar in
        let width = max(bar.size.width, 1)
        HStack(spacing: 2) {
          Capsule()
            .fill(
              LinearGradient(
                colors: [
                  Color(red: 0.44, green: 0.86, blue: 0.76),
                  Color(red: 0.62, green: 0.50, blue: 0.96),
                ],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(width: up > 0 ? max(width * upRatio - 1, 6) : 0)
          Capsule()
            .fill(Color(red: 0.92, green: 0.52, blue: 0.68).opacity(0.85))
            .frame(width: down > 0 ? max(width * (1 - upRatio) - 1, 6) : 0)
        }
      }
      .frame(height: 5)
    }
    .padding(.top, 2)
  }

  /// 按域名或站点名匹配最新流量快照。
  private func trafficStats(for site: NativeSiteItem) -> NativeSiteUserData? {
    if let domain = site.domain?.lowercased(), let matched = userdataByDomain[domain] {
      return matched
    }
    return userdataByName[site.name.lowercased()]
  }

  /// 字节格式化为可读容量单位。
  private static func formatBytes(_ bytes: Double) -> String {
    let value = Int64(exactly: min(bytes, Double(Int64.max - 1)).rounded(.towardZero)) ?? 0
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
  }

  /// 连通检测状态文本。
  @ViewBuilder
  private func testResultBadge(_ state: TestState) -> some View {
    switch state {
    case .testing:
      Text("正在测试站点连通性…").font(.caption2).foregroundStyle(.white.opacity(0.68))
    case .passed:
      Label("连接正常", systemImage: "checkmark.circle.fill")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color(red: 0.56, green: 0.92, blue: 0.72))
        .accessibilityIdentifier("native-site-test-passed")
    case .failed:
      Label("连接测试失败", systemImage: "exclamationmark.triangle.fill")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.orange)
    }
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "globe")
          .font(.largeTitle)
          .foregroundStyle(.white.opacity(0.55))
        Text("暂无匹配的站点").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 载入失败卡片。
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

  /// 从 `GET /api/v1/site/` 并发读取站点清单与 `GET /api/v1/site/userdata/latest` 流量快照。
  private func load() async {
    isLoading = true
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
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 读取所有站点最新流量统计，失败时静默降级不阻断站点管理。
  private func loadLatestTraffic() async -> [NativeSiteUserData] {
    do {
      let endpoint = try APIEndpoint(path: ["site", "userdata", "latest"])
      return try await session.request(endpoint, as: [NativeSiteUserData].self).value
    } catch {
      return []
    }
  }

  /// 单次执行站点连通性测试（`GET /api/v1/site/test/{id}`）。
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
}

/// 站点清单非敏感投影，主动忽略 cookie / apikey / token / rss 敏感字段。
private struct NativeSiteItem: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let domain: String?
  let isActive: Bool?
  let pri: Int?
  let isPublic: Int?

  /// 仅解码展示所需的非敏感字段。
  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case domain
    case isActive = "is_active"
    case pri
    case isPublic = "public"
  }
}

/// `GET /api/v1/site/userdata/latest` 非敏感站点上下行流量投影。
private struct NativeSiteUserData: Decodable, Sendable {
  let domain: String?
  let name: String?
  let upload: Double
  let download: Double
  let ratio: Double
  let seeding: Int

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    domain = try? c.decodeIfPresent(String.self, forKey: .domain)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    upload = (try? c.decodeIfPresent(Double.self, forKey: .upload)) ?? 0
    download = (try? c.decodeIfPresent(Double.self, forKey: .download)) ?? 0
    ratio = (try? c.decodeIfPresent(Double.self, forKey: .ratio)) ?? 0
    seeding = (try? c.decodeIfPresent(Int.self, forKey: .seeding)) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case domain, name, upload, download, ratio, seeding
  }
}
