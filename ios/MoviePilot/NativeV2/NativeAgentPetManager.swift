import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 后端 `GET /api/v1/plugin/agent_pets` 返回的单个助手形象声明（对齐 Web `AgentPetDeclaration` v1）。
struct NativeAgentPetDeclaration: Codable, Identifiable, Equatable, Sendable {
  let pluginID: String
  let sourcePluginID: String?
  let pluginName: String?
  let key: String
  let name: String
  let description: String?
  let mode: String
  let component: String?
  let apiVersion: Int?
  let previewURL: String?
  let avatarURL: String?
  let remoteURL: String?
  let pluginVersion: String?
  let bubbles: String?
  let randomActions: [String]?

  var id: String { "\(pluginID):\(key)" }
  var resolvedSourcePluginID: String {
    (sourcePluginID?.isEmpty == false ? sourcePluginID : nil) ?? pluginID
  }
  var resolvedPluginName: String { (pluginName?.isEmpty == false ? pluginName : nil) ?? pluginID }
  var resolvedComponent: String {
    let raw = (component ?? "AgentPet").trimmingCharacters(in: .whitespacesAndNewlines)
    return raw.hasPrefix("./") ? String(raw.dropFirst(2)) : (raw.isEmpty ? "AgentPet" : raw)
  }
  var isStageMode: Bool { mode == "stage" }

  /// 映射后端蛇形命名字段与 Swift 属性。
  enum CodingKeys: String, CodingKey {
    case pluginID = "plugin_id"
    case sourcePluginID = "source_plugin_id"
    case pluginName = "plugin_name"
    case key
    case name
    case description
    case mode
    case component
    case apiVersion = "api_version"
    case previewURL = "preview_url"
    case avatarURL = "avatar_url"
    case remoteURL = "remote_url"
    case pluginVersion = "plugin_version"
    case bubbles
    case randomActions = "random_actions"
  }
}

/// 用户持久化在 `user/config/AgentPet` 中的形象选择（与 Web 端 100% 互通）。
enum NativeAgentPetSelection: Equatable, Sendable {
  case followDefault
  case builtin
  case plugin(pluginID: String, key: String)

  var petID: String? {
    if case .plugin(let pid, let key) = self { return "\(pid):\(key)" }
    return nil
  }
}

/// 当前登录会话作用域的 Agent 助手形象管理器：
/// - 同步 `GET /api/v1/plugin/agent_pets`、`GET/POST /api/v1/user/config/AgentPet` 与全局默认 `AI_AGENT_PET`；
/// - 加载失败或运行时出错自动记入 `failedIDs` 并无感回退原生内置机器人，切换形象或手动刷新后自动恢复重试。
@MainActor
final class NativeAgentPetStore: ObservableObject {
  private static var current: NativeAgentPetStore?

  /// 返回与当前登录会话匹配的单例助手形象仓库。
  static func shared(for session: NativeSession) -> NativeAgentPetStore {
    if let existing = current, existing.session.scope == session.scope {
      return existing
    }
    current?.cancelTasks()
    let created = NativeAgentPetStore(session: session)
    current = created
    return created
  }

  /// 清除当前会话仓库并取消未完成的刷新任务。
  static func resetAll() {
    current?.cancelTasks()
    current = nil
  }

  let session: NativeSession

  @Published private(set) var declarations: [NativeAgentPetDeclaration] = []
  @Published private(set) var userSelection: NativeAgentPetSelection = .followDefault
  @Published private(set) var adminDefaultPetID: String = ""
  @Published private(set) var failedIDs: Set<String> = []
  @Published private(set) var isLoading = false
  @Published private(set) var isSaving = false
  @Published private(set) var lastFailureMessage: String?

  private var hasLoadedOnce = false
  private var refreshTask: Task<Void, Never>?

  private init(session: NativeSession) {
    self.session = session
  }

