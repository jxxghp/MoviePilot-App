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
  @State private var standaloneConfirm: NativeVueSheetConfirmation?
  @State private var standaloneHeaderActions: [NativeVueSheetAction] = []
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
    .toolbar {
      if sheetBridge == nil, !standaloneHeaderActions.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            ForEach(standaloneHeaderActions) { action in
              Button {
                activeSlot?.bridge.sendHostAction(id: action.id)
              } label: {
                Label(action.title, systemImage: action.sfSymbol)
              }
              .disabled(!action.enabled)
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .tint(.primary)
          .accessibilityIdentifier("native-vue-local-runtime-menu")
        }
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
      detachSheetBridgeCallbacks()
      if let slot = activeSlot {
        activeSlot = nil
        PluginWebViewPool.shared.release(slot)
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
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    }
    .padding(.horizontal, CinematicStyle.margin)
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
      PluginWebViewPool.shared.release(existing)
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
      if let sheetBridge {
        sheetBridge.shouldDismiss = true
      } else {
        dismiss()
      }
    }

    slot.bridge.onHeaderUpdate = { title, actions in
      if let sheetBridge {
        if !title.isEmpty {
          sheetBridge.title = title
        }
        sheetBridge.actions = actions
      } else {
        standaloneHeaderActions = actions
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
        slot?.bridge.sendNavBack()
        return false
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
