import AVFoundation
import AVKit
import UIKit
import VLCKit

/// 统一桥接 `AVPlayerLayer`（系统原生）与 `VLCMediaPlayer`（`AVSampleBufferDisplayLayer`）的系统画中画控制器。
@MainActor
final class MediaPictureInPictureController: NSObject,
  @preconcurrency AVPictureInPictureControllerDelegate,
  @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate
{
  private weak var engine: (any PlaybackEngine)?
  private weak var vlcPlayer: VLCMediaPlayer?
  private weak var videoView: UIView?
  private var controller: AVPictureInPictureController?
  private var availability: NSKeyValueObservation?
  private var restored = false
  private var closed = false
  private let onStart: () -> Void
  private let onRestore: () -> Void
  private let onStop: (_ restored: Bool) -> Void
  private let onAvailability: (Bool) -> Void
  private let onFailure: () -> Void

  init(
    onStart: @escaping () -> Void,
    onRestore: @escaping () -> Void,
    onStop: @escaping (Bool) -> Void,
    onAvailability: @escaping (Bool) -> Void,
    onFailure: @escaping () -> Void
  ) {
    self.onStart = onStart
    self.onRestore = onRestore
    self.onStop = onStop
    self.onAvailability = onAvailability
    self.onFailure = onFailure
    super.init()
  }

  /// 切核或初始化时重新绑定当前活动引擎；若引擎不支持 PiP 则优雅禁用按钮。
  func bind(engine: (any PlaybackEngine)?) {
    self.engine = engine
    self.vlcPlayer = nil
    self.videoView = nil
    if !keepsPlaybackAlive {
      availability = nil
      controller?.delegate = nil
      controller = nil
    }
    guard let engine, engine.capabilities.supportsPiP else {
      onAvailability(false)
      return
    }
    refresh()
  }

  /// 正在转场或已进入系统窗口时保留源画面和解码会话。
  var keepsPlaybackAlive: Bool {
    controller?.isPictureInPictureActive == true || controller?.isPictureInPictureSuspended == true
  }

  /// 视频输出晚于播放器创建；按当前引擎类型绑定 `AVPlayerLayer` 或公开的 `AVSampleBufferDisplayLayer`。
  func refresh() {
    guard !closed, AVPictureInPictureController.isPictureInPictureSupported(), let engine else {
      onAvailability(false)
      return
    }
    guard engine.capabilities.supportsPiP else {
      onAvailability(false)
      return
    }

    switch engine.pipSource {
    case .avPlayerLayer(let playerLayer):
      if controller?.playerLayer !== playerLayer, !keepsPlaybackAlive {
        availability = nil
        if let pictureInPicture = AVPictureInPictureController(playerLayer: playerLayer) {
          pictureInPicture.delegate = self
          pictureInPicture.canStartPictureInPictureAutomaticallyFromInline = true
          controller = pictureInPicture
          observeAvailability(for: pictureInPicture)
        } else {
          onAvailability(false)
        }
      }
      controller?.requiresLinearPlayback = !engine.isSeekable

    case .vlcSampleBuffer(let player, let view):
      vlcPlayer = player
      videoView = view
      if let layer = Self.sampleBufferLayer(in: view.layer),
        controller?.contentSource?.sampleBufferDisplayLayer !== layer,
        !keepsPlaybackAlive
      {
        availability = nil
        let source = AVPictureInPictureController.ContentSource(
          sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let pictureInPicture = AVPictureInPictureController(contentSource: source)
        pictureInPicture.delegate = self
        pictureInPicture.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pictureInPicture
        observeAvailability(for: pictureInPicture)
      }
      controller?.requiresLinearPlayback = !player.isSeekable
      controller?.invalidatePlaybackState()

    case .none:
      onAvailability(false)
    }
  }

  /// 只在系统确认可以呈现时发起画中画；失败仍保留全屏播放和原进度。
  func start() {
    refresh()
    guard let controller, controller.isPictureInPicturePossible else {
      onFailure()
      return
    }
    guard !controller.isPictureInPictureActive else { return }
    restored = false
    controller.startPictureInPicture()
  }

  /// 账号切换或关闭播放时解除观察及系统窗口，不让迟到回调恢复旧播放器。
  func stop() {
    closed = true
    availability = nil
    controller?.delegate = nil
    controller?.stopPictureInPicture()
    controller = nil
    engine = nil
    vlcPlayer = nil
    videoView = nil
    onAvailability(false)
  }

  private func observeAvailability(for pictureInPicture: AVPictureInPictureController) {
    availability = pictureInPicture.observe(
      \.isPictureInPicturePossible, options: [.initial, .new]
    ) { [weak self] _, _ in
      Task { @MainActor [weak self] in
        guard let self, !self.closed else { return }
        self.onAvailability(self.controller?.isPictureInPicturePossible == true)
      }
    }
  }

  private static func sampleBufferLayer(in layer: CALayer) -> AVSampleBufferDisplayLayer? {
    if let sample = layer as? AVSampleBufferDisplayLayer { return sample }
    for child in layer.sublayers ?? [] {
      if let sample = sampleBufferLayer(in: child) { return sample }
    }
    return nil
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    guard !closed else { return }
    restored = false
    onStart()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    guard !closed else {
      completionHandler(false)
      return
    }
    restored = true
    onRestore()
    completionHandler(true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    guard !closed else { return }
    onStop(restored)
    restored = false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: any Error
  ) {
    guard !closed else { return }
    onFailure()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool
  ) {
    guard !closed, let vlcPlayer else { return }
    if playing { vlcPlayer.play() } else { vlcPlayer.pause() }
    pictureInPictureController.invalidatePlaybackState()
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    let duration = Double(vlcPlayer?.media?.length.intValue ?? 0) / 1000
    guard duration > 0 else {
      return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    let elapsed = Double(vlcPlayer?.time.intValue ?? 0) / 1000
    return CMTimeRange(
      start: CMTime(seconds: CACurrentMediaTime() - elapsed, preferredTimescale: 1_000_000),
      duration: CMTime(seconds: duration, preferredTimescale: 1_000_000))
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    vlcPlayer?.isPlaying != true
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    guard !closed, let vlcPlayer, vlcPlayer.isSeekable else {
      completionHandler()
      return
    }
    let milliseconds = CMTimeGetSeconds(skipInterval) * 1000
    guard milliseconds.isFinite else {
      completionHandler()
      return
    }
    if !vlcPlayer.jump(withOffset: Int32(clamping: Int64(milliseconds)), completion: completionHandler)
    {
      completionHandler()
    }
  }

  func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool { false }
}
