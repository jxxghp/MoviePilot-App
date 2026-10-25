import Foundation
import Testing

@testable import MoviePilotCore

/// 系统面板只接受有界展示声明，兼容旧网页且拒绝恶意层级与重复标识。
struct NativePanelTests {
  /// 原生弹窗动作的可选图标向后兼容，不能用控制字符或无限文案污染导航栏。
  @Test func validatesOptionalSheetActionIcons() throws {
    let base = try snapshot(panel: ["title": "空菜单", "sections": []])
    for icon in [nil, "mdi-history", "mdi-history\n", String(repeating: "a", count: 513)]
      as [String?]
    {
      var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
      var action: [String: Any] = ["id": "history", "title": "历史会话", "enabled": true]
      action["icon"] = icon
      object["presentation"] = [
        "overlayOpen": true,
        "sheet": [
          "id": "agent", "title": "助手", "fullscreen": true, "canDismiss": true,
          "actions": [action],
        ],
      ]
      let value = try JSONDecoder().decode(
        NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
      if icon == nil || icon == "mdi-history" {
        try value.validate()
        #expect(value.presentation?.sheet?.actions[0].icon == icon)
      } else {
        #expect(throws: BridgeError.invalidMessage) { try value.validate() }
      }
    }
  }

  /// 正文只允许换行和有界纯文本；旧副标题仍采用原来的严格单行规则。
  @Test func validatesMultilineNotificationBody() throws {
    let body = "10 小时前\n站点：演示\n质量：WEB-DL 2160p\n大小：13.8 GB"
    for candidate in [
      nil, body, "正文\u{0}", "正文\r", "正文\t", "正文\u{202e}", "", String(repeating: "长", count: 683),
    ] as [String?] {
      var row: [String: Any] = ["id": "message", "title": "开始下载", "subtitle": "兼容旧版正文"]
      row["body"] = candidate
      let value = try snapshot(panel: [
        "title": "通知中心", "sections": [["id": "messages", "items": [row]]],
      ])
      if candidate == nil || candidate == body {
        try value.validate()
        #expect(value.actions[0].panel?.sections[0].items[0].body == candidate)
      } else {
        #expect(throws: BridgeError.invalidMessage) { try value.validate() }
      }
    }
  }

  /// 分片只引用当前声明内的唯一分组，拒绝负数、超界和任意布局组合。
  @Test func validatesContinuousFeed() throws {
    let valid: [String: Any] = [
      "id": "feed", "offset": 0, "revision": 1, "sectionIds": ["messages"],
    ]
    for override in [
      [:], ["offset": -1], ["revision": -1], ["sectionIds": []],
      ["sectionIds": ["missing"]], ["sectionIds": ["messages", "messages"]],
      ["id": "invalid id"], ["offset": Int64(Int32.max) + 1],
    ] as [[String: Any]] {
      let value = try snapshot(panel: [
        "title": "通知", "sections": [["id": "messages", "items": []]],
        "feed": valid.merging(override) { _, new in new },
      ])
      if override.isEmpty {
        try value.validate()
        #expect(value.actions[0].panel?.feed?.revision == 1)
      } else {
        #expect(throws: BridgeError.invalidMessage) { try value.validate() }
      }
    }
  }

  /// 宽度声明可选且仅接受已定义值，不依赖标题语言来判断通知面板。
  @Test func acceptsExplicitFullWidth() throws {
    for width in [nil, "full"] as [String?] {
      var panel: [String: Any] = ["title": "消息", "sections": []]
      panel["width"] = width
      let value = try snapshot(panel: panel)
      try value.validate()
      #expect(value.actions[0].panel?.width?.rawValue == width)
    }
    #expect(throws: (any Error).self) {
      try snapshot(panel: ["title": "消息", "width": "arbitrary", "sections": []])
    }
  }

