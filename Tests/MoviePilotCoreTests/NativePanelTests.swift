import Foundation
import Testing

@testable import MoviePilotCore

/// 系统面板只接受有界展示声明，兼容旧网页且拒绝恶意层级与重复标识。
struct NativePanelTests {
  /// 账号信息有独立展示边界，大型或非栅格内联内容不能占满跨桥消息。
  @Test func validatesProfileSummaryAndThumbnail() throws {
    let accepted: [String] = [
      "https://image.example/avatar.png", "data:image/jpeg;base64,/9j/2Q==",
    ]
    let rejected = [
      "data:image/svg+xml,<svg/>", "file:///tmp/avatar.png",
      "https://user:pass@example/avatar.png", "data:image/jpeg;base64,not-a-base64",
      "data:image/jpeg;base64," + String(repeating: "a", count: 8192),
    ]
    for image in accepted + rejected {
      let value = try snapshot(panel: [
        "title": "用户菜单", "profile": ["name": "MoviePilot", "detail": "管理员", "image": image],
        "sections": [],
      ])
      if accepted.contains(image) {
        try value.validate()
        #expect(value.actions[0].panel?.profile?.name == "MoviePilot")
      } else {
        #expect(throws: BridgeError.invalidMessage) { try value.validate() }
      }
    }
  }

  /// 新声明优先，旧全局标识保持兼容，相似的页面标识不能误入常用入口。
  @Test func separatesGlobalActionsFromPageRegistrations() throws {
    /// 从跨桥 JSON 解码，覆盖旧版省略范围字段的真实兼容路径。
    func decode(_ id: String, scope: String? = nil) throws -> ActionSnapshot {
      var object: [String: Any] = [
        "actionId": id, "ownerId": "current", "title": "操作", "icon": "apps",
        "position": "trailing", "enabled": true, "loading": false,
      ]
      object["scope"] = scope
      return try JSONDecoder().decode(
        ActionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    #expect(try decode("r8:global:search").isGlobal)
    #expect(try decode("new-search", scope: "global").isGlobal)
    #expect(try !decode("r8:global:search", scope: "page").isGlobal)
    #expect(try !decode("r8:page-global:search").isGlobal)
    #expect(try !decode("r8:global:page:refresh").isGlobal)
    #expect(try !decode("r8:header:0").isGlobal)
  }

  /// 用真实 JSON 解码构造当前导航快照，覆盖 Codable 到校验的完整边界。
  private func snapshot(panel: [String: Any], chrome: [String: Any] = [:]) throws
    -> NavigationSnapshot
  {
    let object: [String: Any] = [
      "route": ["fullPath": "/apps", "title": "更多", "canGoBack": false],
      "roots": [],
      "actions": [
        [
          "actionId": "profile", "ownerId": "current", "title": "用户菜单", "icon": "profile",
          "position": "trailing", "enabled": true, "loading": false, "panel": panel,
        ]
      ],
      "chrome": ["topVisible": true, "bottomVisible": true, "theme": "light"].merging(chrome) {
        _, new in new
      },
      "presentation": ["overlayOpen": true, "fullscreen": false],
    ]
    return try JSONDecoder().decode(
      NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
  }

  /// 普通菜单声明保留底栏，子项和搜索只包含纯展示数据。
  @Test func acceptsNativePanelAndIndependentFullscreenState() throws {
    let value = try snapshot(
      panel: [
        "title": "用户菜单", "search": ["text": "", "placeholder": "搜索"],
        "sections": [
          [
            "id": "appearance",
            "items": [
              [
                "id": "theme", "title": "主题",
                "children": [["id": "glass", "title": "玻璃设置", "selected": true]],
              ]
            ],
          ]
        ],
      ], chrome: ["backgroundColor": "#F0F2F8", "surfaceColor": "#FFFFFF"])
    try value.validate()
    #expect(value.presentation?.overlayOpen == true)
    #expect(value.presentation?.fullscreen == false)
    #expect(value.actions.first?.panel?.sections.first?.items.first?.children?.first?.id == "glass")
  }

  /// 跨组重复标识、过深菜单、过量行和控制文本都必须拒绝。
  @Test func rejectsAmbiguousOrUnboundedPanelRows() throws {
    let row: [String: Any] = ["id": "one", "title": "菜单"]
    let cases: [[[String: Any]]] = [
      [row, row],
      [
        [
          "id": "a", "title": "一",
          "children": [
            [
              "id": "b", "title": "二",
              "children": [["id": "c", "title": "三", "children": [["id": "d", "title": "四"]]]],
            ]
          ],
        ]
      ],
      (0..<97).map { ["id": "row-\($0)", "title": "菜单"] },
      [["id": "one", "title": "菜单\n脚本"]],
      [["id": "one", "title": "菜单", "subtitle": String(repeating: "长", count: 1000)]],
    ]
    for rows in cases {
      let value = try snapshot(panel: [
        "title": "面板", "sections": [["id": "group", "items": rows]],
      ])
      #expect(throws: BridgeError.invalidMessage) { try value.validate() }
    }
  }

  /// 背景颜色与强调色一样采用封闭格式，不能成为 CSS 或动态代码入口。
  @Test func rejectsThemeInstructions() throws {
    for key in ["backgroundColor", "surfaceColor"] {
      let value = try snapshot(
        panel: ["title": "面板", "sections": []], chrome: [key: "#FFFFFF; display:none"])
      #expect(throws: BridgeError.invalidMessage) { try value.validate() }
    }
  }

  /// 海报声明不能变成本机文件或含凭据的通用 URL 入口。
  @Test func validatesPosterReferences() throws {
    for image in ["https://image.example/poster.jpg", "http://127.0.0.1/poster.png"] {
      let value = try snapshot(panel: [
        "title": "通知",
        "sections": [["id": "media", "items": [["id": "one", "title": "入库", "image": image]]]],
      ])
      try value.validate()
    }
    for image in [
      "file:///tmp/poster.png", "javascript:alert(1)", "https://user:pass@example/a",
      "https://example/\nposter",
    ] {
      let value = try snapshot(panel: [
        "title": "通知",
        "sections": [["id": "media", "items": [["id": "one", "title": "入库", "image": image]]]],
      ])
      #expect(throws: BridgeError.invalidMessage) { try value.validate() }
    }
  }

  /// 系统 Sheet 不接受超量、重复或携带控制字符的标题栏动作。
  @Test func validatesWebSheetOwnershipDeclarations() throws {
    let original = try snapshot(panel: ["title": "面板", "sections": []])
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    for valid in [true, false] {
      object["presentation"] = [
        "overlayOpen": true,
        "sheet": [
          "id": "sheet-1", "title": "插件配置", "fullscreen": true, "canDismiss": false,
          "actions": [
            ["id": "save", "title": "保存", "enabled": true],
            ["id": valid ? "refresh" : "save", "title": "刷新", "enabled": true],
          ],
        ],
      ]
      let value = try JSONDecoder().decode(
        NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
      if valid {
        try value.validate()
        #expect(value.presentation?.sheet?.backdropReady == nil)
        var prepared = object
        var presentation = try #require(prepared["presentation"] as? [String: Any])
        var sheet = try #require(presentation["sheet"] as? [String: Any])
        sheet["backdropReady"] = true
        presentation["sheet"] = sheet
        prepared["presentation"] = presentation
        let ready = try JSONDecoder().decode(
          NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: prepared))
        try ready.validate()
        #expect(ready.presentation?.sheet?.backdropReady == true)
      } else {
        #expect(throws: BridgeError.invalidMessage) { try value.validate() }
      }
    }
  }
}
