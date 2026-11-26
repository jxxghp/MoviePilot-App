import Foundation

/// 用户管理完整更新载荷：仅覆盖表单编辑项，保留 OTP、资料和未知细粒度权限。
public enum UserManagementPayload {
  /// 合并编辑字段；不回传只读用户元数据，也不以空密码覆盖既有密码。
  public static func merging(
    original: [String: JSONValue], edits: [String: JSONValue]
  ) -> [String: JSONValue] {
    let preservedKeys = [
      "id", "name", "email", "avatar", "is_active", "is_superuser", "is_otp", "settings",
      "permissions",
    ]
    var result = original.filter { preservedKeys.contains($0.key) }
    for (key, value) in edits {
      if key == "permissions", case .object(let changed) = value {
        var permissions: [String: JSONValue] = [:]
        if case .object(let existing) = original[key] { permissions = existing }
        permissions.merge(changed) { _, new in new }
        result[key] = .object(permissions)
      } else {
        result[key] = value
      }
    }
    return result
  }
}
