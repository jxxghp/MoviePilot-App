import AuthenticationServices
import MoviePilotCore
import UIKit

/// 系统认证窗口独属于当前登录事务，完成、取消和过期都只交付一次结果。
@MainActor
final class PasskeyAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let anchor: ASPresentationAnchor
  private var session: ASWebAuthenticationSession?
  private var continuation: CheckedContinuation<URL, Error>?
  private var expiry: Task<Void, Never>?
  private var started = false

  /// 使用发起登录的窗口，避免多场景下把验证提示显示到另一个实例。
  init(anchor: ASPresentationAnchor) {
    self.anchor = anchor
  }

  /// 明确点击后打开临时系统认证会话，页面载入后自动申请一次通行密钥。
  func authenticate(url: URL) async throws -> URL {
    guard !started else { throw PasskeyFailure.invalid }
    started = true
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let completion: ASWebAuthenticationSession.CompletionHandler = {
          [weak self] callback, error in
          Task { @MainActor in
            guard let self else { return }
            if let error {
              let failure: PasskeyFailure =
                (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                ? .canceled : .failed
              self.finish(.failure(failure))
            } else if let callback {
              self.finish(.success(callback))
            } else {
              self.finish(.failure(PasskeyFailure.invalid))
            }
          }
        }
        let session: ASWebAuthenticationSession
        if #available(iOS 17.4, *) {
          session = ASWebAuthenticationSession(
            url: url, callback: .customScheme("moviepilot"), completionHandler: completion)
        } else {
          session = ASWebAuthenticationSession(
            url: url, callbackURLScheme: "moviepilot", completionHandler: completion)
        }
        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = self
        self.session = session
        expiry = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(120)) } catch { return }
          self?.finish(.failure(PasskeyFailure.expired))
        }
        if !session.start() { finish(.failure(PasskeyFailure.failed)) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancel() }
    }
  }

  /// 离开或切换实例时关闭系统窗口，并解除挂起的登录任务。
  func cancel() { finish(.failure(PasskeyFailure.canceled)) }

  /// 系统提示绑定原生登录所在的实际窗口。
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    anchor
  }

  /// 先封闭 continuation 再关闭窗口，忽略系统取消回调和任务取消的竞态。
  private func finish(_ result: Result<URL, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    expiry?.cancel()
    expiry = nil
    session?.cancel()
    session = nil
    continuation.resume(with: result)
  }
}
