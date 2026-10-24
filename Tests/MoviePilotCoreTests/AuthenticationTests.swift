import Foundation
import Testing

@testable import MoviePilotCore

/// 原生认证与既有网页持久化契约的边界测试，不访问真实账号或网络。
struct AuthenticationTests {
  /// 登录的原始响应必须映射到现有 store，同时保持细粒度权限。
  @Test func mapsLoginResponse() throws {
    let data = Data(
      #"{"access_token":"test.token.value","super_user":false,"user_id":3,"user_name":"测试用户","avatar":null,"permissions":{"manage":false,"search":true},"level":2}"#
        .utf8)
    let session = try AuthenticationSession(loginData: data)
    guard case .object(let stores) = session.browserStorage,
      case .object(let user) = stores["user"], case .object(let auth) = stores["auth"]
    else {
      Issue.record("缺少现有 store 字段")
      return
    }
    #expect(user["userID"] == .number(3))
    #expect(user["superUser"] == .bool(false))
    #expect(user["avatar"] == .string(""))
    #expect(auth["token"] == .string("test.token.value"))
    #expect(user["permissions"] == .object(["manage": .bool(false), "search": .bool(true)]))
  }

  /// 恢复使用 current 用户的最新权限，失败响应和无效身份不能被视为登录成功。
  @Test func validatesRestoredIdentity() throws {
    let data = Data(
      #"{"success":true,"data":{"id":3,"name":"reader","is_superuser":false,"permissions":{"search":false}}}"#
        .utf8)
    let session = try AuthenticationSession(accessToken: "test.token.value", currentUserData: data)
    guard case .object(let user) = session.user else {
      Issue.record("缺少用户")
      return
    }
    #expect(user["permissions"] == .object(["search": .bool(false)]))
    #expect(throws: (any Error).self) {
      try AuthenticationSession(loginData: Data(#"{"success":false,"data":{}}"#.utf8))
    }
    #expect(throws: (any Error).self) {
      try AuthenticationSession(
        loginData: Data(
          #"{"access_token":"","super_user":true,"user_id":1,"user_name":"admin"}"#.utf8))
    }
  }

  /// 已认证用户重新打开 App 后保留签发等级，current 的最新权限仍覆盖令牌中的旧权限。
  @Test func preservesVerifiedTokenLevelOnRestore() throws {
    let claims = Data(#"{"level":2,"permissions":{"search":true}}"#.utf8)
      .base64EncodedString().replacingOccurrences(of: "=", with: "")
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    let data = Data(
      #"{"id":3,"name":"reader","is_superuser":false,"permissions":{"search":false}}"#.utf8)
    let session = try AuthenticationSession(
      accessToken: "header.\(claims).signature", currentUserData: data)
    guard case .object(let user) = session.user else {
      Issue.record("缺少恢复用户")
      return
    }
    #expect(user["level"] == .number(2))
    #expect(user["permissions"] == .object(["search": .bool(false)]))
  }

  /// 表单中的特殊字符不会成为新的参数，验证码保持原值。
  @Test func encodesPasswordForm() {
    let body = AuthenticationSession.passwordForm(
      username: "甲+a&b", password: "p=1&+%", otp: "012345")
    let text = String(decoding: body, as: UTF8.self)
    #expect(text.contains("password=p%3D1%26%2B%25"))
    #expect(text.contains("otp_password=012345"))
    #expect(text.components(separatedBy: "&").count == 3)
  }

  /// 真实服务会在认证结果中携带内嵌头像，不应误用导航桥的较小消息限制。
  @Test func acceptsExistingInlineAvatar() throws {
    let avatar = "data:image/png;base64," + String(repeating: "A", count: 700_000)
    let data = try JSONSerialization.data(withJSONObject: [
      "access_token": "test.token.value", "super_user": true, "user_id": 1,
      "user_name": "tester", "avatar": avatar,
    ])
    let session = try AuthenticationSession(loginData: data)
    guard case .object(let user) = session.user else {
      Issue.record("缺少用户")
      return
    }
    #expect(user["avatar"] == .string(avatar))
    #expect(throws: (any Error).self) {
      try AuthenticationSession(
        loginData: Data(repeating: 32, count: AuthenticationSession.maximumResponseBytes + 1))
    }
  }
}
