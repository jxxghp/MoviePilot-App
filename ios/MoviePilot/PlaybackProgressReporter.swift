import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import UIKit

extension Notification.Name {
  /// 播放器成功向后端发送 `stopped` 终态后广播，用于触发详情页和继续观看栏静默刷新。
  static let moviePilotPlaybackDidStop = Notification.Name("MoviePilot.PlaybackDidStop")
}

/// 主线程托管的短时后台任务租约，确保播放器关闭后终态 `stopped` 请求能发出且满足 Swift 6 严格并发校验。
@MainActor
private final class PlaybackBackgroundTaskLease {
  private var taskID: UIBackgroundTaskIdentifier = .invalid

  init(name: String) {
    taskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      Task { @MainActor in
        self?.end()
      }
    }
  }

  func end() {
    guard taskID != .invalid else { return }
    let id = taskID
    taskID = .invalid
    UIApplication.shared.endBackgroundTask(id)
  }
}

/// App 级播放进度与会话上报器：生命周期独立于播放器视图，保证 `stopped` 终态不被页面关闭取消并支持离线补报。
@MainActor
final class PlaybackProgressReporter {
  static let shared = PlaybackProgressReporter()

  private static let clientIDKey = "nativeV2.playback.clientId"
  private static let pendingStopsKey = "nativeV2.playback.pendingStops"

  private var serialTailTask: Task<Void, Never>?

  private init() {}

  /// 当前设备匿名稳定的安装标识，用于隔离多台设备在媒体服务器上的并发播放会话。
  var clientID: String {
    if let existing = UserDefaults.standard.string(forKey: Self.clientIDKey), !existing.isEmpty {
      return existing
    }
    let generated = UUID().uuidString.lowercased()
    UserDefaults.standard.set(generated, forKey: Self.clientIDKey)
    return generated
  }

  /// 当前设备展示名称，供 Emby / Jellyfin / Plex 仪表盘展示。
  var deviceName: String {
    let model = UIDevice.current.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    return model.isEmpty ? "iPhone" : model
  }

