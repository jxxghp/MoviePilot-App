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
  @State private var pluginScope: NativeSessionScope?
  @FocusState private var focused: Field?
  @Environment(\.scenePhase) private var scenePhase

  /// 显式观察会话发布者，避免仅刷新表单而漏掉异步失效状态。
  init(model: NativeAppModel) {
    self.model = model
    manager = model.manager
  }

  /// 单一 Rex 背景贯通安全区；系统表单继续承担键盘、旋转和辅助功能布局。
  var body: some View {
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
          .frame(maxWidth: 680)
          .onChange(of: authenticated) { _ in scroll.scrollTo("native-v2-top", anchor: .top) }
          .onChange(of: model.form) { _ in scroll.scrollTo("native-v2-top", anchor: .top) }
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar { toolbar }
      .navigationDestination(isPresented: $showsPlugins) {
        if let session = manager.currentSession, session.scope == pluginScope {
          NativePluginCatalogView(session: session)
        }
      }
      .tint(.white)
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
    .preferredColorScheme(.dark)
    .onChange(of: manager.state) { state in
      model.received(state)
      if case .authenticated(let snapshot) = state,
        snapshot.scope == pluginScope, snapshot.user.isSuperuser
      {
        return
      }
      showsPlugins = false
      pluginScope = nil
    }
    .onChange(of: model.selected?.id) { _ in concealSecrets() }
    .onChange(of: model.form) { _ in concealSecrets() }
    .onChange(of: scenePhase) { if $0 != .active { concealSecrets() } }
    // UIKit 承载的 UIHostingController 不保证发布 SwiftUI scenePhase，直接观察系统场景通知。
    .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) { _ in
      concealSecrets()
    }
  }

  /// 身份页与输入页切换后重置滚动位置，避免沿用大字登录页底部偏移而藏住当前账号。
  private var authenticated: Bool {
    if case .authenticated = manager.state { return true }
    return false
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
      HStack(spacing: 18) {
        Image("BrandMark")
          .resizable().scaledToFit().frame(width: 64, height: 64)
          .clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text("MoviePilot").font(.title2.bold())
          Text(L10n.text("你的媒体世界，随时连接。"))
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 18)
    }
    .listRowBackground(Color.clear).listRowSeparator(.hidden)
  }

  /// 地址是可编辑的标准输入；历史服务使用原 UUID 连接并保留系统左滑删除。
  private var connection: some View {
    Group {
      CinematicFormSection(
        L10n.text("连接服务"),
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
      }
      actionSection {
        primary("连接", id: "native-v2-connect") { model.connectAddress() }
          .disabled(model.address.isEmpty || model.busy)
      }
      if !model.saved.isEmpty {
        Section(L10n.text("已保存的服务")) {
          ForEach(model.saved, id: \.id) { instance in
            Button {
              model.connect(instance)
            } label: {
              CinematicPanel(padding: 0) {
                CinematicFormRow(symbol: "server.rack") {
                  HStack {
                    Text(instance.address.url.absoluteString)
                      .foregroundStyle(.primary).lineLimit(nil)
                    Spacer(minLength: 8)
                    if model.selected?.id == instance.id {
                      Image(systemName: "checkmark.circle.fill")
                        .accessibilityLabel(L10n.text("当前服务"))
                    } else {
                      Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    }
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
        }
        .textCase(nil)
        .disabled(model.busy)
      }
    }
  }

  /// 登录与首次创建使用独立字段语义；验证码只在服务端挑战后出现。
  private var authentication: some View {
    Group {
      CinematicFormSection {
        CinematicFormRow(symbol: "server.rack") {
          Text(model.selected?.address.url.absoluteString ?? "")
            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            .accessibilityIdentifier("native-v2-server")
        }
      }
      CinematicFormSection(
        L10n.text(model.form == .initialization ? "创建管理员" : "登录"),
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
              .tint(.green).accessibilityIdentifier("native-v2-remember-session")
          }
          CinematicFormDivider()
          CinematicFormRow {
            Toggle(
              L10n.text("记住账号密码"),
              isOn: Binding(
                get: { model.rememberCredentials }, set: { model.setRememberCredentials($0) })
            ).tint(.green).accessibilityIdentifier("native-v2-remember-password")
          }
        }
        .disabled(model.busy)
      }
      actionSection {
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
    Text(L10n.text(key)).foregroundColor(.white.opacity(0.70))
  }

  /// 首个真实原生页面只展示已验证身份及可执行的会话管理操作。
  private func account(_ snapshot: NativeSessionSnapshot) -> some View {
    Group {
      CinematicFormSection(L10n.text("当前账号")) {
        CinematicFormRow(symbol: "person.crop.circle.fill") {
          Text(snapshot.user.name)
            .font(.title3.weight(.semibold)).padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(snapshot.user.name)
            .accessibilityIdentifier("native-v2-account")
        }
        if snapshot.user.isSuperuser {
          CinematicFormDivider()
          CinematicFormRow(symbol: "checkmark.shield") { Text(L10n.text("管理员")) }
        }
        CinematicFormDivider()
        CinematicFormRow(symbol: "server.rack") {
          Text(snapshot.instance.address.url.absoluteString)
            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        CinematicFormDivider()
        CinematicFormRow(symbol: "arrow.clockwise") {
          rowAction("刷新账号状态", id: "native-v2-refresh") { model.refreshIdentity() }
            .disabled(model.busy)
        }
      }
      CinematicFormSection {
        if snapshot.user.isSuperuser {
          CinematicFormRow(symbol: "puzzlepiece.extension") {
            rowAction("插件", id: "native-v2-plugins") {
              pluginScope = snapshot.scope
              showsPlugins = true
            }
          }
          CinematicFormDivider()
        }
        CinematicFormRow(symbol: "arrow.left.arrow.right") {
          rowAction("切换服务", id: "native-v2-switch") { model.changeServer() }
        }
        CinematicFormDivider()
        CinematicFormRow(symbol: "rectangle.portrait.and.arrow.right") {
          rowAction("退出登录", id: "native-v2-logout", role: .destructive) { model.logout() }
        }
      }
    }
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

  /// 主操作保留系统点击区域并先收起键盘，不把提交绑定到输入框变化。
  private func primary(_ key: String, id: String, action: @escaping () -> Void) -> some View {
    CinematicPrimaryAction(title: L10n.text(key), symbol: "arrow.right") {
      focused = nil
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      action()
    }
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
