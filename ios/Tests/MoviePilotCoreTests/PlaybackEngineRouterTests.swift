import Foundation
import Testing

@testable import MoviePilotCore

struct PlaybackEngineRouterTests {
  @Test func audioDefaultsToNativeAndExoticRoutesToEnhanced() {
    let flac = PlaybackEngineRouter.resolve(
      PlaybackEngineResolutionInput(
        platform: .ios,
        isAudio: true,
        urlOrFilename: "https://media.example.com/track.flac"
      ))
    #expect(flac.primary == .native)
    #expect(flac.fallback == .enhanced)
    #expect(flac.engineLabelKey == "AVPlayer 原生")

    let dsf = PlaybackEngineRouter.resolve(
      PlaybackEngineResolutionInput(
        platform: .ios,
        isAudio: true,
        urlOrFilename: "https://media.example.com/album.dsf"
      ))
    #expect(dsf.primary == .enhanced)
    #expect(dsf.fallback == .native)
  }

  @Test func iosVideoAutoPrioritizesNativeAVPlayerWithMpvFallback() {
    let mp4 = PlaybackEngineRouter.resolve(
      PlaybackEngineResolutionInput(
        platform: .ios,
        urlOrFilename: "https://cdn.example.com/movie.mp4"
      ))
    #expect(mp4.primary == .native)
    #expect(mp4.fallback == .enhanced)

    let mkv = PlaybackEngineRouter.resolve(
      PlaybackEngineResolutionInput(
        platform: .ios,
        urlOrFilename: "https://cdn.example.com/remux.mkv"
      ))
    #expect(mkv.primary == .native)
    #expect(mkv.fallback == .enhanced)
    #expect(mkv.engineLabelKey == "AVPlayer 原生")

    let forceSw = PlaybackEngineRouter.resolve(
      PlaybackEngineResolutionInput(
        platform: .ios,
        decodeForceSoftware: true,
        urlOrFilename: "https://cdn.example.com/movie.mp4"
      ))
    #expect(forceSw.primary == .enhanced)
    #expect(forceSw.reasonCode == "force_software_decode")
  }

  @Test func pinnedChoiceAndExternalPlayerTemplateValidation() {
    let pinnedLegacy = PlaybackEngineRouter.resolve(
      PlaybackEngineResolutionInput(
        platform: .ios,
        preferred: .legacy,
        urlOrFilename: "https://cdn.example.com/movie.mp4"
      ))
    #expect(pinnedLegacy.primary == .legacy)
    #expect(pinnedLegacy.engineLabelKey == "VLCKit 兼容")

    let valid = PlaybackEngineRouter.buildExternalPlayerURL(
      template: "customplayer://open?url={url}&title={title}",
      mediaURL: "https://cdn.example.com/video.mkv?sign=1",
      title: "流浪地球"
    )
    #expect(valid?.scheme == "customplayer")
    #expect(valid?.absoluteString.contains("https%3A%2F%2Fcdn.example.com") == true)

    #expect(
      PlaybackEngineRouter.buildExternalPlayerURL(
        template: "javascript://alert(1)?url={url}",
        mediaURL: "https://cdn.example.com/video.mp4",
        title: "test"
      ) == nil)
    #expect(
      PlaybackEngineRouter.buildExternalPlayerURL(
        template: "customplayer://open?url={url}",
        mediaURL: "https://admin:secret@cdn.example.com/video.mp4",
        title: "test"
      ) == nil)
  }
}