  /// 当前 App 版本号。
  var appVersion: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "2.0.3"
  }

  /// 请求 `/stream-info` 时附加的客户端设备上下文请求头。
  func clientHeaders() -> [String: String] {
    [
      "X-MP-Client-Id": clientID,
      "X-MP-Device-Name": deviceName,
      "X-MP-Platform": "iOS",
      "X-MP-App-Version": appVersion,
    ]
  }

  /// 按串行队列提交一条播放进度或会话状态，不取消已在途的暂停/停止请求。
  func enqueueReport(
    client: MediaPlaybackClient,
    itemId: String,
    server: String,
    mediaSourceId: String?,
    decision: PlaybackSyncDecision,
    playSessionId: String?,
    durationMs: Int?,
    playMethod: String = "DirectPlay",
    audioStreamIndex: Int? = nil,
    subtitleStreamIndex: Int? = nil
  ) {
    guard !server.isEmpty, !itemId.isEmpty, !itemId.hasPrefix("file."), !itemId.hasPrefix("file:") else {
      return
    }
    let cid = clientID
    let dev = deviceName
    let ver = appVersion
    let isStop = decision.state == "stopped"
    let backgroundLease = isStop ? PlaybackBackgroundTaskLease(name: "MoviePilot.PlaybackStop") : nil

    let previous = serialTailTask
    let task = Task { [weak self] in
      await previous?.value
      let ok = await client.reportProgress(
        itemId: itemId,
        server: server,
        mediaSourceId: mediaSourceId,
        positionMs: Int(decision.positionMs),
        durationMs: durationMs,
        isPaused: decision.isPaused,
        state: decision.state,
        eventName: decision.eventName,
        playSessionId: playSessionId,
        clientId: cid,
        deviceName: dev,
        platform: "iOS",
        appVersion: ver,
        playMethod: playMethod,
        playbackTimeMs: Int(decision.playbackTimeMs),
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        seq: Int(decision.seq)
      )
      await MainActor.run {
        if isStop {
          if ok {
            NotificationCenter.default.post(
              name: .moviePilotPlaybackDidStop,
              object: nil,
              userInfo: ["server": server, "itemId": itemId]
            )
          } else {
            self?.recordPendingStop(
              PendingPlaybackStop(
                server: server,
                itemId: itemId,
                mediaSourceId: mediaSourceId,
                positionMs: decision.positionMs,
                durationMs: durationMs.map(Int64.init),
                playSessionId: playSessionId,
                playbackTimeMs: decision.playbackTimeMs,
                seq: decision.seq,
                updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
              )
            )
          }
          backgroundLease?.end()
        }
      }
    }
    serialTailTask = task
  }

  /// 在网络恢复或下次起播时补报此前离线失败的终态 `stopped` 进度记录。
  func flushPendingStops(using client: MediaPlaybackClient) {
    let pending = loadPendingStops()
    guard !pending.isEmpty else { return }
    let cid = clientID
    let dev = deviceName
    let ver = appVersion
    let previous = serialTailTask
    let task = Task { [weak self] in
      await previous?.value
      var remaining: [PendingPlaybackStop] = []
      var flushedAny = false
      for entry in pending {
        let ok = await client.reportProgress(
          itemId: entry.itemId,
          server: entry.server,
          mediaSourceId: entry.mediaSourceId,
          positionMs: Int(entry.positionMs),
          durationMs: entry.durationMs.map(Int.init),
          isPaused: true,
          state: "stopped",
          eventName: nil,
          playSessionId: entry.playSessionId,
          clientId: cid,
          deviceName: dev,
          platform: "iOS",
          appVersion: ver,
          playMethod: "DirectPlay",
          playbackTimeMs: entry.playbackTimeMs.map(Int.init),
          audioStreamIndex: nil,
          subtitleStreamIndex: nil,
          seq: entry.seq.map(Int.init)
        )
        if ok {
          flushedAny = true
        } else {
          remaining.append(entry)
        }
      }
      await MainActor.run {
        self?.savePendingStops(remaining)
        if flushedAny {
          NotificationCenter.default.post(name: .moviePilotPlaybackDidStop, object: nil)
        }
      }
    }
    serialTailTask = task
  }

  private func loadPendingStops() -> [PendingPlaybackStop] {
    guard let data = UserDefaults.standard.data(forKey: Self.pendingStopsKey),
      let decoded = try? JSONDecoder().decode([PendingPlaybackStop].self, from: data)
    else { return [] }
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    return PlaybackProgressPlanner.normalizePendingStops(decoded, nowEpochMs: nowMs)
  }

  private func savePendingStops(_ entries: [PendingPlaybackStop]) {
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let normalized = PlaybackProgressPlanner.normalizePendingStops(entries, nowEpochMs: nowMs)
    if normalized.isEmpty {
      UserDefaults.standard.removeObject(forKey: Self.pendingStopsKey)
    } else if let data = try? JSONEncoder().encode(normalized) {
      UserDefaults.standard.set(data, forKey: Self.pendingStopsKey)
    }
  }

  private func recordPendingStop(_ stop: PendingPlaybackStop) {
    var existing = loadPendingStops()
    existing.append(stop)
    savePendingStops(existing)
  }
}

/// 媒体服务器账号绑定请求错误。
enum MediaServerAccountBindingError: LocalizedError {
  case unauthorized
  case message(String)

  var errorDescription: String? {
    switch self {
    case .unauthorized:
      return "登录已过期，请重新登录。"
    case .message(let text):
      return text
    }
  }
}

