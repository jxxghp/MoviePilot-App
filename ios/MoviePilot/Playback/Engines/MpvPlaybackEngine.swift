import Foundation
import Libmpv
import MoviePilotCore
import QuartzCore
import UIKit

/// 承载 `CAMetalLayer` 的 Metal/Vulkan（MoltenVK）视频渲染宿主管线视图。
private final class MpvMetalHostView: UIView {
  override class var layerClass: AnyClass { CAMetalLayer.self }

  var metalLayer: CAMetalLayer {
    guard let layer = self.layer as? CAMetalLayer else {
      fatalError("Expected CAMetalLayer")
    }
    return layer
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    metalLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
    metalLayer.drawableSize = CGSize(
      width: max(1, bounds.width * metalLayer.contentsScale),
      height: max(1, bounds.height * metalLayer.contentsScale)
    )
  }
}

/// 线程安全隔离的 `libmpv` 句柄桥接器，避免在 Swift 6 `@MainActor` 与后台事件循环之间产生数据竞争。
private final class MpvHandleBox: @unchecked Sendable {
  private let lock = NSLock()
  private var rawHandle: OpaquePointer?

  init(_ handle: OpaquePointer?) {
    self.rawHandle = handle
  }

  var handle: OpaquePointer? {
    lock.lock()
    defer { lock.unlock() }
    return rawHandle
  }

  func takeHandle() -> OpaquePointer? {
    lock.lock()
    defer { lock.unlock() }
    let current = rawHandle
    rawHandle = nil
    return current
  }
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
/// - 事件循环运行于独立后台队列，销毁通过专用串行队列执行 `mpv_terminate_destroy`，绝不阻塞主线程。
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

  private let hostView = MpvMetalHostView()
  private let eventQueue = DispatchQueue(
    label: "com.moviepilot.playback.mpv.events", qos: .userInitiated)
  private var handleBox = MpvHandleBox(nil)
  private var isPausedState = true
  private var isSeekableState = false
  private var currentPosSec: Double = 0
  private var durationSec: Double = 0
  private var currentRate: Float = 1.0
  private var cachedAudioTracks: [EngineTrack] = []
  private var cachedSubtitleTracks: [EngineTrack] = []
  private var loadedOptions: EngineLoadOptions?

  var onStateChanged: ((PlaybackEngineState) -> Void)?
  var onTracksChanged: (() -> Void)?

  init() {
    hostView.translatesAutoresizingMaskIntoConstraints = false
    hostView.backgroundColor = .clear
    hostView.isUserInteractionEnabled = false
    hostView.metalLayer.framebufferOnly = true
    hostView.metalLayer.pixelFormat = .bgra8Unorm
  }

  var pipSource: EnginePictureInPictureSource { .none }

  var isPlaying: Bool { !isPausedState && handleBox.handle != nil }
  var isSeekable: Bool { isSeekableState }
  var currentTimeMs: Int { max(0, Int((currentPosSec * 1000).rounded())) }
  var durationMs: Int { max(0, Int((durationSec * 1000).rounded())) }

  var rate: Float {
    get { currentRate }
    set {
      let clamped = max(0.5, min(capabilities.maxRate, newValue))
      currentRate = clamped
      if let mpv = handleBox.handle {
        var val = Double(clamped)
        mpv_set_property_async(mpv, 0, "speed", MPV_FORMAT_DOUBLE, &val)
      }
    }
  }

  var audioTracks: [EngineTrack] { cachedAudioTracks }
  var subtitleTracks: [EngineTrack] { cachedSubtitleTracks }

