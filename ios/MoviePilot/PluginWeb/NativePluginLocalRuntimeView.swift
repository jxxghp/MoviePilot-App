import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit
@preconcurrency import WebKit

/// 承载已从 `PluginWebViewPool` 借出的透明 `WKWebView` 的轻量包装视图。
private struct PooledPluginWebViewHost: UIViewRepresentable {
  let webView: WKWebView
  let preferDark: Bool

  func makeUIView(context: Context) -> UIView {
    let container = UIView(frame: .zero)
    container.backgroundColor = .clear
    container.isOpaque = false
    attachWebView(into: container)
    return container
  }

  func updateUIView(_ container: UIView, context: Context) {
    if webView.superview !== container {
      attachWebView(into: container)
    }
    webView.overrideUserInterfaceStyle = preferDark ? .dark : .light
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.underPageBackgroundColor = .clear
  }

  private func attachWebView(into container: UIView) {
    webView.removeFromSuperview()
    webView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: container.topAnchor),
      webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    container.layoutIfNeeded()
    DispatchQueue.main.async { [weak webView] in
      webView?.evaluateJavaScript(
        "window.dispatchEvent(new Event('resize'));", completionHandler: nil)
    }
  }
}

/// Vue 联邦插件本地预热运行时原生容器（Route A）：
/// - 零前端端口依赖：直接向当前后端实例拉取 `/api/v1/plugin/remotes` 并通过 `mp-plugin://shell/` 加载远程分片；
/// - 零令牌暴露：WebView 内无 Bearer Token，`api.request` 全部经 `PluginHostBridgeV2` 由原生代发；
/// - 四层视觉融合：透明 `WKWebView` 透出底层 `CinematicBackground()`，实时同步 `NativeAppearanceStore` 外观与主题切换；
/// - 优雅降级：挂载失败时提供「重新加载」与「用兼容网页容器打开」一键回退。
@MainActor
struct NativePluginLocalRuntimeView: View {
  let session: NativeSession
  let pluginID: String
  let pluginName: String
  let surface: NativeVuePluginWebContainer.Surface
  let sheetBridge: NativeVueSheetBridge?
  let pluginHasPage: Bool
  let onFallbackToLegacy: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  @State private var activeSlot: PooledPluginWebView?
  @State private var isMounted = false
  @State private var errorMessage: String?
  @State private var activeToast: PluginToastPayload?
  @State private var toastDismissTask: Task<Void, Never>?
  @State private var navBackFallbackTask: Task<Void, Never>?
  @State private var standaloneConfirm: NativeVueSheetConfirmation?
  @State private var reloadNonce = 0

  private var preferDark: Bool {
    switch appearance.mode {
    case .dark: return true
    case .light: return false
    case .system: return colorScheme == .dark
    }
  }

