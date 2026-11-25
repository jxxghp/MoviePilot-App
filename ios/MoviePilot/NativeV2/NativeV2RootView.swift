import Combine
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UniformTypeIdentifiers

/// 可运行的原生账号/服务入口；只有已认证快照可以进入账号页。
@MainActor
struct NativeV2RootView: View {
  /// 显式下一项焦点让键盘推动表单滚动，不要求用户点中键盘边缘的输入框。
  private enum Field: Hashable { case address, username, password, confirmation, otp }

  @ObservedObject private var model: NativeAppModel
  @ObservedObject private var manager: NativeSessionManager
  @ObservedObject private var routeHub = NativeSystemRouteHub.shared
  @ObservedObject private var playbackLauncher = NativeMediaPlaybackLauncher.shared
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var pendingForget: SavedInstance?
  @State private var showsAPIKey = false
  @State private var showsPassword = false
  @State private var showsPlugins = false
  @State private var hasCompletedInitialBoot = false
  @FocusState private var focused: Field?
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var colorScheme

  private var showsColdBootSplash: Bool {
    guard !hasCompletedInitialBoot, model.selected != nil else { return false }
    if case .authenticated = manager.state {
      return manager.currentSession == nil
    }
    if model.busy { return true }
    if case .disconnected = manager.state { return true }
    if case .connecting = manager.state { return true }
    return false
  }

  /// 显式观察会话发布者，避免仅刷新表单而漏掉异步失效状态。
  init(model: NativeAppModel) {
    self.model = model
    manager = model.manager
  }

