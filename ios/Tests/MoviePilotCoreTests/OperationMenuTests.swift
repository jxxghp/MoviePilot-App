import Foundation
import Testing

@testable import MoviePilotCore

/// 从真实 JSON 边界验证原菜单树；不以直接构造对象绕过解码或大小约束。
struct OperationMenuTests {
  /// 独立菜单保留副标题与状态徽标，不能把数量状态丢弃或并入主标题。
  @Test func preservesStandaloneBadges() throws {
    let menu = try decode(
      [
        action(
          "passkey", title: "通行密钥",
          extra: [
            "subtitle": "无密码登录", "badge": ["title": "2 个密钥", "color": "success"],
          ])
      ], extra: ["kind": "standalone"])
    try menu.validate()
    #expect(menu.kind == .standalone)
    #expect(menu.items[0].title == "通行密钥")
    #expect(menu.items[0].subtitle == "无密码登录")
    #expect(menu.items[0].badge?.title == "2 个密钥")
    #expect(menu.items[0].badge?.color == .success)
    #expect(
      try JSONDecoder().decode(OperationMenuSnapshot.self, from: JSONEncoder().encode(menu)) == menu
    )
  }

  /// 空白、越界和控制字符状态整体拒绝；未知色也必须在 Codable 边界拒绝。
  @Test func rejectsInvalidBadges() throws {
    for title in ["", "  ", String(repeating: "a", count: 257), "启用\u{1}"] {
      let menu = try decode([action("passkey", extra: ["badge": ["title": title]])])
      #expect(throws: BridgeError.invalidMessage) { try menu.validate() }
    }
    #expect(throws: DecodingError.self) {
      try decode([action("passkey", extra: ["badge": ["title": "启用", "color": "raw-css"]])])
    }
    let menu = try decode([
      action("passkey"), ["id": "divider", "kind": "separator", "badge": ["title": "隐藏状态"]],
    ])
    #expect(throws: BridgeError.invalidMessage) { try menu.validate() }
  }

  /// 子菜单、语义色、顺序、分隔、选中和保留菜单语义均保留在纯展示声明中。
  @Test func preservesMenuTreeAndStates() throws {
    let menu = try decode([
      action("edit", title: "编辑", extra: ["icon": "mdi-file-edit-outline", "color": "info"]),
      ["id": "divider", "kind": "separator"],
      [
        "id": "advanced", "kind": "submenu", "title": "高级操作",
        "items": [
          [
            "id": "group", "kind": "group", "title": "分组",
            "items": [
              action("delete", title: "删除", extra: ["color": "error", "destructive": true]),
              action("pin", title: "置顶", extra: ["selected": true, "keepOpen": true]),
            ],
          ]
        ],
      ],
    ])
    try menu.validate()
    #expect(menu.items.map(\.id) == ["edit", "divider", "advanced"])
    #expect(menu.availableAction(id: "delete")?.destructive == true)
    #expect(menu.availableAction(id: "pin")?.selected == true)
    #expect(menu.availableAction(id: "pin")?.keepOpen == true)
    #expect(menu.availableAction(id: "advanced") == nil)
    #expect(menu.availableAction(id: "missing") == nil)
  }

  /// 原生复核父项禁用或加载，不能因为伪造子项 enabled=true 就放行业务选择。
  @Test(arguments: ["enabled", "loading"])
  func inheritsUnavailableParent(field: String) throws {
    let menu = try decode([
      [
        "id": "advanced", "kind": "submenu", "title": "高级操作",
        field: field == "loading", "items": [action("edit", extra: ["enabled": true])],
      ]
    ])
    try menu.validate()
    #expect(menu.availableAction(id: "edit") == nil)
  }

  /// 单项的加载和禁用同样阻止选择，未声明 enabled 的旧式动作保持可用。
  @Test func blocksDisabledAndLoadingActions() throws {
    let menu = try decode([
      action("disabled", extra: ["enabled": false]), action("loading", extra: ["loading": true]),
      action("default"),
    ])
    try menu.validate()
    #expect(menu.availableAction(id: "disabled") == nil)
    #expect(menu.availableAction(id: "loading") == nil)
    #expect(menu.availableAction(id: "default")?.id == "default")
  }

  /// 标识在整棵树中唯一；跨层重复也必须拒绝整份菜单。
  @Test func rejectsDuplicateIdentifiers() throws {
    let menu = try decode([
      action("edit"),
      ["id": "advanced", "kind": "submenu", "title": "高级操作", "items": [action("edit")]],
    ])
    #expect(throws: BridgeError.invalidMessage) { try menu.validate() }
  }

  /// 空菜单、孤立分隔条、空子菜单及动作携带 children 都不能被部分展示。
  @Test func rejectsIncompleteStructures() throws {
    let invalid: [[[String: Any]]] = [
      [], [["id": "divider", "kind": "separator"]],
      [["id": "empty", "kind": "submenu", "title": "更多", "items": []]],
      [action("edit", extra: ["items": []])],
      [action("edit"), ["id": "divider", "kind": "separator", "title": "伪装动作"]],
      [
        action("edit"),
        ["id": "empty", "kind": "group", "items": [["id": "divider", "kind": "separator"]]],
      ],
    ]
    for rows in invalid {
      let menu = try decode(rows)
      #expect(throws: BridgeError.invalidMessage) { try menu.validate() }
    }
  }

  /// 数量和深度超过前端共享上限时整份拒绝，不截掉尾部可能存在的危险动作。
  @Test func enforcesCountAndDepth() throws {
    let boundary = try decode((0..<96).map { action("item-\($0)") })
    try boundary.validate()
    let excessive = try decode((0..<97).map { action("item-\($0)") })
    #expect(throws: BridgeError.invalidMessage) { try excessive.validate() }
    var rows = [action("nested")]
    for depth in 0..<3 {
      rows = [["id": "level-\(depth)", "kind": "submenu", "title": "更多", "items": rows]]
    }
    let deep = try decode(rows)
    #expect(throws: BridgeError.invalidMessage) { try deep.validate() }
  }

  /// 中文按字节计数，格式字符和控制字符也不能混进标题、图标或副标题。
  @Test func enforcesTextLimits() throws {
    for title in ["", "  ", "操作\n混入", "操作\u{200b}隐藏", String(repeating: "字", count: 683)] {
      let menu = try decode([action("edit", title: title)])
      #expect(throws: BridgeError.invalidMessage) { try menu.validate() }
    }
    for extra in [["icon": String(repeating: "a", count: 257)], ["subtitle": "副标题\u{0}"]] {
      let menu = try decode([action("edit", extra: extra)])
      #expect(throws: BridgeError.invalidMessage) { try menu.validate() }
    }
  }

  /// 单项合法仍需校验整份 UTF-8 展示长度；不能借助很多短项目绕过 24 KB 限额。
  @Test func boundsTotalDisplayBytes() throws {
    let menu = try decode(
      (0..<20).map { action("item-\($0)", title: String(repeating: "字", count: 600)) })
    #expect(throws: BridgeError.invalidMessage) { try menu.validate() }
  }

  /// owner/menu/展示标识和来源枚举来自显式契约，未知值不能进入系统交互。
  @Test func rejectsInvalidEnvelopeIdentity() throws {
    for field in ["ownerId", "menuId", "presentationId"] {
      let menu = try decode([action("edit")], extra: [field: "invalid\nidentifier"])
      #expect(throws: BridgeError.invalidMessage) { try menu.validate() }
    }
    #expect(throws: DecodingError.self) {
      try decode([action("edit")], extra: ["kind": "arbitrary"])
    }
    #expect(throws: DecodingError.self) { try decode([action("edit", extra: ["kind": "script"])]) }
    #expect(throws: DecodingError.self) {
      try decode([action("edit", extra: ["color": "#ff0000"])])
    }
  }

  /// 对照前端投影字段生成合成动作，不加入业务接口、认证或闭包。
  private func action(_ id: String, title: String = "操作", extra: [String: Any] = [:]) -> [String:
    Any]
  {
    ["id": id, "kind": "action", "title": title].merging(extra) { _, new in new }
  }

  /// 使用 JSONDecoder 经过与桥消息一致的 Codable 边界，再由调用方显式校验。
  private func decode(_ items: [[String: Any]], extra: [String: Any] = [:]) throws
    -> OperationMenuSnapshot
  {
    let object: [String: Any] = [
      "ownerId": "card-1", "menuId": "operations", "presentationId": "menu-1", "kind": "card",
      "title": "媒体名称", "items": items,
    ].merging(extra) { _, new in new }
    return try JSONDecoder().decode(
      OperationMenuSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
