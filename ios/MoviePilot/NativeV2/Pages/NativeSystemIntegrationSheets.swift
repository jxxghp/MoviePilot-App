import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit
import UserNotifications

/// 原生 APNs 系统推送通知设置弹窗：直接通过 `NativeSession` 调用 `/api/v1/notification/app` 管理本机 APNs 设备注册与测试推送。
@MainActor
struct NativeNotificationSettingsSheet: View {
  let session: NativeSession

  @Environment(\.dismiss) private var dismiss
  @State private var isLoading = true
  @State private var isBusy = false
  @State private var serverChannelReady = false
  @State private var isBound = false
  @State private var systemAuthorized = false
  @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
  @State private var statusMessage: String?

  private var isPushReady: Bool {
    systemAuthorized && serverChannelReady && isBound
  }

  /// 深色透色玻璃 APNs 推送设置界面。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if let statusMessage {
              CinematicPanel(padding: 12) {
                Text(statusMessage)
                  .font(.subheadline)
                  .foregroundStyle(.primary.opacity(0.90))
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .accessibilityIdentifier("native-notification-status-message")
            }

            CinematicPanel(padding: 16) {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Label("APNs 系统推送", systemImage: "bell.badge.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                  Spacer()
                  if isLoading {
                    ProgressView().controlSize(.small).tint(.primary)
                  } else {
                    Text(isPushReady ? "已开启" : "未开启")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(
                        isPushReady ? NativeTheme.success : NativeTheme.badgeMutedText
                      )
                      .padding(.horizontal, 8)
                      .padding(.vertical, 3)
                      .background { Capsule().fill(.primary.opacity(0.10)) }
                  }
                }
                Text("通过 Apple APNs 接收推送通知。开启时会自动申请系统权限，并将本机 APNs 设备令牌注册到后端 AppPush 渠道。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Divider().overlay(NativeTheme.divider)
                statusRow(
                  "系统通知授权",
                  ok: systemAuthorized,
                  okText: "已允许",
                  pendingText: authorizationStatus == .denied ? "已拒绝" : "未授权"
                )
                statusRow(
                  "后端 AppPush 渠道",
                  ok: serverChannelReady,
                  okText: "已启用",
                  pendingText: "未启用"
                )
                statusRow(
                  "本机 APNs 设备注册",
                  ok: isBound,
                  okText: "已注册",
                  pendingText: "未注册"
                )
                if let err = NotificationService.shared.registrationError, !err.isEmpty {
                  Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
              }
            }

            if NotificationService.shared.environment == nil {
              CinematicPanel(padding: 14) {
                Text("当前安装包签名未启用 APNs 推送能力，请使用支持推送能力的证书重新签名后开启。")
                  .font(.caption)
                  .foregroundStyle(.primary.opacity(0.76))
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            } else {
              VStack(spacing: 10) {
                Button {
                  Task { await enablePush() }
                } label: {
                  HStack(spacing: 8) {
                    if isBusy {
                      ProgressView()
                        .controlSize(.small)
                        .tint(Color(red: 0.12, green: 0.10, blue: 0.16))
                    }
                    Text(
                      isBusy
                        ? "正在注册 APNs…"
                        : (isPushReady ? "重新注册本机 APNs" : "开启 APNs 推送")
                    )
                    .font(.subheadline.weight(.bold))
                  }
                  .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.16))
                  .frame(maxWidth: .infinity, minHeight: 46)
                  .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("native-notification-enable")

                if authorizationStatus == .denied {
                  Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                      UIApplication.shared.open(url)
                    }
                  } label: {
                    Text("前往系统设置开启通知")
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(.primary)
                      .frame(maxWidth: .infinity, minHeight: 44)
                      .background(NativeTheme.chipFill, in: Capsule())
                  }
                  .buttonStyle(.plain)
                }

                if isBound {
                  Button {
                    Task { await sendTest() }
                  } label: {
                    Text("发送测试通知")
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(.primary)
                      .frame(maxWidth: .infinity, minHeight: 44)
                      .background(NativeTheme.chipFill, in: Capsule())
                  }
                  .buttonStyle(.plain)
                  .disabled(isBusy)
                  .accessibilityIdentifier("native-notification-test")

                  Button(role: .destructive) {
                    Task { await disablePush() }
                  } label: {
                    Text("关闭本机推送")
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.60))
                      .frame(maxWidth: .infinity, minHeight: 44)
                      .background(NativeTheme.chipFill, in: Capsule())
                  }
                  .buttonStyle(.plain)
                  .disabled(isBusy)
                  .accessibilityIdentifier("native-notification-disable")
                }
              }
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("native-notification-settings-scroll")
      }
      .navigationTitle("系统推送通知")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-notification-settings-close")
        }
      }
      .task { await refreshStatus() }
    }
    .nativeGlassSheet()
    .nativeAdaptiveSheetSizing()
  }

  /// 状态条目行。
  private func statusRow(_ title: String, ok: Bool, okText: String, pendingText: String) -> some View
  {
    HStack(spacing: 8) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.primary.opacity(0.80))
      Spacer()
      Text(ok ? okText : pendingText)
        .font(.caption.weight(.medium))
        .foregroundStyle(ok ? NativeTheme.success : .secondary)
      Image(systemName: ok ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(ok ? NativeTheme.success : .secondary.opacity(0.55))
    }
  }

  /// 读取本机通知权限与服务端 APNs 设备注册状态。
  private func refreshStatus() async {
    isLoading = true
    defer { isLoading = false }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    authorizationStatus = settings.authorizationStatus
    systemAuthorized =
      settings.authorizationStatus == .authorized
      || settings.authorizationStatus == .provisional
    do {
      let data = try await NotificationService.shared.nativeRequest(
        session: session, action: "status")
      if case .string(let owner) = data["owner"], !owner.isEmpty {
        NotificationService.shared.identified(owner)
      }
      if case .bool(let configured) = data["configured"] {
        serverChannelReady = configured
      } else {
        serverChannelReady = true
      }
      isBound = NotificationService.isCurrentAPNsDeviceRegistered(in: data)
    } catch let error as NotificationFailure {
      serverChannelReady = false
      isBound = false
      statusMessage = error.localizedDescription
    } catch {
      serverChannelReady = false
      isBound = false
      statusMessage = "暂无法读取后端推送状态，请确认 MoviePilot 已启用 AppPush 通知渠道。"
    }
  }

  /// 开启并注册本机 APNs 推送。
  private func enablePush() async {
    isBusy = true
    defer { isBusy = false }
    statusMessage = await NotificationService.shared.enable()
    await refreshStatus()
  }

  /// 发送一次测试推送。
  private func sendTest() async {
    isBusy = true
    defer { isBusy = false }
    do {
      _ = try await NotificationService.shared.nativeRequest(session: session, action: "test")
      statusMessage = "已请求后端发送测试通知，请稍候查看系统横幅。"
    } catch let error as NotificationFailure {
      statusMessage = error.localizedDescription
    } catch {
      statusMessage = "测试通知发送失败，请检查后端 AppPush 通知渠道配置。"
    }
  }

  /// 解除本机 APNs 设备注册并关闭推送。
  private func disablePush() async {
    isBusy = true
    defer { isBusy = false }
    _ = try? await NotificationService.shared.nativeRequest(session: session, action: "unregister")
    NotificationService.shared.disable()
    isBound = false
    statusMessage = "已关闭当前实例的 APNs 系统推送通知。"
  }
}