  /// 单一 Cinematic 背景贯通安全区；已认证主壳由 TabView 承载各标签独立导航栈。
  var body: some View {
    ZStack {
      if showsColdBootSplash {
        NativeLaunchSplashView()
      } else {
        if case .authenticated(let snapshot) = manager.state,
          let session = manager.currentSession, session.scope == snapshot.scope
        {
          NativeV2MainShell(
            session: session,
            snapshot: snapshot,
            showsPlugins: $showsPlugins,
            currentLanguage: model.language,
            onSelectLanguage: { model.selectLanguage($0) },
            onSwitchServer: { model.beginSwitchServer() },
            onLogout: { model.logout() },
            pluginDestination: {
              if let current = manager.currentSession, current.scope == snapshot.scope {
                NativePluginCatalogView(session: current)
              }
            }
          )
          .nativeProvideVerticalBarEdge()
          .id(snapshot.scope.generation)
          .opacity(model.isSwitchingServer ? 0 : 1)
          .allowsHitTesting(!model.isSwitchingServer)
          .accessibilityHidden(model.isSwitchingServer)
        }
        if showingEntryForm {
          NavigationStack {
            ZStack {
              CinematicBackground()
              ScrollViewReader { scroll in
                Form {
                  brand.id("native-v2-top")
                  if let message = model.messageKey {
                    CinematicFormSection {
                      CinematicFormRow(symbol: "info.circle") {
                        Text(L10n.text(message)).font(.callout)
                          .accessibilityIdentifier("native-v2-message")
                          .accessibilityAddTraits(.updatesFrequently)
                      }
                      if case .failed(_, .api) = manager.state, let selected = model.selected {
                        CinematicFormDivider()
                        CinematicFormRow {
                          rowAction("重试连接", id: "native-v2-retry") { model.connect(selected) }
                        }
                      }
                    }
                  }
                  if model.busy {
                    CinematicFormSection {
                      CinematicFormRow {
                        HStack(spacing: 12) {
                          ProgressView()
                          Text(L10n.text("正在连接…"))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("native-v2-progress")
                      }
                    }
                  }
                  if !model.isSwitchingServer, case .authenticated = manager.state {
                    CinematicFormSection {
                      CinematicFormRow {
                        HStack(spacing: 12) {
                          ProgressView()
                          Text("正在准备 MoviePilot…")
                        }
                        .accessibilityElement(children: .combine)
                      }
                    }
                  } else if model.form == .connection {
                    connection
                  } else {
                    authentication
                  }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: 680)
                .onChange(of: authenticated) { _ in scroll.scrollTo("native-v2-top", anchor: .top) }
                .onChange(of: model.form) { _ in scroll.scrollTo("native-v2-top", anchor: .top) }
              }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .nativeTopNavigationBar()
            .toolbar { toolbar }
          }
          if let miniMusic = playbackLauncher.miniMusicState {
            unauthenticatedMiniMusicBar(miniMusic)
              .transition(.move(edge: .bottom).combined(with: .opacity))
              .zIndex(45)
          }
          if let banner = routeHub.bannerMessage {
            unauthenticatedBannerOverlay(banner)
              .transition(.move(edge: .top).combined(with: .opacity))
              .zIndex(60)
          }
        }
      }
    }
    .onAppear {
      playbackLauncher.presentPendingExternalPlaybackIfNeeded()
    }
    .onChange(of: model.busy) { busy in
      if !busy {
        switch manager.state {
        case .disconnected, .connecting:
          break
        default:
          hasCompletedInitialBoot = true
        }
      }
    }
    .alert(
      L10n.text("删除服务？"),
      isPresented: Binding(
        get: { pendingForget != nil }, set: { if !$0 { pendingForget = nil } }),
      presenting: pendingForget
    ) { instance in
      Button(L10n.text("删除"), role: .destructive) {
        pendingForget = nil
        model.forget(instance)
      }
      Button(L10n.text("取消"), role: .cancel) { pendingForget = nil }
    } message: { _ in
      Text(L10n.text("将移除此服务的本机登录信息和缓存。"))
    }
    .environment(\.locale, Locale(identifier: model.language.rawValue))
    .nativeAppearanceRoot()
    .onChange(of: manager.state) { state in
      if case .authenticated(let snapshot) = state, snapshot.user.isSuperuser {
        return
      }
      showsPlugins = false
    }
    .onChange(of: routeHub.pendingTarget) { target in
      guard target != nil else { return }
      if authenticated {
        hasCompletedInitialBoot = true
        if model.isSwitchingServer {
          model.cancelSwitchServer()
        }
      }
    }
    .onChange(of: model.selected?.id) { _ in concealSecrets() }
    .onChange(of: model.form) { _ in concealSecrets() }
    .onChange(of: scenePhase) { phase in
      if phase == .active {
        model.resumeSystemIntegrations()
      } else {
        concealSecrets()
      }
    }
    // UIKit 承载的 UIHostingController 不保证发布 SwiftUI scenePhase，直接观察系统场景通知。
    .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) { _ in
      concealSecrets()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in
      model.resumeSystemIntegrations()
    }
  }

  /// 身份页与输入页切换后重置滚动位置，避免沿用大字登录页底部偏移而藏住当前账号。
  private var authenticated: Bool {
    if case .authenticated = manager.state { return true }
    return false
  }

  /// 是否显示连接/认证表单层（未登录，或用户正在从设置页切换服务）。
  private var showingEntryForm: Bool {
    !authenticated || model.isSwitchingServer
  }

  /// 标题只反映真实可用的入口，不把此基础阶段命名为完整首页。
  private var title: String {
    if !model.isSwitchingServer, case .authenticated = manager.state { return "" }
    switch model.form {
    case .connection: return L10n.text("连接服务")
    case .login: return L10n.text("登录")
    case .initialization: return L10n.text("首次设置")
    }
  }

  /// 极简编排式品牌页眉：去发光与去厚重图标盒，使用纯矢量 LaunchMark 徽标配左对齐大标题，聚焦连接与登录表单主体。
  private var brand: some View {
    Section {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          Image("LaunchMark")
            .resizable()
            .scaledToFit()
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

          Text("MoviePilot")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.90))
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.system(size: 32, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)

          if model.form == .connection {
            Text(L10n.text("你的媒体世界，随时连接。"))
              .font(.subheadline)
              .foregroundStyle(.primary.opacity(0.60))
          } else if let addressText = model.selected?.address.url.absoluteString {
            Button {
              model.changeServer()
            } label: {
              HStack(spacing: 8) {
                Circle()
                  .fill(NativeTheme.success)
                  .frame(width: 7, height: 7)
                Text(addressText)
                  .font(.caption.monospaced().weight(.medium))
                  .foregroundStyle(.primary.opacity(0.88))
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .accessibilityIdentifier("native-v2-server")
                Image(systemName: "arrow.triangle.2.circlepath")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.primary.opacity(0.52))
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 7)
              .background {
                Capsule()
                  .fill(NativeTheme.chipFill)
                  .overlay {
                    Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.7)
                  }
              }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
      .padding(.top, 10)
      .padding(.bottom, 6)
    }
    .listRowBackground(Color.clear).listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
  }

  /// 地址是可编辑的标准输入；支持一键补全协议前缀，历史服务展示主机名与完整地址并保留左滑删除。
  private var connection: some View {
    Group {
      CinematicFormSection(
        footer: L10n.text("支持 HTTPS、局域网地址和部署子路径。")
      ) {
        HStack(spacing: 14) {
          Image(systemName: "link")
            .font(.body.weight(.medium))
            .foregroundStyle(focused == .address ? appearance.accentColor : .secondary)
            .frame(width: 24)
            .accessibilityHidden(true)
          HStack(spacing: 8) {
            TextField(
              L10n.text("MoviePilot 服务地址"), text: $model.address,
              prompt: fieldPrompt("MoviePilot 服务地址")
            )
            .keyboardType(.URL).textInputAutocapitalization(.never)
            .autocorrectionDisabled().submitLabel(.go).focused($focused, equals: .address)
            .accessibilityIdentifier("native-v2-address")
            .onSubmit {
              focused = nil
              model.connectAddress()
            }
            if !model.address.isEmpty {
              Button {
                model.address = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 18))
                  .frame(width: 44, height: 44).contentShape(Rectangle())
              }
              .buttonStyle(.plain).foregroundStyle(.secondary)
              .accessibilityLabel(L10n.text("清除地址"))
              .accessibilityIdentifier("native-v2-clear-address")
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        if !model.address.lowercased().hasPrefix("http://")
          && !model.address.lowercased().hasPrefix("https://")
        {
          CinematicFormDivider()
          HStack(spacing: 8) {
            Text("快捷前缀")
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
            ForEach(["https://", "http://"], id: \.self) { prefix in
              Button {
                model.address = prefix + model.address
                focused = .address
              } label: {
                Text(prefix)
                  .font(.caption.monospaced().weight(.semibold))
                  .foregroundStyle(appearance.accentColor)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background {
                    Capsule()
                      .fill(appearance.accentColor.opacity(colorScheme == .light ? 0.11 : 0.15))
                      .overlay {
                        Capsule().strokeBorder(
                          appearance.accentColor.opacity(0.28), lineWidth: 0.6)
                      }
                  }
              }
              .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 10)
        }
      }
      actionSection {
        primary("连接", id: "native-v2-connect", disabled: model.address.isEmpty || model.busy) {
          model.connectAddress()
        }
      }
      if model.resolvedCloudflareTargetAddress != nil || model.cloudflareChallengeDetected {
        cloudflareAccessSection
      }
      if !model.saved.isEmpty {
        Section {
          ForEach(model.saved, id: \.id) { instance in
            let host = instance.address.url.host ?? instance.address.url.absoluteString
            let isSelected = model.selected?.id == instance.id
            Button {
              model.connect(instance)
            } label: {
              CinematicPanel(padding: 13, showsShadow: false) {
                HStack(spacing: 12) {
                  ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                      .fill(
                        (isSelected ? NativeTheme.success : appearance.accentColor)
                          .opacity(colorScheme == .light ? 0.12 : 0.16)
                      )
                      .frame(width: 38, height: 38)
                    Image(systemName: "server.rack")
                      .font(.system(size: 16, weight: .semibold))
                      .foregroundStyle(isSelected ? NativeTheme.success : appearance.accentColor)
                  }
                  .accessibilityHidden(true)

                  VStack(alignment: .leading, spacing: 3) {
                    Text(host)
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                    Text(instance.address.url.absoluteString)
                      .font(.caption.monospaced())
                      .foregroundStyle(.secondary)
                      .lineLimit(nil)
                  }
                  Spacer(minLength: 8)
                  if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                      .font(.body)
                      .foregroundStyle(NativeTheme.success)
                      .accessibilityLabel(L10n.text("当前服务"))
                  } else {
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary.opacity(0.75))
                      .accessibilityHidden(true)
                  }
                }
              }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .accessibilityIdentifier("native-v2-saved-\(instance.address.url.absoluteString)")
            .swipeActions(allowsFullSwipe: false) {
              Button(L10n.text("删除"), role: .destructive) { pendingForget = instance }
            }
          }
        } header: {
          HStack(spacing: 6) {
            Text(L10n.text("已保存的服务"))
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.secondary)
            Text("\(model.saved.count)")
              .font(.caption2.monospacedDigit().weight(.semibold))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(NativeTheme.chipFill, in: Capsule())
          }
        }
        .textCase(nil)
        .disabled(model.busy)
      }
    }
  }

  /// 登录与首次创建使用独立字段语义；验证码只在服务端挑战后出现。
  private var authentication: some View {
    Group {
      CinematicFormSection(
        model.form == .initialization ? L10n.text("创建管理员") : nil,
        footer: model.form == .initialization
          ? L10n.text("密码为 6–50 位，至少包含字母、数字、符号中的两类。API Key 仅提交到此服务。") : nil
      ) {
        HStack(spacing: 14) {
          Image(systemName: "person")
            .font(.body.weight(.medium))
            .foregroundStyle(focused == .username ? appearance.accentColor : .secondary)
            .frame(width: 24)
            .accessibilityHidden(true)
          TextField(L10n.text("用户名"), text: $model.username, prompt: fieldPrompt("用户名"))
            .textContentType(.username).textInputAutocapitalization(.never)
            .autocorrectionDisabled().disabled(model.fixedUsername)
            .focused($focused, equals: .username).submitLabel(.next)
            .onSubmit { focused = .password }
            .accessibilityIdentifier("native-v2-username")
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        CinematicFormDivider()
        passwordField("密码", text: $model.password, field: .password, id: "native-v2-password")
        if model.form == .initialization {
          CinematicFormDivider()
          passwordField(
            "确认密码", text: $model.confirmation, field: .confirmation,
            id: "native-v2-confirmation")
          CinematicFormDivider()
          CinematicFormRow {
            VStack(alignment: .leading, spacing: 8) {
              Text("API Key").font(.caption).foregroundStyle(.secondary)
              HStack {
                Group {
                  if showsAPIKey {
                    TextField("API Key", text: $model.apiKey, prompt: fieldPrompt("API Key"))
                  } else {
                    SecureField("API Key", text: $model.apiKey, prompt: fieldPrompt("API Key"))
                  }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("native-v2-api-key")
                Button {
                  showsAPIKey.toggle()
                } label: {
                  Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.text(showsAPIKey ? "隐藏 API Key" : "显示 API Key"))
                .accessibilityIdentifier("native-v2-show-api-key")
                Button {
                  UIPasteboard.general.setItems(
                    [[UTType.utf8PlainText.identifier: model.apiKey]],
                    options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                } label: {
                  Image(systemName: "doc.on.doc")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.text("复制 API Key"))
                .accessibilityIdentifier("native-v2-copy-api-key")
              }
            }
          }
          CinematicFormDivider()
          CinematicFormRow(symbol: "arrow.clockwise") {
            rowAction("重新生成 API Key", id: "native-v2-regenerate-api-key") {
              model.regenerateKey()
            }
          }
        } else if model.needsOTP {
          CinematicFormDivider()
          HStack(spacing: 14) {
            Image(systemName: "number.shield")
              .font(.body.weight(.medium))
              .foregroundStyle(focused == .otp ? appearance.accentColor : .secondary)
              .frame(width: 24)
              .accessibilityHidden(true)
            TextField(
              L10n.text("身份验证器验证码"), text: $model.otp, prompt: fieldPrompt("身份验证器验证码")
            )
            .textContentType(.oneTimeCode).keyboardType(.numberPad)
            .focused($focused, equals: .otp)
            .accessibilityIdentifier("native-v2-otp")
          }
          .frame(minHeight: 50)
          .padding(.horizontal, 18)
          .padding(.vertical, 6)
        }
      }
      .disabled(model.busy)
      if model.form == .login {
        CinematicFormSection(
          footer: L10n.text("密码仅在本机安全保存，验证码不会保存。")
        ) {
          CinematicFormRow(symbol: "checkmark.shield") {
            Toggle(
              L10n.text("保持登录"),
              isOn: Binding(
                get: { model.rememberSession }, set: { model.setRememberSession($0) })
            )
            .tint(appearance.accentColor)
            .accessibilityIdentifier("native-v2-remember-session")
          }
          CinematicFormDivider()
          CinematicFormRow(symbol: "key.horizontal") {
            Toggle(
              L10n.text("记住账号密码"),
              isOn: Binding(
                get: { model.rememberCredentials }, set: { model.setRememberCredentials($0) })
            )
            .tint(appearance.accentColor)
            .accessibilityIdentifier("native-v2-remember-password")
          }
        }
        .disabled(model.busy)
      }
      actionSection {
        if model.form == .initialization {
          let isDisabled =
            model.username.isEmpty || model.password.isEmpty || model.confirmation.isEmpty
            || model.apiKey.isEmpty || model.busy
          primary("创建管理员", id: "native-v2-initialize", disabled: isDisabled) {
            model.initialize()
          }
        } else {
          let isDisabled = model.username.isEmpty || model.password.isEmpty || model.busy
          primary("登录", id: "native-v2-login", disabled: isDisabled) {
            model.login()
          }
        }
      }
      if model.resolvedCloudflareTargetAddress != nil || model.cloudflareChallengeDetected {
        cloudflareAccessSection
      }
    }
  }

  /// Cloudflare Access Managed OAuth 网关认证入口：支持一键拉起系统授权会话、查看授权态与清除。
  private var cloudflareAccessSection: some View {
    CinematicFormSection(
      footer: model.cloudflareChallengeDetected
        ? L10n.text("当前服务位于 Cloudflare Access 保护后，请先完成网关授权再连接。")
        : L10n.text("若服务部署在 Cloudflare Access 网关后，可先完成 OAuth 授权；不影响 MoviePilot 账号令牌。")
    ) {
      CinematicFormRow(symbol: "shield.lefthalf.filled") {
        Button {
          model.authenticateCloudflareAccess()
        } label: {
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              Text(
                model.cloudflareAuthenticating
                  ? L10n.text("正在进行 Cloudflare Access 认证…")
                  : (model.hasActiveCloudflareSession
                    ? L10n.text("重新进行 Cloudflare Access 认证")
                    : L10n.text("通过 Cloudflare Access 认证"))
              )
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(
                model.cloudflareChallengeDetected ? appearance.accentColor : .primary)
              if model.hasActiveCloudflareSession {
                Text(L10n.text("已获取 Cloudflare Access 网关凭据"))
                  .font(.caption2)
                  .foregroundStyle(NativeTheme.success)
              }
            }
            Spacer(minLength: 8)
            if model.cloudflareAuthenticating {
              ProgressView()
            } else {
              Image(systemName: "arrow.up.forward.app")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appearance.accentColor)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy || model.cloudflareAuthenticating || model.resolvedCloudflareTargetAddress == nil)
        .accessibilityIdentifier("native-v2-cf-access-auth")
      }
      if model.hasActiveCloudflareSession {
        CinematicFormDivider()
        CinematicFormRow(symbol: "trash") {
          Button(role: .destructive) {
            model.clearCloudflareAccess()
          } label: {
            Text(L10n.text("清除 Cloudflare Access 授权"))
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .foregroundStyle(NativeTheme.danger)
          .disabled(model.busy || model.cloudflareAuthenticating)
          .accessibilityIdentifier("native-v2-cf-access-clear")
        }
      }
    }
  }

  /// 显式可见性只影响当前草稿；用户可检查手动输入，截图与暂离时默认重新遮盖。
  private func passwordField(
    _ title: String, text: Binding<String>, field: Field, id: String
  ) -> some View {
    HStack(spacing: 14) {
      Image(systemName: "lock")
        .font(.body.weight(.medium))
        .foregroundStyle(focused == field ? appearance.accentColor : .secondary)
        .frame(width: 24)
        .accessibilityHidden(true)
      HStack(spacing: 8) {
        Group {
          if showsPassword {
            TextField(L10n.text(title), text: text, prompt: fieldPrompt(title))
          } else {
            SecureField(L10n.text(title), text: text, prompt: fieldPrompt(title))
          }
        }
        .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
        .focused($focused, equals: field)
        .submitLabel(
          field == .password && (model.form == .initialization || model.needsOTP) ? .next : .done
        )
        .onSubmit {
          focused =
            field == .password
            ? (model.form == .initialization ? .confirmation : (model.needsOTP ? .otp : nil)) : nil
        }
        .accessibilityIdentifier(id)
        if field == .password {
          Button {
            showsPassword.toggle()
          } label: {
            Image(systemName: showsPassword ? "eye.slash" : "eye")
              .font(.system(size: 18))
              .frame(width: 44, height: 44).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .accessibilityLabel(L10n.text(showsPassword ? "隐藏密码" : "显示密码"))
          .accessibilityIdentifier("native-v2-show-password")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 50)
    .padding(.horizontal, 18)
    .padding(.vertical, 6)
  }

  /// 换实例、换表单或离开前台后，不继承用户刚刚打开的明文显示选项。
  private func concealSecrets() {
    showsPassword = false
    showsAPIKey = false
    focused = nil
  }

  /// 透底表面上的空字段保持可读；只调整原生 prompt，字段标签与输入语义保持不变。
  private func fieldPrompt(_ key: String) -> Text {
    Text(L10n.text(key)).foregroundColor(.secondary)
  }

  /// 将行内点击区域放进按钮标签，辅助功能边界与实际触控区共同覆盖至少 44pt。
  private func rowAction(
    _ key: String, id: String, role: ButtonRole? = nil, action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Text(L10n.text(key)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier(id)
  }

  /// 主题强调色渐变胶囊主操作按钮（禁用态转为低饱和通透玻璃胶囊），同时适配深浅色模式并先收起键盘再提交。
  private func primary(
    _ key: String, id: String, disabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button {
      focused = nil
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      action()
    } label: {
      Text(L10n.text(key))
        .font(.body.weight(.semibold))
        .foregroundStyle(
          disabled ? Color.primary.opacity(0.48) : Color.white
        )
        .frame(maxWidth: .infinity, minHeight: 52)
        .background {
          if disabled {
            Capsule()
              .fill(appearance.accentColor.opacity(colorScheme == .light ? 0.14 : 0.16))
              .overlay {
                Capsule().strokeBorder(
                  appearance.accentColor.opacity(colorScheme == .light ? 0.24 : 0.28),
                  lineWidth: 0.7)
              }
          } else {
            Capsule()
              .fill(
                LinearGradient(
                  colors: [
                    appearance.accentColor,
                    appearance.accentColor.opacity(colorScheme == .light ? 0.86 : 0.78),
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
              .overlay {
                Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.7)
              }
          }
        }
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityIdentifier(id)
  }

  /// 主动作与正文材质分开，避免把 Liquid Glass 叠加进整块表单背景。
  private func actionSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    Section {
      CinematicGlassGroup { content() }
        .listRowBackground(Color.clear).listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
  }

  /// 换地址在忙碌时仍可取消；从设置切换服务进入连接页时提供左上角返回；语言始终用自身名称，误选后也能找回。
  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if showingEntryForm, model.form == .connection, authenticated || model.canCancelSwitchServer {
      ToolbarItem(placement: .navigationBarLeading) {
        Button {
          model.cancelSwitchServer()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left")
              .font(.body.weight(.semibold))
            Text(L10n.text("返回"))
          }
        }
        .tint(.primary)
        .accessibilityLabel(L10n.text("返回"))
        .accessibilityIdentifier("native-v2-cancel-switch")
      }
    } else if showingEntryForm, model.form != .connection {
      ToolbarItem(placement: .navigationBarLeading) {
        Button {
          model.changeServer()
        } label: {
          Image(systemName: "server.rack")
        }
        .tint(.primary)
        .accessibilityLabel(L10n.text("更改地址"))
        .accessibilityIdentifier("native-v2-change-server")
      }
    }
    if showingEntryForm {
      ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
          languageOptions
        } label: {
          Image(systemName: "globe")
        }
        .tint(.primary)
        .accessibilityLabel(L10n.text("语言"))
        .accessibilityIdentifier("native-v2-language")
      }
    }
    if showingEntryForm {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(L10n.text("完成")) {
          focused = nil
          UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
      }
    }
  }

  /// 登录前系统集成提示横幅（如暂不支持的文件类型、无效链接或需要先完成登录的提示）。
  private func unauthenticatedBannerOverlay(_ message: String) -> some View {
    VStack {
      HStack(spacing: 10) {
        Image(systemName: "info.circle.fill")
          .foregroundStyle(NativeTheme.brand)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
        Button {
          routeHub.bannerMessage = nil
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("关闭提示"))
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(.primary.opacity(0.16), lineWidth: 0.7)
      }
      .padding(.horizontal, 16)
      .padding(.top, 56)
      Spacer(minLength: 0)
    }
  }

  /// 未登录状态下最小化本地/外部音频播放时仍提供悬浮迷你控制条，方便随时还原或停止。
  private func unauthenticatedMiniMusicBar(_ state: NativeMiniMusicState) -> some View {
    VStack {
      Spacer(minLength: 0)
      HStack(spacing: 11) {
        Group {
          if let artwork = state.artwork {
            Image(uiImage: artwork).resizable().scaledToFill()
          } else {
            ZStack {
              LinearGradient(
                colors: [NativeTheme.brand.opacity(0.68), NativeTheme.brand.opacity(0.32)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
              Image(systemName: "music.note")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            }
          }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        VStack(alignment: .leading, spacing: 2) {
          Text(state.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          if !state.subtitle.isEmpty {
            Text(state.subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button {
          playbackLauncher.toggleMinimizedPlayPause()
        } label: {
          Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
            .font(.subheadline.weight(.semibold))
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)

        Button {
          playbackLauncher.stopMinimizedAudio()
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(.primary.opacity(0.16), lineWidth: 0.7)
      }
      .contentShape(Rectangle())
      .onTapGesture {
        playbackLauncher.expandMinimizedAudio()
      }
      .frame(maxWidth: 520)
      .padding(.horizontal, 16)
      .padding(.bottom, 14)
    }
    .frame(maxWidth: .infinity)
  }

  /// 登录前工具栏和登录后账号页提供同一组系统语言选项。
  private var languageOptions: some View {
    ForEach(AppLanguage.allCases, id: \.self) { language in
      Button {
        model.selectLanguage(language)
      } label: {
        if model.language == language {
          Label(language.title, systemImage: "checkmark")
        } else {
          Text(language.title)
        }
      }
    }
  }
}
