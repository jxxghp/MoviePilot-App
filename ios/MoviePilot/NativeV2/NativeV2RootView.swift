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
  @State private var pendingForget: SavedInstance?
  @State private var showsAPIKey = false
  @State private var showsPassword = false
  @State private var showsPlugins = false
  @State private var hasCompletedInitialBoot = false
  @FocusState private var focused: Field?
  @Environment(\.scenePhase) private var scenePhase

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
      } else if case .authenticated(let snapshot) = manager.state,
        let session = manager.currentSession, session.scope == snapshot.scope
      {
        NativeV2MainShell(
          session: session,
          snapshot: snapshot,
          showsPlugins: $showsPlugins,
          currentLanguage: model.language,
          onSelectLanguage: { model.selectLanguage($0) },
          onSwitchServer: { model.changeServer() },
          onLogout: { model.logout() },
          pluginDestination: {
            if let current = manager.currentSession, current.scope == snapshot.scope {
              NativePluginCatalogView(session: current)
            }
          }
        )
        .id(snapshot.scope.generation)
      } else {
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
                if case .authenticated = manager.state {
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
          .navigationTitle(title)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar { toolbar }
        }
      }
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
      model.received(state)
      if case .authenticated(let snapshot) = state, snapshot.user.isSuperuser {
        return
      }
      showsPlugins = false
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

  /// 标题只反映真实可用的入口，不把此基础阶段命名为完整首页。
  private var title: String {
    if case .authenticated = manager.state { return "" }
    switch model.form {
    case .connection: return L10n.text("连接服务")
    case .login: return L10n.text("登录")
    case .initialization: return L10n.text("首次设置")
    }
  }

  /// 居中影院风品牌主视觉：图标微光光晕、品牌标题、副标，以及登录态下的已连接服务地址胶囊。
  private var brand: some View {
    Section {
      VStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(
              RadialGradient(
                colors: [
                  Color(red: 0.58, green: 0.38, blue: 0.98).opacity(0.42),
                  Color(red: 0.84, green: 0.44, blue: 0.72).opacity(0.16),
                  .clear,
                ],
                center: .center,
                startRadius: 8,
                endRadius: 64
              )
            )
            .frame(width: 126, height: 126)
            .accessibilityHidden(true)

          Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .shadow(
              color: Color(red: 0.45, green: 0.25, blue: 0.85).opacity(0.45), radius: 18, y: 8
            )
            .accessibilityHidden(true)
        }
        .frame(height: 92)

        VStack(spacing: 5) {
          Text("MoviePilot")
            .font(.title.bold())
            .foregroundStyle(.primary)
          Text(L10n.text("你的媒体世界，随时连接。"))
            .font(.subheadline)
            .foregroundStyle(.primary.opacity(0.68))
            .multilineTextAlignment(.center)
        }

        if model.form != .connection, let addressText = model.selected?.address.url.absoluteString {
          Button {
            model.changeServer()
          } label: {
            HStack(spacing: 7) {
              Circle()
                .fill(Color(red: 0.42, green: 0.90, blue: 0.60))
                .frame(width: 7, height: 7)
              Text(addressText)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(.primary.opacity(0.90))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("native-v2-server")
              Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.55))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
              Capsule()
                .fill(.primary.opacity(0.10))
                .overlay { Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.6) }
            }
          }
          .buttonStyle(.plain)
          .padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 8)
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
        CinematicFormRow(symbol: "link") {
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
        if !model.address.lowercased().hasPrefix("http://")
          && !model.address.lowercased().hasPrefix("https://")
        {
          CinematicFormDivider()
          HStack(spacing: 8) {
            Text("快捷前缀")
              .font(.caption2)
              .foregroundStyle(.primary.opacity(0.52))
            ForEach(["https://", "http://"], id: \.self) { prefix in
              Button {
                model.address = prefix + model.address
                focused = .address
              } label: {
                Text(prefix)
                  .font(.caption.monospaced().weight(.semibold))
                  .foregroundStyle(NativeTheme.brand)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 4)
                  .background {
                    Capsule()
                      .fill(.primary.opacity(0.09))
                      .overlay { Capsule().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6) }
                  }
              }
              .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
        }
      }
      actionSection {
        primary("连接", id: "native-v2-connect", disabled: model.address.isEmpty || model.busy) {
          model.connectAddress()
        }
      }
      if !model.saved.isEmpty {
        Section {
          ForEach(model.saved, id: \.id) { instance in
            let host = instance.address.url.host ?? instance.address.url.absoluteString
            let isSelected = model.selected?.id == instance.id
            Button {
              model.connect(instance)
            } label: {
              CinematicPanel(padding: 13) {
                HStack(spacing: 12) {
                  Image(systemName: "server.rack")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(
                      isSelected
                        ? NativeTheme.success
                        : .primary
                    )
                    .frame(width: 28, height: 28)

                  VStack(alignment: .leading, spacing: 3) {
                    Text(host)
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                    Text(instance.address.url.absoluteString)
                      .font(.caption.monospaced())
                      .foregroundStyle(.primary.opacity(0.60))
                      .lineLimit(nil)
                  }
                  Spacer(minLength: 8)
                  if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(NativeTheme.success)
                      .accessibilityLabel(L10n.text("当前服务"))
                  } else {
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.primary.opacity(0.40))
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
          Text(L10n.text("已保存的服务"))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.72))
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
        CinematicFormRow(symbol: "person") {
          TextField(L10n.text("用户名"), text: $model.username, prompt: fieldPrompt("用户名"))
            .textContentType(.username).textInputAutocapitalization(.never)
            .autocorrectionDisabled().disabled(model.fixedUsername)
            .focused($focused, equals: .username).submitLabel(.next)
            .onSubmit { focused = .password }
            .accessibilityIdentifier("native-v2-username")
        }
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
          CinematicFormRow(symbol: "number.shield") {
            TextField(
              L10n.text("身份验证器验证码"), text: $model.otp, prompt: fieldPrompt("身份验证器验证码")
            )
            .textContentType(.oneTimeCode).keyboardType(.numberPad)
            .focused($focused, equals: .otp)
            .accessibilityIdentifier("native-v2-otp")
          }
        }
      }
      .disabled(model.busy)
      if model.form == .login {
        CinematicFormSection(
          footer: L10n.text("密码仅在本机安全保存，验证码不会保存。")
        ) {
          CinematicFormRow {
            Toggle(L10n.text("保持登录"), isOn: $model.rememberSession)
              .tint(Color(red: 0.62, green: 0.48, blue: 0.94))
              .accessibilityIdentifier("native-v2-remember-session")
          }
          CinematicFormDivider()
          CinematicFormRow {
            Toggle(
              L10n.text("记住账号密码"),
              isOn: Binding(
                get: { model.rememberCredentials }, set: { model.setRememberCredentials($0) })
            )
            .tint(Color(red: 0.62, green: 0.48, blue: 0.94))
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
    }
  }

  /// 显式可见性只影响当前草稿；用户可检查手动输入，截图与暂离时默认重新遮盖。
  private func passwordField(
    _ title: String, text: Binding<String>, field: Field, id: String
  ) -> some View {
    CinematicFormRow(symbol: "lock") {
      Group {
        if showsPassword {
          TextField(L10n.text(title), text: text, prompt: fieldPrompt(title))
        } else {
          SecureField(L10n.text(title), text: text, prompt: fieldPrompt(title))
        }
      }
      // 首次创建先保留标准密码输入；系统自动生成和 Passkey 在 P6 完整验收。
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
        .accessibilityLabel(L10n.text(showsPassword ? "隐藏密码" : "显示密码"))
        .accessibilityIdentifier("native-v2-show-password")
      }
    }
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

  /// 高对比度白色胶囊主操作按钮（与详情页/设置中心视觉统一），先收起键盘再提交。
  private func primary(
    _ key: String, id: String, disabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button {
      focused = nil
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      action()
    } label: {
      HStack(spacing: 8) {
        Text(L10n.text(key))
          .font(.headline.weight(.bold))
        Image(systemName: "arrow.right")
          .font(.subheadline.weight(.bold))
      }
      .foregroundStyle(
        disabled ? .white.opacity(0.48) : Color(red: 0.10, green: 0.08, blue: 0.16)
      )
      .frame(maxWidth: .infinity, minHeight: 52)
      .background {
        Capsule()
          .fill(disabled ? .white.opacity(0.14) : .white)
          .overlay {
            if disabled {
              Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.7)
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

  /// 换地址在忙碌时仍可取消；语言始终用自身名称，误选后也能找回。
  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if !authenticated, model.form != .connection {
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
    if !authenticated {
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
    if !authenticated {
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
