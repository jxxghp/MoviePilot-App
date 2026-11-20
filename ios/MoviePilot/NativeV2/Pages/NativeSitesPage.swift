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
        Button {
          attempt += 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("刷新站点列表")
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

  /// 单站透色玻璃卡片：站名、域名、启用徽标、优先级与一键连通测试。
  private func siteCard(_ site: NativeSiteItem) -> some View {
    let active = site.isActive ?? true
    let state = testStates[site.id]
    return CinematicPanel(padding: 13) {
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
    }
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

  /// 从 `GET /api/v1/site/` 读取站点清单（只解码非敏感元数据）。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["site"], trailingSlash: true)
      let loaded = try await session.request(endpoint, as: [NativeSiteItem].self).value
      try Task.checkCancellation()
      sites = loaded
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
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
