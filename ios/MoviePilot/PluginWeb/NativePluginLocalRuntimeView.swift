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
    let customText = appearance.useCustomTextColor ? appearance.customTextHex + appearance.customLightTextHex : ""
    return "\(preferDark)|\(accentHex)|\(bgHex)|\(customText)|\(appearance.backgroundPreset.rawValue)"
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
        slot.schemeHandler.updateSessionContext(context)
        slot.bridge.updateSessionContext(context)
        slot.bridge.nativeSession = session
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
      slot.bridge.nativeSession = session
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

  private func fetchRemoteDescriptor(for targetPluginID: String) async throws -> PluginRemoteDescriptor {
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

    if let exact = list.first(where: { $0.id.caseInsensitiveCompare(targetPluginID) == .orderedSame }) {
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
        fallbackName: sheetBridge?.title.isEmpty == false ? (sheetBridge?.title ?? pluginName) : pluginName,
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

/// iOS 全应用跨标签悬浮插件胶囊与可展开小悬浮窗视图（支持自由拖拽、仅跳转胶囊与快捷操作小悬浮窗）。
@MainActor
struct NativePluginFloatingCapsuleOverlay: View {
  @ObservedObject var manager: PluginCapsuleManager
  let onOpenFullWindow: (MinimizedPluginSession) -> Void

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var dragOffset: CGSize = .zero
  @State private var accumulatedOffset: CGSize = .zero

  var body: some View {
    if let session = manager.currentSession {
      let snap = session.snapshot
      VStack(alignment: .trailing, spacing: 8) {
        if manager.isMiniCardExpanded && snap.isMiniWindowMode {
          miniExpandedCard(session: session, snap: snap)
            .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
        }

        capsulePill(session: session, snap: snap)
      }
      .offset(
        x: accumulatedOffset.width + dragOffset.width,
        y: accumulatedOffset.height + dragOffset.height
      )
      .gesture(
        DragGesture()
          .onChanged { value in
            dragOffset = value.translation
          }
          .onEnded { value in
            accumulatedOffset.width += value.translation.width
            accumulatedOffset.height += value.translation.height
            dragOffset = .zero
          }
      )
      .animation(.spring(response: 0.28, dampingFraction: 0.82), value: manager.isMiniCardExpanded)
      .padding(.trailing, 16)
      .padding(.bottom, 102)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
  }

  private func capsulePill(session: MinimizedPluginSession, snap: PluginCapsuleSnapshot) -> some View {
    HStack(spacing: 8) {
      capsuleIcon(url: snap.iconURL, size: 28)

      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if snap.isMiniWindowMode {
          manager.isMiniCardExpanded.toggle()
        } else {
          onOpenFullWindow(session)
        }
      } label: {
        VStack(alignment: .leading, spacing: 1) {
          Text(snap.title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          let secondary = snap.statusText.isEmpty ? snap.subtitle : snap.statusText
          if !secondary.isEmpty {
            Text(secondary)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: 168, alignment: .leading)
      }
      .buttonStyle(.plain)

      if snap.isMiniWindowMode {
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          onOpenFullWindow(session)
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(appearance.accentColor)
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("展开插件窗口")
      }

      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        manager.closeAndRelease()
      } label: {
        Image(systemName: "xmark")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("关闭插件胶囊")
    }
    .padding(.leading, 8)
    .padding(.trailing, 8)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(appearance.accentColor.opacity(0.38), lineWidth: 0.9)
    )
    .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    .accessibilityIdentifier("native-plugin-floating-capsule")
  }

  private func miniExpandedCard(
    session: MinimizedPluginSession,
    snap: PluginCapsuleSnapshot
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        capsuleIcon(url: snap.iconURL, size: 36)
        VStack(alignment: .leading, spacing: 2) {
          Text(snap.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          let sub = snap.subtitle.isEmpty ? (snap.statusText.isEmpty ? snap.pluginName : snap.statusText) : snap.subtitle
          if !sub.isEmpty {
            Text(sub)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 4)
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          onOpenFullWindow(session)
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(appearance.accentColor)
            .frame(width: 30, height: 30)
            .background(appearance.accentColor.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开完整窗口")
      }

      if !snap.actions.isEmpty {
        Divider()
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(snap.actions) { action in
              Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                manager.dispatchAction(action.id)
              } label: {
                Text(action.label)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(
                    action.destructive
                      ? NativeTheme.danger
                      : (action.active ? Color.white : Color.primary)
                  )
                  .padding(.horizontal, 12)
                  .padding(.vertical, 7)
                  .background(
                    action.active
                      ? AnyShapeStyle(appearance.accentColor)
                      : AnyShapeStyle(Color.primary.opacity(0.08)),
                    in: Capsule()
                  )
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .padding(14)
    .frame(width: 276)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
    )
    .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
    .accessibilityIdentifier("native-plugin-floating-mini-card")
  }

  @ViewBuilder
  private func capsuleIcon(url: String?, size: CGFloat) -> some View {
    if let raw = url, let parsed = URL(string: raw) {
      AsyncImage(url: parsed) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          fallbackCapsuleIcon(size: size)
        }
      }
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
