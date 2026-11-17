import AVKit
import UIKit
import VLCKit

/// 将解码器的原生采样画面交给 AVKit，窗口、手势和播放按钮均由 iOS 管理。
@MainActor
final class MediaPictureInPictureController: NSObject,
  @preconcurrency AVPictureInPictureControllerDelegate,
  @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate
{
  private weak var player: VLCMediaPlayer?
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

  /// 保留同一个解码器及其时间轴，避免切换画中画时重新请求或从头播放。
  init(
    player: VLCMediaPlayer, videoView: UIView, onStart: @escaping () -> Void,
    onRestore: @escaping () -> Void, onStop: @escaping (Bool) -> Void,
    onAvailability: @escaping (Bool) -> Void, onFailure: @escaping () -> Void
  ) {
    self.player = player
    self.videoView = videoView
    self.onStart = onStart
    self.onRestore = onRestore
    self.onStop = onStop
    self.onAvailability = onAvailability
    self.onFailure = onFailure
    super.init()
  }

  /// 正在转场或已进入系统窗口时保留源画面和解码会话。
  var keepsPlaybackAlive: Bool {
    controller?.isPictureInPictureActive == true || controller?.isPictureInPictureSuspended == true
  }

  /// 视频输出晚于播放器创建；首帧后绑定公开的 AVSampleBufferDisplayLayer。
  func refresh() {
    guard !closed, AVPictureInPictureController.isPictureInPictureSupported(), let videoView else {
      return
    }
    if let layer = Self.sampleBufferLayer(in: videoView.layer),
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
      availability = pictureInPicture.observe(
        \.isPictureInPicturePossible, options: [.initial, .new]
      ) {
        [weak self] _, _ in
        Task { @MainActor [weak self] in
          guard let self, !self.closed else { return }
          self.onAvailability(self.controller?.isPictureInPicturePossible == true)
        }
      }
    }
    controller?.requiresLinearPlayback = player?.isSeekable != true
    controller?.invalidatePlaybackState()
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
    onAvailability(false)
  }

  /// 解码器可在中间容器下安装采样层；只检查公开的 CALayer 层级。
  private static func sampleBufferLayer(in layer: CALayer) -> AVSampleBufferDisplayLayer? {
    if let sample = layer as? AVSampleBufferDisplayLayer { return sample }
    for child in layer.sublayers ?? [] {
      if let sample = sampleBufferLayer(in: child) { return sample }
    }
    return nil
  }

  /// 系统窗口已接管画面后才隐藏 App 内的全屏界面。
  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    guard !closed else { return }
    restored = false
    onStart()
  }

  /// 返回 App 的按钮先恢复原全屏界面，再告知系统结束画中画转场。
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

  /// 点击系统关闭按钮结束播放；返回全屏时继续保留同一会话。
  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    guard !closed else { return }
    onStop(restored)
    restored = false
  }

  /// 系统拒绝进入时不隐藏原界面，并提供可重试的统一提示。
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: any Error
  ) {
    guard !closed else { return }
    onFailure()
  }

  /// 系统播放按钮只执行播放，不根据当前状态反转用户的操作。
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool
  ) {
    guard !closed, let player else { return }
    if playing { player.play() } else { player.pause() }
    pictureInPictureController.invalidatePlaybackState()
  }

  /// 将解码时间映射到系统单调时钟，让原生进度条与全屏保持一致。
  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    let duration = Double(player?.media?.length.intValue ?? 0) / 1000
    guard duration > 0 else {
      return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    let elapsed = Double(player?.time.intValue ?? 0) / 1000
    return CMTimeRange(
      start: CMTime(seconds: CACurrentMediaTime() - elapsed, preferredTimescale: 1_000_000),
      duration: CMTime(seconds: duration, preferredTimescale: 1_000_000))
  }

  /// 系统查询实际解码状态，暂停后不会因计时刷新自动恢复播放。
  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    player?.isPlaying != true
  }

  /// 系统窗口尺寸由 AVKit 接管，源采样层继续保持解码器的等比布局。
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  /// 系统快进快退在真实 seek 完成后回调；不可跳转时也必须结束系统等待。
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    guard !closed, let player, player.isSeekable else {
      completionHandler()
      return
    }
    let milliseconds = CMTimeGetSeconds(skipInterval) * 1000
    guard milliseconds.isFinite else {
      completionHandler()
      return
    }
    if !player.jump(withOffset: Int32(clamping: Int64(milliseconds)), completion: completionHandler)
    {
      completionHandler()
    }
  }

  /// 允许系统画中画在 App 退到后台后继续保持声音。
  func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool { false }
}
