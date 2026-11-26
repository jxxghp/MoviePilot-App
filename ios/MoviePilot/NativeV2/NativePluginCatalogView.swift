import MoviePilotAPI
import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotSession
import SwiftUI

/// 管理员的真实已安装插件入口，列表/配置都绑定当前原生会话。
@MainActor
struct NativePluginCatalogView: View {
  let session: NativeSession
  @State private var plugins: [NativeInstalledPlugin]?
  @State private var vueRemoteIDs: Set<String> = []
  @State private var loading = false
  @State private var failed = false
  @State private var reload = 0
  @State private var selectedPlugin: NativeInstalledPlugin?
  @State private var isFormPresented = false
  @State private var vueSheetPlugin: NativeInstalledPlugin?

  /// 统一渐变/玻璃列表，没有网页请求或插件脚本加载。
  var body: some View {
    ZStack {
      CinematicBackground()
      Form {
        if loading {
          Section {
            NativeCardListSkeletonView(count: 4, style: .pluginCard)
              .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
          } header: {
            Text(L10n.text("已安装")).textCase(nil)
          }
        }
        if failed {
          CinematicFormSection {
            CinematicFormRow(symbol: "exclamationmark.triangle") { Text(L10n.text("无法加载插件，请重试。")) }
            CinematicFormDivider()
            CinematicFormRow { Button(L10n.text("重试")) { reload += 1 }.frame(minHeight: 44) }
          }.accessibilityIdentifier("native-plugins-error")
        }
        if let plugins {
          if plugins.isEmpty {
            CinematicFormSection {
              CinematicFormRow(symbol: "puzzlepiece.extension") { Text(L10n.text("暂无已安装插件")) }
            }
          } else {
            Section {
              ForEach(plugins) { plugin in
                let isInactive = plugin.state == false
                CinematicPanel(padding: 0) {
                  Button {
                    open(plugin)
                  } label: {
                    VStack(alignment: .leading, spacing: 0) {
                      VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                          Circle()
                            .fill(
                              isInactive
                                ? .white.opacity(0.32)
                                : Color(red: 0.42, green: 0.90, blue: 0.62)
                            )
                            .frame(width: 7, height: 7)
                          Text(plugin.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary.opacity(isInactive ? 0.80 : 0.98))
                            .lineLimit(1)
                          if !plugin.version.isEmpty {
                            Text("v" + plugin.version)
                              .font(.caption.monospacedDigit().weight(.medium))
                              .foregroundStyle(.primary.opacity(0.56))
                              .lineLimit(1)
                          }
                          Spacer(minLength: 4)
                          Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.45))
                        }
                        HStack(alignment: .center, spacing: 12) {
                          Text(plugin.summary.isEmpty ? "已安装插件" : plugin.summary)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.76))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                          NativePluginIconView(
                            session: session,
                            iconReference: plugin.icon,
                            size: 44,
                            cornerRadius: 12,
                            inactive: isInactive
                          )
                        }
                      }
                      .padding(.horizontal, 14)
                      .padding(.vertical, 12)

                      if let author = plugin.author, !author.isEmpty {
                        Divider().overlay(.primary.opacity(0.08))
                        HStack(spacing: 6) {
                          NativePluginAuthorAvatarView(
                            authorURL: plugin.authorURL,
                            authorName: author,
                            size: 18
                          )
                          Text(author)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.68))
                            .lineLimit(1)
                          Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(.white.opacity(0.035))
                      }
                    }
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .accessibilityIdentifier("native-plugin-" + plugin.id)
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
              }
            } header: {
              Text(L10n.text("已安装")).textCase(nil)
            }
          }
        }
      }.scrollContentBackground(.hidden).frame(maxWidth: 680)
        .refreshable { await load() }
    }
    .navigationTitle(L10n.text("插件"))
    .navigationBarTitleDisplayMode(.large)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          NativePluginMarketPage(session: session)
        } label: {
          Label("插件市场", systemImage: "bag.fill")
        }
        .tint(.primary)
        .accessibilityIdentifier("native-plugin-market-open")
      }
    }
    .navigationDestination(isPresented: $isFormPresented) {
      if let selectedPlugin {
        NativePluginLazyFormDestination(session: session, plugin: selectedPlugin)
          .id(selectedPlugin.id)
      }
    }
    .onChange(of: isFormPresented) { presented in
      if !presented {
        selectedPlugin = nil
      }
    }
    .sheet(item: $vueSheetPlugin) { plugin in
      NativeVuePluginSheet(
        session: session,
        pluginID: plugin.id,
        pluginName: plugin.name,
        surface: plugin.hasPage ? .dataPage : .config,
        pluginHasPage: plugin.hasPage
      )
    }
    .task(id: reload) { await load() }
  }

  /// 提升响应上限并逐条容错解码，避免单条非常规插件元数据或较大插件列表导致整个配置页报错。
  private func load() async {
    loading = true
    failed = false
    defer { loading = false }
    async let remotesTask: Set<String>? = Self.fetchVueRemoteIDs(session: session)
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin"],
        query: [.init(name: "state", value: "installed")],
        maximumResponseBytes: 12 * 1024 * 1024,
        timeout: 30,
        trailingSlash: true)
      let result: APIResult<[LossyInstalledPluginRow]> = try await session.request(
        endpoint,
        requiring: PermissionRequirement(category: .admin))
      let loadedRemotes = await remotesTask
      try Task.checkCancellation()
      var seen: Set<String> = []
      let resolved = result.value.compactMap(\.plugin).filter { seen.insert($0.id).inserted }
      if let loadedRemotes {
        vueRemoteIDs = loadedRemotes
      }
      plugins = resolved
    } catch is CancellationError {} catch { failed = true }
  }

  private static func fetchVueRemoteIDs(session: NativeSession) async -> Set<String>? {
    guard
      let endpoint = try? APIEndpoint(
        path: ["plugin", "remotes"],
        query: [URLQueryItem(name: "token", value: "moviepilot")],
        responseContract: .payload
      ),
      let data = try? await session.requestPayload(endpoint).value
    else { return nil }
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
      return nil
    }
    var ids: Set<String> = []
    for item in list {
      ids.insert(item.id.lowercased())
      if let src = item.sourcePluginId?.lowercased(), !src.isEmpty {
        ids.insert(src)
      }
    }
    return ids
  }

  /// 会话再次验证后才创建编辑所有者，不能用缓存列表绕过已撤销的管理员权限。
  private func open(_ plugin: NativeInstalledPlugin) {
    if vueRemoteIDs.contains(plugin.id.lowercased())
      || vueRemoteIDs.contains(plugin.target.sourceID.lowercased())
    {
      vueSheetPlugin = plugin
    } else {
      selectedPlugin = plugin
      isFormPresented = true
    }
  }
}