  /// 当前生效的插件形象；返回 `nil` 时展示原生内置机器人（0 WebView 内存占用）。
  var effectivePet: NativeAgentPetDeclaration? {
    let requestedID: String
    switch userSelection {
    case .builtin:
      return nil
    case .plugin(let pid, let key):
      requestedID = "\(pid):\(key)"
    case .followDefault:
      requestedID = adminDefaultPetID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !requestedID.isEmpty else { return nil }
    guard !failedIDs.contains(requestedID) else { return nil }
    return declarations.first { $0.id == requestedID }
  }

  var adminDefaultDeclaration: NativeAgentPetDeclaration? {
    let trimmed = adminDefaultPetID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return declarations.first { $0.id == trimmed }
  }

  /// 取消仓库持有的异步刷新任务。
  func cancelTasks() {
    refreshTask?.cancel()
    refreshTask = nil
  }

  /// 首次进入助手界面时启动一次数据加载。
  func bootstrapIfNeeded() {
    guard !hasLoadedOnce, !isLoading else { return }
    refresh()
  }

  /// 刷新助手列表和默认选择，可选择同时清除失败记录。
  func refresh(clearFailures: Bool = false) {
    if clearFailures {
      failedIDs.removeAll()
      lastFailureMessage = nil
    }
    refreshTask?.cancel()
    refreshTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.loadAll()
    }
  }

  /// 并发读取助手声明、用户选择与管理员默认项并更新快照。
  func loadAll() async {
    isLoading = true
    defer {
      isLoading = false
      hasLoadedOnce = true
    }

    async let petsTask = fetchDeclarations()
    async let selectionTask = fetchUserSelection()
    async let defaultTask = fetchAdminDefault()

    let (pets, selection, adminDef) = await (petsTask, selectionTask, defaultTask)
    guard !Task.isCancelled else { return }
    if let pets {
      let oldMap = Dictionary(uniqueKeysWithValues: declarations.map { ($0.id, $0) })
      declarations = pets
      // 若某个之前失败过的插件形象已升级或重新启用，允许重新尝试加载
      for pet in pets {
        if let prev = oldMap[pet.id],
          prev.pluginVersion != pet.pluginVersion || prev.remoteURL != pet.remoteURL
        {
          failedIDs.remove(pet.id)
        }
      }
    }
    if let selection {
      userSelection = selection
    }
    if let adminDef {
      adminDefaultPetID = adminDef
    }
  }

  @discardableResult
  /// 保存用户选择并同步更新本地状态，失败时保留提示。
  func select(_ selection: NativeAgentPetSelection) async -> Bool {
    guard !isSaving else { return false }
    isSaving = true
    lastFailureMessage = nil
    defer { isSaving = false }

    let bodyData: Data
    switch selection {
    case .followDefault:
      bodyData = Data("null".utf8)
    case .builtin:
      bodyData = Data("\"builtin\"".utf8)
    case .plugin(let pluginID, let key):
      let payload: [String: String] = ["plugin_id": pluginID, "key": key]
      bodyData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("null".utf8)
    }

    do {
      let ep = try APIEndpoint(
        path: ["user", "config", "AgentPet"],
        method: .post,
        body: bodyData,
        responseContract: .payload
      )
      _ = try await session.requestPayload(ep)
      userSelection = selection
      if let targetID = selection.petID {
        failedIDs.remove(targetID)
      }
      return true
    } catch {
      lastFailureMessage = "保存助手形象失败，请稍后重试。"
      return false
    }
  }

  /// 记录插件助手运行失败并提示已回退到内置助手。
  func markFailed(_ pet: NativeAgentPetDeclaration, reason: String) {
    failedIDs.insert(pet.id)
    lastFailureMessage = "\(pet.name) 加载失败（\(reason)），已回退内置机器人。"
  }

  // MARK: - Network

