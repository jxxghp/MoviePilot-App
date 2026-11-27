import AVFoundation
import CoreMedia
import CoreText
import CoreVideo
import Foundation
import Libmpv
import MoviePilotCore
import MoviePilotSession
import QuartzCore
import UIKit
import os

/// 解析 iOS 18+ / iOS 26+ 系统简体与繁体中文字体真实路径，并通过沙盒软链目录注入 `libass` (`sub-fonts-dir`)，
/// 彻底规避 `ass_coretext` 在新版 iOS 下无法通过字体名匹配 MobileAsset 中文字体导致简繁字幕显示为方框的问题。
private enum MpvSubtitleFontResolver {
  struct ResolvedFontConfig: Sendable {
    let familyName: String
    let fontsDirectory: String?
  }

  private static let cachedConfig: ResolvedFontConfig = buildFontConfig()

  static func resolve() -> ResolvedFontConfig {
    cachedConfig
  }

  private static func buildFontConfig() -> ResolvedFontConfig {
    let probes = ["简体中文字幕", "繁體中文字幕", "日本語字幕"]
    let baseFont = CTFontCreateWithName("Helvetica" as CFString, 18.0, nil)
    var primaryFamily: String?
    var discoveredURLs: [URL] = []
    var seenPaths: Set<String> = []

    for sample in probes {
      let utf16Count = sample.utf16.count
      let matched = CTFontCreateForString(
        baseFont, sample as CFString, CFRange(location: 0, length: utf16Count))
      let family = (CTFontCopyFamilyName(matched) as String)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if primaryFamily == nil, !family.isEmpty, family.lowercased() != "helvetica" {
        primaryFamily = family
      }
      if let url = CTFontCopyAttribute(matched, kCTFontURLAttribute) as? URL {
        let stdPath = url.standardizedFileURL.path
        if !stdPath.isEmpty, !seenPaths.contains(stdPath),
          FileManager.default.isReadableFile(atPath: stdPath)
        {
          seenPaths.insert(stdPath)
          discoveredURLs.append(url)
        }
      }
    }

    let fallbackHiragino = URL(fileURLWithPath: "/System/Library/Fonts/Core/HiraginoKakuGothic.ttc")
    if FileManager.default.isReadableFile(atPath: fallbackHiragino.path),
      !seenPaths.contains(fallbackHiragino.path)
    {
      seenPaths.insert(fallbackHiragino.path)
      discoveredURLs.append(fallbackHiragino)
    }

    let familyName = primaryFamily ?? "Hiragino Sans"
    guard !discoveredURLs.isEmpty else {
      return ResolvedFontConfig(familyName: familyName, fontsDirectory: nil)
    }

    let fm = FileManager.default
    if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
      let linkDir = cachesDir.appendingPathComponent("mpv-sub-fonts", isDirectory: true)
      do {
        try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        var linkedCount = 0
        for (idx, srcURL) in discoveredURLs.enumerated() {
          let ext = srcURL.pathExtension.isEmpty ? "ttc" : srcURL.pathExtension
          let dstURL = linkDir.appendingPathComponent("cjk-\(idx).\(ext)")
          if fm.fileExists(atPath: dstURL.path) {
            try? fm.removeItem(at: dstURL)
          }
          try fm.createSymbolicLink(at: dstURL, withDestinationURL: srcURL)
          if fm.isReadableFile(atPath: dstURL.path) {
            linkedCount += 1
          }
        }
        if linkedCount > 0 {
          return ResolvedFontConfig(familyName: familyName, fontsDirectory: linkDir.path)
        }
      } catch {
        // 软链创建受限时回退至字体所在真实系统目录
      }
    }

    let directDir = discoveredURLs[0].deletingLastPathComponent().path
    return ResolvedFontConfig(
      familyName: familyName,
      fontsDirectory: fm.isReadableFile(atPath: directDir) ? directDir : nil
    )
  }
}

