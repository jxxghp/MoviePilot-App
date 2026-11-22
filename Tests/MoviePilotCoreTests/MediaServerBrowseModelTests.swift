import Foundation
import Testing

@testable import MoviePilotCore

struct MediaServerBrowseModelTests {
  @Test func decodesDetailAndBuildsDefaultChineseTrackSelection() throws {
    let json = """
      {
        "item_id": "ep-101",
        "server": "Emby",
        "server_type": "emby",
        "item_type": "Episode",
        "media_type": "电视剧",
        "title": "第 1 集 试播",
        "year": 2025,
        "rating": 8.6,
        "duration_ms": 3000000,
        "series_id": "series-1",
        "series_name": "测试剧",
        "season_id": "season-1",
        "season_number": 1,
        "episode_number": 1,
        "tmdb_id": "1399",
        "genres": ["科幻", "剧情"],
        "studios": ["HBO"],
        "people": [{"id": "p1", "name": "演员甲", "role": "主角", "type": "Actor"}],
        "media_sources": [
          {
            "id": "src-4k",
            "name": "4K HDR",
            "container": "mkv",
            "size": 4294967296,
            "streams": [
              {"index": 0, "type": "video", "codec": "hevc", "width": 3840, "height": 2160, "video_range": "HDR"},
              {"index": 1, "type": "audio", "codec": "eac3", "language": "eng", "display_title": "英语 5.1", "is_default": true},
              {"index": 2, "type": "audio", "codec": "aac", "language": "chi", "display_title": "国语 2.0", "is_default": false},
              {"index": 3, "type": "subtitle", "codec": "ass", "language": "eng", "display_title": "English", "is_external": false},
              {"index": 4, "type": "subtitle", "codec": "srt", "language": "chi", "display_title": "简体中文", "is_external": true, "subtitle_id": "ms:src-4k:4.srt"}
            ]
          }
        ],
        "can_play": true
      }
      """

    let detail = try JSONDecoder().decode(MediaServerItemDetailDTO.self, from: Data(json.utf8))
    #expect(detail.kind == .episode)
    #expect(detail.formattedDuration == "50 分钟")
    #expect(detail.resolvedExternalIdentity?.source == "themoviedb")
    #expect(detail.resolvedExternalIdentity?.mediaID == "1399")
    #expect(detail.resolvedExternalIdentity?.type == "电视剧")

    let source = try #require(detail.mediaSources.first)
    #expect(source.specSummary.contains("4K"))
    #expect(source.specSummary.contains("HDR"))

    let defaultSelection = MediaPlaybackTrackSelection.defaultSelection(
      for: source, preferChineseSub: true)
    #expect(defaultSelection.mediaSourceID == "src-4k")
    #expect(defaultSelection.audioOrdinal == 0)
    #expect(defaultSelection.subtitleDisabled == false)
    #expect(defaultSelection.subtitleExternalID == "ms:src-4k:4.srt")

    let switchedAudio = defaultSelection.selectingAudio(source.audioStreams[1], in: source)
    #expect(switchedAudio.audioOrdinal == 1)
    #expect(switchedAudio.audioLanguage == "chi")

    let switchedSub = switchedAudio.selectingSubtitle(source.subtitleStreams[0], in: source)
    #expect(switchedSub.subtitleExternalID == nil)
    #expect(switchedSub.subtitleOrdinal == 0)

    let disabledSub = switchedSub.selectingSubtitle(nil, in: source)
    #expect(disabledSub.subtitleDisabled == true)
    #expect(disabledSub.subtitleOrdinal == nil)
    #expect(disabledSub.subtitleExternalID == nil)
  }

  @Test func browseItemComputesEpisodeCodeAndProgress() {
    let item = MediaServerBrowseItemDTO(
      itemId: "ep-2",
      server: "Emby",
      itemType: "Episode",
      mediaType: "电视剧",
      title: "第二集",
      durationMs: 3_600_000,
      seasonNumber: 2,
      episodeNumber: 5,
      resumePositionMs: 900_000
    )
    #expect(item.episodeCode == "S02E05")
    #expect(item.progressFraction == 0.25)
    #expect(item.formattedDuration == "1 小时")
  }
}
