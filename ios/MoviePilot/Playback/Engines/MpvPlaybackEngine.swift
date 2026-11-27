import Foundation
import Libmpv
import MoviePilotCore
import MoviePilotSession
import QuartzCore
import UIKit
import os

/// 专为 MoltenVK / `libplacebo` 定制的 `CAMetalLayer` 子类：
/// 1. 拦截 MoltenVK 在转场期间临时写入的 `1x1` `drawableSize`（规避 mpv#13651 黑屏问题）；
/// 2. 将后台渲染线程触发的 `wantsExtendedDynamicRangeContent` 异步切回主线程更新，杜绝跨线程 UIKit 崩溃与 `main.sync` 死锁。
private final class MpvMetalLayer: CAMetalLayer, @unchecked Sendable {
  override var drawableSize: CGSize {
    get { super.drawableSize }
    set {
      if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
        super.drawableSize = newValue
      }
    }
  }

  override var wantsExtendedDynamicRangeContent: Bool {
    get { super.wantsExtendedDynamicRangeContent }
    set {
      if Thread.isMainThread {
        super.wantsExtendedDynamicRangeContent = newValue
      } else {
        nonisolated(unsafe) weak let weakSelf = self
        DispatchQueue.main.async {
          weakSelf?.wantsExtendedDynamicRangeContent = newValue
        }
      }
    }
  }
}

/// 承载 `MpvMetalLayer` 的独立渲染宿主视图；每次创建 `libmpv` 实例均独占一个宿主视图，
/// 直至后台串行队列完成 `mpv_terminate_destroy` 后再切回主线程释放，彻底根除 `wid` 悬垂指针崩溃。
private final class MpvMetalHostView: UIView {
  override class var layerClass: AnyClass { MpvMetalLayer.self }

  var metalLayer: MpvMetalLayer {
    guard let layer = self.layer as? MpvMetalLayer else {
      fatalError("Expected MpvMetalLayer")
    }
    return layer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .clear
    isUserInteractionEnabled = false
    metalLayer.framebufferOnly = false
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.backgroundColor = UIColor.black.cgColor
    syncDrawableSize()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    syncDrawableSize()
  }

  func syncDrawableSize() {
    let scale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
    metalLayer.contentsScale = max(1.0, scale)
    let sourceSize: CGSize
    if bounds.width > 1 && bounds.height > 1 {
      sourceSize = bounds.size
    } else if let superBounds = superview?.bounds, superBounds.width > 1 && superBounds.height > 1 {
      sourceSize = superBounds.size
    } else {
      sourceSize = UIScreen.main.bounds.size
    }
    metalLayer.drawableSize = CGSize(
      width: max(2, sourceSize.width * metalLayer.contentsScale),
      height: max(2, sourceSize.height * metalLayer.contentsScale)
    )
  }
}

/// 单次 `libmpv` 会话控制器：
/// 所有 `libmpv` C API 调用（`mpv_create`、`mpv_initialize`、`mpv_command_async`、`mpv_wait_event`、`mpv_terminate_destroy`）
/// 100% 独占运行在后台串行队列 `serialQueue` 上，主线程零 `libmpv` 锁等待，
/// 彻底根除 MoltenVK 初始化期间 `dispatch_sync(main)` 与主线程 `mpv_command_async` 抢占 `mp_dispatch` 锁导致的互锁卡死。
private final class MpvSession: @unchecked Sendable {
  let hostView: MpvMetalHostView
  let isAudio: Bool

  private let activeFlag = OSAllocatedUnfairLock(initialState: true)
  private let serialQueue: DispatchQueue
  private let onEvent: @Sendable (MpvDispatchedEvent) -> Void

  // 以下状态仅在 `serialQueue` 内读写
  private var rawHandle: OpaquePointer?
  private var isStopped = false
  private var drainScheduled = false
  private var wakeupContextPtr: UnsafeMutableRawPointer?
  private var loopbackProxy: LoopbackAuthProxy?

  init(
    hostView: MpvMetalHostView,
    isAudio: Bool,
    onEvent: @escaping @Sendable (MpvDispatchedEvent) -> Void
  ) {
    self.hostView = hostView
    self.isAudio = isAudio
    self.serialQueue = DispatchQueue(
      label: "com.moviepilot.playback.mpv.session.\(UUID().uuidString)",
      qos: .userInitiated
    )
    self.onEvent = onEvent
  }