/// 构造 `AVSampleBufferDisplayLayer` 画中画所需的 `CMSampleBuffer` 视频帧（包含起播占位黑帧与软解渲染帧）。
private enum MpvSampleBufferFactory {
  static func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    var formatDesc: CMVideoFormatDescription?
    let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDesc
    )
    guard fmtStatus == noErr, let formatDesc else { return nil }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let createStatus = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDesc,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    guard createStatus == noErr, let sampleBuffer else { return nil }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sampleBuffer, createIfNecessary: true)
    {
      let dict = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        dict,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
      )
    }
    return sampleBuffer
  }

  static func makeBlackSampleBuffer(width: Int, height: Int) -> CMSampleBuffer? {
    let safeW = max(64, min(1920, width & ~1))
    let safeH = max(36, min(1080, height & ~1))
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any]
    ]
    var pb: CVPixelBuffer?
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        safeW,
        safeH,
        kCVPixelFormatType_32BGRA,
        attrs as CFDictionary,
        &pb
      ) == kCVReturnSuccess,
      let pixelBuffer = pb
    else { return nil }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      memset(base, 0, bytesPerRow * safeH)
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    return makeSampleBuffer(from: pixelBuffer)
  }
}

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

/// 同时承载前景 `MpvMetalLayer`（全屏 HDR/硬解渲染）与底层 `AVSampleBufferDisplayLayer`（系统画中画输出）的宿主视图。
private final class MpvMetalHostView: UIView {
  let pipDisplayLayer = AVSampleBufferDisplayLayer()
  let metalLayer = MpvMetalLayer()
  var onDrawableSizeChanged: ((CGSize) -> Void)?
  private var lastReportedDrawableSize: CGSize = .zero

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .black
    isUserInteractionEnabled = false

    pipDisplayLayer.videoGravity = .resizeAspect
    pipDisplayLayer.backgroundColor = UIColor.black.cgColor
    layer.addSublayer(pipDisplayLayer)

    metalLayer.framebufferOnly = false
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.contentsGravity = .resizeAspect
    metalLayer.backgroundColor = UIColor.black.cgColor
    layer.addSublayer(metalLayer)

    syncDrawableSize()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      syncDrawableSize()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    syncDrawableSize()
  }

  func syncDrawableSize() {
    let scale = max(1.0, window?.screen.nativeScale ?? UIScreen.main.nativeScale)
    let sourceRect: CGRect
    if bounds.width > 1 && bounds.height > 1 {
      sourceRect = bounds
    } else if let superBounds = superview?.bounds, superBounds.width > 1 && superBounds.height > 1 {
      sourceRect = CGRect(origin: .zero, size: superBounds.size)
    } else {
      sourceRect = CGRect(origin: .zero, size: UIScreen.main.bounds.size)
    }
    let nextDrawableSize = CGSize(
      width: max(2, (sourceRect.width * scale).rounded()),
      height: max(2, (sourceRect.height * scale).rounded())
    )

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    pipDisplayLayer.frame = sourceRect
    metalLayer.frame = sourceRect
    metalLayer.contentsScale = scale
    metalLayer.drawableSize = nextDrawableSize
    CATransaction.commit()

    if abs(nextDrawableSize.width - lastReportedDrawableSize.width) >= 1
      || abs(nextDrawableSize.height - lastReportedDrawableSize.height) >= 1
    {
      lastReportedDrawableSize = nextDrawableSize
      onDrawableSizeChanged?(nextDrawableSize)
    }
  }
}

/// 单次 `libmpv` 会话控制器：
/// - 所有 `libmpv` 核心调用独占运行在 `serialQueue`；
/// - 画中画激活期间自动从 `MoltenVK` 切换至纯 CPU `MPV_RENDER_API_TYPE_SW` 软渲染管线，规避后台 GPU 强杀并保留 ASS/SRT 字幕渲染。
private final class MpvSession: @unchecked Sendable {
  let hostView: MpvMetalHostView
  let isAudio: Bool
  let preferHardwareDecode: Bool

  private let activeFlag = OSAllocatedUnfairLock(initialState: true)
  private let videoDimState = OSAllocatedUnfairLock(initialState: (width: 1920, height: 1080))
  private let targetDrawableState = OSAllocatedUnfairLock(initialState: (width: 0, height: 0))
  private let osdDimState = OSAllocatedUnfairLock(initialState: (width: 0, height: 0))
  private let pipActiveState = OSAllocatedUnfairLock(initialState: false)
  private let serialQueue: DispatchQueue
  private let pipRenderQueue: DispatchQueue
  private let onEvent: @Sendable (MpvDispatchedEvent) -> Void
  private let onPipFrame: @Sendable (CMSampleBuffer) -> Void

