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
  @FocusState private var focused: Field?
  @Environment(\.scenePhase) private var scenePhase

  /// 显式观察会话发布者，避免仅刷新表单而漏掉异步失效状态。
  init(model: NativeAppModel) {
    self.model = model
    manager = model.manager
  }

  /// 系统导航与可滚动表单承担安全区、键盘、旋转和辅助功能字号布局。
  var body: some View {
    NavigationStack {
      Form {
        brand
        if let message = model.messageKey {
          Section {
            Text(L10n.text(message))
              .font(.callout)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("native-v2-message")
              .accessibilityAddTraits(.updatesFrequently)
            if case .failed(_, .api) = manager.state, let selected = model.selected {
              Button(L10n.text("重试连接")) { model.connect(selected) }
                .accessibilityIdentifier("native-v2-retry")
            }
          }
        }
        if model.busy {
          Section {
            HStack(spacing: 12) {
              ProgressView()
              Text(L10n.text("正在连接…"))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("native-v2-progress")
          }
        }
        if case .authenticated(let snapshot) = manager.state {
          account(snapshot)
        } else if model.form == .connection {
          connection
        } else {
          authentication
        }
      }
      .scrollContentBackground(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .background(Color(uiColor: AccountAppearance.background(for: model.selected?.id)))
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { toolbar }
      .tint(Color(uiColor: AccountAppearance.accent(for: model.selected?.id)))
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
    }
    .environment(\.locale, Locale(identifier: model.language.rawValue))
    .preferredColorScheme(preferredScheme)
    .onChange(of: manager.state) { model.received($0) }
    .onChange(of: model.selected?.id) { _ in concealSecrets() }
    .onChange(of: model.form) { _ in concealSecrets() }
    .onChange(of: scenePhase) { if $0 != .active { concealSecrets() } }
  }

  /// 每次换实例重新读取其明确明暗选择；系统模式不继承上一个实例的强制外观。
  private var preferredScheme: ColorScheme? {
    switch AccountAppearance.interfaceStyle(for: model.selected?.id) {
    case .light: .light
    case .dark: .dark
    default: nil
    }
  }

  /// 标题只反映真实可用的入口，不把此基础阶段命名为完整首页。
  private var title: String {
    if case .authenticated = manager.state { return L10n.text("账号与服务") }
    switch model.form {
    case .connection: return L10n.text("连接服务")
    case .login: return L10n.text("登录")
    case .initialization: return L10n.text("首次设置")
    }
  }

  /// 品牌图标沿用现有资源，字体随系统缩放，不固定海报式大标题高度。
  private var brand: some View {
    Section {
      HStack(spacing: 16) {
        Image("BrandMark")
          .resizable().scaledToFit().frame(width: 56, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text("MoviePilot").font(.title2.bold())
          Text(L10n.text("你的媒体世界，随时连接。"))
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 12)
    }
    .listRowBackground(Color.clear)
  }

  /// 地址是可编辑的标准输入；历史服务使用原 UUID 连接并保留系统左滑删除。
  private var connection: some View {
    Group {
      Section {
        HStack {
          TextField(L10n.text("MoviePilot 服务地址"), text: $model.address)
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
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .accessibilityLabel(L10n.text("清除地址"))
            .accessibilityIdentifier("native-v2-clear-address")
          }
        }
        primary("连接", id: "native-v2-connect") { model.connectAddress() }
          .disabled(model.address.isEmpty || model.busy)
      } header: {
        Text(L10n.text("连接服务"))
      } footer: {
        Text(L10n.text("支持 HTTPS、局域网地址和部署子路径。"))
      }
      if !model.saved.isEmpty {
        Section(L10n.text("已保存的服务")) {
          ForEach(model.saved, id: \.id) { instance in
            Button {
              model.connect(instance)
            } label: {
              HStack {
                Text(instance.address.url.absoluteString)
                  .foregroundStyle(.primary).lineLimit(nil)
                Spacer(minLength: 8)
                if model.selected?.id == instance.id {
                  Image(systemName: "checkmark.circle.fill")
                    .accessibilityLabel(L10n.text("当前服务"))
                }
              }
              .padding(.vertical, 4)
            }
            .accessibilityIdentifier("native-v2-saved-\(instance.address.url.absoluteString)")
            .swipeActions(allowsFullSwipe: false) {
              Button(L10n.text("删除"), role: .destructive) { pendingForget = instance }
            }
          }
        }
        .disabled(model.busy)
      }
    }
  }

  /// 登录与首次创建使用独立字段语义；验证码只在服务端挑战后出现。
  private var authentication: some View {
    Group {
      Section {
        Text(model.selected?.address.url.absoluteString ?? "")
          .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
          .accessibilityIdentifier("native-v2-server")
      }
      Section {
        TextField(L10n.text("用户名"), text: $model.username)
          .textContentType(.username).textInputAutocapitalization(.never)
          .autocorrectionDisabled().disabled(model.fixedUsername)
          .focused($focused, equals: .username).submitLabel(.next)
          .onSubmit { focused = .password }
          .accessibilityIdentifier("native-v2-username")
        passwordField("密码", text: $model.password, field: .password, id: "native-v2-password")
        if model.form == .initialization {
          passwordField(
            "确认密码", text: $model.confirmation, field: .confirmation,
            id: "native-v2-confirmation")
          VStack(alignment: .leading, spacing: 8) {
            Text("API Key").font(.caption).foregroundStyle(.secondary)
            HStack {
              Group {
                if showsAPIKey {
                  TextField("API Key", text: $model.apiKey)
                } else {
                  SecureField("API Key", text: $model.apiKey)
                }
              }
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .accessibilityIdentifier("native-v2-api-key")
              Button {
                showsAPIKey.toggle()
              } label: {
                Image(systemName: showsAPIKey ? "eye.slash" : "eye")
              }
              .buttonStyle(.borderless)
              .accessibilityLabel(L10n.text(showsAPIKey ? "隐藏 API Key" : "显示 API Key"))
              Button {
                UIPasteboard.general.setItems(
                  [[UTType.utf8PlainText.identifier: model.apiKey]],
                  options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
              } label: {
                Image(systemName: "doc.on.doc")
              }
              .buttonStyle(.borderless).accessibilityLabel(L10n.text("复制 API Key"))
            }
          }
          Button(L10n.text("重新生成 API Key")) { model.regenerateKey() }
        } else if model.needsOTP {
          TextField(L10n.text("身份验证器验证码"), text: $model.otp)
            .textContentType(.oneTimeCode).keyboardType(.numberPad)
            .focused($focused, equals: .otp)
            .accessibilityIdentifier("native-v2-otp")
        }
      } header: {
        Text(L10n.text(model.form == .initialization ? "创建管理员" : "登录"))
      } footer: {
        if model.form == .initialization {
          Text(L10n.text("密码为 6–50 位，至少包含字母、数字、符号中的两类。API Key 仅提交到此服务。"))
        }
      }
      .disabled(model.busy)
      if model.form == .login {
        Section {
          Toggle(L10n.text("保持登录"), isOn: $model.rememberSession)
            .accessibilityIdentifier("native-v2-remember-session")
          Toggle(
            L10n.text("记住账号密码"),
            isOn: Binding(
              get: { model.rememberCredentials }, set: { model.setRememberCredentials($0) })
          ).accessibilityIdentifier("native-v2-remember-password")
        } footer: {
          Text(L10n.text("密码仅在本机安全保存，验证码不会保存。"))
        }
        .disabled(model.busy)
      }
      Section {
        if model.form == .initialization {
          primary("创建管理员", id: "native-v2-initialize") { model.initialize() }
            .disabled(
              model.username.isEmpty || model.password.isEmpty || model.confirmation.isEmpty
                || model.apiKey.isEmpty || model.busy)
        } else {
          primary("登录", id: "native-v2-login") { model.login() }
            .disabled(model.username.isEmpty || model.password.isEmpty || model.busy)
        }
      }
    }
  }

  /// 显式可见性只影响当前草稿；用户可检查手动输入，截图与暂离时默认重新遮盖。
  private func passwordField(
    _ title: String, text: Binding<String>, field: Field, id: String
  ) -> some View {
    HStack {
      Group {
        if showsPassword {
          TextField(L10n.text(title), text: text)
        } else {
          SecureField(L10n.text(title), text: text)
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
        }
        .buttonStyle(.borderless)
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

  /// 首个真实原生页面只展示已验证身份及可执行的会话管理操作。
  private func account(_ snapshot: NativeSessionSnapshot) -> some View {
    Group {
      Section(L10n.text("当前账号")) {
        Label(snapshot.user.name, systemImage: "person.crop.circle.fill")
          .font(.title3.weight(.semibold)).padding(.vertical, 4)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(snapshot.user.name)
          .accessibilityIdentifier("native-v2-account")
        if snapshot.user.isSuperuser { Text(L10n.text("管理员")) }
        Text(snapshot.instance.address.url.absoluteString)
          .foregroundStyle(.secondary).textSelection(.enabled)
        Button(L10n.text("刷新账号状态")) { model.refreshIdentity() }
          .accessibilityIdentifier("native-v2-refresh")
          .disabled(model.busy)
      }
      Section {
        Button(L10n.text("切换服务")) { model.changeServer() }
          .accessibilityIdentifier("native-v2-switch")
        Button(L10n.text("退出登录"), role: .destructive) { model.logout() }
          .accessibilityIdentifier("native-v2-logout")
      }
    }
  }

  /// 主操作保留系统点击区域并先收起键盘，不把提交绑定到输入框变化。
  private func primary(_ key: String, id: String, action: @escaping () -> Void) -> some View {
    Button {
      focused = nil
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      action()
    } label: {
      HStack {
        Spacer()
        Text(L10n.text(key)).fontWeight(.semibold)
        Image(systemName: "arrow.right")
        Spacer()
      }.frame(minHeight: 44)
    }
    .accessibilityIdentifier(id)
  }

  /// 换地址在忙碌时仍可取消；语言始终用自身名称，误选后也能找回。
  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if model.form != .connection {
      ToolbarItem(placement: .navigationBarLeading) {
        Button {
          model.changeServer()
        } label: {
          Image(systemName: "server.rack")
        }
        .accessibilityLabel(L10n.text("更改地址"))
        .accessibilityIdentifier("native-v2-change-server")
      }
    }
    ToolbarItem(placement: .navigationBarTrailing) {
      Menu {
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
      } label: {
        Image(systemName: "globe")
      }
      .accessibilityLabel(L10n.text("语言"))
      .accessibilityIdentifier("native-v2-language")
    }
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