  var isActive: Bool {
    activeFlag.withLock { $0 }
  }

  func start(
    source: EngineMediaSource,
    options: EngineLoadOptions,
    layerAddr: Int64,
    initialRate: Float
  ) {
    let retainedView = hostView
    serialQueue.async { [weak self] in
      _ = retainedView
      guard let self, !self.isStopped else { return }
      guard let mpv = mpv_create() else {
        self.activeFlag.withLock { $0 = false }
        self.onEvent(.failed(.unknown))
        return
      }

      if options.isAudio {
        mpv_set_option_string(mpv, "vid", "no")
        mpv_set_option_string(mpv, "vo", "null")
      } else {
        var widValue = layerAddr
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &widValue)
        mpv_set_option_string(mpv, "vo", "gpu-next")
        mpv_set_option_string(mpv, "gpu-api", "vulkan")
        mpv_set_option_string(mpv, "gpu-context", "moltenvk")
        mpv_set_option_string(
          mpv, "hwdec", options.decodeMode == .swForce ? "no" : "videotoolbox")
        mpv_set_option_string(mpv, "panscan", options.aspectFill ? "1.0" : "0.0")
      }

      mpv_set_option_string(mpv, "keep-open", "no")
      mpv_set_option_string(mpv, "cache", "yes")
      mpv_set_option_string(
        mpv, "demuxer-max-bytes", options.bufferProfile == .large ? "180MiB" : "64MiB")
      mpv_set_option_string(
        mpv, "demuxer-readahead-secs", options.bufferProfile == .large ? "60" : "20")
      mpv_set_option_string(
        mpv, "sub-ass-override", options.ignoreAssStyle ? "force" : "no")
      mpv_set_option_string(mpv, "sub-scale", String(format: "%.2f", options.subtitleScale))
      mpv_set_option_string(mpv, "sub-font", "PingFang SC")
      mpv_set_option_string(mpv, "embeddedfonts", "yes")
      if options.audioNightMode {
        mpv_set_option_string(mpv, "af", "acompressor=ratio=4:makeup=4")
      }
      mpv_set_option_string(mpv, "tls-verify", options.allowSelfSignedTls ? "no" : "yes")
      mpv_set_option_string(mpv, "speed", String(format: "%.2f", initialRate))

      if options.startPositionMs > 1_000 {
        mpv_set_option_string(
          mpv, "start", String(format: "%.3f", Double(options.startPositionMs) / 1000.0))
      }

      // 远端流统一经本机环回代理由 `URLSession` 出网：`libmpv` 自带的 GnuTLS 在 iOS 上读不到系统根证书，
      // 直连 HTTPS 必然校验失败；同时避免把实例凭据交给 `libmpv` 后在跨源 302 中外泄。
      let targetString: String
      if source.url.isFileURL {
        targetString = source.url.path
      } else {
        var mergedHeaders = source.headers
        if source.isSameOriginInstance, let cookie = source.sameOriginCookie,
          mergedHeaders["Cookie"] == nil
        {
          mergedHeaders["Cookie"] = "\(cookie.name)=\(cookie.value)"
        }
        guard let proxy = try? LoopbackAuthProxy(target: source.url, headers: mergedHeaders),
          let localURL = try? proxy.start()
        else {
          mpv_terminate_destroy(mpv)
          self.activeFlag.withLock { $0 = false }
          self.onEvent(.failed(.network))
          return
        }
        self.loopbackProxy = proxy
        targetString = localURL.absoluteString
      }

      guard mpv_initialize(mpv) >= 0 else {
        mpv_terminate_destroy(mpv)
        self.closeLoopbackProxy()
        self.activeFlag.withLock { $0 = false }
        self.onEvent(.failed(.unknown))
        return
      }

      if self.isStopped {
        mpv_terminate_destroy(mpv)
        self.closeLoopbackProxy()
        return
      }

      self.rawHandle = mpv
      mpv_observe_property(mpv, 1, "pause", MPV_FORMAT_FLAG)
      mpv_observe_property(mpv, 2, "time-pos", MPV_FORMAT_DOUBLE)
      mpv_observe_property(mpv, 3, "duration", MPV_FORMAT_DOUBLE)
      mpv_observe_property(mpv, 4, "seekable", MPV_FORMAT_FLAG)
      mpv_observe_property(mpv, 5, "paused-for-cache", MPV_FORMAT_FLAG)
      mpv_observe_property(mpv, 6, "track-list", MPV_FORMAT_STRING)

      let box = WeakMpvSessionBox(self)
      let rawCtx = Unmanaged.passRetained(box).toOpaque()
      self.wakeupContextPtr = rawCtx
      mpv_set_wakeup_callback(
        mpv,
        { ctx in
          guard let ctx else { return }
          let box = Unmanaged<WeakMpvSessionBox>.fromOpaque(ctx).takeUnretainedValue()
          box.session?.scheduleDrainFromWakeup()
        },
        rawCtx
      )

      Self.sendCommand(mpv, ["loadfile", targetString, "replace"])
      self.drainEventsOnSerialQueue()
    }
  }

  func setFlagAsync(name: String, value: Bool) {
    guard isActive else { return }
    serialQueue.async { [weak self] in
      guard let self, !self.isStopped, let mpv = self.rawHandle else { return }
      var flag: Int32 = value ? 1 : 0
      _ = mpv_set_property_async(mpv, 0, name, MPV_FORMAT_FLAG, &flag)
    }
  }

  func setDoubleAsync(name: String, value: Double) {
    guard isActive else { return }
    serialQueue.async { [weak self] in
      guard let self, !self.isStopped, let mpv = self.rawHandle else { return }
      var val = value
      _ = mpv_set_property_async(mpv, 0, name, MPV_FORMAT_DOUBLE, &val)
    }
  }

  func setStringAsync(name: String, value: String) {
    guard isActive else { return }
    serialQueue.async { [weak self] in
      guard let self, !self.isStopped, let mpv = self.rawHandle else { return }
      value.withCString { cStr in
        var ptr: UnsafePointer<CChar>? = cStr
        _ = mpv_set_property_async(mpv, 0, name, MPV_FORMAT_STRING, &ptr)
      }
    }
  }

  func sendCommandAsync(_ args: [String]) {
    guard isActive else { return }
    serialQueue.async { [weak self] in
      guard let self, !self.isStopped, let mpv = self.rawHandle else { return }
      Self.sendCommand(mpv, args)
    }
  }

  fileprivate func scheduleDrainFromWakeup() {
    guard isActive else { return }
    serialQueue.async { [weak self] in
      guard let self, !self.isStopped else { return }
      if self.drainScheduled { return }
      self.drainScheduled = true
      self.drainEventsOnSerialQueue()
      self.drainScheduled = false
    }
  }

  private func drainEventsOnSerialQueue() {
    while !isStopped, let mpv = rawHandle {
      guard let eventPtr = mpv_wait_event(mpv, 0) else { return }
      let event = eventPtr.pointee
      if event.event_id == MPV_EVENT_NONE || event.event_id == MPV_EVENT_SHUTDOWN {
        return
      }
      if let translated = Self.translateEvent(event) {
        onEvent(translated)
      }
    }
  }

  private static func translateEvent(_ event: mpv_event) -> MpvDispatchedEvent? {
    switch event.event_id {
    case MPV_EVENT_FILE_LOADED:
      return .fileLoaded
    case MPV_EVENT_END_FILE:
      let endData = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee
      let reason = endData?.reason ?? MPV_END_FILE_REASON_STOP
      let errCode = endData?.error ?? 0
      if reason == MPV_END_FILE_REASON_EOF {
        return .endedEOF
      } else if reason == MPV_END_FILE_REASON_ERROR {
        let kind: PlaybackEngineErrorKind =
          (errCode == MPV_ERROR_UNKNOWN_FORMAT.rawValue
            || errCode == MPV_ERROR_UNSUPPORTED.rawValue)
          ? .unsupportedFormat : .network
        return .failed(kind)
      }
      return nil
    case MPV_EVENT_PROPERTY_CHANGE:
      guard let propPtr = event.data?.assumingMemoryBound(to: mpv_event_property.self) else {
        return nil
      }
      let prop = propPtr.pointee
      guard let cName = prop.name else { return nil }
      let name = String(cString: cName)
      switch name {
      case "pause":
        if prop.format == MPV_FORMAT_FLAG, let data = prop.data {
          return .pauseChanged(data.assumingMemoryBound(to: Int32.self).pointee != 0)
        }
      case "paused-for-cache":
        if prop.format == MPV_FORMAT_FLAG, let data = prop.data {
          return .bufferingChanged(data.assumingMemoryBound(to: Int32.self).pointee != 0)
        }
      case "time-pos":
        if prop.format == MPV_FORMAT_DOUBLE, let data = prop.data {
          let pos = data.assumingMemoryBound(to: Double.self).pointee
          if pos.isFinite { return .timeChanged(max(0, pos)) }
        }
      case "duration":
        if prop.format == MPV_FORMAT_DOUBLE, let data = prop.data {
          let dur = data.assumingMemoryBound(to: Double.self).pointee
          if dur.isFinite { return .durationChanged(max(0, dur)) }
        }
      case "seekable":
        if prop.format == MPV_FORMAT_FLAG, let data = prop.data {
          return .seekableChanged(data.assumingMemoryBound(to: Int32.self).pointee != 0)
        }
      case "track-list":
        if prop.format == MPV_FORMAT_STRING,
          let data = prop.data,
          let cStr = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee
        {
          return .tracksChanged(String(cString: cStr))
        }
      default:
        break
      }
      return nil
    default:
      return nil
    }
  }

  /// 安全异步停止并销毁当前 `mpv_handle`：
  /// 在 `serialQueue` 独占执行 `mpv_terminate_destroy`，随后将 `MpvMetalHostView` 交回主线程析构并回调 `completion`。
  func shutdown(notifyQueue: DispatchQueue, completion: (@Sendable () -> Void)?) {
    let wasActive = activeFlag.withLock { state -> Bool in
      let prev = state
      state = false
      return prev
    }
    guard wasActive else {
      if let completion { notifyQueue.async(execute: completion) }
      return
    }
    let retainedView = hostView
    serialQueue.async { [weak self] in
      if let self, !self.isStopped {
        self.isStopped = true
        if let handleToDestroy = self.rawHandle {
          self.rawHandle = nil
          mpv_set_wakeup_callback(handleToDestroy, nil, nil)
          mpv_terminate_destroy(handleToDestroy)
        }
        if let cbCtx = self.wakeupContextPtr {
          self.wakeupContextPtr = nil
          Unmanaged<WeakMpvSessionBox>.fromOpaque(cbCtx).release()
        }
        self.closeLoopbackProxy()
      }
      DispatchQueue.main.async {
        _ = retainedView
      }
      if let completion {
        notifyQueue.async(execute: completion)
      }
    }
  }

  /// 关闭并释放本会话的环回代理；仅在 `serialQueue` 内调用。
  private func closeLoopbackProxy() {
    loopbackProxy?.close()
    loopbackProxy = nil
  }

  private static func sendCommand(_ mpv: OpaquePointer, _ args: [String]) {
    var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    cStrings.append(nil)
    defer {
      for ptr in cStrings where ptr != nil {
        free(ptr)
      }
    }
    cStrings.withUnsafeMutableBufferPointer { buf in
      let constPtr = UnsafeMutableRawPointer(buf.baseAddress)?
        .assumingMemoryBound(to: UnsafePointer<CChar>?.self)
      _ = mpv_command_async(mpv, 0, constPtr)
    }
  }
}

