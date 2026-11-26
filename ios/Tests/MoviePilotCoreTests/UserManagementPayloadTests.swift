import Foundation
import Testing

@testable import MoviePilotCore

/// 用户管理回归：编辑邮箱和分类权限不得清除安全字段或细粒度限制。
struct UserManagementPayloadTests {
  /// 使用真实后端用户结构，校验完整更新所需的未编辑字段和未知权限被保留。
  @Test func preservesUneditedSecurityAndProfile() throws {
    let original = try JSONDecoder().decode(
      [String: JSONValue].self,
      from: Data(
        """
        {"id":7,"name":"member","email":"old@example.test","is_otp":true,"avatar":"synthetic-avatar",
         "settings":{"theme":"dark"},"permissions":{"discovery":true,"features":{"plugin.demo.main":false}},
         "created_at":"read-only","hashed_password":"never-return-this"}
        """.utf8))
    let result = UserManagementPayload.merging(
      original: original,
      edits: [
        "email": .string("new@example.test"), "permissions": .object(["discovery": .bool(false)]),
      ])
    #expect(result["email"] == .string("new@example.test"))
    for key in ["id", "name", "is_otp", "avatar", "settings"] {
      #expect(result[key] == original[key])
    }
    #expect(
      result["permissions"]
        == .object([
          "discovery": .bool(false), "features": .object(["plugin.demo.main": .bool(false)]),
        ]))
    #expect(result["hashed_password"] == nil)
    #expect(result["created_at"] == nil)
    #expect(result["password"] == nil)
  }

  /// 显式清空和新密码仍能提交，新增账号不需要虚构原始快照。
  @Test func acceptsExplicitChangesAndCreation() {
    let edits: [String: JSONValue] = [
      "name": .string("new-member"), "email": .null, "password": .string("synthetic"),
    ]
    #expect(UserManagementPayload.merging(original: [:], edits: edits) == edits)
  }
}
