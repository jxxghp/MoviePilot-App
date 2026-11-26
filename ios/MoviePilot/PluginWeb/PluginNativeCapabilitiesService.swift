@preconcurrency import AVFoundation
import CoreMedia
import CryptoKit
import Foundation
import LocalAuthentication
import MediaPlayer
@preconcurrency import MediaToolbox
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import Network
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// Vue 联邦插件移动原生能力服务（iOS）：
/// 统一承接录音、内联音频播放、全屏原生播放器、相册/相机/文件选取、保存媒体、系统分享、
/// 剪贴板读写、屏幕常亮、本地通知、扫码、生物认证与设备/权限查询。
/// 严格执行安全与生命周期边界：
/// - WebView 内零令牌：鉴权 `apiPath` 与本地存储流票据完全在原生侧携带凭据请求；
/// - 响应体积上限：`base64` 返回严格限制在 15 MiB 以内，临时录音/分享文件即时清理；
/// - 生命周期兜底：`cleanup()` 在插件卸载、WebView 归还或会话切换时停止录音、播放并恢复屏幕常亮。
@MainActor
final class PluginNativeCapabilitiesService: NSObject {
  static let maxBase64Bytes = 15 * 1024 * 1024
  private static let maxWidgetPayloadBytes = 32 * 1024
  private static let maxWidgetLayoutDepth = 5
  private static let maxWidgetLayoutNodes = 40

  /// 最近一次活跃的原生能力服务实例弱引用。
  static weak var latestActiveService: PluginNativeCapabilitiesService?
  private static var pendingPluginID: String = ""
  private static var pendingPluginName: String = ""

  /// 当前挂载插件的物理标识。
  var activePluginID: String = ""
  /// 当前挂载插件的显示名称。
  var activePluginName: String = ""

  /// 登记最新挂载的插件标识与名称，供懒加载的能力服务实例初始化继承。
  static func registerActivePlugin(id: String, name: String) {
    pendingPluginID = id
    pendingPluginName = name
    latestActiveService?.activePluginID = id
    latestActiveService?.activePluginName = name
  }

  private let sendResponse:
    (
      _ requestId: String,
      _ ok: Bool,
      _ data: [String: Any]?,
      _ error: (code: String, status: Int, message: String)?
    ) -> Void
  private let sendDeviceEvent: (_ event: String, _ data: [String: Any]) -> Void
  private let sessionContextProvider: () -> PluginShellSchemeHandler.SessionContext?
  private let nativeSessionProvider: () -> NativeSession?
  private let urlSession: URLSession

  // MARK: - Recording State
  private var audioRecorder: AVAudioRecorder?
  private var recordingID: String?
  private var recordingURL: URL?
  private var recordingFormat: String = "m4a"
  private var recordingMimeType: String = "audio/mp4"
  private var recordingStartedAt: Date?
  private var recordingPausedAccumulatedMs: Double = 0
  private var recordingPausedAt: Date?
  private var recordingMaxDurationSec: Double = 300
  private var recordingMeteringEnabled: Bool = true
  private var recordingTimer: Timer?
  private var isRecordingPaused: Bool = false

  // MARK: - Inline Audio Playback & Real-Time Spectrum State (#79)
  private var avAudioPlayer: AVAudioPlayer?
  private var avPlayer: AVPlayer?
  private var avPlayerEndObserver: NSObjectProtocol?
  private var playbackID: String?
  private var playbackLoop: Bool = false
  private var playbackRate: Float = 1.0
  private var playbackVolume: Float = 1.0
  private var playbackState: String = "idle"
  private var playbackProgressTimer: Timer?
  private var spectrumEnabled: Bool = false
  private var spectrumBands: Int = 64
  private var spectrumIntervalMs: Int = 50
  private var spectrumTimer: Timer?
  private var activeSpectrumTapBuffer: PluginAudioSpectrumBuffer?
  private var meteringPhase: Double = 0

  // MARK: - System Volume State (#82)
  private var systemVolumeObservation: NSKeyValueObservation?
  private var offscreenVolumeView: MPVolumeView?
  private var lastObservedSystemVolume: Float = -1

  // MARK: - Status Bar / Lock Screen Now Playing State (#56 / #77 / #82)
  private struct NowPlayingLyricLine {
    let timeMs: Int
    let text: String
  }
  private struct NowPlayingCustomAction {
    let id: String
    let title: String
    let active: Bool
  }
  private var nowPlayingActive: Bool = false
  private var nowPlayingTitle: String = ""
  private var nowPlayingArtist: String = ""
  private var nowPlayingAlbum: String = ""
  private var nowPlayingCanNext: Bool = false
  private var nowPlayingCanPrevious: Bool = false
  private var nowPlayingDurationMs: Int = 0
  private var nowPlayingPositionMs: Int = 0
  private var nowPlayingLyrics: String = ""
  private var nowPlayingLyricLines: [NowPlayingLyricLine] = []
  private var lastDisplayedLyricLine: String = ""
  private var nowPlayingHasLike: Bool = false
  private var nowPlayingLiked: Bool = false
  private var nowPlayingCustomActions: [NowPlayingCustomAction] = []
  private var nowPlayingArtwork: MPMediaItemArtwork?
  private var nowPlayingArtworkURL: String = ""
  private var nowPlayingWidgetArtworkFileName: String = ""
  private var nowPlayingArtworkTask: Task<Void, Never>?
  private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []

  // MARK: - System & UI Picker State
  private var keepAwakeEnabled: Bool = false
  private var pendingPickerRequestId: String?
  private var pendingPickerIncludeBase64: Bool = true
  private var activeAsyncTasks: Set<UUID> = []
  private var runningTasks: [UUID: Task<Void, Never>] = [:]
  private let pathMonitor = NWPathMonitor()
  private var currentNetworkType: String = "unknown"

  init(
    urlSession: URLSession,
    sendResponse:
      @escaping (
        _ requestId: String,
        _ ok: Bool,
        _ data: [String: Any]?,
        _ error: (code: String, status: Int, message: String)?
      ) -> Void,
    sendDeviceEvent: @escaping (_ event: String, _ data: [String: Any]) -> Void,
    sessionContextProvider: @escaping () -> PluginShellSchemeHandler.SessionContext?,
    nativeSessionProvider: @escaping () -> NativeSession?
  ) {
    self.urlSession = urlSession
    self.sendResponse = sendResponse
    self.sendDeviceEvent = sendDeviceEvent
    self.sessionContextProvider = sessionContextProvider
    self.nativeSessionProvider = nativeSessionProvider
    self.activePluginID = Self.pendingPluginID
    self.activePluginName = Self.pendingPluginName
    super.init()
    Self.latestActiveService = self
    DarwinWidgetCommandRouter.shared.register(self)
    startNetworkMonitor()
  }

  deinit {
    pathMonitor.cancel()
  }