/// 逐条容错解码已安装插件：单条元数据异常或暂不支持原生表单的目标不拖垮整页插件配置入口。
private struct LossyInstalledPluginRow: Decodable, Sendable {
  let plugin: NativeInstalledPlugin?

  private enum CodingKeys: String, CodingKey {
    case id, installed, state
    case source = "source_plugin_id"
    case name = "plugin_name"
    case summary = "plugin_desc"
    case version = "plugin_version"
    case icon = "plugin_icon"
    case author = "plugin_author"
    case authorURL = "author_url"
    case hasPage = "has_page"
  }

  init(from decoder: any Decoder) throws {
    guard let fields = try? decoder.container(keyedBy: CodingKeys.self),
      let rawID = try? fields.decode(String.self, forKey: .id),
      !rawID.isEmpty
    else {
      plugin = nil
      return
    }
    let installed = (try? fields.decode(Bool.self, forKey: .installed)) ?? true
    guard installed else {
      plugin = nil
      return
    }
    let rawSource = try? fields.decode(String.self, forKey: .source)
    let normalizedSource = (rawSource?.isEmpty == true) ? nil : rawSource
    guard let target = try? PluginFormTarget(physicalID: rawID, sourceID: normalizedSource) else {
      plugin = nil
      return
    }
    plugin = NativeInstalledPlugin(
      target: target,
      name: (try? fields.decode(String.self, forKey: .name)) ?? rawID,
      summary: (try? fields.decode(String.self, forKey: .summary)) ?? "",
      version: (try? fields.decode(String.self, forKey: .version)) ?? "",
      icon: try? fields.decode(String.self, forKey: .icon),
      author: try? fields.decode(String.self, forKey: .author),
      authorURL: try? fields.decode(String.self, forKey: .authorURL),
      state: try? fields.decode(Bool.self, forKey: .state),
      hasPage: (try? fields.decode(Bool.self, forKey: .hasPage)) ?? false
    )
  }
}