  private var themeUpdateKey: String {
    let accentHex = NativeAppearanceStore.hexString(from: appearance.accentColor)
    let bgHex = NativeAppearanceStore.hexString(
      from: appearance.solidBackgroundColor(for: preferDark ? .dark : .light))
    let customText =
      appearance.useCustomTextColor ? appearance.customTextHex + appearance.customLightTextHex : ""
    return
      "\(preferDark)|\(accentHex)|\(bgHex)|\(customText)|\(appearance.backgroundPreset.rawValue)"
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        CinematicBackground()

        if let slot = activeSlot {
          PooledPluginWebViewHost(webView: slot.webView, preferDark: preferDark)
            .opacity(isMounted && errorMessage == nil ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: isMounted)
        }

        if let errorMessage {
          errorPanel(errorMessage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !isMounted {
          loadingSkeleton
            .transition(.opacity)
        }
      }
      .onChange(of: proxy.safeAreaInsets) { insets in
        activeSlot?.bridge.sendSafeArea(
          top: sheetBridge == nil ? insets.top : 0,
          bottom: insets.bottom,
          left: insets.leading,
          right: insets.trailing
        )
      }
    }
    .accessibilityIdentifier(
      isMounted ? "native-vue-local-runtime-ready" : "native-vue-local-runtime-loading"
    )
    .overlay(alignment: .bottom) {
      if let toast = activeToast {
        toastBanner(toast)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.bottom, 24)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .alert(
      standaloneConfirm?.title ?? "",
      isPresented: Binding(
        get: { standaloneConfirm != nil },
        set: { presented in
          if !presented, let current = standaloneConfirm {
            standaloneConfirm = nil
            activeSlot?.bridge.sendConfirmResult(id: current.id, confirmed: false)
          }
        }
      ),
      presenting: standaloneConfirm
    ) { confirmation in
      Button(confirmation.cancelText, role: .cancel) {
        standaloneConfirm = nil
        activeSlot?.bridge.sendConfirmResult(id: confirmation.id, confirmed: false)
      }
      Button(confirmation.confirmText, role: confirmation.destructive ? .destructive : nil) {
        standaloneConfirm = nil
        activeSlot?.bridge.sendConfirmResult(id: confirmation.id, confirmed: true)
      }
    } message: { confirmation in
      Text(confirmation.message)
    }
    .task(id: "\(pluginID)|\(surfaceKey)|\(reloadNonce)") {
      await mountPlugin()
    }
    .onChange(of: themeUpdateKey) { _ in
      guard let slot = activeSlot else { return }
      let tokens = PluginVisualTokensSnapshot.make(from: appearance, colorScheme: colorScheme)
      slot.bridge.sendVisualTokens(tokens)
    }
    .onChange(of: AppLanguage.current.rawValue) { newLocale in
      activeSlot?.bridge.sendLocale(newLocale)
    }
    .onDisappear {
      toastDismissTask?.cancel()
      toastDismissTask = nil
      navBackFallbackTask?.cancel()
      navBackFallbackTask = nil
      detachSheetBridgeCallbacks()
      if let slot = activeSlot {
        activeSlot = nil
        if !PluginCapsuleManager.shared.isSlotParked(slot) {
          PluginWebViewPool.shared.release(slot)
        }
      }
    }
  }

  private var surfaceKey: String {
    switch surface {
    case .dataPage: return "dataPage"
    case .config: return "config"
    case .appPage(let navKey): return "appPage:\(navKey)"
    }
  }

  private var loadingSkeleton: some View {
    ScrollView {
      VStack(spacing: 16) {
        NativeCardListSkeletonView(count: 3, style: .formPanel)
          .frame(maxWidth: 880)
      }
      .padding(.horizontal, CinematicStyle.margin)
      .padding(.vertical, 16)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.hidden)
  }

  private func errorPanel(_ message: String) -> some View {
    CinematicPanel {
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
          .font(.title2)
          .foregroundStyle(NativeTheme.warning)
        Text(L10n.text("本地运行时加载插件失败"))
          .font(.headline)
          .foregroundStyle(.primary)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        HStack(spacing: 12) {
          Button(L10n.text("重新加载")) {
            errorMessage = nil
            isMounted = false
            reloadNonce += 1
          }
          .buttonStyle(.borderedProminent)
          .tint(appearance.accentColor)
          .accessibilityIdentifier("native-vue-local-runtime-retry")

          Button(L10n.text("用兼容网页容器打开")) {
            onFallbackToLegacy()
          }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("native-vue-local-runtime-fallback")
        }
        .padding(.top, 4)

        Button(L10n.text("返回")) {
          dismissHostContainer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("native-vue-local-runtime-exit")
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    }
    .padding(.horizontal, CinematicStyle.margin)
  }

  private func dismissHostContainer() {
    navBackFallbackTask?.cancel()
    navBackFallbackTask = nil
    if let sheetBridge {
      sheetBridge.shouldDismiss = true
    } else {
      dismiss()
    }
  }

  private func toastBanner(_ toast: PluginToastPayload) -> some View {
    let iconName: String
    let tint: Color
    switch toast.level.lowercased() {
    case "success":
      iconName = "checkmark.circle.fill"
      tint = NativeTheme.success
    case "warning":
      iconName = "exclamationmark.triangle.fill"
      tint = NativeTheme.warning
    case "error":
      iconName = "xmark.octagon.fill"
      tint = NativeTheme.danger
    default:
      iconName = "info.circle.fill"
      tint = appearance.accentColor
    }
    return HStack(spacing: 10) {
      Image(systemName: iconName)
        .font(.body.weight(.semibold))
        .foregroundStyle(tint)
      Text(toast.message)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .lineLimit(3)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.white.opacity(preferDark ? 0.16 : 0.35), lineWidth: 0.75)
    )
    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("native-vue-local-runtime-toast")
  }

  // MARK: - Mount Flow

  /// 绑定当前原生会话和动态资源 Cookie 后挂载联邦插件。
  private func mountPlugin() async {
    errorMessage = nil
    isMounted = false
    sheetBridge?.failureMessage = nil
    sheetBridge?.isReady = false

    // 释放上一次挂载的槽
    if let existing = activeSlot {
      activeSlot = nil
      if !PluginCapsuleManager.shared.isSlotParked(existing) {
        PluginWebViewPool.shared.release(existing)
      }
    }

    do {
      let auth = try session.playbackAuthorization()
      let resourceCookie = try? await session.resolveResourceCookie()
      let locale = AppLanguage.current.rawValue
      let context = PluginShellSchemeHandler.SessionContext(
        address: auth.address,
        accessToken: auth.accessToken,
        resourceCookie: resourceCookie,
        locale: locale
      )

      // 若当前插件处于最小化悬浮胶囊保活状态，直接无损接回原 WKWebView 实例（零重载）
      if let resumed = PluginCapsuleManager.shared.consumeMatchingSession(
        pluginID: pluginID, serverURL: auth.address.url)
      {
        let slot = resumed.slot
        slot.sessionContext = context
        slot.schemeHandler.updateSessionContext(context)
        slot.schemeHandler.nativeSession = session
        slot.bridge.updateSessionContext(context)
        slot.bridge.nativeSession = session
        slot.bindActivePlugin(id: pluginID, name: resumed.pluginName)
        PluginNativeCapabilitiesService.latestActiveService?.activePluginID = pluginID
        PluginNativeCapabilitiesService.latestActiveService?.activePluginName = resumed.pluginName
        activeSlot = slot
        bindBridgeCallbacks(for: slot)
        let visualTokens = PluginVisualTokensSnapshot.make(
          from: appearance, colorScheme: colorScheme)
        slot.bridge.sendVisualTokens(visualTokens)
        isMounted = true
        errorMessage = nil
        sheetBridge?.isReady = true
        return
      }

      // 1. 拉取后端 `/api/v1/plugin/remotes?token=moviepilot`，完全不依赖前端 3000 端口！
      let descriptor = try await fetchRemoteDescriptor(for: pluginID)
      try Task.checkCancellation()

      // 2. 规划虚拟源 `/plugin-remote/{id}/{ver}/...` 入口路径
      let entryPlan = try PluginRemoteRuntime.normalizeRemoteEntry(
        pluginId: descriptor.sourcePluginId ?? descriptor.id,
        versionOrHash: descriptor.preferredCacheVersion,
        rawRemoteURL: descriptor.url
      )
      let virtualEntryURL = "\(PluginShellSchemeHandler.origin)\(entryPlan.virtualEntryPath)"

      // 3. 从预热池借出透明 WKWebView 槽
      let slot = PluginWebViewPool.shared.acquire(context: context)
      slot.schemeHandler.nativeSession = session
      slot.bridge.nativeSession = session
      let resolvedDisplayName =
        pluginName.isEmpty ? (descriptor.name ?? pluginID) : pluginName
      slot.bindActivePlugin(id: pluginID, name: resolvedDisplayName)
      PluginNativeCapabilitiesService.latestActiveService?.activePluginID = pluginID
      PluginNativeCapabilitiesService.latestActiveService?.activePluginName = resolvedDisplayName
      activeSlot = slot
      bindBridgeCallbacks(for: slot)

      // 4. 构造 plugin.mount 载荷（零 Bearer Token！）
      let visualTokens = PluginVisualTokensSnapshot.make(from: appearance, colorScheme: colorScheme)
      let mountPayload = buildMountPayload(
        descriptor: descriptor,
        virtualEntryURL: virtualEntryURL,
        locale: locale,
        visualTokens: visualTokens
      )

      // 5. 等待本地壳 shell.ready（预热命中时为 0ms）后立即派发 plugin.mount
      slot.whenShellReady {
        slot.bridge.sendToWeb(type: "plugin.mount", payload: mountPayload)
      }
    } catch is CancellationError {
      return
    } catch {
      let msg = error.localizedDescription.isEmpty ? "无法解析插件联邦入口。" : error.localizedDescription
      errorMessage = msg
      sheetBridge?.failureMessage = nil
      sheetBridge?.isReady = false
    }
  }

  private func fetchRemoteDescriptor(for targetPluginID: String) async throws
    -> PluginRemoteDescriptor
  {
    let endpoint = try APIEndpoint(
      path: ["plugin", "remotes"],
      query: [URLQueryItem(name: "token", value: "moviepilot")],
      responseContract: .payload
    )
    let data = try await session.requestPayload(endpoint).value
    let decoder = JSONDecoder()
    let list: [PluginRemoteDescriptor]
    if let direct = try? decoder.decode([PluginRemoteDescriptor].self, from: data) {
      list = direct
    } else if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let inner = obj["data"],
      let innerData = try? JSONSerialization.data(withJSONObject: inner),
      let decoded = try? decoder.decode([PluginRemoteDescriptor].self, from: innerData)
    {
      list = decoded
    } else {
      throw NSError(
        domain: "PluginLocalRuntime",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "后端未返回有效的联邦插件入口列表。"]
      )
    }

    if let exact = list.first(where: {
      $0.id.caseInsensitiveCompare(targetPluginID) == .orderedSame
    }) {
      return exact
    }
    throw NSError(
      domain: "PluginLocalRuntime",
      code: -2,
      userInfo: [NSLocalizedDescriptionKey: "未在运行态联邦插件列表中找到 \(targetPluginID)。"]
    )
  }