  private func startNetworkMonitor() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let kind: String
      if path.status != .satisfied {
        kind = "none"
      } else if path.usesInterfaceType(.wifi) {
        kind = "wifi"
      } else if path.usesInterfaceType(.cellular) {
        kind = "cellular"
      } else if path.usesInterfaceType(.wiredEthernet) {
        kind = "ethernet"
      } else {
        kind = "other"
      }
      Task { @MainActor [weak self] in
        self?.currentNetworkType = kind
      }
    }
    pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
  }

  /// 释放所有运行中的原生能力资源（录音、内联播放、频谱采集、音量监听、常亮锁与在途异步任务）。
  func cleanup() {
    cancelActiveRecording(emitEvent: false)
    stopInlinePlayback(emitEvent: false)
    clearNowPlayingMetadata()
    stopSystemVolumeMonitoring()
    DarwinWidgetCommandRouter.shared.unregister(self)
    if Self.latestActiveService === self {
      Self.latestActiveService = nil
    }
    activePluginID = ""
    activePluginName = ""
    if keepAwakeEnabled {
      keepAwakeEnabled = false
      UIApplication.shared.isIdleTimerDisabled = false
    }
    for task in runningTasks.values {
      task.cancel()
    }
    runningTasks.removeAll()
    activeAsyncTasks.removeAll()
    if let pendingId = pendingPickerRequestId {
      pendingPickerRequestId = nil
      sendResponse(pendingId, true, ["cancelled": true, "files": []], nil)
    }
  }

  /// 路由原生能力消息；若消息类型属于本服务则返回 `true`。
  func handle(type: String, requestId: String, payload: [String: Any]) -> Bool {
    Self.latestActiveService = self
    DarwinWidgetCommandRouter.shared.register(self)
    if type == "plugin.context.sync" {
      if let pid = (payload["pluginId"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
        !pid.isEmpty
      {
        activePluginID = pid
      }
      if let pname = (payload["pluginName"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
        !pname.isEmpty
      {
        activePluginName = pname
      }
      DarwinWidgetCommandRouter.shared.consumePendingCommandIfNeeded()
      return true
    }
    ensureSystemVolumeMonitoring()
    switch type {
    case "device.capabilities":
      handleCapabilities(requestId: requestId)
      return true
    case "device.info":
      handleDeviceInfo(requestId: requestId)
      return true
    case "device.permission":
      handlePermission(requestId: requestId, payload: payload)
      return true
    case "device.clipboard.read":
      let text = UIPasteboard.general.string ?? ""
      sendSuccess(requestId: requestId, data: ["text": text])
      return true
    case "device.share":
      handleShare(requestId: requestId, payload: payload)
      return true
    case "device.keepAwake":
      let enabled = (payload["enabled"] as? Bool) ?? false
      keepAwakeEnabled = enabled
      UIApplication.shared.isIdleTimerDisabled = enabled
      sendSuccess(requestId: requestId, data: ["enabled": enabled])
      return true
    case "device.notify":
      handleNotify(requestId: requestId, payload: payload)
      return true
    case "device.pickMedia":
      handlePickMedia(requestId: requestId, payload: payload)
      return true
    case "device.pickFile":
      handlePickFile(requestId: requestId, payload: payload)
      return true
    case "device.saveMedia":
      handleSaveMedia(requestId: requestId, payload: payload)
      return true
    case "device.scanCode":
      handleScanCode(requestId: requestId, payload: payload)
      return true
    case "device.authenticate":
      handleAuthenticate(requestId: requestId, payload: payload)
      return true
    case "audio.record.start":
      handleRecordStart(requestId: requestId, payload: payload)
      return true
    case "audio.record.pause":
      handleRecordPause(requestId: requestId)
      return true
    case "audio.record.resume":
      handleRecordResume(requestId: requestId)
      return true
    case "audio.record.stop":
      handleRecordStop(requestId: requestId, payload: payload)
      return true
    case "audio.record.cancel":
      cancelActiveRecording(emitEvent: true)
      sendSuccess(requestId: requestId, data: ["cancelled": true])
      return true
    case "audio.record.status":
      sendSuccess(requestId: requestId, data: currentRecordStatusDict())
      return true
    case "audio.play":
      handleAudioPlay(requestId: requestId, payload: payload)
      return true
    case "audio.pause":
      handleAudioPause(requestId: requestId)
      return true
    case "audio.resume":
      handleAudioResume(requestId: requestId)
      return true
    case "audio.stop":
      stopInlinePlayback(emitEvent: true)
      sendSuccess(requestId: requestId, data: ["stopped": true])
      return true
    case "audio.seek":
      handleAudioSeek(requestId: requestId, payload: payload)
      return true
    case "audio.setRate":
      handleAudioSetRate(requestId: requestId, payload: payload)
      return true
    case "audio.setVolume":
      handleAudioSetVolume(requestId: requestId, payload: payload)
      return true
    case "audio.getSystemVolume":
      handleGetSystemVolume(requestId: requestId)
      return true
    case "audio.setSystemVolume":
      handleSetSystemVolume(requestId: requestId, payload: payload)
      return true
    case "audio.setSpectrum":
      handleAudioSetSpectrum(requestId: requestId, payload: payload)
      return true
    case "audio.status":
      sendSuccess(requestId: requestId, data: currentPlaybackStatusDict())
      return true
    case "audio.setNowPlaying":
      handleAudioSetNowPlaying(requestId: requestId, payload: payload)
      return true
    case "audio.clearNowPlaying":
      clearNowPlayingMetadata()
      sendSuccess(requestId: requestId, data: ["cleared": true])
      return true
    case "media.playNative":
      handlePlayNativeMedia(requestId: requestId, payload: payload)
      return true
    case "widget.update":
      handleWidgetUpdate(requestId: requestId, payload: payload)
      return true
    case "widget.remove":
      handleWidgetRemove(requestId: requestId, payload: payload)
      return true
    case "widget.list":
      handleWidgetList(requestId: requestId)
      return true
    default:
      return false
    }
  }

  // MARK: - Device Info & Capabilities

  private func handleCapabilities(requestId: String) {
    var caps: [String] = [
      "audio.record",
      "audio.play",
      "audio.nowPlaying",
      "native.audio.nowPlaying",
      "native.audio.lyrics",
      "native.audio.customActions",
      "native.audio.systemVolume",
      "native.audio.spectrum",
      "native.widget",
      "media.playNative",
      "device.info",
      "device.permission",
      "device.haptic",
      "device.clipboard",
      "device.clipboard.read",
      "device.share",
      "device.keepAwake",
      "device.notify",
      "device.pickMedia",
      "device.pickFile",
      "device.saveMedia",
      "device.authenticate",
    ]
    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      caps.append("device.camera")
      caps.append("device.scanCode")
    }
    let isDark = UITraitCollection.current.userInterfaceStyle == .dark
    let appVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    sendSuccess(
      requestId: requestId,
      data: [
        "platform": "ios",
        "osVersion": UIDevice.current.systemVersion,
        "appVersion": appVersion,
        "deviceModel": UIDevice.current.model,
        "networkType": currentNetworkType,
        "isDark": isDark,
        "capabilities": caps,
      ]
    )
  }

  private func handleDeviceInfo(requestId: String) {
    let bounds = UIScreen.main.bounds
    let scale = UIScreen.main.scale
    let isDark = UITraitCollection.current.userInterfaceStyle == .dark
    let appVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    sendSuccess(
      requestId: requestId,
      data: [
        "platform": "ios",
        "osVersion": UIDevice.current.systemVersion,
        "appVersion": appVersion,
        "deviceModel": UIDevice.current.model,
        "networkType": currentNetworkType,
        "locale": AppLanguage.current.rawValue,
        "isDark": isDark,
        "screenWidth": Int(bounds.width),
        "screenHeight": Int(bounds.height),
        "pixelRatio": Double(scale),
      ]
    )
  }

  // MARK: - Permissions

  private func handlePermission(requestId: String, payload: [String: Any]) {
    let perm = (payload["permission"] as? String ?? "").lowercased()
    if perm == "overlay" {
      sendSuccess(requestId: requestId, data: ["permission": "overlay", "status": "unsupported"])
      return
    }
    let shouldRequest = (payload["request"] as? Bool) ?? false

    runManagedTask { [weak self] in
      guard let self else { return }
      let status: String
      switch perm {
      case "microphone":
        if shouldRequest {
          let granted = await self.requestMicrophonePermission()
          status = granted ? "granted" : "denied"
        } else {
          status = self.currentMicrophonePermissionStatus()
        }
      case "camera":
        if shouldRequest {
          let granted = await AVCaptureDevice.requestAccess(for: .video)
          status = granted ? "granted" : "denied"
        } else {
          status = Self.mapAVAuthStatus(AVCaptureDevice.authorizationStatus(for: .video))
        }
      case "photos":
        if shouldRequest {
          let res = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
          status = Self.mapPhotoStatus(res)
        } else {
          status = Self.mapPhotoStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        }
      case "notifications":
        if shouldRequest {
          let granted =
            (try? await UNUserNotificationCenter.current().requestAuthorization(
              options: [.alert, .sound, .badge]
            )) ?? false
          status = granted ? "granted" : "denied"
        } else {
          let settings = await UNUserNotificationCenter.current().notificationSettings()
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral: status = "granted"
          case .denied: status = "denied"
          case .notDetermined: status = "undetermined"
          @unknown default: status = "undetermined"
          }
        }
      default:
        self.sendError(
          requestId: requestId, code: "INVALID_PERMISSION", status: 400,
          message: "Unsupported permission: \(perm)")
        return
      }
      self.sendSuccess(
        requestId: requestId,
        data: ["permission": perm, "status": status]
      )
    }
  }

  private func currentMicrophonePermissionStatus() -> String {
    if #available(iOS 17.0, *) {
      switch AVAudioApplication.shared.recordPermission {
      case .granted: return "granted"
      case .denied: return "denied"
      case .undetermined: return "undetermined"
      @unknown default: return "undetermined"
      }
    } else {
      switch AVAudioSession.sharedInstance().recordPermission {
      case .granted: return "granted"
      case .denied: return "denied"
      case .undetermined: return "undetermined"
      @unknown default: return "undetermined"
      }
    }
  }

  private func requestMicrophonePermission() async -> Bool {
    if #available(iOS 17.0, *) {
      return await AVAudioApplication.requestRecordPermission()
    } else {
      return await withCheckedContinuation { cont in
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
          cont.resume(returning: ok)
        }
      }
    }
  }

  private static func mapAVAuthStatus(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "undetermined"
    @unknown default: return "undetermined"
    }
  }

  private static func mapPhotoStatus(_ status: PHAuthorizationStatus) -> String {
    switch status {
    case .authorized, .limited: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "undetermined"
    @unknown default: return "undetermined"
    }
  }

  // MARK: - Audio Recording (`audio.record.*`)

  private func handleRecordStart(requestId: String, payload: [String: Any]) {
    let rawFormat = (payload["format"] as? String ?? "m4a").lowercased()
    let format = rawFormat == "wav" ? "wav" : "m4a"
    let sampleRate = min(max((payload["sampleRate"] as? Double) ?? 24_000, 8_000), 48_000)
    let channels = min(max((payload["channels"] as? Int) ?? 1, 1), 2)
    let bitRate = min(max((payload["bitRate"] as? Int) ?? 96_000, 16_000), 256_000)
    let maxDuration = min(max((payload["maxDurationSec"] as? Double) ?? 300, 1), 1_800)
    let metering = (payload["metering"] as? Bool) ?? true

    runManagedTask { [weak self] in
      guard let self else { return }
      let granted = await self.requestMicrophonePermission()
      guard granted else {
        self.sendError(
          requestId: requestId, code: "PERMISSION_DENIED", status: 403,
          message: "未获得麦克风权限，请在系统设置中允许访问麦克风")
        return
      }

      self.cancelActiveRecording(emitEvent: false)
      self.stopInlinePlayback(emitEvent: false)

      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
          .playAndRecord,
          mode: .default,
          options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
        try session.setActive(true)

        let recID = "rec_\(UUID().uuidString.prefix(12))"
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
          .appendingPathComponent("mp_plugin_recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = format == "wav" ? "wav" : "m4a"
        let mime = format == "wav" ? "audio/wav" : "audio/mp4"
        let fileURL = dir.appendingPathComponent("\(recID).\(ext)")

        var settings: [String: Any] = [
          AVSampleRateKey: sampleRate,
          AVNumberOfChannelsKey: channels,
        ]
        if format == "wav" {
          settings[AVFormatIDKey] = Int(kAudioFormatLinearPCM)
          settings[AVLinearPCMBitDepthKey] = 16
          settings[AVLinearPCMIsBigEndianKey] = false
          settings[AVLinearPCMIsFloatKey] = false
        } else {
          settings[AVFormatIDKey] = Int(kAudioFormatMPEG4AAC)
          settings[AVEncoderBitRateKey] = bitRate
          settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        }

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = metering
        guard recorder.prepareToRecord(), recorder.record() else {
          throw NSError(
            domain: "PluginAudioRecorder", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "无法启动原生音频录制器"])
        }

        let now = Date()
        self.audioRecorder = recorder
        self.recordingID = recID
        self.recordingURL = fileURL
        self.recordingFormat = format
        self.recordingMimeType = mime
        self.recordingStartedAt = now
        self.recordingPausedAccumulatedMs = 0
        self.recordingPausedAt = nil
        self.recordingMaxDurationSec = maxDuration
        self.recordingMeteringEnabled = metering
        self.isRecordingPaused = false
        self.startRecordingTimer()

        self.sendDeviceEvent(
          "audio.record.state",
          [
            "recordingId": recID,
            "state": "recording",
            "durationMs": 0,
          ]
        )
        self.sendSuccess(
          requestId: requestId,
          data: [
            "recordingId": recID,
            "mimeType": mime,
            "format": format,
            "startedAt": Int(now.timeIntervalSince1970 * 1000),
          ]
        )
      } catch {
        self.cancelActiveRecording(emitEvent: false)
        self.sendError(
          requestId: requestId, code: "RECORD_START_FAILED", status: 500,
          message: error.localizedDescription)
      }
    }
  }

  private func handleRecordPause(requestId: String) {
    guard let recorder = audioRecorder, let recID = recordingID else {
      sendError(requestId: requestId, code: "NOT_RECORDING", status: 400, message: "当前未在录音")
      return
    }
    if !isRecordingPaused {
      recorder.pause()
      isRecordingPaused = true
      recordingPausedAt = Date()
    }
    let dur = currentRecordingDurationMs()
    sendDeviceEvent(
      "audio.record.state",
      ["recordingId": recID, "state": "paused", "durationMs": dur]
    )
    sendSuccess(
      requestId: requestId,
      data: ["recordingId": recID, "state": "paused", "durationMs": dur]
    )
  }

  private func handleRecordResume(requestId: String) {
    guard let recorder = audioRecorder, let recID = recordingID else {
      sendError(requestId: requestId, code: "NOT_RECORDING", status: 400, message: "当前未在录音")
      return
    }
    if isRecordingPaused {
      if let pausedAt = recordingPausedAt {
        recordingPausedAccumulatedMs += Date().timeIntervalSince(pausedAt) * 1000
      }
      recordingPausedAt = nil
      isRecordingPaused = false
      recorder.record()
    }
    let dur = currentRecordingDurationMs()
    sendDeviceEvent(
      "audio.record.state",
      ["recordingId": recID, "state": "recording", "durationMs": dur]
    )
    sendSuccess(
      requestId: requestId,
      data: ["recordingId": recID, "state": "recording", "durationMs": dur]
    )
  }

  private func handleRecordStop(requestId: String, payload: [String: Any]) {
    guard let recorder = audioRecorder, let recID = recordingID, let fileURL = recordingURL else {
      sendError(requestId: requestId, code: "NOT_RECORDING", status: 400, message: "当前没有进行中的录音")
      return
    }
    let includeBase64 = (payload["includeBase64"] as? Bool) ?? true
    let durationMs = currentRecordingDurationMs()
    let mime = recordingMimeType
    let fileName = fileURL.lastPathComponent

    recordingTimer?.invalidate()
    recordingTimer = nil
    recorder.stop()
    audioRecorder = nil
    recordingID = nil
    recordingURL = nil
    recordingStartedAt = nil
    recordingPausedAt = nil
    recordingPausedAccumulatedMs = 0
    isRecordingPaused = false

    let rawData = (try? Data(contentsOf: fileURL)) ?? Data()
    try? FileManager.default.removeItem(at: fileURL)

    var result: [String: Any] = [
      "recordingId": recID,
      "durationMs": durationMs,
      "sizeBytes": rawData.count,
      "mimeType": mime,
      "fileName": fileName,
      "truncated": false,
    ]
    if includeBase64 {
      if rawData.count <= Self.maxBase64Bytes {
        result["base64"] = rawData.base64EncodedString()
      } else {
        result["truncated"] = true
      }
    }

    sendDeviceEvent(
      "audio.record.state",
      ["recordingId": recID, "state": "stopped", "durationMs": durationMs]
    )
    sendSuccess(requestId: requestId, data: result)
  }

  private func cancelActiveRecording(emitEvent: Bool) {
    let recID = recordingID
    recordingTimer?.invalidate()
    recordingTimer = nil
    audioRecorder?.stop()
    audioRecorder = nil
    if let url = recordingURL {
      try? FileManager.default.removeItem(at: url)
    }
    recordingURL = nil
    recordingID = nil
    recordingStartedAt = nil
    recordingPausedAt = nil
    recordingPausedAccumulatedMs = 0
    isRecordingPaused = false
    if emitEvent, let recID {
      sendDeviceEvent(
        "audio.record.state",
        ["recordingId": recID, "state": "cancelled", "durationMs": 0]
      )
    }
  }

  private func startRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, let recorder = self.audioRecorder, let recID = self.recordingID else {
          return
        }
        guard !self.isRecordingPaused else { return }
        let durMs = self.currentRecordingDurationMs()
        if self.recordingMeteringEnabled {
          recorder.updateMeters()
          let db = Double(recorder.averagePower(forChannel: 0))
          let normalized = max(0.0, min(1.0, (db + 60.0) / 60.0))
          self.sendDeviceEvent(
            "audio.record.level",
            [
              "recordingId": recID,
              "durationMs": durMs,
              "meteringDb": db,
              "normalizedLevel": normalized,
            ]
          )
        }
        if Double(durMs) >= self.recordingMaxDurationSec * 1000.0 {
          recorder.pause()
          self.isRecordingPaused = true
          self.recordingPausedAt = Date()
          self.sendDeviceEvent(
            "audio.record.state",
            [
              "recordingId": recID,
              "state": "paused",
              "durationMs": durMs,
              "message": "已达最大录音时长上限",
            ]
          )
        }
      }
    }
  }

  private func currentRecordingDurationMs() -> Int {
    if let recorder = audioRecorder, recorder.currentTime > 0 {
      return Int(recorder.currentTime * 1000)
    }
    guard let started = recordingStartedAt else { return 0 }
    let endRef = recordingPausedAt ?? Date()
    let elapsed = endRef.timeIntervalSince(started) * 1000 - recordingPausedAccumulatedMs
    return max(0, Int(elapsed))
  }

  private func currentRecordStatusDict() -> [String: Any] {
    guard let recorder = audioRecorder, let recID = recordingID else {
      return ["state": "idle", "durationMs": 0]
    }
    var dict: [String: Any] = [
      "state": isRecordingPaused ? "paused" : "recording",
      "recordingId": recID,
      "durationMs": currentRecordingDurationMs(),
    ]
    if recordingMeteringEnabled {
      recorder.updateMeters()
      let db = Double(recorder.averagePower(forChannel: 0))
      dict["meteringDb"] = db
      dict["normalizedLevel"] = max(0.0, min(1.0, (db + 60.0) / 60.0))
    }
    return dict
  }

  // MARK: - Inline Audio Playback (`audio.*`)

  private func handleAudioPlay(requestId: String, payload: [String: Any]) {
    let loop = (payload["loop"] as? Bool) ?? false
    let volume = Float(min(max((payload["volume"] as? Double) ?? 1.0, 0.0), 1.0))
    let rate = Float(min(max((payload["rate"] as? Double) ?? 1.0, 0.5), 2.0))
    let startPosMs = max((payload["startPositionMs"] as? Double) ?? 0, 0)
    let specDict = payload["spectrum"] as? [String: Any]
    let reqSpecEnabled = (specDict?["enabled"] as? Bool) ?? false
    let reqSpecBands = min(max((specDict?["bands"] as? NSNumber)?.intValue ?? 64, 16), 256)
    let reqSpecInterval = min(max((specDict?["intervalMs"] as? NSNumber)?.intValue ?? 50, 30), 250)

    stopInlinePlayback(emitEvent: false)
    let playID = "play_\(UUID().uuidString.prefix(12))"
    playbackID = playID
    playbackLoop = loop
    playbackVolume = volume
    playbackRate = rate
    spectrumEnabled = reqSpecEnabled
    spectrumBands = reqSpecBands
    spectrumIntervalMs = reqSpecInterval

    // 1. Base64 内联音频（录音回放 / TTS / 提示音）
    if let rawBase64 = payload["base64"] as? String, !rawBase64.isEmpty {
      let cleanBase64 = Self.stripDataURIPrefix(rawBase64)
      guard let data = Data(base64Encoded: cleanBase64), !data.isEmpty else {
        sendError(
          requestId: requestId, code: "INVALID_AUDIO", status: 400, message: "无效的 Base64 音频数据")
        return
      }
      do {
        try configurePlaybackAudioSession()
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.enableRate = true
        player.isMeteringEnabled = reqSpecEnabled
        player.rate = rate
        player.volume = volume
        player.numberOfLoops = loop ? -1 : 0
        if startPosMs > 0 {
          player.currentTime = startPosMs / 1000.0
        }
        guard player.prepareToPlay(), player.play() else {
          throw NSError(
            domain: "PluginAudioPlayer", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "无法启动原生音频播放"])
        }
        avAudioPlayer = player
        playbackState = "playing"
        startPlaybackProgressTimer()
        let specActive = syncSpectrumTimerState()
        let durationMs = Int(player.duration * 1000)
        emitPlaybackState()
        sendSuccess(
          requestId: requestId,
          data: [
            "playbackId": playID,
            "state": "playing",
            "durationMs": durationMs,
            "spectrumActive": specActive,
          ]
        )
      } catch {
        stopInlinePlayback(emitEvent: false)
        sendError(
          requestId: requestId, code: "AUDIO_PLAY_FAILED", status: 500,
          message: error.localizedDescription)
      }
      return
    }

    let showInStatusBar = (payload["showInStatusBar"] as? Bool) ?? true
    let playTitle = (payload["title"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let playArtist = (payload["artist"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let playAlbum = (payload["album"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let playArtworkUrl = (payload["artworkUrl"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let maybeApplyNowPlaying = { [weak self] in
      guard let self, showInStatusBar, !playTitle.isEmpty else { return }
      self.applyNowPlayingMetadata(
        title: playTitle,
        artist: playArtist,
        album: playAlbum,
        artworkUrl: playArtworkUrl,
        durationMs: nil,
        positionMs: Int(startPosMs),
        isPlaying: true,
        rate: rate
      )
    }

    // 2. 存储文件（优先签发本地/远端流票据边加载边播放）
    if let storage = payload["storage"] as? String, !storage.isEmpty,
      let path = payload["path"] as? String, !path.isEmpty
    {
      runManagedTask { [weak self] in
        guard let self else { return }
        guard let context = self.sessionContextProvider() else {
          self.sendError(requestId: requestId, code: "NO_SESSION", status: 401, message: "当前无活跃会话")
          return
        }
        do {
          let (streamURL, headers) = try await self.resolveStorageStreamURL(
            context: context, storage: storage, path: path)
          let specActive = try await self.startAVPlayer(
            playID: playID, url: streamURL, headers: headers,
            volume: volume, rate: rate, startPosMs: startPosMs)
          maybeApplyNowPlaying()
          self.sendSuccess(
            requestId: requestId,
            data: ["playbackId": playID, "state": "playing", "spectrumActive": specActive]
          )
        } catch {
          self.stopInlinePlayback(emitEvent: false)
          self.sendError(
            requestId: requestId, code: "AUDIO_PLAY_FAILED", status: 500,
            message: error.localizedDescription)
        }
      }
      return
    }

    // 3. 受鉴权 MoviePilot API 音频流路径（如 /api/v1/...，原生代附 Bearer/Cookie）
    let resolvedRelativeURLPath: String? = {
      if let rawAPIPath = payload["apiPath"] as? String, !rawAPIPath.isEmpty {
        return rawAPIPath
      }
      if let rawURL = payload["url"] as? String,
        rawURL.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
      {
        return rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return nil
    }()
    if let rawAPIPath = resolvedRelativeURLPath {
      guard let normalized = try? PluginRemoteRuntime.validateAPIPath(rawAPIPath) else {
        sendError(requestId: requestId, code: "FORBIDDEN_PATH", status: 403, message: "非法 API 路径")
        return
      }
      guard let context = sessionContextProvider(),
        let targetURL = buildSameOriginURL(address: context.address, apiPath: normalized)
      else {
        sendError(requestId: requestId, code: "NO_SESSION", status: 401, message: "当前无活跃会话")
        return
      }
      var headers: [String: String] = [
        "Authorization": "Bearer \(context.accessToken)",
        "X-MoviePilot-Locale": context.locale,
      ]
      if let cookie = context.resourceCookie {
        headers["Cookie"] = "\(cookie.name)=\(cookie.value)"
      }
      runManagedTask { [weak self] in
        guard let self else { return }
        do {
          let specActive = try await self.startAVPlayer(
            playID: playID, url: targetURL, headers: headers,
            volume: volume, rate: rate, startPosMs: startPosMs)
          maybeApplyNowPlaying()
          self.sendSuccess(
            requestId: requestId,
            data: ["playbackId": playID, "state": "playing", "spectrumActive": specActive]
          )
        } catch {
          self.stopInlinePlayback(emitEvent: false)
          self.sendError(
            requestId: requestId, code: "AUDIO_PLAY_FAILED", status: 500,
            message: error.localizedDescription)
        }
      }
      return
    }

    // 4. 公开 HTTP(S) 音频直链（流式边播）
    if let rawURL = payload["url"] as? String,
      let url = URL(string: rawURL),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    {
      runManagedTask { [weak self] in
        guard let self else { return }
        do {
          let specActive = try await self.startAVPlayer(
            playID: playID, url: url, headers: nil,
            volume: volume, rate: rate, startPosMs: startPosMs)
          maybeApplyNowPlaying()
          self.sendSuccess(
            requestId: requestId,
            data: ["playbackId": playID, "state": "playing", "spectrumActive": specActive]
          )
        } catch {
          self.stopInlinePlayback(emitEvent: false)
          self.sendError(
            requestId: requestId, code: "AUDIO_PLAY_FAILED", status: 500,
            message: error.localizedDescription)
        }
      }
      return
    }

    sendError(
      requestId: requestId, code: "INVALID_AUDIO_SOURCE", status: 400,
      message: "请提供 url、base64、apiPath 或 storage+path 音频源")
  }

  private func configurePlaybackAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default, options: [])
    try session.setActive(true)
  }

  private func startAVPlayer(
    playID: String,
    url: URL,
    headers: [String: String]?,
    volume: Float,
    rate: Float,
    startPosMs: Double
  ) async throws -> Bool {
    try configurePlaybackAudioSession()
    let asset: AVURLAsset
    if let headers, !headers.isEmpty {
      asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    } else {
      asset = AVURLAsset(url: url)
    }
    let item = AVPlayerItem(asset: asset)
    item.preferredForwardBufferDuration = 3.0

    var specActive = false
    if spectrumEnabled {
      specActive = await attachSpectrumTapIfPossible(to: item, asset: asset, url: url)
    }

    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = false
    player.volume = volume
    if startPosMs > 0 {
      await player.seek(to: CMTime(seconds: startPosMs / 1000.0, preferredTimescale: 1000))
    }
    player.playImmediately(atRate: rate)

    avPlayer = player
    playbackID = playID
    playbackState = "playing"
    if specActive {
      _ = syncSpectrumTimerState()
    }
    avPlayerEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.avPlayer === player else { return }
        if self.playbackLoop {
          player.seek(to: .zero)
          player.playImmediately(atRate: self.playbackRate)
        } else {
          let dur = self.currentPlaybackDurationMs()
          self.playbackState = "ended"
          self.playbackProgressTimer?.invalidate()
          self.playbackProgressTimer = nil
          self.stopSpectrumTimerOnly()
          self.sendDeviceEvent(
            "audio.play.ended",
            ["playbackId": self.playbackID ?? "", "durationMs": dur]
          )
          self.emitPlaybackState()
        }
      }
    }
    startPlaybackProgressTimer()
    emitPlaybackState()
    return specActive
  }

  private func handleAudioPause(requestId: String) {
    if let p = avAudioPlayer {
      p.pause()
      playbackState = "paused"
    } else if let p = avPlayer {
      p.pause()
      playbackState = "paused"
    }
    stopSpectrumTimerOnly()
    emitPlaybackState()
    sendSuccess(requestId: requestId, data: currentPlaybackStatusDict())
  }

  private func handleAudioResume(requestId: String) {
    if let p = avAudioPlayer {
      p.rate = playbackRate
      p.play()
      playbackState = "playing"
      startPlaybackProgressTimer()
      _ = syncSpectrumTimerState()
    } else if let p = avPlayer {
      p.playImmediately(atRate: playbackRate)
      playbackState = "playing"
      startPlaybackProgressTimer()
      _ = syncSpectrumTimerState()
    }
    emitPlaybackState()
    sendSuccess(requestId: requestId, data: currentPlaybackStatusDict())
  }

  private func handleAudioSeek(requestId: String, payload: [String: Any]) {
    let posMs = max((payload["positionMs"] as? Double) ?? 0, 0)
    if let p = avAudioPlayer {
      p.currentTime = min(posMs / 1000.0, p.duration)
    } else if let p = avPlayer {
      p.seek(to: CMTime(seconds: posMs / 1000.0, preferredTimescale: 1000))
    }
    sendSuccess(requestId: requestId, data: currentPlaybackStatusDict())
  }

  private func handleAudioSetRate(requestId: String, payload: [String: Any]) {
    let rate = Float(min(max((payload["rate"] as? Double) ?? 1.0, 0.5), 2.0))
    playbackRate = rate
    if let p = avAudioPlayer {
      p.rate = rate
    } else if let p = avPlayer, playbackState == "playing" {
      p.rate = rate
    }
    sendSuccess(
      requestId: requestId,
      data: ["playbackId": playbackID ?? "", "rate": Double(rate)]
    )
  }

  private func handleAudioSetVolume(requestId: String, payload: [String: Any]) {
    let volume = Float(min(max((payload["volume"] as? Double) ?? 1.0, 0.0), 1.0))
    playbackVolume = volume
    avAudioPlayer?.volume = volume
    avPlayer?.volume = volume
    sendSuccess(
      requestId: requestId,
      data: ["playbackId": playbackID ?? "", "volume": Double(volume)]
    )
  }

  private func stopInlinePlayback(emitEvent: Bool) {
    let oldId = playbackID
    playbackProgressTimer?.invalidate()
    playbackProgressTimer = nil
    detachSpectrumProcessor()
    spectrumEnabled = false
    if let obs = avPlayerEndObserver {
      NotificationCenter.default.removeObserver(obs)
      avPlayerEndObserver = nil
    }
    avAudioPlayer?.stop()
    avAudioPlayer = nil
    avPlayer?.pause()
    avPlayer?.replaceCurrentItem(with: nil)
    avPlayer = nil
    playbackID = nil
    playbackState = "idle"
    PluginCapsuleManager.shared.syncAudioPlaybackState(
      pluginID: resolvedActivePluginID(),
      isPlaying: false
    )
    if emitEvent, let oldId {
      sendDeviceEvent(
        "audio.play.state",
        [
          "playbackId": oldId,
          "state": "stopped",
          "positionMs": 0,
          "durationMs": 0,
          "rate": Double(playbackRate),
          "volume": Double(playbackVolume),
        ]
      )
    }
  }

  // MARK: - Real-Time Audio Spectrum & Stereo Levels (`audio.setSpectrum` / `audio.play.spectrum`)

  /// 动态开启、关闭或调整实时音频频谱与左右声道电平回调。
  private func handleAudioSetSpectrum(requestId: String, payload: [String: Any]) {
    let nextEnabled = (payload["enabled"] as? Bool) ?? spectrumEnabled
    let nextBands = min(max((payload["bands"] as? NSNumber)?.intValue ?? spectrumBands, 16), 256)
    let nextInterval = min(
      max((payload["intervalMs"] as? NSNumber)?.intValue ?? spectrumIntervalMs, 30), 250)
    spectrumEnabled = nextEnabled
    spectrumBands = nextBands
    spectrumIntervalMs = nextInterval

    if !nextEnabled {
      detachSpectrumProcessor()
      sendSuccess(
        requestId: requestId,
        data: ["spectrumActive": false, "bands": spectrumBands, "intervalMs": spectrumIntervalMs]
      )
      return
    }

    if let audioPlayer = avAudioPlayer {
      audioPlayer.isMeteringEnabled = true
      let active = syncSpectrumTimerState()
      sendSuccess(
        requestId: requestId,
        data: ["spectrumActive": active, "bands": spectrumBands, "intervalMs": spectrumIntervalMs]
      )
      return
    }

    if let item = avPlayer?.currentItem, let urlAsset = item.asset as? AVURLAsset {
      if activeSpectrumTapBuffer != nil {
        let active = syncSpectrumTimerState()
        sendSuccess(
          requestId: requestId,
          data: [
            "spectrumActive": active, "bands": spectrumBands, "intervalMs": spectrumIntervalMs,
          ]
        )
        return
      }
      runManagedTask { [weak self] in
        guard let self else { return }
        let attached = await self.attachSpectrumTapIfPossible(
          to: item, asset: urlAsset, url: urlAsset.url)
        let active = attached ? self.syncSpectrumTimerState() : false
        self.sendSuccess(
          requestId: requestId,
          data: [
            "spectrumActive": active,
            "bands": self.spectrumBands,
            "intervalMs": self.spectrumIntervalMs,
          ]
        )
      }
      return
    }

    sendSuccess(
      requestId: requestId,
      data: ["spectrumActive": false, "bands": spectrumBands, "intervalMs": spectrumIntervalMs]
    )
  }

  /// 尝试在 `AVPlayerItem` 首个音频轨挂载零拷贝 `MTAudioProcessingTap`。
  private func attachSpectrumTapIfPossible(
    to item: AVPlayerItem,
    asset: AVURLAsset,
    url: URL
  ) async -> Bool {
    if url.pathExtension.lowercased() == "m3u8" {
      return false
    }
    let tracks: [AVAssetTrack]
    if let loaded = try? await asset.loadTracks(withMediaType: .audio), !loaded.isEmpty {
      tracks = loaded
    } else {
      tracks = item.tracks.compactMap(\.assetTrack).filter { $0.mediaType == .audio }
    }
    guard let audioTrack = tracks.first else {
      return false
    }
    let buffer = PluginAudioSpectrumBuffer()
    guard let tap = Self.makeAudioSpectrumTap(buffer: buffer) else {
      return false
    }
    let params = AVMutableAudioMixInputParameters(track: audioTrack)
    params.audioTapProcessor = tap
    let mix = AVMutableAudioMix()
    mix.inputParameters = [params]
    item.audioMix = mix
    activeSpectrumTapBuffer = buffer
    return true
  }

  /// 创建绑定到环形浮点样本缓冲的 `MTAudioProcessingTap`。
  private static func makeAudioSpectrumTap(
    buffer: PluginAudioSpectrumBuffer
  ) -> MTAudioProcessingTap? {
    let retainedInfo = UnsafeMutableRawPointer(Unmanaged.passRetained(buffer).toOpaque())
    var callbacks = MTAudioProcessingTapCallbacks(
      version: kMTAudioProcessingTapCallbacksVersion_0,
      clientInfo: retainedInfo,
      init: { _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
      },
      finalize: { tap in
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<PluginAudioSpectrumBuffer>.fromOpaque(storage).release()
      },
      prepare: { tap, _, processingFormat in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let target = Unmanaged<PluginAudioSpectrumBuffer>.fromOpaque(storage).takeUnretainedValue()
        target.configureFormat(processingFormat.pointee)
      },
      unprepare: { _ in },
      process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
        let status = MTAudioProcessingTapGetSourceAudio(
          tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        guard status == noErr, numberFramesOut.pointee > 0 else { return }
        let storage = MTAudioProcessingTapGetStorage(tap)
        let target = Unmanaged<PluginAudioSpectrumBuffer>.fromOpaque(storage).takeUnretainedValue()
        target.ingest(bufferList: bufferListInOut, frameCount: Int(numberFramesOut.pointee))
      }
    )
    var tapRef: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(
      kCFAllocatorDefault,
      &callbacks,
      kMTAudioProcessingTapCreationFlag_PostEffects,
      &tapRef
    )
    guard status == noErr, let tapRef else {
      Unmanaged<PluginAudioSpectrumBuffer>.fromOpaque(retainedInfo).release()
      return nil
    }
    return tapRef
  }

  /// 仅停止频谱推送定时器（用于暂停或自然播完，保留已挂载的 Tap 以便恢复播放时零延迟重启）。
  private func stopSpectrumTimerOnly() {
    spectrumTimer?.invalidate()
    spectrumTimer = nil
  }

  /// 彻底卸载频谱定时器与 `AVPlayerItem.audioMix`。
  private func detachSpectrumProcessor() {
    stopSpectrumTimerOnly()
    avPlayer?.currentItem?.audioMix = nil
    activeSpectrumTapBuffer = nil
  }

  /// 按当前 `spectrumEnabled` 与 `playbackState` 启动或停止频谱采样定时器。
  private func syncSpectrumTimerState() -> Bool {
    stopSpectrumTimerOnly()
    guard spectrumEnabled, playbackState == "playing" else {
      return false
    }
    let hasTap = activeSpectrumTapBuffer != nil
    let hasMeterPlayer = avAudioPlayer != nil
    guard hasTap || hasMeterPlayer else {
      return false
    }
    let intervalSec = Double(spectrumIntervalMs) / 1000.0
    spectrumTimer = Timer.scheduledTimer(withTimeInterval: intervalSec, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        self?.emitSpectrumFrameIfPlaying()
      }
    }
    return true
  }

  /// 计算并向前端推送单帧 `audio.play.spectrum`（FFT 频段 + 左右声道电平）。
  private func emitSpectrumFrameIfPlaying() {
    guard spectrumEnabled, playbackState == "playing", let pid = playbackID else { return }
    let posMs = currentPlaybackPositionMs()
    let bandCount = min(max(spectrumBands, 16), 256)

    if let tapBuffer = activeSpectrumTapBuffer {
      let snapshot = tapBuffer.snapshotWindow()
      let fftValues = PluginRadix2FFT.computeBands(
        samples: snapshot.samples,
        bandCount: bandCount
      )
      let left = Self.mapRMSToByte(snapshot.leftRMS)
      let right = Self.mapRMSToByte(snapshot.rightRMS)
      sendDeviceEvent(
        "audio.play.spectrum",
        [
          "playbackId": pid,
          "positionMs": posMs,
          "fft": fftValues,
          "left": left,
          "right": right,
        ]
      )
      return
    }

    if let player = avAudioPlayer {
      player.updateMeters()
      let ch0Db = Double(player.averagePower(forChannel: 0))
      let ch1Db = Double(
        player.averagePower(forChannel: player.numberOfChannels > 1 ? 1 : 0))
      let normL = max(0.0, min(1.0, (ch0Db + 55.0) / 55.0))
      let normR = max(0.0, min(1.0, (ch1Db + 55.0) / 55.0))
      let left = Int((normL * 255.0).rounded())
      let right = Int((normR * 255.0).rounded())
      let avgEnergy = (normL + normR) * 0.5
      meteringPhase += 0.35
      var bands: [Int] = []
      bands.reserveCapacity(bandCount)
      for i in 0..<bandCount {
        let ratio = Double(i) / Double(max(1, bandCount - 1))
        let curve = sin(ratio * .pi) * 0.65 + 0.35 * cos(meteringPhase + ratio * 6.0)
        let val = max(0.0, min(1.0, avgEnergy * max(0.15, curve)))
        bands.append(Int((val * 255.0).rounded()))
      }
      sendDeviceEvent(
        "audio.play.spectrum",
        [
          "playbackId": pid,
          "positionMs": posMs,
          "fft": bands,
          "left": left,
          "right": right,
        ]
      )
    }
  }

  /// 将浮点声道 RMS 映射为 `0..255` 整数电平。
  private static func mapRMSToByte(_ rms: Float) -> Int {
    let clamped = max(0.0, min(1.0, Double(rms)))
    let curved = pow(clamped, 0.6) * 280.0
    return min(255, max(0, Int(curved.rounded())))
  }

  // MARK: - System Media Volume (`audio.getSystemVolume` / `audio.setSystemVolume` / `audio.systemVolume`)

  /// 确保已激活音频会话输出音量 KVO 监听（支持响应侧边物理音量键）。
  private func ensureSystemVolumeMonitoring() {
    guard systemVolumeObservation == nil else { return }
    let session = AVAudioSession.sharedInstance()
    if audioRecorder == nil && avAudioPlayer == nil && avPlayer == nil && !nowPlayingActive {
      try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try? session.setActive(true)
    }
    lastObservedSystemVolume = session.outputVolume
    systemVolumeObservation = session.observe(\.outputVolume, options: [.new]) {
      [weak self] observedSession, change in
      let newVol = change.newValue ?? observedSession.outputVolume
      Task { @MainActor [weak self] in
        guard let self else { return }
        if abs(newVol - self.lastObservedSystemVolume) > 0.002 {
          self.lastObservedSystemVolume = newVol
          self.sendDeviceEvent(
            "audio.systemVolume",
            [
              "volume": Double(min(max(newVol, 0.0), 1.0)),
              "muted": newVol <= 0.001,
            ]
          )
        }
      }
    }
  }

  /// 释放系统音量 KVO 观察者与离屏 `MPVolumeView`。
  private func stopSystemVolumeMonitoring() {
    systemVolumeObservation?.invalidate()
    systemVolumeObservation = nil
    lastObservedSystemVolume = -1
    offscreenVolumeView?.removeFromSuperview()
    offscreenVolumeView = nil
  }

  /// 读取当前 iOS 系统媒体输出音量（`0.0...1.0`）。
  private func handleGetSystemVolume(requestId: String) {
    let vol = min(max(AVAudioSession.sharedInstance().outputVolume, 0.0), 1.0)
    sendSuccess(
      requestId: requestId,
      data: [
        "volume": Double(vol),
        "muted": vol <= 0.001,
      ]
    )
  }

  /// 通过离屏隐藏 `MPVolumeView` 内部 `UISlider` 调节系统硬件媒体音量。
  private func handleSetSystemVolume(requestId: String, payload: [String: Any]) {
    let target = Float(min(max((payload["volume"] as? NSNumber)?.doubleValue ?? 0.5, 0.0), 1.0))
    let volumeView: MPVolumeView
    if let existing = offscreenVolumeView {
      volumeView = existing
    } else {
      let created = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
      created.alpha = 0.01
      created.clipsToBounds = true
      created.isUserInteractionEnabled = false
      offscreenVolumeView = created
      volumeView = created
    }
    if volumeView.superview == nil {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let hostWindow =
        scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
      hostWindow?.addSubview(volumeView)
    }
    if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
      slider.setValue(target, animated: false)
      slider.sendActions(for: .valueChanged)
    }
    lastObservedSystemVolume = target
    sendSuccess(
      requestId: requestId,
      data: [
        "volume": Double(target),
        "muted": target <= 0.001,
      ]
    )
  }

  private func startPlaybackProgressTimer() {
    playbackProgressTimer?.invalidate()
    playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.playbackState == "playing", let pid = self.playbackID else { return }
        let posMs = self.currentPlaybackPositionMs()
        self.sendDeviceEvent(
          "audio.play.progress",
          [
            "playbackId": pid,
            "positionMs": posMs,
            "durationMs": self.currentPlaybackDurationMs(),
            "bufferedMs": self.currentPlaybackBufferedMs(),
          ]
        )
        if self.nowPlayingActive && !self.nowPlayingLyricLines.isEmpty {
          let matched = self.resolveCurrentLyricLine(positionMs: posMs)
          if matched != self.lastDisplayedLyricLine {
            self.lastDisplayedLyricLine = matched
            self.refreshNowPlayingPlaybackState(reloadWidgetTimeline: true)
          }
        }
      }
    }
  }

  private func currentPlaybackPositionMs() -> Int {
    if let p = avAudioPlayer {
      return max(0, Int(p.currentTime * 1000))
    }
    if let p = avPlayer {
      let sec = p.currentTime().seconds
      return sec.isFinite ? max(0, Int(sec * 1000)) : 0
    }
    return 0
  }

  private func currentPlaybackDurationMs() -> Int {
    if let p = avAudioPlayer {
      return max(0, Int(p.duration * 1000))
    }
    if let sec = avPlayer?.currentItem?.duration.seconds, sec.isFinite, sec > 0 {
      return Int(sec * 1000)
    }
    return 0
  }

  private func currentPlaybackBufferedMs() -> Int {
    if let p = avAudioPlayer {
      return max(0, Int(p.duration * 1000))
    }
    if let range = avPlayer?.currentItem?.loadedTimeRanges.first?.timeRangeValue {
      let end = CMTimeAdd(range.start, range.duration).seconds
      return end.isFinite ? max(0, Int(end * 1000)) : 0
    }
    return 0
  }

  private func currentPlaybackStatusDict() -> [String: Any] {
    var dict: [String: Any] = [
      "state": playbackState,
      "positionMs": currentPlaybackPositionMs(),
      "durationMs": currentPlaybackDurationMs(),
      "bufferedMs": currentPlaybackBufferedMs(),
      "rate": Double(playbackRate),
      "volume": Double(playbackVolume),
    ]
    if let pid = playbackID {
      dict["playbackId"] = pid
    }
    return dict
  }

  private func emitPlaybackState() {
    sendDeviceEvent("audio.play.state", currentPlaybackStatusDict())
    PluginCapsuleManager.shared.syncAudioPlaybackState(
      pluginID: resolvedActivePluginID(),
      isPlaying: playbackState == "playing"
    )
    refreshNowPlayingPlaybackState(reloadWidgetTimeline: true)
  }

  // MARK: - Status Bar / Control Center Now Playing (`audio.setNowPlaying` / `audio.clearNowPlaying`)

  private func handleAudioSetNowPlaying(requestId: String, payload: [String: Any]) {
    let title = (payload["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      sendError(requestId: requestId, code: "INVALID_PARAMS", status: 400, message: "title 不能为空")
      return
    }
    let artist = (payload["artist"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let album = (payload["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let artworkUrl = (payload["artworkUrl"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let durationMs = (payload["durationMs"] as? NSNumber)?.intValue
    let positionMs = (payload["positionMs"] as? NSNumber)?.intValue
    let isPlaying = (payload["isPlaying"] as? Bool) ?? (playbackState == "playing")
    let rate = (payload["rate"] as? NSNumber)?.floatValue ?? playbackRate
    let canNext = (payload["canNext"] as? Bool) ?? false
    let canPrevious = (payload["canPrevious"] as? Bool) ?? false
    let canSeek = (payload["canSeek"] as? Bool) ?? true
    let lyrics = (payload["lyrics"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let rawLines = payload["lyricLines"] as? [[String: Any]] ?? []
    let lyricLines: [NowPlayingLyricLine] = rawLines.compactMap { item in
      guard let tMs = (item["timeMs"] as? NSNumber)?.intValue else { return nil }
      let txt = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return txt.isEmpty ? nil : NowPlayingLyricLine(timeMs: max(0, tMs), text: txt)
    }.sorted { $0.timeMs < $1.timeMs }
    let liked = payload["liked"] as? Bool
    let rawCustom = payload["customActions"] as? [[String: Any]] ?? []
    let customActions: [NowPlayingCustomAction] = rawCustom.compactMap { item in
      let id = (item["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty else { return nil }
      let cTitle = (item["title"] as? String ?? item["label"] as? String ?? id)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let active = (item["active"] as? Bool) ?? false
      return NowPlayingCustomAction(id: id, title: cTitle.isEmpty ? id : cTitle, active: active)
    }

    try? configurePlaybackAudioSession()
    applyNowPlayingMetadata(
      title: title,
      artist: artist,
      album: album,
      artworkUrl: artworkUrl,
      durationMs: durationMs,
      positionMs: positionMs,
      isPlaying: isPlaying,
      rate: rate,
      canNext: canNext,
      canPrevious: canPrevious,
      canSeek: canSeek,
      lyrics: lyrics,
      lyricLines: lyricLines,
      liked: liked,
      customActions: customActions
    )
    sendSuccess(requestId: requestId, data: ["registered": true])
  }

  private func resolveCurrentLyricLine(positionMs: Int) -> String {
    if !nowPlayingLyricLines.isEmpty,
      let matched = nowPlayingLyricLines.last(where: { $0.timeMs <= positionMs })?.text,
      !matched.isEmpty
    {
      return matched
    }
    return nowPlayingLyrics
  }

  private func applyNowPlayingMetadata(
    title: String,
    artist: String,
    album: String,
    artworkUrl: String,
    durationMs: Int?,
    positionMs: Int?,
    isPlaying: Bool,
    rate: Float,
    canNext: Bool = false,
    canPrevious: Bool = false,
    canSeek: Bool = true,
    lyrics: String = "",
    lyricLines: [NowPlayingLyricLine] = [],
    liked: Bool? = nil,
    customActions: [NowPlayingCustomAction] = []
  ) {
    nowPlayingActive = true
    nowPlayingTitle = title
    nowPlayingArtist = artist
    nowPlayingAlbum = album
    nowPlayingCanNext = canNext
    nowPlayingCanPrevious = canPrevious
    if !lyrics.isEmpty || !lyricLines.isEmpty {
      nowPlayingLyrics = lyrics
      if !lyricLines.isEmpty {
        nowPlayingLyricLines = lyricLines
      }
    }
    if let liked {
      nowPlayingHasLike = true
      nowPlayingLiked = liked
    }
    if !customActions.isEmpty {
      nowPlayingCustomActions = customActions
    }

    let effectivePositionMs = positionMs ?? currentPlaybackPositionMs()
    let effectiveDurationMs = durationMs ?? currentPlaybackDurationMs()
    nowPlayingPositionMs = effectivePositionMs
    nowPlayingDurationMs = effectiveDurationMs
    lastDisplayedLyricLine = resolveCurrentLyricLine(positionMs: effectivePositionMs)

    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = title
    if !artist.isEmpty {
      info[MPMediaItemPropertyArtist] = artist
    } else {
      info.removeValue(forKey: MPMediaItemPropertyArtist)
    }
    if !lastDisplayedLyricLine.isEmpty {
      info[MPMediaItemPropertyLyrics] = lastDisplayedLyricLine
      info[MPMediaItemPropertyAlbumTitle] = lastDisplayedLyricLine
    } else if !album.isEmpty {
      info[MPMediaItemPropertyAlbumTitle] = album
    } else {
      info.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
    }
    if effectiveDurationMs > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = Double(effectiveDurationMs) / 1000.0
    }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(max(effectivePositionMs, 0)) / 1000.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
    let resolvedArtwork = resolveArtworkSource(artworkUrl)
    let resolvedArtworkKey = resolvedArtwork?.url.absoluteString ?? ""
    if let artwork = nowPlayingArtwork, !resolvedArtworkKey.isEmpty,
      resolvedArtworkKey == nowPlayingArtworkURL
    {
      info[MPMediaItemPropertyArtwork] = artwork
    } else if artworkUrl.isEmpty {
      nowPlayingArtwork = nil
      nowPlayingArtworkURL = ""
      nowPlayingWidgetArtworkFileName = ""
      info.removeValue(forKey: MPMediaItemPropertyArtwork)
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    configureRemoteCommands(canNext: canNext, canPrevious: canPrevious, canSeek: canSeek)
    PluginCapsuleManager.shared.syncAudioPlaybackState(
      pluginID: resolvedActivePluginID(),
      isPlaying: isPlaying,
      title: title,
      subtitle: artist,
      iconURL: artworkUrl
    )
    syncNowPlayingToWidgetStorage(active: true, isPlaying: isPlaying, reloadTimeline: true)

    if let resolvedArtwork, resolvedArtworkKey != nowPlayingArtworkURL {
      nowPlayingArtworkURL = resolvedArtworkKey
      nowPlayingArtworkTask?.cancel()
      nowPlayingArtworkTask = Task { [weak self] in
        guard let self else { return }
        var req = URLRequest(url: resolvedArtwork.url)
        if let ctx = self.sessionContextProvider(),
          resolvedArtwork.attachAuth || ctx.address.contains(resolvedArtwork.url)
        {
          req.setValue("Bearer \(ctx.accessToken)", forHTTPHeaderField: "Authorization")
          req.setValue(ctx.locale, forHTTPHeaderField: "X-MoviePilot-Locale")
          if let cookie = ctx.resourceCookie {
            req.setValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
          }
          CloudflareAccessCredentialRegistry.shared.applyHeaders(to: &req, for: ctx.address)
        }
        guard let (data, _) = try? await self.urlSession.data(for: req),
          let image = UIImage(data: data),
          !Task.isCancelled
        else { return }
        let savedFileName = Self.saveWidgetDownsampledJPEG(
          image: image,
          fileName: "now_playing_art.jpg"
        )
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.nowPlayingArtwork = artwork
        self.nowPlayingWidgetArtworkFileName = savedFileName
        if self.nowPlayingActive,
          var current = MPNowPlayingInfoCenter.default().nowPlayingInfo
        {
          current[MPMediaItemPropertyArtwork] = artwork
          MPNowPlayingInfoCenter.default().nowPlayingInfo = current
          let playingNow =
            ((current[MPNowPlayingInfoPropertyPlaybackRate] as? Double) ?? 0.0) > 0.01
            || self.playbackState == "playing"
          self.syncNowPlayingToWidgetStorage(
            active: true,
            isPlaying: playingNow,
            reloadTimeline: true
          )
        }
      }
    }
  }

  /// 解析插件传入的封面地址：支持相对路径（`/api/v1/plugin/...`）自动拼接实例 `serverUrl` 并附带鉴权头。
  private func resolveArtworkSource(_ rawURL: String) -> (url: URL, attachAuth: Bool)? {
    let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("/") {
      guard let ctx = sessionContextProvider(),
        let fullURL = buildSameOriginURL(address: ctx.address, apiPath: trimmed)
      else { return nil }
      return (url: fullURL, attachAuth: true)
    }
    guard let parsed = URL(string: trimmed),
      let scheme = parsed.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else { return nil }
    let isSameOrigin = sessionContextProvider()?.address.contains(parsed) ?? false
    return (url: parsed, attachAuth: isSameOrigin)
  }

  private func refreshNowPlayingPlaybackState(reloadWidgetTimeline: Bool = false) {
    guard nowPlayingActive, !nowPlayingTitle.isEmpty else { return }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    let dur = currentPlaybackDurationMs()
    if dur > 0 {
      nowPlayingDurationMs = dur
      info[MPMediaItemPropertyPlaybackDuration] = Double(dur) / 1000.0
    }
    if !lastDisplayedLyricLine.isEmpty {
      info[MPMediaItemPropertyLyrics] = lastDisplayedLyricLine
      info[MPMediaItemPropertyAlbumTitle] = lastDisplayedLyricLine
    }
    let pos = max(currentPlaybackPositionMs(), 0)
    nowPlayingPositionMs = pos
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(pos) / 1000.0
    let playing = playbackState == "playing"
    info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? Double(playbackRate) : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    syncNowPlayingToWidgetStorage(
      active: true,
      isPlaying: playing,
      reloadTimeline: reloadWidgetTimeline
    )
  }

  private func configureRemoteCommands(canNext: Bool, canPrevious: Bool, canSeek: Bool) {
    removeRemoteCommandTargets()
    let center = MPRemoteCommandCenter.shared()

    func bind(
      _ command: MPRemoteCommand, enabled: Bool,
      handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
      command.isEnabled = enabled
      if enabled {
        let token = command.addTarget(handler: handler)
        remoteCommandTargets.append((command, token))
      }
    }

    bind(center.playCommand, enabled: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.avAudioPlayer != nil || self.avPlayer != nil {
          if let p = self.avAudioPlayer {
            p.rate = self.playbackRate
            p.play()
            self.playbackState = "playing"
          } else if let p = self.avPlayer {
            p.playImmediately(atRate: self.playbackRate)
            self.playbackState = "playing"
          }
          self.startPlaybackProgressTimer()
          self.emitPlaybackState()
        }
        self.sendDeviceEvent("audio.remoteCommand", ["command": "play"])
      }
      return .success
    }
    bind(center.pauseCommand, enabled: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.avAudioPlayer != nil || self.avPlayer != nil {
          self.avAudioPlayer?.pause()
          self.avPlayer?.pause()
          self.playbackState = "paused"
          self.emitPlaybackState()
        }
        self.sendDeviceEvent("audio.remoteCommand", ["command": "pause"])
      }
      return .success
    }
    bind(center.togglePlayPauseCommand, enabled: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.playbackState == "playing" {
          self.avAudioPlayer?.pause()
          self.avPlayer?.pause()
          self.playbackState = "paused"
          self.emitPlaybackState()
        } else if self.avAudioPlayer != nil || self.avPlayer != nil {
          if let p = self.avAudioPlayer {
            p.rate = self.playbackRate
            p.play()
            self.playbackState = "playing"
          } else if let p = self.avPlayer {
            p.playImmediately(atRate: self.playbackRate)
            self.playbackState = "playing"
          }
          self.startPlaybackProgressTimer()
          self.emitPlaybackState()
        }
        self.sendDeviceEvent("audio.remoteCommand", ["command": "togglePlayPause"])
      }
      return .success
    }
    bind(center.stopCommand, enabled: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.stopInlinePlayback(emitEvent: true)
        self.sendDeviceEvent("audio.remoteCommand", ["command": "stop"])
      }
      return .success
    }
    bind(center.nextTrackCommand, enabled: canNext) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.sendDeviceEvent("audio.remoteCommand", ["command": "next"])
      }
      return .success
    }
    bind(center.previousTrackCommand, enabled: canPrevious) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.sendDeviceEvent("audio.remoteCommand", ["command": "previous"])
      }
      return .success
    }
    bind(center.changePlaybackPositionCommand, enabled: canSeek) { [weak self] event in
      guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      let targetMs = max(0, Int(posEvent.positionTime * 1000))
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let p = self.avAudioPlayer {
          p.currentTime = min(posEvent.positionTime, p.duration)
        } else if let p = self.avPlayer {
          p.seek(to: CMTime(seconds: posEvent.positionTime, preferredTimescale: 1000))
        }
        self.refreshNowPlayingPlaybackState()
        self.sendDeviceEvent("audio.remoteCommand", ["command": "seek", "positionMs": targetMs])
      }
      return .success
    }

    center.likeCommand.isActive = nowPlayingLiked
    center.likeCommand.localizedTitle = nowPlayingLiked ? "取消喜欢" : "喜欢"
    bind(center.likeCommand, enabled: nowPlayingHasLike) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.nowPlayingLiked.toggle()
        center.likeCommand.isActive = self.nowPlayingLiked
        center.likeCommand.localizedTitle = self.nowPlayingLiked ? "取消喜欢" : "喜欢"
        self.syncNowPlayingToWidgetStorage(
          active: self.nowPlayingActive,
          isPlaying: self.playbackState == "playing",
          reloadTimeline: true
        )
        self.sendDeviceEvent(
          "audio.remoteCommand",
          ["command": "toggleLike", "liked": self.nowPlayingLiked]
        )
      }
      return .success
    }

    if let firstCustom = nowPlayingCustomActions.first {
      center.bookmarkCommand.isActive = firstCustom.active
      center.bookmarkCommand.localizedTitle = firstCustom.title
      bind(center.bookmarkCommand, enabled: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.sendDeviceEvent(
            "audio.remoteCommand",
            ["command": "custom", "actionId": firstCustom.id]
          )
        }
        return .success
      }
    } else {
      center.bookmarkCommand.isEnabled = false
    }
  }

  private func removeRemoteCommandTargets() {
    for (command, token) in remoteCommandTargets {
      command.removeTarget(token)
    }
    remoteCommandTargets.removeAll()
    let center = MPRemoteCommandCenter.shared()
    center.likeCommand.isEnabled = false
    center.bookmarkCommand.isEnabled = false
  }

  private func clearNowPlayingMetadata() {
    let wasActive = nowPlayingActive
    nowPlayingArtworkTask?.cancel()
    nowPlayingArtworkTask = nil
    nowPlayingArtwork = nil
    nowPlayingArtworkURL = ""
    nowPlayingWidgetArtworkFileName = ""
    nowPlayingTitle = ""
    nowPlayingArtist = ""
    nowPlayingAlbum = ""
    nowPlayingCanNext = false
    nowPlayingCanPrevious = false
    nowPlayingDurationMs = 0
    nowPlayingPositionMs = 0
    nowPlayingLyrics = ""
    nowPlayingLyricLines = []
    lastDisplayedLyricLine = ""
    nowPlayingHasLike = false
    nowPlayingLiked = false
    nowPlayingCustomActions = []
    if nowPlayingActive {
      nowPlayingActive = false
      removeRemoteCommandTargets()
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    if wasActive {
      PluginCapsuleManager.shared.syncAudioPlaybackState(
        pluginID: resolvedActivePluginID(),
        isPlaying: playbackState == "playing"
      )
      syncNowPlayingToWidgetStorage(active: false, isPlaying: false, reloadTimeline: true)
    }
  }

  // MARK: - App Group Widget Shared Storage & Darwin Command Handling

  /// 解析当前活跃插件物理 ID（优先读取实例字段，回退活动槽或最小化胶囊槽）。
  fileprivate func resolvedActivePluginID() -> String {
    let trimmed = activePluginID.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    if let slotID = PluginWebViewPool.shared.currentActiveSlot?.activePluginID, !slotID.isEmpty {
      return slotID
    }
    if let parkedID = PluginCapsuleManager.shared.currentSession?.pluginID, !parkedID.isEmpty {
      return parkedID
    }
    return Self.pendingPluginID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 解析当前活跃插件显示名称。
  fileprivate func resolvedActivePluginName() -> String {
    let trimmed = activePluginName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    let pid = resolvedActivePluginID()
    if let slot = PluginWebViewPool.shared.currentActiveSlot,
      slot.activePluginID.caseInsensitiveCompare(pid) == .orderedSame,
      !slot.activePluginName.isEmpty
    {
      return slot.activePluginName
    }
    if let parked = PluginCapsuleManager.shared.currentSession,
      parked.pluginID.caseInsensitiveCompare(pid) == .orderedSame,
      !parked.pluginName.isEmpty
    {
      return parked.pluginName
    }
    return Self.pendingPluginName.isEmpty ? pid : Self.pendingPluginName
  }

  /// 获取小组件共享根目录 `MoviePilotWidgets-v1`（个人签名环境无 App Group 时安全回退 Caches 目录）。
  static func resolveWidgetSharedDirectory() -> URL {
    let baseContainer: URL
    if let group = WidgetSharedStorage.groupIdentifier,
      let groupContainer = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group)
    {
      baseContainer = groupContainer
    } else {
      baseContainer =
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    }
    let dir = baseContainer.appendingPathComponent("MoviePilotWidgets-v1", isDirectory: true)
    let mediaDir = dir.appendingPathComponent("media", isDirectory: true)
    try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    return dir
  }

  /// 将图片等比缩小至不超过 512px 并写入 `MoviePilotWidgets-v1/media/`，返回文件名。
  private static func saveWidgetDownsampledJPEG(image: UIImage, fileName: String) -> String {
    let mediaDir = resolveWidgetSharedDirectory().appendingPathComponent("media", isDirectory: true)
    let targetURL = mediaDir.appendingPathComponent(fileName)
    let srcSize = image.size
    let maxSide = max(srcSize.width, srcSize.height)
    let rendered: UIImage
    if maxSide > 512, maxSide > 0 {
      let ratio = 512.0 / maxSide
      let targetSize = CGSize(
        width: max(1, (srcSize.width * ratio).rounded()),
        height: max(1, (srcSize.height * ratio).rounded())
      )
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1.0
      rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
      }
    } else {
      rendered = image
    }
    guard let jpegData = rendered.jpegData(compressionQuality: 0.82) else {
      return ""
    }
    do {
      try jpegData.write(to: targetURL, options: [.atomic])
      return fileName
    } catch {
      return ""
    }
  }

  /// 同步当前播放信息至 `MoviePilotWidgets-v1/now_playing.json`，按需通知 WidgetKit 刷新时间线。
  private func syncNowPlayingToWidgetStorage(
    active: Bool,
    isPlaying: Bool,
    reloadTimeline: Bool
  ) {
    let dir = Self.resolveWidgetSharedDirectory()
    let fileURL = dir.appendingPathComponent("now_playing.json")
    let payload: [String: Any] = [
      "active": active,
      "pluginId": active ? resolvedActivePluginID() : "",
      "pluginName": active ? resolvedActivePluginName() : "",
      "title": active ? nowPlayingTitle : "",
      "artist": active ? nowPlayingArtist : "",
      "album": active ? nowPlayingAlbum : "",
      "lyrics": active
        ? (lastDisplayedLyricLine.isEmpty ? nowPlayingLyrics : lastDisplayedLyricLine) : "",
      "artworkFileName": active ? nowPlayingWidgetArtworkFileName : "",
      "isPlaying": active && isPlaying,
      "liked": active ? nowPlayingLiked : false,
      "hasLike": active ? nowPlayingHasLike : false,
      "canNext": active ? nowPlayingCanNext : false,
      "canPrevious": active ? nowPlayingCanPrevious : false,
      "durationMs": active ? max(0, nowPlayingDurationMs) : 0,
      "positionMs": active ? max(0, nowPlayingPositionMs) : 0,
      "updatedAt": Date().timeIntervalSince1970,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload) {
      try? data.write(to: fileURL, options: [.atomic])
    }
    if reloadTimeline {
      WidgetService.reloadTimeline(ofKind: "MoviePilotNowPlaying")
    }
  }

  /// 执行来自桌面小组件 Darwin 通知的音频或自定义指令。
  fileprivate func executeWidgetPendingCommand(_ cmd: [String: Any]) {
    let rawKind = ((cmd["kind"] as? String) ?? (cmd["type"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if rawKind == "audio" || rawKind == "nowplaying" {
      let command = (cmd["command"] as? String ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines)
      switch command {
      case "togglePlayPause":
        if playbackState == "playing" {
          avAudioPlayer?.pause()
          avPlayer?.pause()
          playbackState = "paused"
          stopSpectrumTimerOnly()
          emitPlaybackState()
        } else if avAudioPlayer != nil || avPlayer != nil {
          if let p = avAudioPlayer {
            p.rate = playbackRate
            p.play()
            playbackState = "playing"
          } else if let p = avPlayer {
            p.playImmediately(atRate: playbackRate)
            playbackState = "playing"
          }
          startPlaybackProgressTimer()
          _ = syncSpectrumTimerState()
          emitPlaybackState()
        }
        sendDeviceEvent("audio.remoteCommand", ["command": "togglePlayPause"])
      case "play":
        if let p = avAudioPlayer {
          p.rate = playbackRate
          p.play()
          playbackState = "playing"
          startPlaybackProgressTimer()
          _ = syncSpectrumTimerState()
          emitPlaybackState()
        } else if let p = avPlayer {
          p.playImmediately(atRate: playbackRate)
          playbackState = "playing"
          startPlaybackProgressTimer()
          _ = syncSpectrumTimerState()
          emitPlaybackState()
        }
        sendDeviceEvent("audio.remoteCommand", ["command": "play"])
      case "pause":
        avAudioPlayer?.pause()
        avPlayer?.pause()
        if avAudioPlayer != nil || avPlayer != nil {
          playbackState = "paused"
          stopSpectrumTimerOnly()
          emitPlaybackState()
        }
        sendDeviceEvent("audio.remoteCommand", ["command": "pause"])
      case "next":
        sendDeviceEvent("audio.remoteCommand", ["command": "next"])
      case "previous":
        sendDeviceEvent("audio.remoteCommand", ["command": "previous"])
      case "toggleLike":
        nowPlayingLiked.toggle()
        let center = MPRemoteCommandCenter.shared()
        center.likeCommand.isActive = nowPlayingLiked
        center.likeCommand.localizedTitle = nowPlayingLiked ? "取消喜欢" : "喜欢"
        syncNowPlayingToWidgetStorage(
          active: nowPlayingActive,
          isPlaying: playbackState == "playing",
          reloadTimeline: true
        )
        sendDeviceEvent(
          "audio.remoteCommand",
          ["command": "toggleLike", "liked": nowPlayingLiked]
        )
      default:
        if !command.isEmpty {
          sendDeviceEvent("audio.remoteCommand", ["command": command])
        }
      }
    } else if rawKind == "widget" || rawKind == "pluginaction" {
      let widgetKey =
        (cmd["widgetKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "default"
      let actionId =
        (cmd["actionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? (cmd["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""
      guard !actionId.isEmpty else { return }
      sendDeviceEvent(
        "widget.action",
        [
          "pluginId": resolvedActivePluginID(),
          "widgetKey": widgetKey.isEmpty ? "default" : widgetKey,
          "actionId": actionId,
        ]
      )
    }
  }

  /// 校验并规范化小组件 `widgetKey`。
  private static func normalizeWidgetKey(_ raw: Any?) -> String {
    let candidate: String
    if let s = raw as? String {
      candidate = s
    } else if let dict = raw as? [String: Any], let s = dict["widgetKey"] as? String {
      candidate = s
    } else {
      candidate = ""
    }
    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "default" }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
    let sanitized = String(
      trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.prefix(64)
    )
    return sanitized.isEmpty ? "default" : sanitized
  }

  /// 在原生后台携带当前实例会话凭据预缓存小组件图片至 `MoviePilotWidgets-v1/media/`。
  private func cacheWidgetImageIfNeeded(rawURL: String, filePrefix: String) async -> (
    fileName: String, fullPath: String
  )? {
    guard let resolved = resolveArtworkSource(rawURL) else { return nil }
    var req = URLRequest(url: resolved.url)
    if let ctx = sessionContextProvider(),
      resolved.attachAuth || ctx.address.contains(resolved.url)
    {
      req.setValue("Bearer \(ctx.accessToken)", forHTTPHeaderField: "Authorization")
      req.setValue(ctx.locale, forHTTPHeaderField: "X-MoviePilot-Locale")
      if let cookie = ctx.resourceCookie {
        req.setValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
      }
      CloudflareAccessCredentialRegistry.shared.applyHeaders(to: &req, for: ctx.address)
    }
    guard let (data, resp) = try? await urlSession.data(for: req),
      let http = resp as? HTTPURLResponse,
      (200..<300).contains(http.statusCode),
      data.count <= 5 * 1024 * 1024,
      let image = UIImage(data: data)
    else { return nil }
    let digest = SHA256.hash(data: Data(resolved.url.absoluteString.utf8))
    let shortHash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    let fileName = "\(filePrefix)_\(shortHash).jpg"
    let saved = Self.saveWidgetDownsampledJPEG(image: image, fileName: fileName)
    guard !saved.isEmpty else { return nil }
    let fullPath =
      Self.resolveWidgetSharedDirectory()
      .appendingPathComponent("media", isDirectory: true)
      .appendingPathComponent(saved)
      .path
    return (fileName: saved, fullPath: fullPath)
  }

  /// 递归校验自定义小组件布局树（最大深度 5、最多 40 节点）并预下载相对路径图片。
  private func validateAndTransformWidgetLayout(
    _ node: [String: Any],
    filePrefix: String,
    depth: Int,
    nodeCount: inout Int
  ) async throws -> [String: Any] {
    if depth > Self.maxWidgetLayoutDepth {
      throw NSError(
        domain: "PluginWidget", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey: "小组件 layout 嵌套深度不能超过 \(Self.maxWidgetLayoutDepth) 层"
        ])
    }
    nodeCount += 1
    if nodeCount > Self.maxWidgetLayoutNodes {
      throw NSError(
        domain: "PluginWidget", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey: "小组件 layout 节点总数不能超过 \(Self.maxWidgetLayoutNodes) 个"
        ])
    }
    var copy = node
    if let rawChildren = node["children"] as? [Any] {
      var nextChildren: [[String: Any]] = []
      nextChildren.reserveCapacity(rawChildren.count)
      for child in rawChildren {
        guard let childDict = child as? [String: Any] else {
          throw NSError(
            domain: "PluginWidget", code: 400,
            userInfo: [NSLocalizedDescriptionKey: "小组件 layout 子节点必须为字典对象"])
        }
        let processed = try await validateAndTransformWidgetLayout(
          childDict,
          filePrefix: filePrefix,
          depth: depth + 1,
          nodeCount: &nodeCount
        )
        nextChildren.append(processed)
      }
      copy["children"] = nextChildren
    }
    let nodeType = (node["type"] as? String ?? "").lowercased()
    if nodeType == "image",
      let imgURL = (node["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      imgURL.hasPrefix("/")
    {
      if let cached = await cacheWidgetImageIfNeeded(
        rawURL: imgURL, filePrefix: "\(filePrefix)_img")
      {
        copy["artworkFileName"] = cached.fileName
        copy["artworkPath"] = cached.fullPath
        copy["localPath"] = cached.fullPath
      }
    }
    return copy
  }

  /// 读取 `plugin_runtime_widgets.json` 中的全部字典条目。
  private static func loadRuntimeWidgetsMap() -> [String: [String: Any]] {
    let url = resolveWidgetSharedDirectory().appendingPathComponent("plugin_runtime_widgets.json")
    guard let data = try? Data(contentsOf: url),
      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]]
    else { return [:] }
    return obj
  }

  /// 原子写回 `plugin_runtime_widgets.json` 并刷新 `MoviePilotPlugin` 桌面小组件时间线。
  private static func saveRuntimeWidgetsMap(_ map: [String: [String: Any]]) {
    let url = resolveWidgetSharedDirectory().appendingPathComponent("plugin_runtime_widgets.json")
    if let data = try? JSONSerialization.data(withJSONObject: map) {
      try? data.write(to: url, options: [.atomic])
    }
    WidgetService.reloadTimeline(ofKind: "MoviePilotPlugin")
  }

  /// 处理前端运行态小组件推送（`widget.update`）。
  private func handleWidgetUpdate(requestId: String, payload: [String: Any]) {
    let pluginId = resolvedActivePluginID()
    guard !pluginId.isEmpty else {
      sendError(
        requestId: requestId, code: "NO_ACTIVE_PLUGIN", status: 400, message: "当前无活跃插件上下文")
      return
    }
    let title = (payload["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      sendError(
        requestId: requestId, code: "INVALID_PARAMS", status: 400, message: "小组件 title 不能为空")
      return
    }
    let widgetKey = Self.normalizeWidgetKey(payload["widgetKey"])
    let pluginName = resolvedActivePluginName()

    runManagedTask { [weak self] in
      guard let self else { return }
      let allowedKinds: Set<String> = ["metrics", "list", "poster", "nowPlaying", "custom"]
      let rawKind = (payload["kind"] as? String ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines)
      let kind: String
      if allowedKinds.contains(rawKind) {
        kind = rawKind
      } else if payload["layout"] is [String: Any] {
        kind = "custom"
      } else {
        kind = "metrics"
      }

      let safePrefix =
        "rt_\(pluginId.replacingOccurrences(of: "/", with: "_"))_\(widgetKey)"
      var processedLayout: [String: Any]?
      if let rawLayout = payload["layout"] as? [String: Any] {
        var count = 0
        do {
          processedLayout = try await self.validateAndTransformWidgetLayout(
            rawLayout,
            filePrefix: safePrefix,
            depth: 1,
            nodeCount: &count
          )
        } catch {
          self.sendError(
            requestId: requestId, code: "INVALID_WIDGET_LAYOUT", status: 400,
            message: error.localizedDescription)
          return
        }
      }

      let rawArtworkURL = (payload["artworkUrl"] as? String ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines)
      let cachedArtwork =
        rawArtworkURL.isEmpty
        ? nil : await self.cacheWidgetImageIfNeeded(rawURL: rawArtworkURL, filePrefix: safePrefix)

      let metrics = Array((payload["metrics"] as? [Any] ?? []).prefix(8))
      let items = Array((payload["items"] as? [Any] ?? []).prefix(8))
      let nowTs = Date().timeIntervalSince1970

      var entry: [String: Any] = [
        "pluginId": pluginId,
        "pluginName": pluginName,
        "widgetKey": widgetKey,
        "title": title,
        "kind": kind,
        "metrics": metrics,
        "items": items,
        "updatedAt": nowTs,
      ]
      if let subtitle = (payload["subtitle"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
        !subtitle.isEmpty
      {
        entry["subtitle"] = subtitle
      }
      if let badgeText = (payload["badgeText"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
        !badgeText.isEmpty
      {
        entry["badgeText"] = badgeText
      }
      if let accentHex = (payload["accentHex"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
        !accentHex.isEmpty
      {
        entry["accentHex"] = accentHex
      }
      if let tapAction = payload["tapAction"], !(tapAction is NSNull) {
        entry["tapAction"] = tapAction
      }
      if let processedLayout {
        entry["layout"] = processedLayout
      }
      if !rawArtworkURL.isEmpty {
        entry["artworkUrl"] = rawArtworkURL
      }
      if let cachedArtwork {
        entry["artworkFileName"] = cachedArtwork.fileName
        entry["artworkPath"] = cachedArtwork.fullPath
      }

      guard JSONSerialization.isValidJSONObject(entry),
        let encoded = try? JSONSerialization.data(withJSONObject: entry)
      else {
        self.sendError(
          requestId: requestId, code: "INVALID_PARAMS", status: 400, message: "小组件数据不是有效 JSON")
        return
      }
      guard encoded.count <= Self.maxWidgetPayloadBytes else {
        self.sendError(
          requestId: requestId, code: "PAYLOAD_TOO_LARGE", status: 400,
          message: "小组件序列化数据超过 32 KiB 上限")
        return
      }

      var allWidgets = Self.loadRuntimeWidgetsMap()
      allWidgets["\(pluginId)::\(widgetKey)"] = entry
      Self.saveRuntimeWidgetsMap(allWidgets)
      self.sendSuccess(
        requestId: requestId,
        data: [
          "updated": true,
          "pluginId": pluginId,
          "widgetKey": widgetKey,
          "updatedAt": Int(nowTs),
        ]
      )
    }
  }

  /// 移除当前插件指定的运行态小组件（`widget.remove`）。
  private func handleWidgetRemove(requestId: String, payload: [String: Any]) {
    let pluginId = resolvedActivePluginID()
    guard !pluginId.isEmpty else {
      sendError(
        requestId: requestId, code: "NO_ACTIVE_PLUGIN", status: 400, message: "当前无活跃插件上下文")
      return
    }
    let widgetKey = Self.normalizeWidgetKey(payload["widgetKey"])
    var allWidgets = Self.loadRuntimeWidgetsMap()
    let targetKey = "\(pluginId)::\(widgetKey)"
    allWidgets = allWidgets.filter { key, _ in
      key.caseInsensitiveCompare(targetKey) != .orderedSame
    }
    Self.saveRuntimeWidgetsMap(allWidgets)
    sendSuccess(
      requestId: requestId,
      data: [
        "removed": true,
        "pluginId": pluginId,
        "widgetKey": widgetKey,
      ]
    )
  }

  /// 列出当前活跃插件注册的所有运行态桌面小组件（`widget.list`）。
  private func handleWidgetList(requestId: String) {
    let pluginId = resolvedActivePluginID()
    guard !pluginId.isEmpty else {
      sendSuccess(requestId: requestId, data: ["widgets": []])
      return
    }
    let allWidgets = Self.loadRuntimeWidgetsMap()
    let prefix = "\(pluginId)::"
    let summaries: [[String: Any]] =
      allWidgets
      .filter { key, _ in key.lowercased().hasPrefix(prefix.lowercased()) }
      .sorted { $0.key < $1.key }
      .map { key, dict in
        let wKey = (dict["widgetKey"] as? String) ?? String(key.dropFirst(prefix.count))
        var item: [String: Any] = [
          "widgetKey": wKey,
          "title": (dict["title"] as? String) ?? "",
          "kind": (dict["kind"] as? String) ?? "metrics",
        ]
        if let sub = dict["subtitle"] as? String, !sub.isEmpty {
          item["subtitle"] = sub
        }
        if let badge = dict["badgeText"] as? String, !badge.isEmpty {
          item["badgeText"] = badge
        }
        if let ts = (dict["updatedAt"] as? NSNumber)?.doubleValue {
          item["updatedAt"] = Int(ts)
        }
        return item
      }
    sendSuccess(requestId: requestId, data: ["widgets": summaries])
  }

  private func resolveStorageStreamURL(
    context: PluginShellSchemeHandler.SessionContext,
    storage: String,
    path: String
  ) async throws -> (URL, [String: String]?) {
    let fileName = (path as NSString).lastPathComponent
    let ext = (fileName as NSString).pathExtension
    var authHeaders: [String: String] = [
      "Authorization": "Bearer \(context.accessToken)",
      "X-MoviePilot-Locale": context.locale,
    ]
    if let cookie = context.resourceCookie {
      authHeaders["Cookie"] = "\(cookie.name)=\(cookie.value)"
    }
    if let mergedCookie = CloudflareAccessCredentialRegistry.shared.mergedCookieHeader(
      existing: authHeaders["Cookie"], for: context.address)
    {
      authHeaders["Cookie"] = mergedCookie
    }
    if let cfToken = CloudflareAccessCredentialRegistry.shared.accessToken(for: context.address) {
      authHeaders["cf-access-token"] = cfToken
    }

    // 优先通过真实后端 `POST /api/v1/mediaserver/stream-ticket` -> `GET /api/v1/mediaserver/stream-info` 获取支持 HTTP Range 的流式播放地址
    if let ticketURL = buildSameOriginURL(
      address: context.address, apiPath: "/api/v1/mediaserver/stream-ticket")
    {
      var req = URLRequest(url: ticketURL)
      req.httpMethod = "POST"
      req.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
      req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
      CloudflareAccessCredentialRegistry.shared.applyHeaders(to: &req, for: context.address)
      req.httpBody = try? JSONSerialization.data(withJSONObject: [
        "file": [
          "storage": storage,
          "type": "file",
          "path": path,
          "name": fileName,
          "extension": ext,
        ],
        "media_type": "audio",
      ])
      if let (data, resp) = try? await urlSession.data(for: req),
        let http = resp as? HTTPURLResponse,
        (200..<300).contains(http.statusCode),
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      {
        let payloadObj = (obj["data"] as? [String: Any]) ?? obj
        if let ticketId = payloadObj["item_id"] as? String, !ticketId.isEmpty,
          let encodedId = ticketId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let infoURL = buildSameOriginURL(
            address: context.address, apiPath: "/api/v1/mediaserver/stream-info?itemid=\(encodedId)"
          )
        {
          var infoReq = URLRequest(url: infoURL)
          infoReq.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
          CloudflareAccessCredentialRegistry.shared.applyHeaders(to: &infoReq, for: context.address)
          if let (infoData, infoResp) = try? await urlSession.data(for: infoReq),
            let infoHttp = infoResp as? HTTPURLResponse,
            (200..<300).contains(infoHttp.statusCode),
            let infoObj = (try? JSONSerialization.jsonObject(with: infoData)) as? [String: Any]
          {
            let infoPayload = (infoObj["data"] as? [String: Any]) ?? infoObj
            if let rawContentUrl = infoPayload["content_url"] as? String, !rawContentUrl.isEmpty,
              let resolved = URL(string: rawContentUrl)
                ?? buildSameOriginURL(address: context.address, apiPath: rawContentUrl)
            {
              return (resolved, authHeaders)
            }
          }
          // 若 stream-info 失败，仍可直接请求 stream?itemid=...
          if let directStreamURL = buildSameOriginURL(
            address: context.address, apiPath: "/api/v1/mediaserver/stream?itemid=\(encodedId)")
          {
            return (directStreamURL, authHeaders)
          }
        }
      }
    }

    throw NSError(
      domain: "PluginAudioPlayer", code: -2,
      userInfo: [NSLocalizedDescriptionKey: "当前存储暂不支持在线流式播放，请检查存储配置或升级后端"])
  }

  // MARK: - Full-Screen Native Media Player (`media.playNative`)

  private func handlePlayNativeMedia(requestId: String, payload: [String: Any]) {
    let title = (payload["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let mediaType = (payload["mediaType"] as? String ?? "").lowercased()

    if let storage = payload["storage"] as? String, !storage.isEmpty,
      let path = payload["path"] as? String, !path.isEmpty
    {
      guard let session = nativeSessionProvider() else {
        sendError(requestId: requestId, code: "NO_SESSION", status: 401, message: "当前无活跃会话")
        return
      }
      let fileName =
        (payload["fileName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        ?? (path as NSString).lastPathComponent
      runManagedTask { [weak self] in
        guard let self else { return }
        if let err = await NativeMediaPlaybackLauncher.shared.playStorageFile(
          session: session, storage: storage, path: path, fileName: fileName
        ) {
          self.sendError(requestId: requestId, code: "PLAY_FAILED", status: 500, message: err)
        } else {
          self.sendSuccess(requestId: requestId, data: ["launched": true])
        }
      }
      return
    }

    if let itemId = payload["itemId"] as? String, !itemId.isEmpty {
      guard let session = nativeSessionProvider() else {
        sendError(requestId: requestId, code: "NO_SESSION", status: 401, message: "当前无活跃会话")
        return
      }
      let server = (payload["server"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      let artworkURL = NativeMediaPlaybackLauncher.proxiedArtworkURL(
        session: session, raw: payload["artworkUrl"] as? String)
      runManagedTask { [weak self] in
        guard let self else { return }
        if let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
          session: session,
          itemID: itemId,
          server: server,
          title: title,
          artworkURL: artworkURL
        ) {
          self.sendError(requestId: requestId, code: "PLAY_FAILED", status: 500, message: err)
        } else {
          self.sendSuccess(requestId: requestId, data: ["launched": true])
        }
      }
      return
    }

    if let rawURL = payload["url"] as? String,
      let url = URL(string: rawURL),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    {
      let kind: PlayableMediaKind =
        mediaType == "audio" || NativeMediaPlaybackLauncher.isAudioExtension(url.pathExtension)
        ? .audio
        : .video
      NativeMediaPlaybackLauncher.shared.enqueueOrPlayExternalURL(
        url: url, title: title.isEmpty ? nil : title, kind: kind)
      sendSuccess(requestId: requestId, data: ["launched": true])
      return
    }

    sendError(
      requestId: requestId, code: "INVALID_MEDIA", status: 400,
      message: "请提供 url、storage+path 或 itemId 媒体参数")
  }

  // MARK: - Share / Notify / Save Media / Biometric / Pickers / QR Scan

  private func handleShare(requestId: String, payload: [String: Any]) {
    guard let presenter = Self.topViewController() else {
      sendError(requestId: requestId, code: "NO_PRESENTER", status: 500, message: "当前界面无法打开系统分享")
      return
    }
    var items: [Any] = []
    if let text = payload["text"] as? String, !text.isEmpty {
      items.append(text)
    }
    if let rawURL = payload["url"] as? String, let url = URL(string: rawURL) {
      items.append(url)
    }
    var tempFileURL: URL? = nil
    if let rawB64 = payload["base64"] as? String, !rawB64.isEmpty,
      let bytes = Data(base64Encoded: Self.stripDataURIPrefix(rawB64)),
      bytes.count <= Self.maxBase64Bytes
    {
      let fileName =
        (payload["fileName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        ?? "share_\(UUID().uuidString).bin"
      let safeName = fileName.replacingOccurrences(of: "/", with: "_")
      let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
      if (try? bytes.write(to: tempURL)) != nil {
        tempFileURL = tempURL
        items.append(tempURL)
      }
    }
    guard !items.isEmpty else {
      sendError(requestId: requestId, code: "EMPTY_SHARE", status: 400, message: "缺少可分享的内容")
      return
    }
    let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let pop = vc.popoverPresentationController {
      pop.sourceView = presenter.view
      pop.sourceRect = CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    }
    vc.completionWithItemsHandler = { [weak self] _, completed, _, _ in
      if let tempFileURL {
        try? FileManager.default.removeItem(at: tempFileURL)
      }
      Task { @MainActor [weak self] in
        self?.sendSuccess(
          requestId: requestId,
          data: ["completed": completed, "cancelled": !completed]
        )
      }
    }
    presenter.present(vc, animated: true)
  }

  private func handleNotify(requestId: String, payload: [String: Any]) {
    let title = (payload["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let body = (payload["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let notifId =
      (payload["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "plugin_\(UUID().uuidString)"
    let delaySec = max((payload["delaySec"] as? Double) ?? 0.2, 0.2)
    guard !title.isEmpty || !body.isEmpty else {
      sendError(
        requestId: requestId, code: "INVALID_NOTIFICATION", status: 400, message: "通知标题和内容不能同时为空")
      return
    }
    runManagedTask { [weak self] in
      guard let self else { return }
      let center = UNUserNotificationCenter.current()
      let granted =
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
      guard granted else {
        self.sendError(
          requestId: requestId, code: "PERMISSION_DENIED", status: 403, message: "未获得系统通知权限")
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title.isEmpty ? "MoviePilot" : title
      content.body = body
      content.sound = .default
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delaySec, repeats: false)
      let req = UNNotificationRequest(identifier: notifId, content: content, trigger: trigger)
      do {
        try await center.add(req)
        self.sendSuccess(requestId: requestId, data: ["scheduled": true, "id": notifId])
      } catch {
        self.sendError(
          requestId: requestId, code: "NOTIFY_FAILED", status: 500,
          message: error.localizedDescription)
      }
    }
  }

  private func handlePickMedia(requestId: String, payload: [String: Any]) {
    guard pendingPickerRequestId == nil else {
      sendError(requestId: requestId, code: "PICKER_BUSY", status: 409, message: "已有打开的媒体或文件选择器")
      return
    }
    guard let presenter = Self.topViewController() else {
      sendError(requestId: requestId, code: "NO_PRESENTER", status: 500, message: "当前界面无法打开媒体选择器")
      return
    }
    let source = (payload["source"] as? String ?? "library").lowercased()
    let mediaType = (payload["mediaType"] as? String ?? "image").lowercased()
    let multiple = (payload["multiple"] as? Bool) ?? false
    let maxCount = max(1, min((payload["maxCount"] as? Int) ?? (multiple ? 9 : 1), 20))
    let includeBase64 = (payload["includeBase64"] as? Bool) ?? true

    pendingPickerRequestId = requestId
    pendingPickerIncludeBase64 = includeBase64

    if source == "camera" {
      guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
        pendingPickerRequestId = nil
        sendError(requestId: requestId, code: "UNSUPPORTED", status: 400, message: "当前设备不支持相机拍摄")
        return
      }
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.mediaTypes =
        mediaType == "video" ? [UTType.movie.identifier] : [UTType.image.identifier]
      picker.delegate = self
      presenter.present(picker, animated: true)
      return
    }

    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.selectionLimit = multiple ? maxCount : 1
    switch mediaType {
    case "video": config.filter = .videos
    case "any": config.filter = .any(of: [.images, .videos])
    default: config.filter = .images
    }
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  private func handlePickFile(requestId: String, payload: [String: Any]) {
    guard pendingPickerRequestId == nil else {
      sendError(requestId: requestId, code: "PICKER_BUSY", status: 409, message: "已有打开的文件选择器")
      return
    }
    guard let presenter = Self.topViewController() else {
      sendError(requestId: requestId, code: "NO_PRESENTER", status: 500, message: "当前界面无法打开文件选择器")
      return
    }
    let accept = (payload["accept"] as? [String]) ?? []
    let multiple = (payload["multiple"] as? Bool) ?? false
    let includeBase64 = (payload["includeBase64"] as? Bool) ?? true

    var types: [UTType] = []
    for item in accept {
      let lower = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if lower.hasPrefix("image/") {
        types.append(.image)
      } else if lower.hasPrefix("audio/") {
        types.append(.audio)
      } else if lower.hasPrefix("video/") {
        types.append(.movie)
      } else if lower == "application/pdf" || lower == ".pdf" {
        types.append(.pdf)
      } else if lower.hasPrefix(".") {
        let ext = String(lower.dropFirst())
        if let ut = UTType(filenameExtension: ext) { types.append(ut) }
      } else if let ut = UTType(mimeType: lower) {
        types.append(ut)
      }
    }
    if types.isEmpty {
      types = [.item]
    }

    pendingPickerRequestId = requestId
    pendingPickerIncludeBase64 = includeBase64

    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.allowsMultipleSelection = multiple
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  private func handleSaveMedia(requestId: String, payload: [String: Any]) {
    runManagedTask { [weak self] in
      guard let self else { return }
      let authStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
      guard authStatus == .authorized || authStatus == .limited else {
        self.sendError(
          requestId: requestId, code: "PERMISSION_DENIED", status: 403, message: "未获得保存至相册的权限")
        return
      }
      do {
        let rawData: Data
        if let b64 = payload["base64"] as? String, !b64.isEmpty {
          guard let decoded = Data(base64Encoded: Self.stripDataURIPrefix(b64)), !decoded.isEmpty
          else {
            throw NSError(
              domain: "PluginSaveMedia", code: -1,
              userInfo: [NSLocalizedDescriptionKey: "无效的 Base64 媒体数据"])
          }
          rawData = decoded
        } else if let rawAPI = payload["apiPath"] as? String, !rawAPI.isEmpty {
          guard let normalized = try? PluginRemoteRuntime.validateAPIPath(rawAPI),
            let ctx = self.sessionContextProvider(),
            let url = self.buildSameOriginURL(address: ctx.address, apiPath: normalized)
          else {
            throw NSError(
              domain: "PluginSaveMedia", code: -2,
              userInfo: [NSLocalizedDescriptionKey: "非法或未认证的 API 路径"])
          }
          var req = URLRequest(url: url)
          req.setValue("Bearer \(ctx.accessToken)", forHTTPHeaderField: "Authorization")
          if let cookie = ctx.resourceCookie {
            req.setValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
          }
          let (data, _) = try await self.urlSession.data(for: req)
          rawData = data
        } else if let rawURL = payload["url"] as? String, let url = URL(string: rawURL),
          let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        {
          let (data, _) = try await self.urlSession.data(from: url)
          rawData = data
        } else {
          throw NSError(
            domain: "PluginSaveMedia", code: -3,
            userInfo: [NSLocalizedDescriptionKey: "缺少 base64、apiPath 或 url 媒体源"])
        }

        guard let image = UIImage(data: rawData) else {
          throw NSError(
            domain: "PluginSaveMedia", code: -4,
            userInfo: [NSLocalizedDescriptionKey: "仅支持将有效图片保存至系统相册"])
        }
        try await PHPhotoLibrary.shared().performChanges {
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
        self.sendSuccess(requestId: requestId, data: ["saved": true])
      } catch {
        self.sendError(
          requestId: requestId, code: "SAVE_MEDIA_FAILED", status: 500,
          message: error.localizedDescription)
      }
    }
  }

  private func handleScanCode(requestId: String, payload: [String: Any]) {
    guard UIImagePickerController.isSourceTypeAvailable(.camera),
      let presenter = Self.topViewController()
    else {
      sendError(requestId: requestId, code: "UNSUPPORTED", status: 400, message: "当前设备不支持相机扫码")
      return
    }
    let prompt = (payload["prompt"] as? String) ?? "将二维码或条形码放入框内扫描"
    runManagedTask { [weak self] in
      guard let self else { return }
      let granted = await AVCaptureDevice.requestAccess(for: .video)
      guard granted else {
        self.sendError(
          requestId: requestId, code: "PERMISSION_DENIED", status: 403, message: "未获得相机权限")
        return
      }
      let scanner = PluginQRScannerViewController(prompt: prompt) { [weak self] result in
        Task { @MainActor [weak self] in
          guard let self else { return }
          if let (value, format) = result {
            self.sendSuccess(
              requestId: requestId,
              data: ["cancelled": false, "value": value, "format": format]
            )
          } else {
            self.sendSuccess(requestId: requestId, data: ["cancelled": true])
          }
        }
      }
      scanner.modalPresentationStyle = .fullScreen
      presenter.present(scanner, animated: true)
    }
  }

  private func handleAuthenticate(requestId: String, payload: [String: Any]) {
    let reason =
      (payload["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "验证你的身份以继续插件操作"
    runManagedTask { [weak self] in
      guard let self else { return }
      let ctx = LAContext()
      var authErr: NSError?
      let policy: LAPolicy = .deviceOwnerAuthentication
      guard ctx.canEvaluatePolicy(policy, error: &authErr) else {
        self.sendSuccess(
          requestId: requestId,
          data: ["authenticated": false, "biometryType": "none"]
        )
        return
      }
      let biometryType: String
      switch ctx.biometryType {
      case .faceID: biometryType = "faceID"
      case .touchID: biometryType = "touchID"
      case .opticID: biometryType = "opticID"
      default: biometryType = "passcode"
      }
      let ok = (try? await ctx.evaluatePolicy(policy, localizedReason: reason)) ?? false
      self.sendSuccess(
        requestId: requestId,
        data: ["authenticated": ok, "biometryType": biometryType]
      )
    }
  }

  // MARK: - Helpers

  private func runManagedTask(_ operation: @escaping @MainActor () async -> Void) {
    let id = UUID()
    activeAsyncTasks.insert(id)
    let task = Task { @MainActor [weak self] in
      defer {
        self?.runningTasks.removeValue(forKey: id)
        self?.activeAsyncTasks.remove(id)
      }
      await operation()
    }
    runningTasks[id] = task
  }

  private func sendSuccess(requestId: String, data: [String: Any]) {
    guard !requestId.isEmpty else { return }
    sendResponse(requestId, true, data, nil)
  }

  private func sendError(requestId: String, code: String, status: Int, message: String) {
    guard !requestId.isEmpty else { return }
    sendResponse(requestId, false, nil, (code: code, status: status, message: message))
  }

  private func buildSameOriginURL(address: ServerAddress, apiPath: String) -> URL? {
    var base = address.url.absoluteString
    while base.hasSuffix("/") { base.removeLast() }
    let joined = base + (apiPath.hasPrefix("/") ? apiPath : "/\(apiPath)")
    guard let url = URL(string: joined), address.contains(url) else { return nil }
    return url
  }

  private static func stripDataURIPrefix(_ raw: String) -> String {
    if let comma = raw.firstIndex(of: ","), raw[..<comma].contains("base64") {
      return String(raw[raw.index(after: comma)...])
    }
    return raw
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let keyWindow =
      scenes.flatMap(\.windows).first(where: \.isKeyWindow)
      ?? scenes.flatMap(\.windows).first
    var current = keyWindow?.rootViewController
    while let presented = current?.presentedViewController {
      if presented.isBeingDismissed { break }
      current = presented
    }
    return current
  }

  private func encodePickedFile(
    data: Data,
    name: String,
    mimeType: String,
    includeBase64: Bool
  ) -> [String: Any] {
    var obj: [String: Any] = [
      "name": name,
      "mimeType": mimeType,
      "sizeBytes": data.count,
      "truncated": false,
    ]
    if includeBase64 {
      if data.count <= Self.maxBase64Bytes {
        obj["base64"] = data.base64EncodedString()
      } else {
        obj["truncated"] = true
      }
    }
    return obj
  }
}

// MARK: - AVAudioPlayerDelegate

extension PluginNativeCapabilitiesService: AVAudioPlayerDelegate {
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor [weak self] in
      guard let self, self.avAudioPlayer === player else { return }
      let dur = self.currentPlaybackDurationMs()
      let pid = self.playbackID ?? ""
      self.playbackProgressTimer?.invalidate()
      self.playbackProgressTimer = nil
      self.stopSpectrumTimerOnly()
      self.playbackState = "ended"
      self.sendDeviceEvent("audio.play.ended", ["playbackId": pid, "durationMs": dur])
      self.emitPlaybackState()
    }
  }
}

// MARK: - Lock-Free / Low-Overhead Audio Spectrum Ring Buffer & Radix-2 FFT (#79)

/// 实时音频渲染线程与主线程共享的固定容量环形样本缓冲（处理回调内零堆内存分配）。
private final class PluginAudioSpectrumBuffer: @unchecked Sendable {
  static let windowSize = 512

  private let lock = NSLock()
  private var ring: [Float] = Array(repeating: 0, count: windowSize)
  private var writeIndex: Int = 0
  private var leftRMS: Float = 0
  private var rightRMS: Float = 0
  private var isFloatPCM: Bool = true
  private var isNonInterleaved: Bool = true
  private var bitsPerChannel: Int = 32
  private var channelsPerFrame: Int = 2

  /// 记录 `MTAudioProcessingTap` 协商得到的音频流格式参数。
  func configureFormat(_ asbd: AudioStreamBasicDescription) {
    lock.lock()
    isFloatPCM = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    bitsPerChannel = Int(asbd.mBitsPerChannel)
    channelsPerFrame = max(1, Int(asbd.mChannelsPerFrame))
    lock.unlock()
  }

  /// 在实时音频回调中拷贝最新一帧 PCM 样本并计算左右声道 RMS。
  func ingest(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
    guard frameCount > 0 else { return }
    let abl = UnsafeMutableAudioBufferListPointer(bufferList)
    guard !abl.isEmpty else { return }

    lock.lock()
    let floatFormat = isFloatPCM
    let planar = isNonInterleaved
    let bits = bitsPerChannel
    let channels = channelsPerFrame
    lock.unlock()

    var sumL: Float = 0
    var sumR: Float = 0

    if floatFormat && bits == 32 {
      if planar || abl.count >= 2 {
        guard let rawL = abl[0].mData else { return }
        let ptrL = rawL.assumingMemoryBound(to: Float.self)
        let ptrR: UnsafeMutablePointer<Float>
        if abl.count >= 2, let rawR = abl[1].mData {
          ptrR = rawR.assumingMemoryBound(to: Float.self)
        } else {
          ptrR = ptrL
        }
        lock.lock()
        for i in 0..<frameCount {
          let l = ptrL[i]
          let r = ptrR[i]
          sumL += l * l
          sumR += r * r
          ring[writeIndex] = (l + r) * 0.5
          writeIndex = (writeIndex + 1) & (Self.windowSize - 1)
        }
        let inv = 1.0 / Float(frameCount)
        leftRMS = sqrt(sumL * inv)
        rightRMS = sqrt(sumR * inv)
        lock.unlock()
      } else if let raw = abl[0].mData {
        let ptr = raw.assumingMemoryBound(to: Float.self)
        let stride = max(1, channels)
        lock.lock()
        for i in 0..<frameCount {
          let base = i * stride
          let l = ptr[base]
          let r = stride > 1 ? ptr[base + 1] : l
          sumL += l * l
          sumR += r * r
          ring[writeIndex] = (l + r) * 0.5
          writeIndex = (writeIndex + 1) & (Self.windowSize - 1)
        }
        let inv = 1.0 / Float(frameCount)
        leftRMS = sqrt(sumL * inv)
        rightRMS = sqrt(sumR * inv)
        lock.unlock()
      }
    } else if bits == 16, let raw0 = abl[0].mData {
      let scale: Float = 1.0 / 32768.0
      if planar && abl.count >= 2, let raw1 = abl[1].mData {
        let ptrL = raw0.assumingMemoryBound(to: Int16.self)
        let ptrR = raw1.assumingMemoryBound(to: Int16.self)
        lock.lock()
        for i in 0..<frameCount {
          let l = Float(ptrL[i]) * scale
          let r = Float(ptrR[i]) * scale
          sumL += l * l
          sumR += r * r
          ring[writeIndex] = (l + r) * 0.5
          writeIndex = (writeIndex + 1) & (Self.windowSize - 1)
        }
        let inv = 1.0 / Float(frameCount)
        leftRMS = sqrt(sumL * inv)
        rightRMS = sqrt(sumR * inv)
        lock.unlock()
      } else {
        let ptr = raw0.assumingMemoryBound(to: Int16.self)
        let stride = max(1, channels)
        lock.lock()
        for i in 0..<frameCount {
          let base = i * stride
          let l = Float(ptr[base]) * scale
          let r = stride > 1 ? Float(ptr[base + 1]) * scale : l
          sumL += l * l
          sumR += r * r
          ring[writeIndex] = (l + r) * 0.5
          writeIndex = (writeIndex + 1) & (Self.windowSize - 1)
        }
        let inv = 1.0 / Float(frameCount)
        leftRMS = sqrt(sumL * inv)
        rightRMS = sqrt(sumR * inv)
        lock.unlock()
      }
    }
  }

  /// 读取最新一帧连续时间序窗口及左右声道 RMS。
  func snapshotWindow() -> (samples: [Float], leftRMS: Float, rightRMS: Float) {
    lock.lock()
    defer { lock.unlock() }
    var ordered = Array(repeating: Float(0), count: Self.windowSize)
    let cursor = writeIndex
    for i in 0..<Self.windowSize {
      ordered[i] = ring[(cursor + i) & (Self.windowSize - 1)]
    }
    return (ordered, leftRMS, rightRMS)
  }
}

/// 纯 Swift 512 点基 2 Cooley-Tukey 快速傅里叶变换与频段重采样器（零不安全指针开销）。
private enum PluginRadix2FFT {
  private static let n = PluginAudioSpectrumBuffer.windowSize
  private static let hannWindow: [Float] = {
    let denom = Float(n - 1)
    return (0..<n).map { i in
      0.5 * (1.0 - cos(2.0 * .pi * Float(i) / denom))
    }
  }()

  /// 对 512 点时域样本加 Hann 窗后执行基 2 FFT，并重采样为 `bandCount` 个 `0..255` 频段幅值。
  static func computeBands(samples: [Float], bandCount: Int) -> [Int] {
    guard samples.count == n else {
      return Array(repeating: 0, count: bandCount)
    }
    var real = Array(repeating: Float(0), count: n)
    var imag = Array(repeating: Float(0), count: n)
    for i in 0..<n {
      real[i] = samples[i] * hannWindow[i]
    }

    // 位反转重排
    var j = 0
    for i in 1..<n {
      var bit = n >> 1
      while (j & bit) != 0 {
        j ^= bit
        bit >>= 1
      }
      j ^= bit
      if i < j {
        real.swapAt(i, j)
      }
    }

    // 蝶形迭代运算
    var length = 2
    while length <= n {
      let half = length >> 1
      let angle = -2.0 * Float.pi / Float(length)
      let wLenCos = cos(angle)
      let wLenSin = sin(angle)
      var start = 0
      while start < n {
        var wCos: Float = 1.0
        var wSin: Float = 0.0
        for k in 0..<half {
          let evenIdx = start + k
          let oddIdx = evenIdx + half
          let uR = real[evenIdx]
          let uI = imag[evenIdx]
          let vR = real[oddIdx] * wCos - imag[oddIdx] * wSin
          let vI = real[oddIdx] * wSin + imag[oddIdx] * wCos
          real[evenIdx] = uR + vR
          imag[evenIdx] = uI + vI
          real[oddIdx] = uR - vR
          imag[oddIdx] = uI - vI
          let nextCos = wCos * wLenCos - wSin * wLenSin
          wSin = wCos * wLenSin + wSin * wLenCos
          wCos = nextCos
        }
        start += length
      }
      length <<= 1
    }

    let halfBins = n >> 1
    var mags = Array(repeating: Float(0), count: halfBins)
    let scale = 2.0 / Float(n)
    for k in 1..<halfBins {
      mags[k] = hypot(real[k], imag[k]) * scale
    }

    let usableBins = halfBins - 1
    let logMax = log(Double(usableBins + 1))
    var out: [Int] = []
    out.reserveCapacity(bandCount)
    for b in 0..<bandCount {
      let t0 = Double(b) / Double(bandCount)
      let t1 = Double(b + 1) / Double(bandCount)
      let startBin = min(usableBins, max(1, Int(exp(t0 * logMax) - 1.0)))
      let endBin = min(usableBins, max(startBin, Int(exp(t1 * logMax) - 1.0)))
      var peak: Float = 0
      for idx in startBin...endBin where mags[idx] > peak {
        peak = mags[idx]
      }
      let db = 20.0 * log10(Double(peak) + 1e-5)
      let normalized = max(0.0, min(1.0, (db + 62.0) / 56.0))
      out.append(Int((normalized * 255.0).rounded()))
    }
    return out
  }
}

// MARK: - Darwin Notification Router for Desktop Widget Commands

/// 监听桌面小组件进程发出的 `"org.moviepilot.widgets.command"` Darwin 通知并转发给活跃插件宿主。
@MainActor
private final class DarwinWidgetCommandRouter {
  static let shared = DarwinWidgetCommandRouter()
  private static let notificationName = "org.moviepilot.widgets.command" as CFString

  private final class WeakBox {
    weak var value: PluginNativeCapabilitiesService?
    init(_ value: PluginNativeCapabilitiesService) { self.value = value }
  }

  private var services: [WeakBox] = []
  private var isObserving = false

  private init() {}

  /// 注册活跃能力服务实例并按需启动跨进程 Darwin 通知监听。
  func register(_ service: PluginNativeCapabilitiesService) {
    services.removeAll { $0.value == nil || $0.value === service }
    services.append(WeakBox(service))
    startObservingIfNeeded()
    consumePendingCommandIfNeeded()
  }

  /// 注销能力服务实例。
  func unregister(_ service: PluginNativeCapabilitiesService) {
    services.removeAll { $0.value == nil || $0.value === service }
  }

  private func startObservingIfNeeded() {
    guard !isObserving else { return }
    isObserving = true
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterAddObserver(
      center,
      Unmanaged.passUnretained(self).toOpaque(),
      { _, _, _, _, _ in
        Task { @MainActor in
          DarwinWidgetCommandRouter.shared.consumePendingCommandIfNeeded()
        }
      },
      Self.notificationName,
      nil,
      .deliverImmediately
    )
  }

  /// 读取并原子消费 `MoviePilotWidgets-v1/pending_widget_command.json`，路由给匹配的插件实例。
  func consumePendingCommandIfNeeded() {
    services.removeAll { $0.value == nil }
    guard !services.isEmpty else { return }
    let cmdURL =
      PluginNativeCapabilitiesService.resolveWidgetSharedDirectory()
      .appendingPathComponent("pending_widget_command.json")
    guard let data = try? Data(contentsOf: cmdURL),
      let cmd = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return }

    let targetPlugin = (cmd["pluginId"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let matched: PluginNativeCapabilitiesService? = {
      if !targetPlugin.isEmpty {
        if let exact = services.last(where: {
          $0.value?.resolvedActivePluginID().caseInsensitiveCompare(targetPlugin) == .orderedSame
        })?.value {
          return exact
        }
      }
      return services.last?.value
    }()

    guard let matched else { return }
    try? FileManager.default.removeItem(at: cmdURL)
    matched.executeWidgetPendingCommand(cmd)
  }
}

// MARK: - PHPickerViewControllerDelegate

private struct PickedMediaPayload: Sendable {
  let index: Int
  let name: String
  let mimeType: String
  let data: Data
}

private final class PickedMediaAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [PickedMediaPayload] = []

  func append(_ item: PickedMediaPayload) {
    lock.lock()
    items.append(item)
    lock.unlock()
  }

  func sortedItems() -> [PickedMediaPayload] {
    lock.lock()
    defer { lock.unlock() }
    return items.sorted { $0.index < $1.index }
  }
}

extension PluginNativeCapabilitiesService: PHPickerViewControllerDelegate {
  nonisolated func picker(
    _ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]
  ) {
    let group = DispatchGroup()
    let accumulator = PickedMediaAccumulator()
    for (index, item) in results.enumerated() {
      let provider = item.itemProvider
      let typeId = provider.registeredTypeIdentifiers.first ?? UTType.image.identifier
      let ut = UTType(typeId)
      let mime = ut?.preferredMIMEType ?? "application/octet-stream"
      let ext = ut?.preferredFilenameExtension ?? "bin"
      let suggested = provider.suggestedName.map { "\($0).\(ext)" } ?? "media_\(index + 1).\(ext)"
      group.enter()
      provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, _ in
        if let data {
          accumulator.append(
            PickedMediaPayload(index: index, name: suggested, mimeType: mime, data: data))
        }
        group.leave()
      }
    }
    let isEmpty = results.isEmpty
    DispatchQueue.main.async {
      picker.dismiss(animated: true)
    }
    group.notify(queue: .main) { [weak self] in
      let loaded = accumulator.sortedItems()
      Task { @MainActor [weak self] in
        guard let self, let reqId = self.pendingPickerRequestId else { return }
        let includeBase64 = self.pendingPickerIncludeBase64
        self.pendingPickerRequestId = nil
        if isEmpty || loaded.isEmpty {
          self.sendSuccess(requestId: reqId, data: ["cancelled": true, "files": []])
          return
        }
        let files = loaded.map { entry in
          self.encodePickedFile(
            data: entry.data, name: entry.name, mimeType: entry.mimeType,
            includeBase64: includeBase64)
        }
        self.sendSuccess(requestId: reqId, data: ["cancelled": false, "files": files])
      }
    }
  }
}

// MARK: - UIImagePickerControllerDelegate

extension PluginNativeCapabilitiesService: UIImagePickerControllerDelegate,
  UINavigationControllerDelegate
{
  nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    Task { @MainActor [weak self] in
      picker.dismiss(animated: true)
      guard let self, let reqId = self.pendingPickerRequestId else { return }
      self.pendingPickerRequestId = nil
      self.sendSuccess(requestId: reqId, data: ["cancelled": true, "files": []])
    }
  }

  nonisolated func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    let image = info[.originalImage] as? UIImage
    let mediaURL = info[.mediaURL] as? URL
    Task { @MainActor [weak self] in
      picker.dismiss(animated: true)
      guard let self, let reqId = self.pendingPickerRequestId else { return }
      let includeBase64 = self.pendingPickerIncludeBase64
      self.pendingPickerRequestId = nil
      var files: [[String: Any]] = []
      if let image, let data = image.jpegData(compressionQuality: 0.88) {
        files.append(
          self.encodePickedFile(
            data: data,
            name: "camera_\(Int(Date().timeIntervalSince1970)).jpg",
            mimeType: "image/jpeg",
            includeBase64: includeBase64
          ))
      } else if let mediaURL, let data = try? Data(contentsOf: mediaURL) {
        files.append(
          self.encodePickedFile(
            data: data,
            name: mediaURL.lastPathComponent,
            mimeType: "video/mp4",
            includeBase64: includeBase64
          ))
      }
      self.sendSuccess(requestId: reqId, data: ["cancelled": files.isEmpty, "files": files])
    }
  }
}

// MARK: - UIDocumentPickerDelegate

extension PluginNativeCapabilitiesService: UIDocumentPickerDelegate {
  nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    Task { @MainActor [weak self] in
      guard let self, let reqId = self.pendingPickerRequestId else { return }
      self.pendingPickerRequestId = nil
      self.sendSuccess(requestId: reqId, data: ["cancelled": true, "files": []])
    }
  }

  nonisolated func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    Task { @MainActor [weak self] in
      guard let self, let reqId = self.pendingPickerRequestId else { return }
      let includeBase64 = self.pendingPickerIncludeBase64
      self.pendingPickerRequestId = nil
      var files: [[String: Any]] = []
      for url in urls {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
          let ut = UTType(filenameExtension: url.pathExtension)
          let mime = ut?.preferredMIMEType ?? "application/octet-stream"
          files.append(
            self.encodePickedFile(
              data: data,
              name: url.lastPathComponent,
              mimeType: mime,
              includeBase64: includeBase64
            ))
        }
      }
      self.sendSuccess(requestId: reqId, data: ["cancelled": files.isEmpty, "files": files])
    }
  }
}

// MARK: - Lightweight Native QR / Barcode Scanner

@MainActor
private final class PluginQRScannerViewController: UIViewController,
  AVCaptureMetadataOutputObjectsDelegate
{
  private let promptText: String
  private var onFinish: (((String, String)?) -> Void)?
  private let session = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var didComplete = false

  init(prompt: String, onFinish: @escaping (((String, String)?) -> Void)) {
    self.promptText = prompt
    self.onFinish = onFinish
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    if let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    {
      session.addInput(input)
      let output = AVCaptureMetadataOutput()
      if session.canAddOutput(output) {
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [
          .qr, .ean8, .ean13, .code128, .code39, .pdf417, .aztec, .dataMatrix,
        ]
      }
      let preview = AVCaptureVideoPreviewLayer(session: session)
      preview.videoGravity = .resizeAspectFill
      preview.frame = view.bounds
      view.layer.addSublayer(preview)
      previewLayer = preview
      let capSession = session
      DispatchQueue.global(qos: .userInitiated).async {
        capSession.startRunning()
      }
    }

    let closeBtn = UIButton(type: .system)
    closeBtn.setTitle(L10n.text("取消"), for: .normal)
    closeBtn.setTitleColor(.white, for: .normal)
    closeBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    closeBtn.layer.cornerRadius = 18
    closeBtn.translatesAutoresizingMaskIntoConstraints = false
    closeBtn.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
    view.addSubview(closeBtn)

    let label = UILabel()
    label.text = promptText
    label.textColor = .white
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textAlignment = .center
    label.numberOfLines = 2
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)

    NSLayoutConstraint.activate([
      closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      closeBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
      closeBtn.heightAnchor.constraint(equalToConstant: 36),
      label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  @objc private func handleCancel() {
    complete(with: nil)
  }

  private func complete(with result: (String, String)?) {
    guard !didComplete else { return }
    didComplete = true
    let capSession = session
    DispatchQueue.global(qos: .userInitiated).async {
      if capSession.isRunning { capSession.stopRunning() }
    }
    let cb = onFinish
    onFinish = nil
    dismiss(animated: true) {
      cb?(result)
    }
  }

  nonisolated func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
      let val = readable.stringValue, !val.isEmpty
    else { return }
    let format = readable.type.rawValue
    Task { @MainActor [weak self] in
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      self?.complete(with: (val, format))
    }
  }
}
