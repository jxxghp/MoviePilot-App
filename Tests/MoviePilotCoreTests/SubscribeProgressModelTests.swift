import Testing

@testable import MoviePilotCore

@Suite("SubscribeProgressProjection 离散胶片刻度测试")
struct SubscribeProgressModelTests {
  @Test("未开始更新的 36 集剧集全部为空槽且展示待更新文案")
  func unstartedLargeSeriesShowsEmptyFoldedTicks() throws {
    let projection = try #require(
      SubscribeProgressProjection.make(
        type: "电视剧",
        totalEpisode: 36,
        lackEpisode: 36,
        completedEpisode: 0,
        note: []
      )
    )
    #expect(projection.ticks.count == 18)
    #expect(!projection.isExactPerUnit)
    #expect(projection.ticks.allSatisfy { $0 == .empty })
    #expect(projection.summaryText == "待更新 · 共 36 集")
    #expect(projection.detailText == nil)
    #expect(projection.fraction == 0)
  }

  @Test("24 集以内精确命中 note 时保留跳集空槽并列出缺失集号")
  func exactEpisodeNoteHighlightsSkippedGaps() throws {
    let projection = try #require(
      SubscribeProgressProjection.make(
        type: "电视剧",
        totalEpisode: 12,
        lackEpisode: 2,
        completedEpisode: 10,
        note: [1, 2, 3, 5, 6, 7, 8, 9, 10, 11]
      )
    )
    #expect(projection.isExactPerUnit)
    #expect(projection.ticks.count == 12)
    #expect(projection.ticks[3] == .empty)
    #expect(projection.ticks[11] == .empty)
    #expect(projection.ticks.filter { $0 == .complete }.count == 10)
    #expect(projection.missingNumbers == [4, 12])
    #expect(projection.summaryText == "已收 10 / 12 集")
    #expect(projection.detailText == "缺 E04, E12")
  }

  @Test("缺失超过 3 集但存在中间跳集时同时提示漏集与总缺集数")
  func internalGapWithTrailingMissingShowsGapPreview() throws {
    let projection = try #require(
      SubscribeProgressProjection.make(
        type: "电视剧",
        totalEpisode: 12,
        lackEpisode: 6,
        completedEpisode: 6,
        note: [1, 2, 3, 5, 6, 7]
      )
    )
    #expect(projection.ticks[3] == .empty)
    #expect(projection.ticks[4] == .complete)
    #expect(projection.detailText == "缺 E04 等 6 集")
  }

  @Test("库内已有集未记入 note 时按完成数补足不虚报漏集")
  func preExistingLibraryEpisodesFallbackCleanly() throws {
    let projection = try #require(
      SubscribeProgressProjection.make(
        type: "电视剧",
        totalEpisode: 12,
        lackEpisode: 4,
        completedEpisode: 8,
        note: [7, 8]
      )
    )
    #expect(projection.ticks.count == 12)
    #expect(projection.ticks.prefix(8).allSatisfy { $0 == .complete })
    #expect(projection.ticks.suffix(4).allSatisfy { $0 == .empty })
    #expect(projection.missingNumbers.isEmpty)
    #expect(projection.detailText == "缺 4 集")
  }

  @Test("非第 1 集起订时前序集视为已覆盖并准确标出目标范围缺集")
  func nonOneStartEpisodeCoversPreStartSlots() throws {
    let projection = try #require(
      SubscribeProgressProjection.make(
        type: "电视剧",
        totalEpisode: 12,
        startEpisode: 5,
        lackEpisode: 2,
        completedEpisode: 10,
        note: [5, 6, 7, 8, 9, 11]
      )
    )
    #expect(projection.ticks[0] == .complete)
    #expect(projection.ticks[3] == .complete)
    #expect(projection.ticks[9] == .empty)
    #expect(projection.ticks[10] == .complete)
    #expect(projection.ticks[11] == .empty)
    #expect(projection.detailText == "缺 E10, E12")
  }

  @Test("超大集数聚合保留区间部分完成态")
  func largeSeriesBucketingPreservesPartialState() throws {
    let thirtySix = try #require(
      SubscribeProgressProjection.make(
        type: "电视剧",
        totalEpisode: 36,
        lackEpisode: 17,
        completedEpisode: 19,
        note: nil
      )
    )
    #expect(thirtySix.ticks.count == 18)
    #expect(thirtySix.ticks.prefix(9).allSatisfy { $0 == .complete })
    #expect(thirtySix.ticks[9] == .partial)
    #expect(thirtySix.ticks.suffix(8).allSatisfy { $0 == .empty })
    #expect(thirtySix.summaryText == "已收 19 / 36 集")
    #expect(thirtySix.detailText == "缺 17 集")

    let fiftyFive = try #require(
      SubscribeProgressProjection.make(
        type: "电视剧",
        totalEpisode: 55,
        lackEpisode: 0,
        completedEpisode: 55,
        note: nil
      )
    )
    #expect(fiftyFive.ticks.count == 20)
    #expect(fiftyFive.ticks.allSatisfy { $0 == .complete })
    #expect(fiftyFive.summaryText == "已收齐 55 / 55 集")
    #expect(fiftyFive.detailText == nil)
  }

  @Test("洗版模式区分已达标、已有初版与未获取三态")
  func bestVersionSeparatesUpgradedAcquiredAndMissing() throws {
    let projection = try #require(
      SubscribeProgressProjection.make(
        type: "电视剧",
        totalEpisode: 8,
        lackEpisode: 2,
        completedEpisode: 4,
        note: [1, 2, 3, 4, 5, 6],
        bestVersion: 1,
        episodePriority: [
          "1": 100, "2": 100, "3": 100, "4": 100,
          "5": 60, "6": 60,
        ]
      )
    )
    #expect(projection.isBestVersion)
    #expect(
      projection.ticks == [
        .complete, .complete, .complete, .complete, .partial, .partial, .empty, .empty,
      ])
    #expect(projection.summaryText == "洗版 4 / 8 集")
    #expect(projection.detailText == "已有 6 集")
  }

  @Test("音乐专辑展示曲目刻度，单曲与电影不展示刻度")
  func musicAlbumTracksAndNonTickTypes() throws {
    let album = try #require(
      SubscribeProgressProjection.make(
        type: "音乐",
        musicType: "album",
        totalTracks: 10,
        completedTracks: 4
      )
    )
    #expect(album.unit == .track)
    #expect(album.ticks.count == 10)
    #expect(album.ticks.prefix(4).allSatisfy { $0 == .complete })
    #expect(album.ticks.suffix(6).allSatisfy { $0 == .empty })
    #expect(album.summaryText == "已收 4 / 10 首")
    #expect(album.detailText == "缺 6 首")

    #expect(
      SubscribeProgressProjection.make(
        type: "音乐",
        musicType: "recording",
        totalTracks: 1,
        completedTracks: 0
      ) == nil
    )
    #expect(SubscribeProgressProjection.make(type: "电影") == nil)
  }
}
