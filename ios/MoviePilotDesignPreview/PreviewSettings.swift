import SwiftUI

/// 设置页以少量玻璃分组、状态卡和原生入口保持层级，不提供多主题选项。
@MainActor
struct PreviewSettings: View {
  @EnvironmentObject private var library: PreviewLibrary

  /// 同一背景贯穿服务信息、模块入口和配置表单。
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          CinematicPanel {
            HStack(spacing: 14) {
              Image(systemName: "person.crop.circle.fill").font(.system(size: 42)).foregroundStyle(
                .white.opacity(0.9))
              VStack(alignment: .leading, spacing: 6) {
                Text("我的 MoviePilot").font(.headline)
                Text("管理员 · 家庭媒体服务").font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer()
            }
          }
          HStack(spacing: 14) {
            statusCard(title: "媒体服务", symbol: "play.tv.fill", value: "已连接", color: .cyan)
            statusCard(
              title: "下载器", symbol: "arrow.down.circle.fill", value: "运行正常", color: .purple)
          }
          Text("服务与自动化").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
          CinematicPanel(padding: 0) {
            VStack(spacing: 0) {
              NavigationLink {
                PreviewPluginForm()
              } label: {
                settingsRow("插件配置", symbol: "puzzlepiece.extension", detail: "站点自动签到")
              }.accessibilityIdentifier("preview-plugin-form")
              separator
              NavigationLink {
                PreviewServiceSettings()
              } label: {
                settingsRow("连接与服务", symbol: "server.rack", detail: "家庭服务")
              }
              separator
              Toggle(isOn: $library.notify) {
                Label("消息通知", systemImage: "bell")
              }.tint(.green).padding(18)
                .accessibilityIdentifier("preview-notification-toggle")
            }
          }
          Text("常用管理").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
          LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
          ) {
            NavigationLink {
              PreviewPluginForm()
            } label: {
              module("插件", symbol: "puzzlepiece.extension")
            }
            NavigationLink {
              PreviewServiceSettings()
            } label: {
              module("服务", symbol: "slider.horizontal.3")
            }
            NavigationLink {
              PreviewAboutContent()
            } label: {
              module("关于", symbol: "info.circle")
            }
          }
          NavigationLink {
            PreviewAboutContent()
          } label: {
            HStack {
              Text("关于本预览")
              Spacer()
              Image(systemName: "chevron.right")
            }
            .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            .frame(minHeight: 44).contentShape(Rectangle())
          }
        }.padding(CinematicStyle.margin).frame(maxWidth: 820).frame(maxWidth: .infinity)
          .padding(.bottom, 22)
      }
      .background(CinematicBackground()).navigationTitle("设置")
      .toolbarBackground(.hidden, for: .navigationBar)
      .buttonStyle(.plain)
    }
  }

  /// 表单行使用统一高度和前后信息对齐，长文案可自适应换行。
  private func settingsRow(_ title: String, symbol: String, detail: String) -> some View {
    HStack(spacing: 12) {
      Label(title, systemImage: symbol)
      Spacer(minLength: 12)
      Text(detail).font(.subheadline).foregroundStyle(.secondary)
      Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
    }.padding(18).frame(minHeight: 56).contentShape(Rectangle()).foregroundStyle(.primary)
  }

  /// 分组内部只用一条轻分隔，避免每行都有圆角边框。
  private var separator: some View {
    CinematicStyle.separator.frame(height: 0.6).padding(.leading, 18)
  }

  /// 二级模块仅有图标和名称，保持与参考一致的玻璃入口层级。
  private func module(_ title: String, symbol: String) -> some View {
    CinematicPanel(padding: 16) {
      VStack(spacing: 10) {
        Image(systemName: symbol).font(.title2)
        Text(title).font(.footnote)
      }.frame(maxWidth: .infinity)
    }.contentShape(RoundedRectangle(cornerRadius: CinematicStyle.radius, style: .continuous))
      .foregroundStyle(.primary)
  }

  /// 轻量状态卡通过系统图标及语义色表达连接状态。
  private func statusCard(title: String, symbol: String, value: String, color: Color) -> some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 14) {
        Image(systemName: symbol).font(.largeTitle).foregroundStyle(color)
        Text(title).font(.headline)
        Label(value, systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// 这是插件配置的视觉/交互预览，后续由 JSON 组件绑定同一套原生表面。
@MainActor
struct PreviewPluginForm: View {
  @EnvironmentObject private var library: PreviewLibrary

  /// 开关、输入与保存真实绑定预览状态，不宣称已经完成 JSON 协议解析。
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 14) {
          Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(.mint)
          VStack(alignment: .leading, spacing: 5) {
            Text("站点自动签到").font(.title3.bold())
            Text("定时完成站点签到，汇总执行结果。")
              .font(.subheadline).foregroundStyle(.secondary)
          }
        }.padding(.vertical, 8)
        CinematicPanel(padding: 0) {
          VStack(spacing: 0) {
            Toggle("启用插件", isOn: $library.pluginEnabled).padding(18)
              .accessibilityIdentifier("preview-plugin-enabled")
            CinematicStyle.separator.frame(height: 0.6).padding(.leading, 18)
            Toggle("仅执行一次", isOn: $library.pluginOnce).padding(18)
            CinematicStyle.separator.frame(height: 0.6).padding(.leading, 18)
            HStack {
              Text("运行周期")
              Spacer()
              TextField("Cron 表达式", text: $library.pluginSchedule)
                .multilineTextAlignment(.trailing).autocorrectionDisabled()
                .textInputAutocapitalization(.never).foregroundStyle(.secondary)
                .accessibilityIdentifier("preview-plugin-cron")
            }.padding(18)
          }.tint(.green)
        }
        Text("按设定的时间运行；仅执行一次会在完成后自动关闭。")
          .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
        CinematicPanel {
          Toggle("发送执行通知", isOn: $library.notify).tint(.green)
        }
        CinematicPrimaryAction(title: "保存配置", symbol: "checkmark") { library.savedNotice = true }
          .accessibilityIdentifier("preview-plugin-save")
      }.padding(CinematicStyle.margin).frame(maxWidth: 740).frame(maxWidth: .infinity)
    }
    .background(CinematicBackground()).navigationTitle("插件配置").navigationBarTitleDisplayMode(
      .inline
    )
    .toolbarBackground(.hidden, for: .navigationBar)
    .alert("配置已保存", isPresented: $library.savedNotice) { Button("好", role: .cancel) {} }
  }
}