private final class WeakMpvSessionBox: @unchecked Sendable {
  weak var session: MpvSession?
  init(_ session: MpvSession) {
    self.session = session
  }
}

private enum MpvDispatchedEvent: Sendable {
  case fileLoaded
  case endedEOF
  case failed(PlaybackEngineErrorKind)
  case pauseChanged(Bool)
  case bufferingChanged(Bool)
  case timeChanged(Double)
  case durationChanged(Double)
  case seekableChanged(Bool)
  case tracksChanged(String)
}

private struct MpvTrackJSON: Decodable {
  let id: Int
  let type: String
  let title: String?
  let lang: String?
  let codec: String?
  let selected: Bool?
}

/// 全能增强播放引擎（基于 `MPVKit-GPL` / `libmpv` + MoltenVK / `libplacebo` / `libass` / `libdovi`）：
/// - 支持 MKV / DTS / TrueHD / HDR10 / Dolby Vision 色调映射、完整 ASS 特效与 PGS 蓝光图形字幕；
/// - 支持 VideoToolbox 硬解与强制视频软解切换、标准/大缓冲档位、人声增强滤镜与自定义自签 TLS 策略；
/// - 所有 `libmpv` C 调用全异步运行于会话专属串行队列，主线程零阻塞、零互锁，切后台自动挂起 `vid=no` 规避 GPU 强杀。
@MainActor
final class MpvPlaybackEngine: PlaybackEngine {
  let kind: ResolvedPlaybackEngine = .enhanced
  let capabilities = EngineCapabilities(
    supportsPiP: false,
    supportsAirPlayVideo: false,
    supportsAssStyling: true,
    supportsSoftwareVideoDecode: true,
    maxRate: 3.0
  )

