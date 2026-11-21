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
  @State private var loading = false
  @State private var failed = false
  @State private var reload = 0
  @State private var selection: Selection?

  /// 当前导航拥有独立草稿控制器，物理插件与源插件不混淆。
  private struct Selection {
    let plugin: NativeInstalledPlugin
    let form: NativePluginForm
  }

  /// 统一渐变/玻璃列表，没有网页请求或插件脚本加载。
  var body: some View {
    ZStack {
      CinematicBackground()
      Form {
        if loading {
          CinematicFormSection {
            CinematicFormRow {
              ProgressView()
              Text(L10n.text("正在加载…"))
            }
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
    }
    .navigationTitle(L10n.text("插件"))
    .navigationBarTitleDisplayMode(.large)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          NativePluginMarketPage(session: session)
        } label: {
          Label("插件市场", systemImage: "bag.fill")
        }
        .accessibilityIdentifier("native-plugin-market-open")
      }
    }
    .navigationDestination(
      isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })
    ) {
      if let selection { NativePluginFormView(plugin: selection.plugin, form: selection.form) }
    }
    .task(id: reload) { await load() }
  }

  /// 显式 state/尾斜杠与现有 API 一致；单个非法身份导致整体失败，不能偷偷漏插件。
  private func load() async {
    loading = true
    failed = false
    defer { loading = false }
    do {
      let result: APIResult<[NativeInstalledPlugin]> = try await session.request(
        APIEndpoint(
          path: ["plugin"], query: [.init(name: "state", value: "installed")],
          responseContract: .payload, trailingSlash: true),
        requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      guard Set(result.value.map(\.id)).count == result.value.count else {
        throw PluginFormError.invalidTarget
      }
      plugins = result.value
    } catch is CancellationError {} catch { failed = true }
  }

  /// 会话再次验证后才创建编辑所有者，不能用缓存列表绕过已撤销的管理员权限。
  private func open(_ plugin: NativeInstalledPlugin) {
    do {
      let form = try NativePluginForm(
        session: session, target: plugin.target, validator: NativeFormValidator())
      selection = Selection(plugin: plugin, form: form)
    } catch { failed = true }
  }
}