  private func buildMountPayload(
    descriptor: PluginRemoteDescriptor,
    virtualEntryURL: String,
    locale: String,
    visualTokens: PluginVisualTokensSnapshot
  ) -> [String: Any] {
    let surfaceStr: String
    var navKey: String? = nil
    switch surface {
    case .dataPage:
      surfaceStr = "dataPage"
    case .config:
      surfaceStr = "config"
    case .appPage(let key):
      surfaceStr = "appPage"
      navKey = key
    }

    let user = session.user
    let userPayload: [String: Any] = [
      "id": user.id,
      "superUser": user.isSuperuser,
      "userName": user.name,
      "avatar": user.avatar,
      "level": user.level,
      "permissions": [
        "discovery": user.allows(.init(category: .discovery)),
        "search": user.allows(.init(category: .search)),
        "subscribe": user.allows(.init(category: .subscribe)),
        "manage": user.allows(.init(category: .manage)),
        "admin": user.allows(.init(category: .admin)),
      ],
    ]

    let visualTokensObj: [String: Any]
    if let encoded = try? JSONEncoder().encode(visualTokens),
      let obj = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any]
    {
      visualTokensObj = obj
    } else {
      visualTokensObj = [:]
    }

    var payload: [String: Any] = [
      "mountId": UUID().uuidString,
      "pluginId": pluginID,
      "pluginName": pluginName,
      "remoteEntryUrl": virtualEntryURL,
      "surface": surfaceStr,
      "showSwitch": pluginHasPage,
      "locale": locale,
      "visualTokens": visualTokensObj,
      "safeArea": [
        "top": 0,
        "bottom": 16,
        "left": 0,
        "right": 0,
      ],
      "user": userPayload,
    ]
    if let sourceId = descriptor.sourcePluginId, !sourceId.isEmpty {
      payload["sourcePluginId"] = sourceId
    }
    if let version = descriptor.version, !version.isEmpty {
      payload["pluginVersion"] = version
    }
    if let navKey {
      payload["navKey"] = navKey
    }
    return payload
  }

  private func bindBridgeCallbacks(for slot: PooledPluginWebView) {
    slot.bridge.onPluginMounted = { _, _ in
      withAnimation(.easeOut(duration: 0.16)) {
        isMounted = true
        errorMessage = nil
      }
      sheetBridge?.isReady = true
      sheetBridge?.failureMessage = nil
    }

    slot.bridge.onPluginError = { _, message, _ in
      isMounted = false
      errorMessage = message
      sheetBridge?.isReady = false
    }

    slot.bridge.onPluginClose = {
      dismissHostContainer()
    }

    slot.bridge.onPluginMinimize = { reqId, payload in
      guard let auth = try? session.playbackAuthorization() else {
        slot.bridge.sendSimpleResponse(requestId: reqId, data: ["minimized": false])
        return
      }
      let snap = PluginCapsuleSnapshot.from(
        pluginID: pluginID,
        fallbackName: sheetBridge?.title.isEmpty == false
          ? (sheetBridge?.title ?? pluginName) : pluginName,
        payload: payload
      )
      slot.bridge.sendSimpleResponse(
        requestId: reqId,
        data: [
          "minimized": true,
          "overlaySupported": false,
          "overlayGranted": false,
        ]
      )
      let parked = MinimizedPluginSession(
        pluginID: pluginID,
        pluginName: snap.pluginName,
        surface: surface,
        pluginHasPage: pluginHasPage,
        serverURL: auth.address.url,
        slot: slot,
        snapshot: snap
      )
      PluginCapsuleManager.shared.parkSession(parked)
      activeSlot = nil
      dismissHostContainer()
    }

    slot.bridge.onCapsuleUpdate = { patch in
      PluginCapsuleManager.shared.updateActiveSnapshot(patch)
    }

    slot.bridge.onPluginRestore = { reqId in
      slot.bridge.sendSimpleResponse(requestId: reqId, data: ["restored": true])
    }

    slot.bridge.onNavBackResult = { handled in
      navBackFallbackTask?.cancel()
      navBackFallbackTask = nil
      if !handled {
        dismissHostContainer()
      }
    }

    slot.bridge.onHeaderUpdate = { title, actions in
      if let sheetBridge {
        if !title.isEmpty {
          sheetBridge.title = title
        }
        sheetBridge.actions = actions
      }
    }

    slot.bridge.onToast = { toast in
      toastDismissTask?.cancel()
      withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
        activeToast = toast
      }
      toastDismissTask = Task {
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
          if activeToast?.id == toast.id {
            activeToast = nil
          }
        }
      }
    }

    slot.bridge.onConfirm = { confirmation in
      if let sheetBridge {
        sheetBridge.confirmation = confirmation
      } else {
        standaloneConfirm = confirmation
      }
    }

    slot.bridge.onOpenRoute = { path in
      _ = NativeSystemRouteHub.shared.open(route: path)
    }

    slot.onProcessTerminated = {
      isMounted = false
      errorMessage = "插件渲染进程异常中断，请重新加载。"
      sheetBridge?.isReady = false
    }

    if let sheetBridge {
      sheetBridge.localInvokeAction = { [weak slot] id in
        slot?.bridge.sendHostAction(id: id)
      }
      sheetBridge.localRequestClose = { [weak slot] in
        guard isMounted, let slot else { return false }
        navBackFallbackTask?.cancel()
        navBackFallbackTask = Task { @MainActor in
          try? await Task.sleep(nanoseconds: 500_000_000)
          guard !Task.isCancelled else { return }
          dismissHostContainer()
        }
        slot.bridge.sendNavBack()
        return true
      }
      sheetBridge.localRespondConfirmation = { [weak slot] id, confirmed in
        slot?.bridge.sendConfirmResult(id: id, confirmed: confirmed)
      }
    }
  }

  private func detachSheetBridgeCallbacks() {
    sheetBridge?.localInvokeAction = nil
    sheetBridge?.localRequestClose = nil
    sheetBridge?.localRespondConfirmation = nil
  }
}