  /// 读取并解码当前服务公开的插件助手声明。
  private func fetchDeclarations() async -> [NativeAgentPetDeclaration]? {
    do {
      let ep = try APIEndpoint(path: ["plugin", "agent_pets"], responseContract: .payload)
      let raw = try await session.requestPayload(ep).value
      let decoder = JSONDecoder()
      if let direct = try? decoder.decode([NativeAgentPetDeclaration].self, from: raw) {
        return filterSupported(direct)
      }
      /// 承载插件助手声明接口返回的数据负载。
      struct Envelope: Decodable { let data: [NativeAgentPetDeclaration]? }
      if let env = try? decoder.decode(Envelope.self, from: raw), let items = env.data {
        return filterSupported(items)
      }
      return []
    } catch {
      return nil
    }
  }

  /// 过滤当前原生宿主能够安全运行的助手声明。
  private func filterSupported(_ items: [NativeAgentPetDeclaration]) -> [NativeAgentPetDeclaration]
  {
    items.filter { ($0.apiVersion ?? 1) == 1 && ($0.mode == "stage" || $0.mode == "renderer") }
  }

  /// 读取用户持久化的助手形象选择。
  private func fetchUserSelection() async -> NativeAgentPetSelection? {
    do {
      let ep = try APIEndpoint(path: ["user", "config", "AgentPet"], responseContract: .payload)
      let raw = try await session.requestPayload(ep).value
      guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
        return .followDefault
      }
      let container = (json["data"] as? [String: Any]) ?? json
      let value = container["value"]
      if let str = value as? String, str == "builtin" {
        return .builtin
      }
      if let dict = value as? [String: Any],
        let pid = dict["plugin_id"] as? String, !pid.isEmpty,
        let key = dict["key"] as? String, !key.isEmpty
      {
        return .plugin(pluginID: pid, key: key)
      }
      return .followDefault
    } catch {
      return nil
    }
  }

  /// 读取管理员配置的默认助手形象 ID。
  private func fetchAdminDefault() async -> String? {
    do {
      let ep = try APIEndpoint(path: ["system", "global", "user"], responseContract: .payload)
      let raw = try await session.requestPayload(ep).value
      guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
        return ""
      }
      let data = (json["data"] as? [String: Any]) ?? json
      return (data["AI_AGENT_PET"] as? String) ?? ""
    } catch {
      return nil
    }
  }
}

/// 助手形象缩略图加载器：支持 `data:`、`http(s):` 以及需要鉴权的 `/api/v1/plugin/file/...` 相对路径。
@MainActor
struct NativeAgentPetThumbnailView: View {
  let session: NativeSession
  let urlString: String?
  var size: CGFloat = 48
  var cornerRadius: CGFloat = 12

  @State private var image: UIImage?
  @State private var failed = false

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: size, height: size)
          .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.08))
          Image(systemName: failed ? "sparkles" : "sparkle")
            .font(.system(size: size * 0.42))
            .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
      }
    }
    .task(id: urlString ?? "") {
      await loadImage()
    }
  }

  /// 异步加载缩略图并在任务结束后更新视图状态。
  private func loadImage() async {
    image = nil
    failed = false
    guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      failed = true
      return
    }
    if raw.hasPrefix("data:image/") {
      if let comma = raw.firstIndex(of: ",") {
        let b64 = String(raw[raw.index(after: comma)...])
        if let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
          let uiImg = UIImage(data: data)
        {
          image = uiImg
          return
        }
      }
      failed = true
      return
    }
    do {
      let auth = try session.playbackAuthorization()
      let targetURL: URL
      if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://"),
        let parsed = URL(string: raw)
      {
        targetURL = parsed
      } else {
        let trimmedPath = raw.hasPrefix("/") ? raw : "/api/v1/\(raw)"
        guard var comp = URLComponents(url: auth.address.url, resolvingAgainstBaseURL: false) else {
          failed = true
          return
        }
        let parts = trimmedPath.split(separator: "?", maxSplits: 1)
        comp.path = String(parts[0])
        if parts.count > 1 { comp.percentEncodedQuery = String(parts[1]) }
        guard let built = comp.url else {
          failed = true
          return
        }
        targetURL = built
      }
      var req = URLRequest(url: targetURL)
      req.timeoutInterval = 15
      if allowsInstanceCredentials(for: targetURL, address: auth.address) {
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let cookie = try? await session.resolveResourceCookie() {
          req.setValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
        }
        CloudflareAccessCredentialRegistry.shared.applyHeaders(to: &req, for: auth.address)
      }
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard !Task.isCancelled,
        let http = resp as? HTTPURLResponse,
        (200..<300).contains(http.statusCode),
        let uiImg = UIImage(data: data)
      else {
        failed = true
        return
      }
      image = uiImg
    } catch {
      failed = true
    }
  }

  /// 仅允许实例同源请求或默认端口的同主机 HTTP 到 HTTPS 升级携带实例凭据。
  private func allowsInstanceCredentials(for url: URL, address: ServerAddress) -> Bool {
    guard url.user == nil, url.password == nil, let targetOrigin = WebOrigin(url: url) else {
      return false
    }
    let sourceOrigin = address.origin
    if targetOrigin == sourceOrigin { return true }
    return sourceOrigin.scheme == "http" && sourceOrigin.port == 80
      && targetOrigin.scheme == "https" && targetOrigin.port == 443
      && targetOrigin.host == sourceOrigin.host
  }
}