  // 以下状态仅在 `serialQueue` 内读写
  private var rawHandle: OpaquePointer?
  private var swRenderCtx: OpaquePointer?
  private var isStopped = false
  private var hasLoadedFile = false
  private var viewportCropStep = 0
  private var hasTemporaryViewportCrop = false
  private var drainScheduled = false
  private var wakeupContextPtr: UnsafeMutableRawPointer?
  private var renderCallbackCtxPtr: UnsafeMutableRawPointer?
  private var loopbackProxy: LoopbackAuthProxy?

  // 以下状态仅在 `pipRenderQueue` 内读写
  private var renderUpdateScheduled = false
  private var pipPixelBufferPool: CVPixelBufferPool?
  private var pipPoolDimensions: (width: Int, height: Int) = (0, 0)

  init(
    hostView: MpvMetalHostView,
    isAudio: Bool,
    preferHardwareDecode: Bool,
    onEvent: @escaping @Sendable (MpvDispatchedEvent) -> Void,
    onPipFrame: @escaping @Sendable (CMSampleBuffer) -> Void
  ) {
    self.hostView = hostView
    self.isAudio = isAudio
    self.preferHardwareDecode = preferHardwareDecode
    let id = UUID().uuidString
    self.serialQueue = DispatchQueue(
      label: "com.moviepilot.playback.mpv.session.\(id)",
      qos: .userInitiated
    )
    self.pipRenderQueue = DispatchQueue(
      label: "com.moviepilot.playback.mpv.pip.\(id)",
      qos: .userInitiated
    )
    self.onEvent = onEvent
    self.onPipFrame = onPipFrame
  }

  var isActive: Bool {
    activeFlag.withLock { $0 }
  }

  func updateTargetDrawableSize(_ size: CGSize) {
    let w = max(0, Int(size.width.rounded()))
    let h = max(0, Int(size.height.rounded()))
    targetDrawableState.withLock { state in
      state = (w, h)
    }
  }

  var isViewportAlignedWithDrawable: Bool {
    let target = targetDrawableState.withLock { $0 }
    let osd = osdDimState.withLock { $0 }
    guard target.width > 1, target.height > 1, osd.width > 1, osd.height > 1 else {
      return false
    }
    return abs(osd.width - target.width) <= 2 && abs(osd.height - target.height) <= 2
  }