  private weak var attachedContainer: UIView?
  private var activeSession: MpvSession?
  private var backgroundObserver: NSObjectProtocol?
  private var foregroundObserver: NSObjectProtocol?
  private var isPausedState = true
  private var isSeekableState = false
  private var currentPosSec: Double = 0
  private var durationSec: Double = 0
  private var currentRate: Float = 1.0
  private var cachedAudioTracks: [EngineTrack] = []
  private var cachedSubtitleTracks: [EngineTrack] = []

  var onStateChanged: ((PlaybackEngineState) -> Void)?
  var onTracksChanged: (() -> Void)?

  init() {
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleDidEnterBackground()
      }
    }
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleWillEnterForeground()
      }
    }
  }

  var pipSource: EnginePictureInPictureSource { .none }

  var isPlaying: Bool { !isPausedState && activeSession?.isActive == true }
  var isSeekable: Bool { isSeekableState }
  var currentTimeMs: Int { max(0, Int((currentPosSec * 1000).rounded())) }
  var durationMs: Int { max(0, Int((durationSec * 1000).rounded())) }

  var rate: Float {
    get { currentRate }
    set {
      let clamped = max(0.5, min(capabilities.maxRate, newValue))
      currentRate = clamped
      activeSession?.setDoubleAsync(name: "speed", value: Double(clamped))
    }
  }

  var audioTracks: [EngineTrack] { cachedAudioTracks }
  var subtitleTracks: [EngineTrack] { cachedSubtitleTracks }

  func attachVideoContainer(_ container: UIView) {
    attachedContainer = container
    if let hostView = activeSession?.hostView {
      mountHostView(hostView, into: container)
    }
  }

  func detachVideoContainer() {
    activeSession?.hostView.removeFromSuperview()
    attachedContainer = nil
  }

  private func mountHostView(_ hostView: MpvMetalHostView, into container: UIView) {
    if hostView.superview !== container {
      hostView.removeFromSuperview()
      container.addSubview(hostView)
      NSLayoutConstraint.activate([
        hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        hostView.topAnchor.constraint(equalTo: container.topAnchor),
        hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
    }
    container.layoutIfNeeded()
    hostView.syncDrawableSize()
  }

  func load(source: EngineMediaSource, options: EngineLoadOptions) throws {
    guard
      source.url.isFileURL
        || ["http", "https"].contains(source.url.scheme?.lowercased() ?? "")
    else {
      throw MediaPlaybackError.unavailable
    }

    currentRate = max(0.5, min(capabilities.maxRate, options.rate))
    isPausedState = false
    isSeekableState = false
    currentPosSec = Double(max(0, options.startPositionMs)) / 1000.0
    durationSec = 0
    cachedAudioTracks = []
    cachedSubtitleTracks = []

    if let previous = activeSession {
      activeSession = nil
      previous.hostView.removeFromSuperview()
      previous.shutdown(notifyQueue: .main, completion: nil)
    }

    let initialFrame = attachedContainer?.bounds ?? UIScreen.main.bounds
    let hostView = MpvMetalHostView(
      frame: initialFrame.width > 1 && initialFrame.height > 1 ? initialFrame : UIScreen.main.bounds
    )
    if !options.isAudio, let container = attachedContainer {
      mountHostView(hostView, into: container)
    }
    let layerAddr = Int64(
      Int(bitPattern: Unmanaged.passUnretained(hostView.metalLayer).toOpaque())
    )

    let sessionBox = WeakEngineEventRelay(self)
    let session = MpvSession(
      hostView: hostView,
      isAudio: options.isAudio,
      onEvent: { event in
        Task { @MainActor in
          sessionBox.engine?.handleSessionEvent(event, from: sessionBox)
        }
      }
    )
    sessionBox.boundSession = session
    activeSession = session

    onStateChanged?(.opening)
    session.start(
      source: source,
      options: options,
      layerAddr: layerAddr,
      initialRate: currentRate
    )
  }

  func play() {
    activeSession?.setFlagAsync(name: "pause", value: false)
  }

  func pause() {
    activeSession?.setFlagAsync(name: "pause", value: true)
  }

  func seek(toMs: Int) {
    let secs = max(0.0, Double(toMs) / 1000.0)
    currentPosSec = secs
    activeSession?.sendCommandAsync(["seek", String(format: "%.3f", secs), "absolute"])
  }

  func jump(byOffsetMs deltaMs: Int, completion: (@MainActor () -> Void)?) {
    seek(toMs: currentTimeMs + deltaMs)
    completion?()
  }

  func setAspectFill(_ fill: Bool) {
    activeSession?.setDoubleAsync(name: "panscan", value: fill ? 1.0 : 0.0)
  }

  func selectAudioTrack(id: String) {
    activeSession?.setStringAsync(name: "aid", value: id)
  }

  func selectSubtitleTrack(id: String) {
    activeSession?.setStringAsync(name: "sid", value: id)
  }

  func deselectAllSubtitles() {
    activeSession?.setStringAsync(name: "sid", value: "no")
  }

  @discardableResult
  func addExternalSubtitle(fileURL: URL) -> Bool {
    guard let session = activeSession, session.isActive else { return false }
    session.sendCommandAsync(["sub-add", fileURL.path, "select"])
    return true
  }

  func stopAndReleaseAsync(on queue: DispatchQueue, completion: (@Sendable () -> Void)?) {
    removeLifecycleObservers()
    onStateChanged = nil
    onTracksChanged = nil
    attachedContainer = nil
    if let session = activeSession {
      activeSession = nil
      session.hostView.removeFromSuperview()
      session.shutdown(notifyQueue: queue, completion: completion)
    } else if let completion {
      queue.async(execute: completion)
    }
  }

  private func removeLifecycleObservers() {
    if let backgroundObserver {
      NotificationCenter.default.removeObserver(backgroundObserver)
      self.backgroundObserver = nil
    }
    if let foregroundObserver {
      NotificationCenter.default.removeObserver(foregroundObserver)
      self.foregroundObserver = nil
    }
  }

  private func handleDidEnterBackground() {
    guard let session = activeSession, !session.isAudio else { return }
    pause()
    session.setStringAsync(name: "vid", value: "no")
  }

  private func handleWillEnterForeground() {
    guard let session = activeSession, !session.isAudio else { return }
    session.setStringAsync(name: "vid", value: "auto")
  }

  fileprivate func handleSessionEvent(
    _ event: MpvDispatchedEvent,
    from relay: WeakEngineEventRelay
  ) {
    guard let session = relay.boundSession, session === activeSession else { return }
    switch event {
    case .fileLoaded:
      onStateChanged?(.playing)
    case .endedEOF:
      isPausedState = true
      onStateChanged?(.ended)
    case .failed(let kind):
      isPausedState = true
      onStateChanged?(.error(kind))
    case .pauseChanged(let paused):
      isPausedState = paused
      onStateChanged?(paused ? .paused : .playing)
    case .bufferingChanged(let buffering):
      if buffering {
        onStateChanged?(.buffering)
      } else if !isPausedState {
        onStateChanged?(.playing)
      }
    case .timeChanged(let pos):
      currentPosSec = pos
    case .durationChanged(let dur):
      durationSec = dur
    case .seekableChanged(let seekable):
      isSeekableState = seekable
    case .tracksChanged(let jsonStr):
      updateTracksFromJSON(jsonStr)
    }
  }

  private func updateTracksFromJSON(_ json: String) {
    guard let data = json.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([MpvTrackJSON].self, from: data)
    else { return }
    var audios: [EngineTrack] = []
    var subs: [EngineTrack] = []
    for item in decoded {
      let pieces = [item.title, item.lang, item.codec]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      let label = pieces.isEmpty ? "#\(item.id)" : pieces.joined(separator: " · ")
      let track = EngineTrack(
        id: "\(item.id)",
        label: label,
        language: item.lang,
        isSelected: item.selected == true
      )
      if item.type == "audio" {
        audios.append(track)
      } else if item.type == "sub" {
        subs.append(track)
      }
    }
    cachedAudioTracks = audios
    cachedSubtitleTracks = subs
    onTracksChanged?()
  }
}

private final class WeakEngineEventRelay: @unchecked Sendable {
  weak var engine: MpvPlaybackEngine?
  weak var boundSession: MpvSession?
  init(_ engine: MpvPlaybackEngine) {
    self.engine = engine
  }
}
