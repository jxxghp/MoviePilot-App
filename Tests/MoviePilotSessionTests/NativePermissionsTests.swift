import Foundation
import MoviePilotAPI
import Testing

@testable import MoviePilotSession

/// 原生权限逐项对照既有用户/功能契约，不访问后端或使用真实账号。
struct NativePermissionsTests {
  /// 历史空权限保留三类普通功能，管理和管理员仍默认关闭。
  @Test func preservesLegacyDefaults() throws {
    let permissions = try JSONDecoder().decode(NativePermissions.self, from: Data("{}".utf8))
    let user = try SessionUser(id: 1, name: "reader", isSuperuser: false, permissions: permissions)
    for category in [NativePermission.discovery, .search, .subscribe] {
      #expect(user.allows(PermissionRequirement(category: category)))
    }
    #expect(!user.allows(PermissionRequirement(category: .manage)))
    #expect(!user.allows(PermissionRequirement(category: .admin)))
    #expect(user.allows(PermissionRequirement(feature: "future.feature")))
  }

  /// permissions.admin、truthy 字符串和功能开关不能绕过分类或管理员身份。
  @Test func refusesPermissionEscalation() throws {
    let data = Data(
      #"{"admin":true,"manage":"true","search":false,"features":{"search.resource":true,"extra":"false"}}"#
        .utf8)
    let permissions = try JSONDecoder().decode(NativePermissions.self, from: data)
    let user = try SessionUser(id: 1, name: "reader", isSuperuser: false, permissions: permissions)
    #expect(!user.allows(PermissionRequirement(category: .admin)))
    #expect(!user.allows(PermissionRequirement(category: .manage)))
    #expect(!user.allows(PermissionRequirement(category: .search, feature: "search.resource")))
    #expect(permissions.features["extra"] == nil)
  }

  /// 明确禁用功能覆盖分类允许，null 与缺省分类继续使用历史默认值。
  @Test func narrowsFeaturesWithoutChangingDefaults() throws {
    let data = Data(
      #"{"search":null,"features":{"search.resource":false,"plugin.Example.main":false}}"#.utf8)
    let permissions = try JSONDecoder().decode(NativePermissions.self, from: data)
    let user = try SessionUser(id: 1, name: "reader", isSuperuser: false, permissions: permissions)
    #expect(user.allows(PermissionRequirement(category: .search)))
    #expect(!user.allows(PermissionRequirement(category: .search, feature: "search.resource")))
    #expect(!user.allows(.plugin(id: "Example")))
    #expect(user.allows(.plugin(id: "Example_clone")))
  }

  /// 超级管理员由服务器字段决定，覆盖普通分类和功能开关。
  @Test func grantsAdministratorOnlyFromServerIdentity() throws {
    let user = try SessionUser(
      id: 1, name: "administrator", isSuperuser: true,
      permissions: NativePermissions(
        discovery: false, search: false, subscribe: false,
        features: ["search.resource": false]))
    for category in NativePermission.allCases {
      #expect(user.allows(PermissionRequirement(category: category, feature: "search.resource")))
    }
  }

  /// 非法用户 ID、名称、等级不能进入会话；非布尔 features 不变成禁用或授权。
  @Test func validatesIdentityAndMalformedFeatures() throws {
    #expect(throws: APIError.invalidResponse) {
      try SessionUser(id: -1, name: "reader", isSuperuser: false)
    }
    #expect(throws: APIError.invalidResponse) {
      try SessionUser(id: 1, name: "", isSuperuser: false)
    }
    #expect(throws: APIError.invalidResponse) {
      try SessionUser(id: 1, name: "reader", isSuperuser: false, level: -1)
    }
    let data = Data(#"{"features":[false]}"#.utf8)
    let permissions = try JSONDecoder().decode(NativePermissions.self, from: data)
    #expect(permissions.features.isEmpty && permissions.search)
  }
}