  func start(
    source: EngineMediaSource,
    options: EngineLoadOptions,
    layerAddr: Int64,
    initialRate: Float
  ) {
    let retainedView = hostView
    let fontConfig = MpvSubtitleFontResolver.resolve()
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
      mpv_set_option_string(mpv, "sub-font", fontConfig.familyName)
      if let fontsDir = fontConfig.fontsDirectory {
        mpv_set_option_string(mpv, "sub-fonts-dir", fontsDir)
      }
      if options.ignoreAssStyle {
        mpv_set_option_string(
          mpv, "sub-ass-style-overrides", "FontName=\(fontConfig.familyName)")
      }
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
      mpv_observe_property(mpv, 7, "dwidth", MPV_FORMAT_INT64)
      mpv_observe_property(mpv, 8, "dheight", MPV_FORMAT_INT64)
      mpv_observe_property(mpv, 9, "osd-width", MPV_FORMAT_INT64)
      mpv_observe_property(mpv, 10, "osd-height", MPV_FORMAT_INT64)

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

  /// 横竖屏旋转或容器尺寸变化后强制触发 `_vo_reconfig2` -> `moltenvk_reconfig`：
  /// 由于 `moltenvk_control` 未实现 `VO_EVENT_RESIZE`，且空裁剪 `""` 与 `"100%x100%"` 在 `_m_rect_apply` 后均生成
  /// `{0, 0, w, h}` 导致 `_mp_image_params_static_equal` 判定参数未变而跳过 `_vo_reconfig2`（横屏画面滞留在左下角），
  /// 此处在 `"+1+0"` 与 `"+2+0"` 对称微调参数间交替切换以驱动 `_vo_reconfig2` 立即同步最新 `CAMetalLayer.drawableSize`，
  /// 并在 `osd-width`/`osd-height` 与目标画布对齐后自动复位回无裁剪全画幅 `""`。
  func reconfigureVideoViewport() {
    guard isActive, !isAudio else { return }
    serialQueue.async { [weak self] in
      guard let self, !self.isStopped, self.hasLoadedFile,
        !self.pipActiveState.withLock({ $0 }),
        let mpv = self.rawHandle
      else { return }
      self.viewportCropStep = (self.viewportCropStep == 1) ? 2 : 1
      self.hasTemporaryViewportCrop = true
      let cropValue = "+\(self.viewportCropStep)+0"
      _ = mpv_set_property_string(mpv, "video-crop", cropValue)
      Self.sendCommand(mpv, ["video-reconfig"])
    }
  }

  /// 在 `osd-width`/`osd-height` 已对齐当前 `CAMetalLayer.drawableSize` 后，复位临时对称裁剪回完整原始画幅。
  func restoreFullFrameViewportIfNeeded() {
    guard isActive, !isAudio else { return }
    serialQueue.async { [weak self] in
      guard let self, !self.isStopped, self.hasLoadedFile,
        self.hasTemporaryViewportCrop,
        !self.pipActiveState.withLock({ $0 }),
        let mpv = self.rawHandle
      else { return }
      self.hasTemporaryViewportCrop = false
      self.viewportCropStep = 0
      _ = mpv_set_property_string(mpv, "video-crop", "")
      Self.sendCommand(mpv, ["video-reconfig"])
    }
  }

  /// 切换画中画纯 CPU 软渲染输出与前台 MoltenVK 硬解输出。
  func setSoftwarePipMode(_ active: Bool, appInBackground: Bool) {
    guard isActive, !isAudio else { return }
    serialQueue.async { [weak self] in
      guard let self, !self.isStopped, let mpv = self.rawHandle else { return }
      let wasActive = self.pipActiveState.withLock { state -> Bool in
        let prev = state
        state = active
        return prev
      }
      if active {
        guard !wasActive else { return }
        // 先关闭当前 MoltenVK 视频输出释放 GPU 句柄，再切换至 libmpv SW 软渲染管线
        _ = mpv_set_property_string(mpv, "vid", "no")
        _ = mpv_set_property_string(mpv, "hwdec", "no")
        _ = mpv_set_property_string(mpv, "sws-fast", "yes")
        if self.swRenderCtx == nil {
          self.createSwRenderContextOnSerialQueue(mpv: mpv)
        }
        if self.swRenderCtx != nil {
          _ = mpv_set_property_string(mpv, "vo", "libmpv")
          _ = mpv_set_property_string(mpv, "vid", "auto")
        }
      } else {
        guard wasActive else { return }
        _ = mpv_set_property_string(mpv, "vid", "no")
        self.destroySwRenderContextOnSerialQueue()
        _ = mpv_set_property_string(mpv, "vo", "gpu-next")
        _ = mpv_set_property_string(
          mpv, "hwdec", self.preferHardwareDecode ? "videotoolbox" : "no")
        if !appInBackground {
          _ = mpv_set_property_string(mpv, "vid", "auto")
          if self.hasLoadedFile {
            self.viewportCropStep = (self.viewportCropStep == 1) ? 2 : 1
            self.hasTemporaryViewportCrop = true
            let cropValue = "+\(self.viewportCropStep)+0"
            _ = mpv_set_property_string(mpv, "video-crop", cropValue)
            Self.sendCommand(mpv, ["video-reconfig"])
          }
        }
      }
    }
  }

  private func createSwRenderContextOnSerialQueue(mpv: OpaquePointer) {
    let box = WeakMpvSessionBox(self)
    let rawCbCtx = Unmanaged.passRetained(box).toOpaque()
    var newCtx: OpaquePointer?
    let rc: Int32 = "sw".withCString { swCString in
      var advancedControl: Int32 = 0
      return withUnsafeMutablePointer(to: &advancedControl) { advPtr in
        var params = [
          mpv_render_param(
            type: MPV_RENDER_PARAM_API_TYPE,
            data: UnsafeMutableRawPointer(mutating: swCString)
          ),
          mpv_render_param(
            type: MPV_RENDER_PARAM_ADVANCED_CONTROL,
            data: UnsafeMutableRawPointer(advPtr)
          ),
          mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        ]
        return params.withUnsafeMutableBufferPointer { buf in
          mpv_render_context_create(&newCtx, mpv, buf.baseAddress)
        }
      }
    }
    guard rc >= 0, let created = newCtx else {
      Unmanaged<WeakMpvSessionBox>.fromOpaque(rawCbCtx).release()
      return
    }
    self.swRenderCtx = created
    self.renderCallbackCtxPtr = rawCbCtx
    mpv_render_context_set_update_callback(
      created,
      { ctx in
        guard let ctx else { return }
        let box = Unmanaged<WeakMpvSessionBox>.fromOpaque(ctx).takeUnretainedValue()
        box.session?.schedulePipRenderUpdate(renderCtx: box.session?.swRenderCtx)
      },
      rawCbCtx
    )
  }

  private func destroySwRenderContextOnSerialQueue() {
    guard let ctxToFree = swRenderCtx else { return }
    swRenderCtx = nil
    mpv_render_context_set_update_callback(ctxToFree, nil, nil)
    // 确保后台渲染队列中不再访问即将释放的 `mpv_render_context`
    pipRenderQueue.sync {
      self.pipPixelBufferPool = nil
      self.pipPoolDimensions = (0, 0)
    }
    mpv_render_context_free(ctxToFree)
    if let cbCtx = renderCallbackCtxPtr {
      renderCallbackCtxPtr = nil
      Unmanaged<WeakMpvSessionBox>.fromOpaque(cbCtx).release()
    }
  }

  fileprivate func schedulePipRenderUpdate(renderCtx: OpaquePointer?) {
    guard isActive, pipActiveState.withLock({ $0 }), let renderCtx else { return }
    nonisolated(unsafe) let unsafeCtx = renderCtx
    pipRenderQueue.async { [weak self] in
      guard let self, self.isActive, self.pipActiveState.withLock({ $0 }) else { return }
      if self.renderUpdateScheduled { return }
      self.renderUpdateScheduled = true
      self.renderPipFrames(using: unsafeCtx)
      self.renderUpdateScheduled = false
    }
  }

  private func renderPipFrames(using ctx: OpaquePointer) {
    while isActive && pipActiveState.withLock({ $0 }) {
      let flags = mpv_render_context_update(ctx)
      guard (flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue)) != 0 else { break }

      let srcDim = videoDimState.withLock { $0 }
      let maxW = 640
      let rawW = max(64, srcDim.width)
      let rawH = max(36, srcDim.height)
      let scale = rawW > maxW ? (Double(maxW) / Double(rawW)) : 1.0
      let targetW = max(64, Int((Double(rawW) * scale).rounded()) & ~1)
      let targetH = max(36, Int((Double(rawH) * scale).rounded()) & ~1)

      guard let pixelBuffer = obtainPipPixelBuffer(width: targetW, height: targetH) else { break }
      CVPixelBufferLockBaseAddress(pixelBuffer, [])
      let renderStatus: Int32
      if let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) {
        var sizeVec: [Int32] = [Int32(targetW), Int32(targetH)]
        var stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var blockForTargetTime: Int32 = 0
        renderStatus = "bgr0".withCString { fmtCStr in
          sizeVec.withUnsafeMutableBufferPointer { sizeBuf in
            withUnsafeMutablePointer(to: &stride) { stridePtr in
              withUnsafeMutablePointer(to: &blockForTargetTime) { blockPtr in
                var params = [
                  mpv_render_param(
                    type: MPV_RENDER_PARAM_SW_SIZE,
                    data: UnsafeMutableRawPointer(sizeBuf.baseAddress)
                  ),
                  mpv_render_param(
                    type: MPV_RENDER_PARAM_SW_FORMAT,
                    data: UnsafeMutableRawPointer(mutating: fmtCStr)
                  ),
                  mpv_render_param(
                    type: MPV_RENDER_PARAM_SW_STRIDE,
                    data: UnsafeMutableRawPointer(stridePtr)
                  ),
                  mpv_render_param(
                    type: MPV_RENDER_PARAM_SW_POINTER,
                    data: baseAddr
                  ),
                  mpv_render_param(
                    type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME,
                    data: UnsafeMutableRawPointer(blockPtr)
                  ),
                  mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return params.withUnsafeMutableBufferPointer { buf in
                  mpv_render_context_render(ctx, buf.baseAddress)
                }
              }
            }
          }
        }
      } else {
        renderStatus = -1
      }
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

      if renderStatus >= 0, let sample = MpvSampleBufferFactory.makeSampleBuffer(from: pixelBuffer)
      {
        onPipFrame(sample)
      }
    }
  }