private struct CapsuleMeasuredSizePreferenceKey: PreferenceKey {
  static let defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
    let candidate = nextValue()
    if candidate.width > 0 && candidate.height > 0 {
      value = candidate
    }
  }
}

/// 兼容 iOS 16+ 的贴边半圆胶囊裁剪形状（贴左或贴右为直角，朝内为全圆弧，未贴边为完整胶囊）。
private struct DockedCapsuleShape: Shape {
  let dockedEdge: String

  func path(in rect: CGRect) -> Path {
    let radius = min(rect.width, rect.height) * 0.5
    let corners: UIRectCorner
    switch dockedEdge {
    case "left":
      corners = [.topRight, .bottomRight]
    case "right":
      corners = [.topLeft, .bottomLeft]
    default:
      corners = .allCorners
    }
    let bezier = UIBezierPath(
      roundedRect: rect,
      byRoundingCorners: corners,
      cornerRadii: CGSize(width: radius, height: radius)
    )
    return Path(bezier.cgPath)
  }
}

/// iOS 全应用跨标签紧凑单行横向悬浮胶囊视图：
/// - 拖动与松手全程约束在屏幕安全区内（避开灵动岛/状态栏与底部栏），持久化安全坐标；
/// - 拖至左右边缘 `< edgeSnapThresholdDp`（默认 24pt）自动吸附并收缩为半圆「超级最小化」，点击恢复完整单行胶囊。
@MainActor
struct NativePluginFloatingCapsuleOverlay: View {
  @ObservedObject var manager: PluginCapsuleManager
  let onOpenFullWindow: (MinimizedPluginSession) -> Void

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @AppStorage("mp.pluginCapsule.normX") private var normX: Double = 1.0
  @AppStorage("mp.pluginCapsule.normY") private var normY: Double = 0.78
  @AppStorage("mp.pluginCapsule.dockedEdge") private var dockedEdge: String = "none"