  func attachVideoContainer(_ container: UIView) {
    if hostView.superview !== container {
      hostView.removeFromSuperview()
      container.addSubview(hostView)
      NSLayoutConstraint.activate([
        hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        hostView.topAnchor.constraint(equalTo: container.topAnchor),
        hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
      container.layoutIfNeeded()
    }
  }

  func detachVideoContainer() {
    hostView.removeFromSuperview()
  }

  func load(source: EngineMediaSource, options: EngineLoadOptions) throws {
    loadedOptions = options
    currentRate = max(0.5, min(capabilities.maxRate, options.rate))
    isPausedState = false
    currentPosSec = Double(max(0, options.startPositionMs)) / 1000.0
    durationSec = 0
    cachedAudioTracks = []
    cachedSubtitleTracks = []

    // 若之前已有 mpv 实例，安全重建以确保渲染层、解码模式和 TLS 参数彻底生效。
    if let old = handleBox.takeHandle() {
      nonisolated(unsafe) let oldPtr = old
      eventQueue.async {
        mpv_terminate_destroy(oldPtr)
      }
    }

    guard let mpv = mpv_create() else {
      throw MediaPlaybackError.unavailable
    }

    // 渲染输出配置
    if options.isAudio {
      mpv_set_option_string(mpv, "vid", "no")
      mpv_set_option_string(mpv, "vo", "null")
    } else {
      var layerAddr = Int64(Int(bitPattern: Unmanaged.passUnretained(hostView.metalLayer).toOpaque()))
      mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerAddr)
      mpv_set_option_string(mpv, "vo", "gpu-next")
      mpv_set_option_string(mpv, "gpu-api", "vulkan")
      mpv_set_option_string(mpv, "gpu-context", "moltenvk")
      mpv_set_option_string(mpv, "target-colorspace-hint", "yes")
      mpv_set_option_string(
        mpv, "hwdec", options.decodeMode == .swForce ? "no" : "videotoolbox")
      mpv_set_option_string(mpv, "panscan", options.aspectFill ? "1.0" : "0.0")
    }

    // 缓冲、倍速、字幕与声音增强配置
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
    mpv_set_option_string(mpv, "speed", String(format: "%.2f", currentRate))

    if options.startPositionMs > 1_000 {
      mpv_set_option_string(
        mpv, "start", String(format: "%.3f", Double(options.startPositionMs) / 1000.0))
    }

    // 注入安全 HTTP 头（使用 MPV_FORMAT_NODE_ARRAY 避免 Cookie/Authorization 内逗号被误拆）
    var mergedHeaders = source.headers
    if source.isSameOriginInstance, let cookie = source.sameOriginCookie,
      mergedHeaders["Cookie"] == nil
    {
      mergedHeaders["Cookie"] = "\(cookie.name)=\(cookie.value)"
    }
    if !mergedHeaders.isEmpty && !source.url.isFileURL {
      Self.applyHeaderFields(mergedHeaders, to: mpv)
    }

    guard mpv_initialize(mpv) >= 0 else {
      mpv_terminate_destroy(mpv)
      throw MediaPlaybackError.unavailable
    }

    // 注册核心属性监听
    mpv_observe_property(mpv, 1, "pause", MPV_FORMAT_FLAG)
    mpv_observe_property(mpv, 2, "time-pos", MPV_FORMAT_DOUBLE)
    mpv_observe_property(mpv, 3, "duration", MPV_FORMAT_DOUBLE)
    mpv_observe_property(mpv, 4, "seekable", MPV_FORMAT_FLAG)
    mpv_observe_property(mpv, 5, "paused-for-cache", MPV_FORMAT_FLAG)
    mpv_observe_property(mpv, 6, "track-list", MPV_FORMAT_STRING)

    let box = MpvHandleBox(mpv)
    self.handleBox = box
    startEventLoop(for: box)

    onStateChanged?(.opening)
    let targetString = source.url.isFileURL ? source.url.path : source.url.absoluteString
    Self.sendCommand(mpv, ["loadfile", targetString, "replace"])
  }

  func play() {
    guard let mpv = handleBox.handle else { return }
    var flag: Int32 = 0
    mpv_set_property_async(mpv, 0, "pause", MPV_FORMAT_FLAG, &flag)
  }

  func pause() {
    guard let mpv = handleBox.handle else { return }
    var flag: Int32 = 1
    mpv_set_property_async(mpv, 0, "pause", MPV_FORMAT_FLAG, &flag)
  }

  func seek(toMs: Int) {
    guard let mpv = handleBox.handle else { return }
    let secs = max(0.0, Double(toMs) / 1000.0)
    currentPosSec = secs
    Self.sendCommand(mpv, ["seek", String(format: "%.3f", secs), "absolute"])
  }

  func jump(byOffsetMs deltaMs: Int, completion: (@MainActor () -> Void)?) {
    seek(toMs: currentTimeMs + deltaMs)
    completion?()
  }

  func setAspectFill(_ fill: Bool) {
    guard let mpv = handleBox.handle else { return }
    var val: Double = fill ? 1.0 : 0.0
    mpv_set_property_async(mpv, 0, "panscan", MPV_FORMAT_DOUBLE, &val)
  }

  func selectAudioTrack(id: String) {
    guard let mpv = handleBox.handle else { return }
    mpv_set_property_string(mpv, "aid", id)
  }

  func selectSubtitleTrack(id: String) {
    guard let mpv = handleBox.handle else { return }
    mpv_set_property_string(mpv, "sid", id)
  }

  func deselectAllSubtitles() {
    guard let mpv = handleBox.handle else { return }
    mpv_set_property_string(mpv, "sid", "no")
  }

  @discardableResult
  func addExternalSubtitle(fileURL: URL) -> Bool {
    guard let mpv = handleBox.handle else { return false }
    Self.sendCommand(mpv, ["sub-add", fileURL.path, "select"])
    return true
  }

  func stopAndReleaseAsync(on queue: DispatchQueue, completion: (@Sendable () -> Void)?) {
    detachVideoContainer()
    onStateChanged = nil
    onTracksChanged = nil
    nonisolated(unsafe) let oldHandle = handleBox.takeHandle()
    queue.async {
      if let oldHandle {
        mpv_wakeup(oldHandle)
        mpv_terminate_destroy(oldHandle)
      }
      completion?()
    }
  }

  private func startEventLoop(for box: MpvHandleBox) {
    eventQueue.async { [weak self] in
      while let mpv = box.handle {
        guard let eventPtr = mpv_wait_event(mpv, 0.25) else { continue }
        let event = eventPtr.pointee
        switch event.event_id {
        case MPV_EVENT_NONE:
          continue
        case MPV_EVENT_SHUTDOWN:
          return
        case MPV_EVENT_FILE_LOADED:
          Task { @MainActor [weak self] in
            self?.onStateChanged?(.playing)
          }
        case MPV_EVENT_END_FILE:
          let endData = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee
          let reason = endData?.reason ?? MPV_END_FILE_REASON_STOP
          let errCode = endData?.error ?? 0
          Task { @MainActor [weak self] in
            guard let self else { return }
            if reason == MPV_END_FILE_REASON_EOF {
              self.isPausedState = true
              self.onStateChanged?(.ended)
            } else if reason == MPV_END_FILE_REASON_ERROR {
              self.isPausedState = true
              let kind: PlaybackEngineErrorKind =
                (errCode == MPV_ERROR_UNKNOWN_FORMAT.rawValue
                  || errCode == MPV_ERROR_UNSUPPORTED.rawValue)
                ? .unsupportedFormat : .network
              self.onStateChanged?(.error(kind))
            }
          }
        case MPV_EVENT_PROPERTY_CHANGE:
          guard let propPtr = event.data?.assumingMemoryBound(to: mpv_event_property.self) else {
            continue
          }
          let prop = propPtr.pointee
          guard let cName = prop.name else { continue }
          let name = String(cString: cName)
          switch name {
          case "pause":
            if prop.format == MPV_FORMAT_FLAG, let data = prop.data {
              let paused = data.assumingMemoryBound(to: Int32.self).pointee != 0
              Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPausedState = paused
                self.onStateChanged?(paused ? .paused : .playing)
              }
            }
          case "paused-for-cache":
            if prop.format == MPV_FORMAT_FLAG, let data = prop.data {
              let buffering = data.assumingMemoryBound(to: Int32.self).pointee != 0
              Task { @MainActor [weak self] in
                guard let self else { return }
                if buffering {
                  self.onStateChanged?(.buffering)
                } else if !self.isPausedState {
                  self.onStateChanged?(.playing)
                }
              }
            }
          case "time-pos":
            if prop.format == MPV_FORMAT_DOUBLE, let data = prop.data {
              let pos = data.assumingMemoryBound(to: Double.self).pointee
              if pos.isFinite {
                Task { @MainActor [weak self] in
                  self?.currentPosSec = max(0, pos)
                }
              }
            }
          case "duration":
            if prop.format == MPV_FORMAT_DOUBLE, let data = prop.data {
              let dur = data.assumingMemoryBound(to: Double.self).pointee
              if dur.isFinite {
                Task { @MainActor [weak self] in
                  self?.durationSec = max(0, dur)
                }
              }
            }
          case "seekable":
            if prop.format == MPV_FORMAT_FLAG, let data = prop.data {
              let seekable = data.assumingMemoryBound(to: Int32.self).pointee != 0
              Task { @MainActor [weak self] in
                self?.isSeekableState = seekable
              }
            }
          case "track-list":
            if prop.format == MPV_FORMAT_STRING,
              let data = prop.data,
              let cStr = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee
            {
              let jsonStr = String(cString: cStr)
              Task { @MainActor [weak self] in
                self?.updateTracksFromJSON(jsonStr)
              }
            }
          default:
            break
          }
        default:
          break
        }
      }
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

  private static func applyHeaderFields(_ headers: [String: String], to mpv: OpaquePointer) {
    let lines = headers
      .filter { !$0.key.isEmpty && !$0.value.isEmpty }
      .map { "\($0.key): \($0.value)" }
    guard !lines.isEmpty else { return }
    let cStrings = lines.map { strdup($0) }
    defer {
      for ptr in cStrings where ptr != nil {
        free(ptr)
      }
    }
    var nodes: [mpv_node] = cStrings.map { ptr in
      var node = mpv_node()
      node.format = MPV_FORMAT_STRING
      node.u.string = ptr
      return node
    }
    nodes.withUnsafeMutableBufferPointer { buf in
      var list = mpv_node_list()
      list.num = Int32(buf.count)
      list.values = buf.baseAddress
      withUnsafeMutablePointer(to: &list) { listPtr in
        var root = mpv_node()
        root.format = MPV_FORMAT_NODE_ARRAY
        root.u.list = listPtr
        _ = mpv_set_option(mpv, "http-header-fields", MPV_FORMAT_NODE, &root)
      }
    }
  }
}
