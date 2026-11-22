import Foundation
import Testing

@testable import MoviePilotCore

@Suite("CommunityMedalsModel 社区勋章模型与档位进度测试")
struct CommunityMedalsModelTests {
  @Test("完整解码后端 /api/v1/github/community 响应并按官方目录排序")
  func decodesProfileAndOrdersMedals() throws {
    let json = """
      {
        "state": "ready",
        "login": "jxxghp",
        "user_id": 51039935,
        "medals": [
          {"key": "pioneer", "at": "2026-10-16"},
          {"key": "unknown_future", "at": "2026-11-01"},
          {
            "key": "code",
            "tier": 4,
            "specialty": "ecosystem",
            "at": "2023-06-10",
            "basis": "reached",
            "facts": {
              "total": 14676,
              "repositories": [
                {"repository": "MoviePilot", "area": "backend", "commits": 8186, "merged_prs": 175}
              ]
            }
          },
          {
            "key": "plugin",
            "tier": 2,
            "at": "2026-10-15",
            "basis": "recognized",
            "facts": {
              "installs": 55000,
              "plugins": [
                {"id": "SiteStatistic", "name": "站点数据统计", "market": "jxxghp/MoviePilot-Plugins", "installs": 55000}
              ]
            }
          }
        ],
        "generated_at": "2026-11-21T23:23:15Z",
        "checked_at": 1795334528,
        "stale": false,
        "refreshing": false
      }
      """
    let profile = try JSONDecoder().decode(CommunityProfile.self, from: Data(json.utf8))
    #expect(profile.state == .ready)
    #expect(profile.login == "jxxghp")
    #expect(profile.userID == 51_039_935)
    #expect(profile.hasEarnedMedals)
    #expect(profile.orderedKnownMedals.map(\.key) == ["code", "plugin", "pioneer"])

    let code = profile.orderedKnownMedals[0]
    #expect(code.seenToken == "code:t4")
    #expect(CommunityMedalCatalog.frontAssetStem(for: code) == "code-front-t4")
    #expect(CommunityMedalCatalog.badgeAssetStem(for: code) == "code-badge-t4")
    #expect(CommunityMedalCatalog.backAssetStem(for: code) == "code-back")

    let engraving = CommunityMedalCatalog.engraving(for: code, login: profile.login)
    #expect(engraving.title == "编剧")
    #expect(engraving.tierLine == "核心 · 生态共建者")
    #expect(engraving.recipientLine == "授予 @jxxghp")
    #expect(engraving.timeLine == "达成 2023.06.10")
    #expect(engraving.makerMark == "MoviePilot")

    let codeProgress = try #require(CommunityMedalCatalog.tierProgress(for: code))
    #expect(codeProgress.currentTier == 4)
    #expect(codeProgress.nextTier == nil)
    #expect(codeProgress.trackFill == 1)
    #expect(codeProgress.statusText == "已达最高档")

    let plugin = profile.orderedKnownMedals[1]
    let pluginProgress = try #require(CommunityMedalCatalog.tierProgress(for: plugin))
    #expect(pluginProgress.currentTier == 2)
    #expect(pluginProgress.nextTier == 3)
    #expect(pluginProgress.fractionToNext == 0.5)
    #expect(pluginProgress.statusText.contains("距卓越还差"))
    #expect(pluginProgress.statusText.contains("45,000"))

    let pioneer = profile.orderedKnownMedals[2]
    #expect(pioneer.seenToken == "pioneer")
    #expect(CommunityMedalCatalog.frontAssetStem(for: pioneer) == "pioneer-front")
    #expect(CommunityMedalCatalog.tierProgress(for: pioneer) == nil)
    #expect(CommunityMedalCatalog.timeLine(for: pioneer) == "2026.10.16")
  }

  @Test("官方仓库白名单正确构造或拒绝 GitHub 证据链接")
  func officialRepositoryEvidenceURLs() {
    let prURL = CommunityMedalCatalog.officialRepoPRsURL(
      repository: "MoviePilot", login: "jxxghp")
    #expect(prURL?.absoluteString.contains("github.com/jxxghp/MoviePilot/pulls") == true)
    let commitURL = CommunityMedalCatalog.officialRepoCommitsURL(
      repository: "MoviePilot-Frontend", login: "jxxghp")
    #expect(
      commitURL?.absoluteString.contains("github.com/jxxghp/MoviePilot-Frontend/commits") == true)

    #expect(
      CommunityMedalCatalog.officialRepoPRsURL(repository: "EvilRepo", login: "jxxghp") == nil)
    #expect(
      CommunityMedalCatalog.officialRepoCommitsURL(repository: "MoviePilot", login: nil) == nil)
  }
}