  @State private var measuredSize: CGSize = .zero
  @State private var isDragging: Bool = false
  @State private var liveDragOrigin: CGPoint = .zero

  private var isSuperMinimized: Bool {
    dockedEdge == "left" || dockedEdge == "right"
  }

  var body: some View {
    if let session = manager.currentSession {
      let snap = session.snapshot
      GeometryReader { proxy in
        let viewportW = max(proxy.size.width, 1)
        let viewportH = max(proxy.size.height, 1)
        let itemW = max(measuredSize.width, isSuperMinimized ? 42 : 230)
        let itemH = max(measuredSize.height, 40)
        let hMargin: CGFloat = 12
        let topMargin: CGFloat = 10
        let bottomClearance: CGFloat = 94
        let snapThreshold = CGFloat(snap.edgeSnapThresholdDp)

        let minDragX: CGFloat = 0
        let maxDragX = max(viewportW - itemW, minDragX)
        let minY = topMargin
        let maxY = max(viewportH - bottomClearance - itemH, minY)

        let resolvedOrigin: CGPoint = {
          let clampedNormY = min(max(CGFloat(normY), 0), 1)
          let y = min(max(minY + (maxY - minY) * clampedNormY, minY), maxY)
          switch dockedEdge {
          case "left":
            return CGPoint(x: 0, y: y)
          case "right":
            return CGPoint(x: max(viewportW - itemW, 0), y: y)
          default:
            let minFreeX = hMargin
            let maxFreeX = max(viewportW - hMargin - itemW, minFreeX)
            let clampedNormX = min(max(CGFloat(normX), 0), 1)
            let x = min(max(minFreeX + (maxFreeX - minFreeX) * clampedNormX, minFreeX), maxFreeX)
            return CGPoint(x: x, y: y)
          }
        }()

        let activeOrigin: CGPoint =
          isDragging
          ? CGPoint(
            x: min(max(liveDragOrigin.x, minDragX), maxDragX),
            y: min(max(liveDragOrigin.y, minY), maxY)
          )
          : resolvedOrigin

        capsuleContent(session: session, snap: snap)
          .background(
            GeometryReader { pillProxy in
              Color.clear.preference(
                key: CapsuleMeasuredSizePreferenceKey.self, value: pillProxy.size)
            }
          )
          .onPreferenceChange(CapsuleMeasuredSizePreferenceKey.self) { nextSize in
            if abs(nextSize.width - measuredSize.width) > 0.5
              || abs(nextSize.height - measuredSize.height) > 0.5
            {
              measuredSize = nextSize
            }
          }
          .task(id: "\(session.serverURL.absoluteString)|\(snap.iconURL ?? "")") {
            manager.ensureIconLoaded(for: session)
          }
          .position(x: activeOrigin.x + itemW * 0.5, y: activeOrigin.y + itemH * 0.5)
          .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("mp-plugin-capsule-space"))
              .onChanged { value in
                let startOrigin = resolvedOrigin
                let rawX = startOrigin.x + value.translation.width
                let rawY = startOrigin.y + value.translation.height
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                  isDragging = true
                  liveDragOrigin = CGPoint(
                    x: min(max(rawX, minDragX), maxDragX),
                    y: min(max(rawY, minY), maxY)
                  )
                }
              }
              .onEnded { value in
                let startOrigin = resolvedOrigin
                let clampedX = min(max(startOrigin.x + value.translation.width, minDragX), maxDragX)
                let clampedY = min(max(startOrigin.y + value.translation.height, minY), maxY)
                let distLeft = max(clampedX, 0)
                let distRight = max(viewportW - (clampedX + itemW), 0)
                let nextNormY =
                  maxY > minY ? Double(min(max((clampedY - minY) / (maxY - minY), 0), 1)) : 0.78

                let nextEdge: String
                let nextNormX: Double
                if snapThreshold > 0 && distLeft <= snapThreshold && distLeft <= distRight {
                  nextEdge = "left"
                  nextNormX = 0.0
                } else if snapThreshold > 0 && distRight <= snapThreshold {
                  nextEdge = "right"
                  nextNormX = 1.0
                } else {
                  nextEdge = "none"
                  let minFreeX = hMargin
                  let maxFreeX = max(viewportW - hMargin - itemW, minFreeX)
                  let settledX = min(max(clampedX, minFreeX), maxFreeX)
                  nextNormX =
                    maxFreeX > minFreeX
                    ? Double(min(max((settledX - minFreeX) / (maxFreeX - minFreeX), 0), 1))
                    : 1.0
                }

                if nextEdge != dockedEdge {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                  isDragging = false
                  normX = nextNormX
                  normY = nextNormY
                  dockedEdge = nextEdge
                }
              }
          )
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .coordinateSpace(name: "mp-plugin-capsule-space")
    }
  }

  @ViewBuilder
  private func capsuleContent(session: MinimizedPluginSession, snap: PluginCapsuleSnapshot)
    -> some View
  {
    let shape = DockedCapsuleShape(dockedEdge: dockedEdge)
    if isSuperMinimized {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
          normX = dockedEdge == "left" ? 0.0 : 1.0
          dockedEdge = "none"
        }
      } label: {
        capsuleIcon(session: session, size: 28)
          .padding(.leading, dockedEdge == "left" ? 6 : 8)
          .padding(.trailing, dockedEdge == "right" ? 6 : 8)
          .padding(.vertical, 5)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(.ultraThinMaterial, in: shape)
      .overlay(
        shape
          .stroke(
            appearance.accentColor.opacity(snap.isPlaying ? 0.62 : 0.38),
            lineWidth: 0.9
          )
      )
      .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
      .accessibilityLabel("展开插件胶囊")
      .accessibilityIdentifier("native-plugin-floating-capsule-docked")
    } else {
      capsulePill(session: session, snap: snap)
    }
  }

  private func capsulePill(session: MinimizedPluginSession, snap: PluginCapsuleSnapshot)
    -> some View
  {
    HStack(spacing: 2) {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onOpenFullWindow(session)
      } label: {
        HStack(spacing: 6) {
          capsuleIcon(session: session, size: 26)

          VStack(alignment: .leading, spacing: 1) {
            Text(snap.displayTitle)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .truncationMode(.tail)
            let secondary = snap.displaySubtitle
            if !secondary.isEmpty {
              Text(secondary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }
          .frame(width: 64, alignment: .leading)
        }
        .padding(.trailing, 2)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("恢复打开 \(snap.displayTitle)")

      ForEach(Array(snap.actions.prefix(3))) { action in
        inlineActionButton(action: action, isPlaying: snap.isPlaying)
      }

      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        manager.closeAndRelease()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 23, height: 25)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("关闭插件胶囊")
    }
    .padding(.leading, 6)
    .padding(.trailing, 4)
    .padding(.vertical, 5)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(appearance.accentColor.opacity(0.38), lineWidth: 0.9)
    )
    .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    .accessibilityIdentifier("native-plugin-floating-capsule")
  }

  /// 渲染紧凑单行胶囊内联纯图标快捷按钮（实时同步播放/暂停与选中态）。
  private func inlineActionButton(
    action: PluginCapsuleActionItem,
    isPlaying: Bool
  ) -> some View {
    let kind = action.inlineKind
    let symbolName: String = {
      switch kind {
      case .previous:
        return "backward.end.fill"
      case .playPause:
        return isPlaying ? "pause.fill" : "play.fill"
      case .next:
        return "forward.end.fill"
      case .heart:
        return action.active ? "heart.fill" : "heart"
      case .repeatOne:
        return "repeat.1"
      case .repeatAll:
        return "repeat"
      case .shuffle:
        return "shuffle"
      case .lyrics:
        return "quote.bubble"
      case .generic:
        return "star.fill"
      }
    }()
    let foreground: Color = {
      if action.destructive {
        return NativeTheme.danger
      }
      if kind == .heart && action.active {
        return Color(red: 1.0, green: 0.36, blue: 0.54)
      }
      if kind != .playPause && action.active {
        return appearance.accentColor
      }
      return .primary
    }()

    return Button {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      manager.dispatchAction(action.id)
    } label: {
      Image(systemName: symbolName)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(foreground)
        .frame(width: 25, height: 25)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(action.label)
  }

  @ViewBuilder
  private func capsuleIcon(session: MinimizedPluginSession, size: CGFloat) -> some View {
    let revision = manager.iconCacheRevision
    if revision >= 0, let cached = manager.cachedIcon(for: session) {
      Image(uiImage: cached)
        .resizable()
        .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(Circle())
    } else {
      fallbackCapsuleIcon(size: size)
    }
  }

  private func fallbackCapsuleIcon(size: CGFloat) -> some View {
    ZStack {
      Circle()
        .fill(appearance.accentColor.opacity(0.18))
      Image(systemName: "puzzlepiece.extension.fill")
        .font(.system(size: size * 0.48, weight: .semibold))
        .foregroundStyle(appearance.accentColor)
    }
    .frame(width: size, height: size)
  }
}
