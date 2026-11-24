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

  @Test func decodesBoxSetCollectionItem() throws {
    let json = """
      {
        "item_id": 9001,
        "server": "Emby",
        "server_type": "emby",
        "item_type": "BoxSet",
        "media_type": "合集",
        "title": "哈利·波特合集",
        "subtitle": "共 8 部",
        "child_count": 8
      }
      """
    let item = try JSONDecoder().decode(MediaServerBrowseItemDTO.self, from: Data(json.utf8))
    #expect(item.itemId == "9001")
    #expect(item.kind == .boxSet)
    #expect(item.childCount == 8)
    #expect(!item.kind.isDirectlyPlayable)

    let detailJSON = """
      {
        "item_id": "9001",
        "server": "Emby",
        "item_type": "BoxSet",
        "media_type": "合集",
        "title": "哈利·波特合集",
        "tmdb_id": "1241",
        "child_count": 8
      }
      """
    let boxDetail = try JSONDecoder().decode(
      MediaServerItemDetailDTO.self, from: Data(detailJSON.utf8))
    #expect(boxDetail.kind == .boxSet)
    #expect(boxDetail.resolvedExternalIdentity == nil)
  }

  @Test func decodesExtendedStreamMetadataAndFormatsMediaInfo() throws {
    let json = """
      {
        "streams": [
          {
            "index": 0,
            "type": "video",
            "display_title": "1080p H264",
            "title": "内嵌视频",
            "codec": "h264",
            "width": 1920,
            "height": 1080,
            "frame_rate": 23.976025,
            "bitrate": 14300000,
            "video_range": "SDR",
            "profile": "High",
            "level": 41.0,
            "is_interlaced": false,
            "color_primaries": "bt709",
            "color_space": "bt709",
            "bit_depth": 8
          },
          {
            "index": 1,
            "type": "audio",
            "display_title": "English EAC3",
            "title": "英语",
            "language": "English",
            "channel_layout": "5.1",
            "channels": 6,
            "codec": "eac3",
            "bitrate": 1000000,
            "sample_rate": 48000,
            "is_external": false,
            "is_default": true
          }
        ],
        "id": "src-1080p"
      }
      """
    let source = try JSONDecoder().decode(MediaServerSourceDTO.self, from: Data(json.utf8))
    let video = try #require(source.videoStreams.first)
    #expect(video.formattedResolution == "1920x1080")
    #expect(video.inferredAspectRatio == "16:9")
    #expect(video.formattedBitrate == "14.3mbps")
    #expect(video.frameRate == "23.976025")
    #expect(video.profile == "High")
    #expect(video.level == "41.0")
    #expect(video.isInterlaced == false)
    #expect(video.colorPrimaries == "bt709")
    #expect(video.colorSpace == "bt709")
    #expect(video.bitDepth == 8)

    let audio = try #require(source.audioStreams.first)
    #expect(audio.formattedBitrate == "1000kbps")
    #expect(audio.formattedSampleRate == "48000Hz")
    #expect(audio.channelLayout == "5.1")
    #expect(audio.channels == 6)
    #expect(audio.isDefault == true)
    #expect(audio.isExternal == false)
  }
}