/// 服务设置是只读设计内容，避免把合成地址当成实际连接功能。
@MainActor
struct PreviewServiceSettings: View {
  /// 真实连接与账号管理由主 App 原生会话入口承担，预览仅表现视觉层级。
  var body: some View {
    ScrollView {
      CinematicPanel {
        VStack(alignment: .leading, spacing: 16) {
          Label("家庭服务", systemImage: "server.rack").font(.headline)
          Text("MoviePilot").foregroundStyle(.secondary)
          Label("连接正常", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.padding(CinematicStyle.margin)
    }.background(CinematicBackground()).navigationTitle("连接与服务")
      .toolbarBackground(.hidden, for: .navigationBar)
  }
}

/// 预览身份说明与实际产品分开，防止合成媒体/指标被误认为真实业务结果。
@MainActor
struct PreviewAboutContent: View {
  /// 明确数据边界，仍使用同一原生材质和字体体系。
  var body: some View {
    ScrollView {
      CinematicPanel {
        VStack(alignment: .leading, spacing: 16) {
          Text("MoviePilot v2").font(.title2.bold())
          Text("原生界面预览").font(.headline)
          Text("此 App 用于界面评审，媒体与指标为演示内容，未连接后端，不会执行真实订阅或下载。")
            .foregroundStyle(.secondary)
        }
      }.padding(CinematicStyle.margin)
    }.background(CinematicBackground()).navigationTitle("关于本预览")
      .toolbarBackground(.hidden, for: .navigationBar)
  }
}

/// 发现页的说明以原生弹层呈现，不打开网页或系统浏览器。
@MainActor
struct PreviewAbout: View {
  @Environment(\.dismiss) private var dismiss

  /// 完成按钮按原生约定关闭弹层。
  var body: some View {
    NavigationStack {
      PreviewAboutContent().toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
      }
    }.preferredColorScheme(.dark).presentationDetents([.medium])
  }
}