/// 原生桌面小组件设置弹窗：直接通过 `WidgetService` 原生会话接口管理只读小组件授权、改名、刷新与撤销。
@MainActor
struct NativeWidgetSettingsSheet: View {
  let session: NativeSession

  @Environment(\.dismiss) private var dismiss
  @State private var isLoading = true
  @State private var isBusy = false
  @State private var state: WidgetSettingsState?
  @State private var profileName = ""
  @State private var feedback: String?

  /// 深色透色玻璃小组件设置界面。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if let feedback {
              CinematicPanel(padding: 12) {
                Text(feedback)
                  .font(.subheadline)
                  .foregroundStyle(.primary.opacity(0.90))
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .accessibilityIdentifier("native-widget-settings-feedback")
            }

            if !WidgetFeature.isEnabled {
              CinematicPanel(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                  Label("当前构建未启用小组件扩展", systemImage: "square.grid.2x2")
                    .font(.headline)
                    .foregroundStyle(.primary)
                  Text("需在 iOS 17+ 且开启 App Group 共享容器的构建中使用桌面小组件。")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.70))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            } else if isLoading && state == nil {
              VStack(spacing: 14) {
                CinematicPanel(padding: 16) {
                  VStack(alignment: .leading, spacing: 10) {
                    HStack {
                      Label("小组件只读授权", systemImage: "square.grid.2x2.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                      Spacer()
                      NativeSkeletonBlock(width: 48, height: 20, cornerRadius: 10)
                    }
                    NativeSkeletonBlock(height: 12, cornerRadius: 4)
                    Divider().overlay(.primary.opacity(0.10))
                    HStack(spacing: 12) {
                      Text("小组件名称")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                      Spacer()
                      NativeSkeletonBlock(width: 124, height: 15, cornerRadius: 5)
                    }
                    .padding(.vertical, 2)
                  }
                }
                NativeSkeletonBlock(height: 46, cornerRadius: 23)
              }
              .nativeSkeletonShimmer()
              .transition(.opacity)
            } else if let state {
              CinematicPanel(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                  HStack {
                    Label("小组件只读授权", systemImage: "square.grid.2x2.fill")
                      .font(.headline)
                      .foregroundStyle(.primary)
                    Spacer()
                    Text(state.profile != nil ? "已启用" : "未启用")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(
                        state.profile != nil
                          ? NativeTheme.success : NativeTheme.badgeMutedText
                      )
                      .padding(.horizontal, 8)
                      .padding(.vertical, 3)
                      .background { Capsule().fill(.primary.opacity(0.10)) }
                  }
                  Text("小组件使用独立 30 天只读凭据，不接触主登录令牌，退出登录时自动撤销。")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.68))

                  Divider().overlay(.primary.opacity(0.10))
                  HStack(spacing: 12) {
                    Text("小组件名称")
                      .font(.subheadline)
                      .foregroundStyle(.primary)
                      .layoutPriority(1)
                    TextField("本机小组件显示名称", text: $profileName)
                      .textFieldStyle(.plain)
                      .font(.subheadline)
                      .foregroundStyle(.primary)
                      .multilineTextAlignment(.trailing)
                      .accessibilityIdentifier("native-widget-profile-name")
                  }
                  .padding(.vertical, 2)

                  if let generatedAt = state.generatedAt {
                    Text(
                      "最近快照：\(generatedAt.formatted(date: .abbreviated, time: .shortened))"
                    )
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.58))
                  }
                }
              }

              VStack(spacing: 10) {
                Button {
                  Task { await enableOrRenew() }
                } label: {
                  Text(state.profile == nil ? "启用桌面小组件" : "轮换并续期只读凭据")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.16))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("native-widget-enable")

                if let profile = state.profile {
                  HStack(spacing: 10) {
                    Button {
                      Task { await rename(profile) }
                    } label: {
                      Text("保存名称")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(NativeTheme.chipFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)

                    Button {
                      Task { await refreshSnapshot(profile) }
                    } label: {
                      Text("立即刷新快照")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(NativeTheme.chipFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                  }

                  Button(role: .destructive) {
                    Task { await disableWidgets() }
                  } label: {
                    Text("停用并撤销本机小组件")
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.60))
                      .frame(maxWidth: .infinity, minHeight: 44)
                      .background(NativeTheme.chipFill, in: Capsule())
                  }
                  .buttonStyle(.plain)
                  .disabled(isBusy)
                  .accessibilityIdentifier("native-widget-disable")
                }
              }
            } else {
              CinematicPanel(padding: 16) {
                VStack(spacing: 10) {
                  Text("暂时无法读取小组件配置").font(.headline)
                  Button("重试") { Task { await load() } }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
              }
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("native-widget-settings-scroll")
      }
      .navigationTitle("桌面小组件")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-widget-settings-close")
        }
      }
      .task { await load() }
    }
    .nativeGlassSheet()
    .nativeAdaptiveSheetSizing()
  }

  /// 读取当前实例的小组件上下文与已安装资料。
  private func load() async {
    guard WidgetFeature.isEnabled else {
      isLoading = false
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let loaded = try await WidgetService.shared.settings(native: session)
      state = loaded
      if profileName.isEmpty {
        profileName = loaded.profile?.name ?? session.instance.address.url.host ?? "MoviePilot"
      }
    } catch {
      feedback = "读取小组件授权状态失败，请确认后端已支持小组件接口。"
    }
  }

  /// 启用或续期只读小组件授权。
  private func enableOrRenew() async {
    isBusy = true
    defer { isBusy = false }
    let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = session.instance.address.url.host ?? "MoviePilot"
    do {
      try await WidgetService.shared.enable(native: session, name: name.isEmpty ? fallback : name)
      feedback = "桌面小组件已启用并完成首次快照同步。"
      await load()
    } catch {
      feedback = "启用桌面小组件失败，请检查账号权限或存储访问状态。"
    }
  }

  /// 仅修改本机小组件显示名称。
  private func rename(_ profile: WidgetProfile) async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await WidgetService.shared.rename(native: session, profile: profile, name: profileName)
      feedback = "小组件名称已更新。"
      await load()
    } catch {
      feedback = "请输入 1 至 80 个有效字符作为名称。"
    }
  }

  /// 手动刷新小组件只读快照。
  private func refreshSnapshot(_ profile: WidgetProfile) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let outcome = try await WidgetService.shared.refresh(native: session, profile: profile)
      feedback = outcome == .updated ? "小组件快照已刷新。" : "暂未获取到更新的小组件快照。"
      await load()
    } catch {
      feedback = "刷新小组件快照失败。"
    }
  }

  /// 停用并尝试撤销本机小组件只读凭据。
  private func disableWidgets() async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await WidgetService.shared.disable(native: session)
      feedback = "已停用并清理当前实例的小组件资料。"
      await load()
    } catch {
      feedback = "停用小组件时遇到本机存储错误，请稍后重试。"
    }
  }
}