  private func obtainPipPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    if pipPixelBufferPool == nil || pipPoolDimensions.width != width
      || pipPoolDimensions.height != height
    {
      let poolAttrs: [CFString: Any] = [kCVPixelBufferPoolMinimumBufferCountKey: 3]
      let bufferAttrs: [CFString: Any] = [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
        kCVPixelBufferBytesPerRowAlignmentKey: 64,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
      ]
      var createdPool: CVPixelBufferPool?
      CVPixelBufferPoolCreate(
        kCFAllocatorDefault,
        poolAttrs as CFDictionary,
        bufferAttrs as CFDictionary,
        &createdPool
      )
      pipPixelBufferPool = createdPool
      pipPoolDimensions = (width, height)
    }
    guard let pool = pipPixelBufferPool else { return nil }
    var pb: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess
    else {
      return nil
    }
    return pb
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
      if event.event_id == MPV_EVENT_FILE_LOADED {
        hasLoadedFile = true
      }
      if let translated = translateEvent(event) {
        onEvent(translated)
      }
    }
  }

  private func translateEvent(_ event: mpv_event) -> MpvDispatchedEvent? {
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
      case "dwidth":
        if prop.format == MPV_FORMAT_INT64, let data = prop.data {
          let w = Int(data.assumingMemoryBound(to: Int64.self).pointee)
          if w > 0 {
            let updated = videoDimState.withLock { state -> (Int, Int) in
              state.width = w
              return state
            }
            return .videoDimensionsChanged(width: updated.0, height: updated.1)
          }
        }
      case "dheight":
        if prop.format == MPV_FORMAT_INT64, let data = prop.data {
          let h = Int(data.assumingMemoryBound(to: Int64.self).pointee)
          if h > 0 {
            let updated = videoDimState.withLock { state -> (Int, Int) in
              state.height = h
              return state
            }
            return .videoDimensionsChanged(width: updated.0, height: updated.1)
          }
        }
      case "osd-width":
        if prop.format == MPV_FORMAT_INT64, let data = prop.data {
          let w = Int(data.assumingMemoryBound(to: Int64.self).pointee)
          if w > 0 {
            let updated = osdDimState.withLock { state -> (Int, Int) in
              state.width = w
              return state
            }
            return .osdDimensionsChanged(width: updated.0, height: updated.1)
          }
        }
      case "osd-height":
        if prop.format == MPV_FORMAT_INT64, let data = prop.data {
          let h = Int(data.assumingMemoryBound(to: Int64.self).pointee)
          if h > 0 {
            let updated = osdDimState.withLock { state -> (Int, Int) in
              state.height = h
              return state
            }
            return .osdDimensionsChanged(width: updated.0, height: updated.1)
          }
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
  /// 先释放 `mpv_render_context` 再执行 `mpv_terminate_destroy`，随后将 `MpvMetalHostView` 交回主线程析构。
  func shutdown(notifyQueue: DispatchQueue, completion: (@Sendable () -> Void)?) {
    let wasActive = activeFlag.withLock { state -> Bool in
      let prev = state
      state = false
      return prev
    }
    pipActiveState.withLock { $0 = false }
    guard wasActive else {
      if let completion { notifyQueue.async(execute: completion) }
      return
    }
    let retainedView = hostView
    serialQueue.async { [weak self] in
      if let self, !self.isStopped {
        self.isStopped = true
        self.destroySwRenderContextOnSerialQueue()
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
  case videoDimensionsChanged(width: Int, height: Int)
  case osdDimensionsChanged(width: Int, height: Int)
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
/// - 支持 MKV / DTS / TrueHD / HDR10 / Dolby Vision 色调映射、完整 ASS 简繁中文字体与 PGS 蓝光图形字幕；
/// - 支持横竖屏动态 `video-reconfig` 严格居中与基于 `AVSampleBufferDisplayLayer` + 纯 CPU `libmpv_sw` 的安全系统画中画小窗播放。
@MainActor
final class MpvPlaybackEngine: PlaybackEngine {
  let kind: ResolvedPlaybackEngine = .enhanced
  let capabilities = EngineCapabilities(
    supportsPiP: true,
    supportsAirPlayVideo: false,
    supportsAssStyling: true,
    supportsSoftwareVideoDecode: true,
    maxRate: 3.0
  )

  private weak var attachedContainer: UIView?
  private var activeSession: MpvSession?
  private var viewportSettleTask: Task<Void, Never>?
  private var backgroundObserver: NSObjectProtocol?
  private var foregroundObserver: NSObjectProtocol?
  private var isPausedState = true
  private var isSeekableState = false
  private var isPipActive = false
  private var hasPrimedPipBuffer = false
  private var videoDimensions: (width: Int, height: Int) = (1920, 1080)
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

  var pipSource: EnginePictureInPictureSource {
    guard let session = activeSession, !session.isAudio, attachedContainer != nil else {
      return .none
    }
    return .sampleBufferLayer(session.hostView.pipDisplayLayer)
  }

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
    viewportSettleTask?.cancel()
    viewportSettleTask = nil
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
    container.superview?.layoutIfNeeded()
    container.layoutIfNeeded()
    hostView.syncDrawableSize()
  }

  func setPictureInPictureActive(_ active: Bool) {
    guard isPipActive != active else { return }
    isPipActive = active
    guard let session = activeSession, !session.isAudio else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    session.hostView.metalLayer.isHidden = active
    CATransaction.commit()
    let inBg = UIApplication.shared.applicationState == .background
    session.setSoftwarePipMode(active, appInBackground: inBg)
  }

  func load(source: EngineMediaSource, options: EngineLoadOptions) throws {
    guard
      source.url.isFileURL
        || ["http", "https"].contains(source.url.scheme?.lowercased() ?? "")
    else {
      throw MediaPlaybackError.unavailable
    }

    viewportSettleTask?.cancel()
    viewportSettleTask = nil
    currentRate = max(0.5, min(capabilities.maxRate, options.rate))
    isPausedState = false
    isSeekableState = false
    isPipActive = false
    hasPrimedPipBuffer = false
    videoDimensions = (1920, 1080)
    currentPosSec = Double(max(0, options.startPositionMs)) / 1000.0
    durationSec = 0
    cachedAudioTracks = []
    cachedSubtitleTracks = []

    if let previous = activeSession {
      activeSession = nil
      previous.hostView.onDrawableSizeChanged = nil
      previous.hostView.removeFromSuperview()
      previous.shutdown(notifyQueue: .main, completion: nil)
    }

    attachedContainer?.superview?.layoutIfNeeded()
    attachedContainer?.layoutIfNeeded()
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
      preferHardwareDecode: options.decodeMode != .swForce,
      onEvent: { event in
        Task { @MainActor in
          sessionBox.engine?.handleSessionEvent(event, from: sessionBox)
        }
      },
      onPipFrame: { sampleBuffer in
        nonisolated(unsafe) let transferredSample = sampleBuffer
        Task { @MainActor in
          sessionBox.engine?.enqueuePipSampleBuffer(transferredSample, from: sessionBox)
        }
      }
    )
    sessionBox.boundSession = session
    activeSession = session
    session.updateTargetDrawableSize(hostView.metalLayer.drawableSize)

    hostView.onDrawableSizeChanged = { [weak self, weak session] newDrawableSize in
      guard let self, let session, self.activeSession === session else { return }
      session.updateTargetDrawableSize(newDrawableSize)
      self.scheduleViewportReconfig(for: session)
    }

    onStateChanged?(.opening)
    session.start(
      source: source,
      options: options,
      layerAddr: layerAddr,
      initialRate: currentRate
    )
  }

  private func scheduleViewportReconfig(for session: MpvSession) {
    guard !isPipActive else { return }
    session.reconfigureVideoViewport()
    viewportSettleTask?.cancel()
    viewportSettleTask = Task { @MainActor [weak self, weak session] in
      defer {
        if let self, self.activeSession === session {
          self.viewportSettleTask = nil
        }
      }
      for delayMs in [80, 180, 320, 500] {
        try? await Task.sleep(for: .milliseconds(delayMs))
        guard !Task.isCancelled, let self, let session, self.activeSession === session,
          !self.isPipActive
        else { return }
        session.hostView.syncDrawableSize()
        session.updateTargetDrawableSize(session.hostView.metalLayer.drawableSize)
        if session.isViewportAlignedWithDrawable {
          session.restoreFullFrameViewportIfNeeded()
        } else {
          session.reconfigureVideoViewport()
        }
      }
    }
  }

  private func primePipDisplayLayerIfNeeded() {
    guard let session = activeSession, !session.isAudio, !isPipActive else { return }
    guard
      let blackSample = MpvSampleBufferFactory.makeBlackSampleBuffer(
        width: videoDimensions.width,
        height: videoDimensions.height
      )
    else { return }
    let layer = session.hostView.pipDisplayLayer
    if layer.status == .failed {
      layer.flush()
    }
    layer.enqueue(blackSample)
    hasPrimedPipBuffer = true
  }

  fileprivate func enqueuePipSampleBuffer(
    _ sampleBuffer: CMSampleBuffer,
    from relay: WeakEngineEventRelay
  ) {
    guard let session = relay.boundSession, session === activeSession, isPipActive else { return }
    let layer = session.hostView.pipDisplayLayer
    if layer.status == .failed {
      layer.flush()
    }
    layer.enqueue(sampleBuffer)
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
    if let session = activeSession {
      session.hostView.pipDisplayLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
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
    viewportSettleTask?.cancel()
    viewportSettleTask = nil
    removeLifecycleObservers()
    onStateChanged = nil
    onTracksChanged = nil
    attachedContainer = nil
    if let session = activeSession {
      activeSession = nil
      session.hostView.onDrawableSizeChanged = nil
      session.hostView.pipDisplayLayer.flushAndRemoveImage()
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
    // 画中画处于激活态时由纯 CPU `libmpv_sw` 持续向系统小窗供帧，不得暂停或关闭视频轨
    if isPipActive {
      return
    }
    pause()
    session.setStringAsync(name: "vid", value: "no")
  }

  private func handleWillEnterForeground() {
    guard let session = activeSession, !session.isAudio else { return }
    if isPipActive {
      return
    }
    session.setStringAsync(name: "vid", value: "auto")
    scheduleViewportReconfig(for: session)
  }

  fileprivate func handleSessionEvent(
    _ event: MpvDispatchedEvent,
    from relay: WeakEngineEventRelay
  ) {
    guard let session = relay.boundSession, session === activeSession else { return }
    switch event {
    case .fileLoaded:
      if !session.isAudio {
        session.hostView.syncDrawableSize()
        session.updateTargetDrawableSize(session.hostView.metalLayer.drawableSize)
        if !session.isViewportAlignedWithDrawable {
          scheduleViewportReconfig(for: session)
        }
        if !hasPrimedPipBuffer {
          primePipDisplayLayerIfNeeded()
        }
      }
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
    case .videoDimensionsChanged(let width, let height):
      let aspectChanged =
        abs(
          Double(width) / Double(max(1, height))
            - Double(videoDimensions.width) / Double(max(1, videoDimensions.height))) > 0.02
      videoDimensions = (width, height)
      if !hasPrimedPipBuffer || aspectChanged {
        primePipDisplayLayerIfNeeded()
      }
    case .osdDimensionsChanged:
      if !session.isAudio, !isPipActive {
        session.hostView.syncDrawableSize()
        session.updateTargetDrawableSize(session.hostView.metalLayer.drawableSize)
        if session.isViewportAlignedWithDrawable {
          session.restoreFullFrameViewportIfNeeded()
        } else if viewportSettleTask == nil {
          scheduleViewportReconfig(for: session)
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
}

private final class WeakEngineEventRelay: @unchecked Sendable {
  weak var engine: MpvPlaybackEngine?
  weak var boundSession: MpvSession?
  init(_ engine: MpvPlaybackEngine) {
    self.engine = engine
  }
}
