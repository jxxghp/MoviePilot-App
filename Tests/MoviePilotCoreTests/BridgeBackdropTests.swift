#if os(macOS)
  import Testing
  import WebKit

  /// 使用真实 WebKit 验证注入样式对 body 浮层的隐藏与恢复，不依赖前端版本。
  @MainActor
  struct BridgeBackdropTests {
    /// 原生页面排除 Teleport 助手，业务页、Sheet 与协商回退仍保留网页内容。
    @Test func restoresTeleportedAssistantAfterNativePages() async throws {
      let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ios/MoviePilot/Resources/BridgeBootstrap.js")
      let source = try String(contentsOf: sourceURL, encoding: .utf8)
      let page = BackdropPage(source: source)
      defer { page.webView.configuration.userContentController.removeAllScriptMessageHandlers() }
      try await page.load()
      let result = try await page.webView.evaluateJavaScript(
        #"""
        (() => {
          const root = document.documentElement;
          const content = document.querySelector('.layout-page-content');
          const fab = document.querySelector('.agent-assistant-fab');
          const stage = document.querySelector('.agent-pet-stage-layer');
          const pet = stage.firstElementChild;
          const visible = element => element.getClientRects().length > 0 &&
            getComputedStyle(element).visibility === 'visible';
          const check = (condition, message) => { if (!condition) throw new Error(message); };
          const navigate = content => window.MoviePilotNative.postMessage({
            type: 'navigation.state', payload: { chrome: { content } }
          });
          const allVisible = () => [content, fab, pet].every(visible);
          root.dataset.nativeChrome = 'active';
          check(allVisible(), 'normal web content must start visible');
          for (const mode of ['menu', 'search']) {
            navigate(mode);
            check(!visible(content), `${mode}: HTML directory must be hidden`);
            check(!visible(fab), `${mode}: assistant entry must be hidden`);
            check(!visible(pet), `${mode}: stage child must be hidden even with explicit visibility`);
            check(visible(document.querySelector('#wallpaper')), `${mode}: wallpaper must remain visible`);
            root.dataset.nativeSheet = 'fixture';
            check(allVisible(), `${mode}: Sheet must retain ownership of HTML content`);
            delete root.dataset.nativeSheet;
            check(!visible(pet), `${mode}: closing Sheet must hide stage again`);
            delete root.dataset.nativeChrome;
            check(allVisible(), `${mode}: negotiation fallback must restore content`);
            root.dataset.nativeChrome = 'active';
            navigate('web');
            check(allVisible(), `${mode}: leaving native page must restore content`);
            check(stage.firstElementChild === pet, 'pet instance must survive navigation');
          }
          return 'restored';
        })()
        """#
      )
      #expect(result as? String == "restored")
    }
  }

  /// 仅加载合成 HTML 与发布用桥接脚本，不访问网络或真实账号。
  @MainActor
  private final class BackdropPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private var completion: CheckedContinuation<Void, any Error>?

    /// 按宿主的 document-start 时序注入原脚本，使用无副作用的消息接收器。
    init(source: String) {
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      configuration.userContentController.addUserScript(
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
      webView = WKWebView(
        frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
      super.init()
      configuration.userContentController.add(self, name: "moviepilotChrome")
      webView.navigationDelegate = self
    }

    /// 保留舞台子节点显式可见的情况，防止只隐藏父层的 visibility 被插件覆盖。
    func load() async throws {
      try await withCheckedThrowingContinuation { continuation in
        completion = continuation
        webView.loadHTMLString(
          """
          <!doctype html><html><body>
          <div id="wallpaper">wallpaper</div>
          <main class="layout-page-content">business content</main>
          <button class="agent-assistant-fab">assistant</button>
          <div class="agent-pet-stage-layer" style="pointer-events: none">
            <button style="visibility: visible; pointer-events: auto">stage pet</button>
          </div>
          </body></html>
          """, baseURL: nil)
      }
    }

    /// 等待真实文档完成加载后再读取 WebKit 计算样式。
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      completion?.resume()
      completion = nil
    }

    /// 导航失败直接结束测试，避免掩盖 WebKit 环境异常。
    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: any Error
    ) {
      completion?.resume(throwing: error)
      completion = nil
    }

    /// 合成导航消息仅驱动脚本中的状态属性，不调用真实原生业务。
    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {}
  }
#endif