/// 原生「更换助手形象」弹窗（选中后点击右上角「保存」持久化至 `user/config/AgentPet` 并自动关闭，与 Web 端实时互通）。
@MainActor
struct NativeAgentPetPickerSheet: View {
  let session: NativeSession
  @ObservedObject var petStore: NativeAgentPetStore
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.dismiss) private var dismiss

  @State private var draftSelection: NativeAgentPetSelection = .followDefault
  @State private var hasEditedDraft = false

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if let err = petStore.lastFailureMessage, !err.isEmpty {
              HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(NativeTheme.warning)
                Text(err)
                  .font(.footnote)
                  .foregroundStyle(.primary.opacity(0.88))
              }
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // 1. 跟随默认 / 内置机器人
            sectionHeader("基础形象")
            VStack(spacing: 10) {
              if !petStore.adminDefaultPetID.isEmpty {
                let defaultName = petStore.adminDefaultDeclaration?.name ?? "内置机器人"
                petOptionCard(
                  title: "跟随默认（\(defaultName)）",
                  subtitle: "使用管理员配置的默认助手形象",
                  badge: "系统默认",
                  isSelected: draftSelection == .followDefault,
                  leading: {
                    Image(systemName: "sparkles.rectangle.stack")
                      .font(.system(size: 22, weight: .semibold))
                      .foregroundStyle(appearance.accentColor)
                      .frame(width: 52, height: 52)
                      .background(
                        appearance.accentColor.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                  }
                ) {
                  pickDraft(.followDefault)
                }
              }

              petOptionCard(
                title: "内置机器人",
                subtitle: "原生矢量绘制，支持贴边探头、呼吸眨眼与 16 种动作，零额外内存占用",
                badge: "原生",
                isSelected: draftSelection == .builtin
                  || (draftSelection == .followDefault && petStore.adminDefaultPetID.isEmpty),
                leading: {
                  NativeCssRobotView(
                    palette: NativeRobotPalette.derived(from: appearance.accentColor),
                    time: 0,
                    isDocked: false,
                    dockOnLeft: false,
                    isDragging: false,
                    isPressed: false,
                    isThinking: false,
                    action: nil,
                    actionProgress: 0,
                    reduceMotion: true
                  )
                  .frame(width: 44, height: 52)
                  .frame(width: 52, height: 52)
                  .background(
                    appearance.accentColor.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
              ) {
                pickDraft(.builtin)
              }
            }

            // 2. 已安装插件提供的全部形象（如 AgentPets：小映、奶龙、助手、天照、放映猫、自定义素材包等）
            HStack {
              sectionHeader("插件形象（\(petStore.declarations.count)）")
              Spacer()
              Button {
                petStore.refresh(clearFailures: true)
              } label: {
                HStack(spacing: 4) {
                  Image(systemName: "arrow.clockwise")
                    .font(.caption2.weight(.semibold))
                  Text("刷新")
                    .font(.caption.weight(.medium))
                }
                .foregroundStyle(.primary.opacity(0.86))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(NativeTheme.chipFill, in: Capsule())
                .overlay(Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6))
              }
              .buttonStyle(.plain)
              .disabled(petStore.isLoading)
            }
            if petStore.isLoading && petStore.declarations.isEmpty {
              HStack(spacing: 10) {
                ProgressView().tint(appearance.accentColor)
                Text("正在读取已安装插件形象…")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .padding(16)
              .frame(maxWidth: .infinity)
            } else if petStore.declarations.isEmpty {
              CinematicPanel {
                VStack(alignment: .leading, spacing: 6) {
                  Text("暂无可用的插件助手形象")
                    .font(.subheadline.weight(.semibold))
                  Text("安装并启用支持助手形象的 Vue 插件（如「助手形象 / AgentPets」）后，即可在 APP 全界面直接运行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            } else {
              VStack(spacing: 10) {
                ForEach(petStore.declarations) { pet in
                  let candidate = NativeAgentPetSelection.plugin(
                    pluginID: pet.pluginID, key: pet.key)
                  let isSelected = draftSelection == candidate
                  let isFailed = petStore.failedIDs.contains(pet.id)
                  petOptionCard(
                    title: pet.name,
                    subtitle: (pet.description?.isEmpty == false
                      ? pet.description! : pet.resolvedPluginName),
                    badge: isFailed ? "加载异常·保存重试" : (pet.isStageMode ? "全屏舞台" : "悬浮形象"),
                    isSelected: isSelected,
                    leading: {
                      NativeAgentPetThumbnailView(
                        session: session,
                        urlString: pet.previewURL ?? pet.avatarURL,
                        size: 52,
                        cornerRadius: 14
                      )
                    }
                  ) {
                    pickDraft(candidate)
                  }
                }
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("更换助手形象")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") {
            dismiss()
          }
          .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task {
              if await petStore.select(draftSelection) {
                dismiss()
              }
            }
          } label: {
            Text(petStore.isSaving ? "保存中…" : "保存")
              .fontWeight(.semibold)
          }
          .tint(.primary)
          .disabled(petStore.isSaving)
        }
      }
      .onAppear {
        draftSelection = petStore.userSelection
      }
      .onChange(of: petStore.userSelection) { latest in
        if !hasEditedDraft {
          draftSelection = latest
        }
      }
      .task {
        petStore.refresh()
      }
    }
    .nativeAdaptiveSheetSizing()
    .nativeGlassSheet()
  }

  /// 更新弹层中的临时选择并触发相应预览状态。
  private func pickDraft(_ selection: NativeAgentPetSelection) {
    UISelectionFeedbackGenerator().selectionChanged()
    hasEditedDraft = true
    draftSelection = selection
  }

  /// 构建助手选择列表中的分组标题。
  private func sectionHeader(_ text: String) -> some View {
    Text(text)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.leading, 4)
      .padding(.top, 4)
  }

  /// 构建单个插件助手的可选卡片及预览信息。
  private func petOptionCard<Leading: View>(
    title: String,
    subtitle: String,
    badge: String,
    isSelected: Bool,
    @ViewBuilder leading: () -> Leading,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        leading()
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            Text(badge)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(isSelected ? appearance.accentColor : .secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(
                (isSelected ? appearance.accentColor : Color.secondary).opacity(0.14),
                in: Capsule()
              )
          }
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        Spacer(minLength: 4)
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(appearance.accentColor)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(
            isSelected ? appearance.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
            lineWidth: isSelected ? 1.5 : 0.75
          )
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-agent-pet-option-\(title)")
    .disabled(petStore.isSaving)
  }
}
