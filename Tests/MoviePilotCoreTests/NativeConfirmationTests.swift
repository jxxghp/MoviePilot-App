import Foundation
import Testing

@testable import MoviePilotCore

/// 系统确认协议保留多行纯文字，同时约束大小、身份和导航互锁。
struct NativeConfirmationTests {
  /// 普通旧快照继续解码，多行正文不会被当成简短标题拒绝。
  @Test func acceptsOptionalConfirmationAndMultilineMessage() throws {
    let old = try snapshot(confirmation: nil)
    try old.validate()
    #expect(old.presentation?.confirmation == nil)
    let current = try snapshot(confirmation: confirmation(message: "第一行\n第二行\t详情"))
    try current.validate()
    #expect(current.presentation?.confirmation?.message == "第一行\n第二行\t详情")
    #expect(current.presentation?.confirmation?.destructive == true)
  }

  /// 超大正文、控制字符、伪造标识和没有模态互锁的声明都不能进入 UIKit。
  @Test func rejectsInvalidConfirmation() throws {
    for message in [String(repeating: "字", count: 2731), "内容\u{0}控制符"] {
      let value = try snapshot(confirmation: confirmation(message: message))
      #expect(throws: BridgeError.invalidMessage) { try value.validate() }
    }
    var invalid = confirmation(message: "普通正文")
    invalid["id"] = "invalid\nidentifier"
    let identity = try snapshot(confirmation: invalid)
    #expect(throws: BridgeError.invalidMessage) { try identity.validate() }
    let unlocked = try snapshot(confirmation: confirmation(message: "正文"), overlayOpen: false)
    #expect(throws: BridgeError.invalidMessage) { try unlocked.validate() }
  }

  /// 模拟前端稳定 ID 与普通纯文字，不含业务脚本或确认回调。
  private func confirmation(message: String) -> [String: Any] {
    [
      "id": "confirmation-1", "title": "确认删除？", "message": message,
      "confirmText": "删除", "cancelText": "保留", "confirmEnabled": true,
      "cancelEnabled": true, "destructive": true,
    ]
  }

  /// 通过真实跨桥 JSON 验证可选字段，避免测试直接构造绕过解码约束。
  private func snapshot(confirmation: [String: Any]?, overlayOpen: Bool = true) throws
    -> NavigationSnapshot
  {
    var presentation: [String: Any] = ["overlayOpen": overlayOpen]
    presentation["confirmation"] = confirmation
    let object: [String: Any] = [
      "route": ["fullPath": "/dashboard", "title": "仪表盘", "canGoBack": false],
      "roots": [], "actions": [], "presentation": presentation,
      "chrome": ["topVisible": true, "bottomVisible": true, "theme": "dark"],
    ]
    return try JSONDecoder().decode(
      NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