  /// 旧面板省略布局仍可解码，未知布局不能成为原生容器的任意显示指令。
  @Test func acceptsOptionalGridLayout() throws {
    for layout in [nil, "grid"] as [String?] {
      var panel: [String: Any] = ["title": "捷径", "sections": []]
      panel["layout"] = layout
      let value = try snapshot(panel: panel)
      try value.validate()
      #expect(value.actions[0].panel?.layout?.rawValue == layout)
    }
    #expect(throws: (any Error).self) {
      try snapshot(panel: ["title": "捷径", "layout": "unknown", "sections": []])
    }
  }

  /// 主要按钮只能引用本层唯一的叶子动作，旧版缺省声明继续保留原列表。
  @Test func validatesPrimarySubmenuAction() throws {
    let run: [String: Any] = ["id": "run", "title": "搜索", "primary": true]
    let source: [String: Any] = ["id": "source", "title": "TheMovieDb", "keepOpen": true]
    let rows: [[String: Any]] = [["id": "media", "title": "电影、电视剧", "children": [run, source]]]
    let valid = try snapshot(panel: [
      "title": "搜索", "sections": [["id": "actions", "items": rows]],
    ])
    try valid.validate()
    #expect(valid.actions[0].panel?.sections[0].items[0].children?[0].primary == true)
    let root = try snapshot(panel: [
      "title": "搜索", "sections": [["id": "actions", "items": [run]]],
    ])
    #expect(throws: BridgeError.invalidMessage) { try root.validate() }
    let invalid: [[[String: Any]]] = [
      [run, ["id": "another", "title": "再次搜索", "primary": true]],
      [["id": "run", "title": "搜索", "primary": true, "keepOpen": true]],
      [["id": "run", "title": "搜索", "primary": true, "children": [source]]],
    ]
    for children in invalid {
      let value = try snapshot(panel: [
        "title": "搜索",
        "sections": [
          [
            "id": "actions",
            "items": [
              ["id": "media", "title": "媒体", "children": children]
            ],
          ]
        ],
      ])
      #expect(throws: BridgeError.invalidMessage) { try value.validate() }
    }
  }

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
        #expect(value.presentation?.sheet?.progress == nil)
        #expect(value.presentation?.sheet?.prefersMediumDetent == nil)
        var prepared = object
        var presentation = try #require(prepared["presentation"] as? [String: Any])
        var sheet = try #require(presentation["sheet"] as? [String: Any])
        sheet["backdropReady"] = true
        sheet["prefersMediumDetent"] = true
        sheet["fullscreen"] = false
        presentation["sheet"] = sheet
        prepared["presentation"] = presentation
        let ready = try JSONDecoder().decode(
          NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: prepared))
        try ready.validate()
        #expect(ready.presentation?.sheet?.backdropReady == true)
        #expect(ready.presentation?.sheet?.prefersMediumDetent == true)
        #expect(ready.presentation?.sheet?.fullscreen == false)
      } else {
        #expect(throws: BridgeError.invalidMessage) { try value.validate() }
      }
    }
  }

  /// 原生进度只能展示合法百分比与有界文本，不能声明关闭或业务按钮。
  @Test func validatesNativeProgressState() throws {
    let original = try snapshot(panel: ["title": "面板", "sections": []])
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    let invalid: [[String: Any]] = [
      ["message": "处理中", "value": -1], ["message": "处理中", "value": 101],
      ["message": ""], ["message": "异常\n文本"], ["message": String(repeating: "海", count: 200)],
    ]
    for progress in [
      ["message": "处理中"], ["message": "识别文件", "value": 0], ["message": "识别文件", "value": 100],
    ] + invalid {
      let sheet: [String: Any] = [
        "id": "progress-1", "title": "处理中", "fullscreen": false, "canDismiss": false,
        "actions": [], "progress": progress,
      ]
      object["presentation"] = ["overlayOpen": true, "sheet": sheet]
      let value = try JSONDecoder().decode(
        NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
      if invalid.contains(where: { NSDictionary(dictionary: $0).isEqual(to: progress) }) {
        #expect(throws: BridgeError.invalidMessage) { try value.validate() }
      } else {
        try value.validate()
        var dismissible = sheet
        dismissible["canDismiss"] = true
        object["presentation"] = ["overlayOpen": true, "sheet": dismissible]
        let unsafe = try JSONDecoder().decode(
          NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: BridgeError.invalidMessage) { try unsafe.validate() }
      }
    }
  }
}