/// 媒体服务器账号绑定专用客户端：支持任意服务器名称（含中文/空格）安全编码，绝不本地持久化密码或令牌。
@MainActor
enum MediaServerAccountBindingClient {
  private struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let message: String?
    let data: Value?
  }

  private struct DetailErrorBody: Decodable, Sendable {
    let detail: String?
    let message: String?
  }

  private static func makeSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.httpCookieStorage = nil
    cfg.httpShouldSetCookies = false
    cfg.urlCache = nil
    cfg.timeoutIntervalForRequest = 20
    return URLSession(configuration: cfg)
  }

  private static func buildURL(address: ServerAddress, segments: [String]) throws -> URL {
    var url = address.url.appendingPathComponent("api", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true)
    for segment in segments {
      guard !segment.isEmpty, segment != ".", segment != "..", !segment.contains("/"),
        !segment.contains("\\")
      else {
        throw MediaServerAccountBindingError.message("媒体服务器名称格式无效")
      }
      url.appendPathComponent(segment, isDirectory: false)
    }
    guard address.contains(url) else {
      throw MediaServerAccountBindingError.message("目标地址超出当前服务范围")
    }
    return url
  }

  private static func parseErrorMessage(from data: Data, fallback: String) -> String {
    if let parsed = try? JSONDecoder().decode(DetailErrorBody.self, from: data) {
      if let detail = parsed.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
        !detail.isEmpty
      {
        return detail
      }
      if let message = parsed.message?.trimmingCharacters(in: .whitespacesAndNewlines),
        !message.isEmpty
      {
        return message
      }
    }
    return fallback
  }

  static func listBindings(session: NativeSession) async throws -> [MediaServerAccountBindingDTO] {
    let auth = try session.playbackAuthorization()
    let url = try buildURL(address: auth.address, segments: ["mediaserver", "account-bindings"])
    var request = URLRequest(url: url)
    request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await makeSession().data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw MediaServerAccountBindingError.message("无法连接服务器")
    }
    if http.statusCode == 401 || (http.statusCode == 403 && APIClient.isTokenInvalidForbiddenBody(data)) {
      session.handleExternalUnauthorized()
      throw MediaServerAccountBindingError.unauthorized
    }
    guard (200..<300).contains(http.statusCode) else {
      throw MediaServerAccountBindingError.message(
        parseErrorMessage(from: data, fallback: "加载媒体服务器账号绑定失败"))
    }
    let decoder = JSONDecoder()
    if let envelope = try? decoder.decode(Envelope<[MediaServerAccountBindingDTO]>.self, from: data),
      envelope.success
    {
      return envelope.data ?? []
    }
    if let direct = try? decoder.decode([MediaServerAccountBindingDTO].self, from: data) {
      return direct
    }
    throw MediaServerAccountBindingError.message("媒体服务器绑定响应格式异常")
  }

  static func bind(
    session: NativeSession,
    server: String,
    username: String?,
    password: String?,
    token: String?
  ) async throws -> MediaServerAccountBindingDTO {
    let auth = try session.playbackAuthorization()
    let url = try buildURL(address: auth.address, segments: ["mediaserver", "account-bindings"])
    var payload: [String: String] = ["server": server]
    if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
      payload["token"] = token
    } else {
      if let username = username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
        payload["username"] = username
      }
      if let password, !password.isEmpty {
        payload["password"] = password
      }
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (data, response) = try await makeSession().data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw MediaServerAccountBindingError.message("无法连接服务器")
    }
    if http.statusCode == 401 || (http.statusCode == 403 && APIClient.isTokenInvalidForbiddenBody(data)) {
      session.handleExternalUnauthorized()
      throw MediaServerAccountBindingError.unauthorized
    }
    guard (200..<300).contains(http.statusCode) else {
      throw MediaServerAccountBindingError.message(
        parseErrorMessage(from: data, fallback: "媒体服务器账号验证失败，请检查凭据"))
    }
    let envelope = try JSONDecoder().decode(Envelope<MediaServerAccountBindingDTO>.self, from: data)
    guard envelope.success, let updated = envelope.data else {
      throw MediaServerAccountBindingError.message(envelope.message ?? "绑定媒体服务器账号失败")
    }
    return updated
  }

  static func unbind(session: NativeSession, server: String) async throws {
    let auth = try session.playbackAuthorization()
    let url = try buildURL(address: auth.address, segments: ["mediaserver", "account-bindings", server])
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await makeSession().data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw MediaServerAccountBindingError.message("无法连接服务器")
    }
    if http.statusCode == 401 || (http.statusCode == 403 && APIClient.isTokenInvalidForbiddenBody(data)) {
      session.handleExternalUnauthorized()
      throw MediaServerAccountBindingError.unauthorized
    }
    guard (200..<300).contains(http.statusCode) else {
      throw MediaServerAccountBindingError.message(
        parseErrorMessage(from: data, fallback: "解绑媒体服务器账号失败"))
    }
  }
}
