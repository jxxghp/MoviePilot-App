import Foundation
import Testing

@testable import MoviePilotCore

/// 直接验证系统未来时间线和隐私投影，防止只有联网时才隐藏过期内容。
struct WidgetDisplayTests {
  private let now = Date(timeIntervalSince1970: 1_792_800_000)

  /// 未配置、缺失快照或 owner 不符均不显示任何业务数据。
  @Test func rejectsMissingOrDifferentAccount() throws {
    let profile = try WidgetTestData.profile(now: now)
    let snapshot = try WidgetTestData.snapshot(profile, at: now)
    let other = try WidgetTestData.profile(owner: String(repeating: "b", count: 32), now: now)
    for candidate in [nil, other] {
      let value = WidgetDisplay(
        profile: candidate, snapshot: snapshot, content: .downloads, showMediaNames: true, at: now)
      #expect(value.metrics.isEmpty && value.items.isEmpty)
      #expect(value.updatedAt == nil)
    }
    let value = WidgetDisplay(
      profile: profile, snapshot: nil, content: .downloads, showMediaNames: true, at: now)
    #expect(value.state == .unavailable)
    #expect(value.metrics.isEmpty)
  }

  /// 未授权内容不能退回显示另一个内容，链接仍只含本机资料与固定内容。
  @Test func keepsSelectionAndAllowedContentsSeparate() throws {
    let profile = try WidgetTestData.profile(now: now)
    let snapshot = try WidgetTestData.snapshot(profile, at: now)
    let value = WidgetDisplay(
      profile: profile, snapshot: snapshot, content: .overview, showMediaNames: true, at: now)
    #expect(value.state == .unavailable)
    #expect(value.metrics.isEmpty)
    #expect(
      value.link.flatMap { WidgetLink(url: $0) }
        == WidgetLink(profileId: profile.id, content: .overview))
  }

  /// 断网只改变提示，不改变真实采样时间；30分钟后变旧，到期节点清空具体内容。
  @Test func changesFreshnessWithoutAnotherNetworkRequest() throws {
    let profile = try WidgetTestData.profile(now: now)
    let snapshot = try WidgetTestData.snapshot(profile, at: now)
    let fresh = WidgetDisplay(
      profile: profile, snapshot: snapshot, content: .downloads, showMediaNames: false,
      at: now, connectionFailed: true)
    #expect(fresh.state == .ready && fresh.metrics.first?.value == "1")
    #expect(fresh.updatedAt == now)
    #expect(fresh.message == "暂时无法连接")
    let stale = WidgetDisplay(
      profile: profile, snapshot: snapshot, content: .downloads, showMediaNames: false,
      at: now.addingTimeInterval(1800))
    #expect(stale.state == .stale)
    #expect(stale.updatedAt == now)
    let expired = WidgetDisplay(
      profile: profile, snapshot: snapshot, content: .downloads, showMediaNames: true,
      at: now.addingTimeInterval(3600))
    #expect(expired.state == .expired)
    #expect(expired.metrics.isEmpty && expired.items.isEmpty && expired.updatedAt == nil)
  }

  /// 凭据期限早于缓存时同样到期隐藏，不允许网络失败沿用授权外的内容。
  @Test func hidesDataAtCredentialExpiry() throws {
    let original = try WidgetTestData.profile(now: now)
    let profile = try WidgetProfile(
      id: original.id, instanceId: original.instanceId, owner: original.owner, name: original.name,
      address: original.address, registrationId: original.registrationId,
      credentialExpiresAt: now.timeIntervalSince1970 + 100)
    let snapshot = try WidgetTestData.snapshot(profile, at: now)
    let value = WidgetDisplay(
      profile: profile, snapshot: snapshot, content: .downloads, showMediaNames: true,
      at: now.addingTimeInterval(100))
    #expect(value.state == .expired)
    #expect(value.link == nil && value.metrics.isEmpty)
  }

  /// 锁屏默认投影移除媒体名称、副标题和时间，只留下已有的自然进度。
  @Test func removesMediaNamesUntilExplicitlyEnabled() throws {
    let profile = try WidgetTestData.profile(now: now)
    var json = try #require(
      JSONSerialization.jsonObject(with: WidgetTestData.data(profile, at: now)) as? [String: Any])
    var sections = try #require(json["sections"] as? [[String: Any]])
    sections[0]["items"] = [
      [
        "id": "synthetic-1", "title": "合成电影", "subtitle": "合成说明", "progress": 0.4,
        "timestamp": now.timeIntervalSince1970,
      ]
    ]
    json["sections"] = sections
    let snapshot = try WidgetSnapshot.decode(
      JSONSerialization.data(withJSONObject: json), owner: profile.owner, now: now)
    let hidden = WidgetDisplay(
      profile: profile, snapshot: snapshot, content: .downloads, showMediaNames: false, at: now)
    let visible = WidgetDisplay(
      profile: profile, snapshot: snapshot, content: .downloads, showMediaNames: true, at: now)
    #expect(hidden.items.first?.title == "项目 1")
    #expect(hidden.items.first?.subtitle == nil && hidden.items.first?.timestamp == nil)
    #expect(hidden.items.first?.progress == 0.4)
    #expect(visible.items.first?.title == "合成电影")
  }

  /// 时间线精确包含失效边界并去重排序，系统推迟联网也能及时隐藏本地数据。
  @Test func schedulesLocalRedactionBoundaries() throws {
    let profile = try WidgetTestData.profile(now: now)
    let snapshot = try WidgetTestData.snapshot(profile, at: now)
    let dates = WidgetDisplay.timelineDates(
      profile: profile, snapshot: snapshot, content: .downloads, now: now)
    #expect(
      dates == [
        now, now.addingTimeInterval(1800), now.addingTimeInterval(3600),
        now.addingTimeInterval(86_400),
      ])
    #expect(
      WidgetDisplay.timelineDates(profile: nil, snapshot: nil, content: .downloads, now: now) == [
        now
      ])
  }
}
