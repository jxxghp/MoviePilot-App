import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生用户管理页（五.3）：全面采用 iOS 原生分组列表风格，支持新增、编辑与删除非管理员用户（保护当前账号与管理员）。
@MainActor
struct NativeUsersPage: View {
  let session: NativeSession

  @State private var users: [NativeUserRecord] = []
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var showsCreateSheet = false
  @State private var editingUser: NativeUserRecord?
  @State private var pendingDeleteUser: NativeUserRecord?
  @State private var feedback: (isError: Bool, text: String)?

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let feedback {
            CinematicPanel(padding: 11) {
              HStack(spacing: 8) {
                Image(
                  systemName: feedback.isError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.text).font(.caption.weight(.medium))
                Spacer(minLength: 0)
              }
            }
            .accessibilityIdentifier("native-users-feedback")
          }
          if isLoading && users.isEmpty {
            NativeCardListSkeletonView(count: 4, style: .iconRow)
              .transition(.opacity)
          } else if loadFailed && users.isEmpty {
            failureCard
          } else if filteredUsers.isEmpty {
            emptyCard
          } else {
            let admins = filteredUsers.filter(\.isSuperuser)
            let members = filteredUsers.filter { !$0.isSuperuser }

            if !admins.isEmpty {
              userGroupSection(title: "管理员 (\(admins.count))", list: admins)
            }
            if !members.isEmpty {
              userGroupSection(title: "普通成员 (\(members.count))", list: members)
            }
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-users-scroll")
    }
    .navigationTitle(users.isEmpty ? "用户管理" : "用户管理 (\(users.count))")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .searchable(text: $searchText, prompt: "按用户名或邮箱筛选")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsCreateSheet = true
        } label: {
          Image(systemName: "person.badge.plus")
        }
        .tint(.primary)
        .accessibilityLabel("新增用户")
        .accessibilityIdentifier("native-users-add")
      }
    }
    .sheet(isPresented: $showsCreateSheet) {
      NativeUserEditorSheet(session: session, existing: nil, canDelete: false) { message in
        feedback = (false, message)
        NativePageDataCache.shared.remove("users|all", session: session)
        NativePageDataCache.shared.remove("settingsHub|overview.v2", session: session)
        attempt += 1
      }
    }
    .sheet(item: $editingUser) { target in
      let allowDelete = canDeleteUser(target)
      NativeUserEditorSheet(
        session: session,
        existing: target,
        canDelete: allowDelete,
        onDelete: {
          editingUser = nil
          pendingDeleteUser = target
        }
      ) { message in
        feedback = (false, message)
        NativePageDataCache.shared.remove("users|all", session: session)
        NativePageDataCache.shared.remove("settingsHub|overview.v2", session: session)
        attempt += 1
      }
    }
    .alert(
      "删除用户",
      isPresented: Binding(
        get: { pendingDeleteUser != nil },
        set: { if !$0 { pendingDeleteUser = nil } }),
      presenting: pendingDeleteUser
    ) { target in
      Button("删除用户", role: .destructive) {
        Task { await deleteUser(target) }
      }
      Button("取消", role: .cancel) {}
    } message: { target in
      Text("确认删除普通用户「\(target.name)」吗？删除后该账号将立即失效。")
    }
    .task(id: attempt) { await load(forceRefresh: attempt > 0) }
  }

  /// 仅允许删除非管理员且非当前登录账号的用户。
  private func canDeleteUser(_ user: NativeUserRecord) -> Bool {
    !user.isSuperuser && user.id != session.user.id
  }

  private var filteredUsers: [NativeUserRecord] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return users }
    return users.filter { user in
      user.name.lowercased().contains(trimmed)
        || (user.email ?? "").lowercased().contains(trimmed)
    }
  }

  private func userGroupSection(title: String, list: [NativeUserRecord]) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(list.enumerated()), id: \.element.id) { idx, user in
            if idx > 0 { CinematicFormDivider() }
            userRow(user)
          }
        }
      }
    }
  }

  private func userRow(_ user: NativeUserRecord) -> some View {
    let isCurrent = user.id == session.user.id
    return Button {
      editingUser = user
    } label: {
      HStack(spacing: 12) {
        NativeUserAvatarView(
          session: session,
          avatar: user.avatar,
          name: user.name,
          isSuperuser: user.isSuperuser,
          size: 38
        )
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(user.name)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
            if isCurrent {
              NativeAdaptiveBadge("当前", tint: NativeTheme.info)
            }
            if user.isOTP {
              NativeAdaptiveBadge("2FA", tint: NativeTheme.cyan)
            }
          }
          Text(
            (user.email?.isEmpty == false
              ? user.email! : user.permissionLabels.joined(separator: " · "))
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
        Spacer(minLength: 6)
        NativeAdaptiveBadge(
          user.isActive ? "正常" : "已停用",
          tint: user.isActive ? NativeTheme.success : NativeTheme.warning)
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary.opacity(0.55))
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button {
        editingUser = user
      } label: {
        Label("编辑用户", systemImage: "pencil")
      }
      if canDeleteUser(user) {
        Button(role: .destructive) {
          pendingDeleteUser = user
        } label: {
          Label("删除用户", systemImage: "trash")
        }
      }
    }
    .accessibilityIdentifier("native-user-card-\(user.id)")
  }

  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "person.2")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
        Text("暂无匹配的用户").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入用户列表", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-users-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func load(forceRefresh: Bool = false) async {
    let cacheKey = "users|all"
    if !forceRefresh,
      let cached: [NativeUserRecord] = NativePageDataCache.shared.get(cacheKey, session: session)
    {
      users = cached
      isLoading = false
      loadFailed = false
      return
    }
    if users.isEmpty { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["user"], trailingSlash: true)
      let loaded = try await session.request(endpoint, as: [NativeUserRecord].self).value
      try Task.checkCancellation()
      users = loaded
      NativePageDataCache.shared.set(loaded, for: cacheKey, session: session)
    } catch is CancellationError {
      return
    } catch {
      if users.isEmpty { loadFailed = true }
    }
  }

  private func deleteUser(_ user: NativeUserRecord) async {
    guard canDeleteUser(user) else { return }
    do {
      let ep = try APIEndpoint(path: ["user", "id", String(user.id)], method: .delete)
      try await session.perform(ep, requiring: .init(category: .admin))
      users.removeAll { $0.id == user.id }
      NativePageDataCache.shared.remove("users|all", session: session)
      NativePageDataCache.shared.remove("settingsHub|overview.v2", session: session)
      feedback = (false, "已删除用户「\(user.name)」。")
    } catch {
      feedback = (true, "删除用户失败，请稍后重试。")
    }
  }
}

private struct NativeUserRecord: Decodable, Sendable, Identifiable {
  struct Permissions: Decodable, Sendable {
    let discovery: Bool?
    let search: Bool?
    let subscribe: Bool?
    let manage: Bool?
  }

  let id: Int
  let name: String
  let email: String?
  let avatar: String?
  let isActive: Bool
  let isSuperuser: Bool
  let isOTP: Bool
  let permissions: Permissions?

  var permissionLabels: [String] {
    if isSuperuser { return ["全部管理权限"] }
    var labels: [String] = []
    if permissions?.discovery ?? true { labels.append("发现") }
    if permissions?.search ?? true { labels.append("搜索") }
    if permissions?.subscribe ?? true { labels.append("订阅") }
    if permissions?.manage ?? false { labels.append("管理") }
    return labels
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
    isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    isSuperuser = try container.decodeIfPresent(Bool.self, forKey: .isSuperuser) ?? false
    isOTP = try container.decodeIfPresent(Bool.self, forKey: .isOTP) ?? false
    permissions = try container.decodeIfPresent(Permissions.self, forKey: .permissions)
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, email, avatar, permissions
    case isActive = "is_active"
    case isSuperuser = "is_superuser"
    case isOTP = "is_otp"
  }
}

/// 原生用户新增/编辑弹层：采用 iOS 原生分组列表行布局（右对齐内联输入 + 原生开关），非管理员支持底部删除。
@MainActor
private struct NativeUserEditorSheet: View {
  let session: NativeSession
  let existing: NativeUserRecord?
  let canDelete: Bool
  var onDelete: (() -> Void)? = nil
  let onSaved: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var name = ""
  @State private var email = ""
  @State private var password = ""
  @State private var isActive = true
  @State private var isSuperuser = false
  @State private var permDiscovery = true
  @State private var permSearch = true
  @State private var permSubscribe = true
  @State private var permManage = false
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  private var isCreate: Bool { existing == nil }

  private var canSubmit: Bool {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty, !isSubmitting else { return false }
    if isCreate { return !password.isEmpty }
    return true
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let errorMessage {
              CinematicPanel(padding: 11) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                  .font(.caption)
                  .foregroundStyle(NativeTheme.danger)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }

            VStack(alignment: .leading, spacing: 7) {
              Text("账号资料")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  HStack(spacing: 12) {
                    Text("用户名").font(.subheadline).frame(width: 78, alignment: .leading)
                    TextField("必填", text: $name)
                      .font(.subheadline)
                      .multilineTextAlignment(.trailing)
                      .textInputAutocapitalization(.never)
                      .autocorrectionDisabled()
                      .accessibilityIdentifier("native-user-editor-name")
                  }
                  .padding(.horizontal, 15).padding(.vertical, 12)
                  CinematicFormDivider()
                  HStack(spacing: 12) {
                    Text("邮箱").font(.subheadline).frame(width: 78, alignment: .leading)
                    TextField("可选", text: $email)
                      .font(.subheadline)
                      .multilineTextAlignment(.trailing)
                      .textInputAutocapitalization(.never)
                      .autocorrectionDisabled()
                      .keyboardType(.emailAddress)
                      .accessibilityIdentifier("native-user-editor-email")
                  }
                  .padding(.horizontal, 15).padding(.vertical, 12)
                  CinematicFormDivider()
                  HStack(spacing: 12) {
                    Text(isCreate ? "密码" : "重置密码").font(.subheadline)
                      .frame(width: 78, alignment: .leading)
                    SecureField(isCreate ? "输入初始密码" : "留空不修改", text: $password)
                      .font(.subheadline)
                      .multilineTextAlignment(.trailing)
                      .accessibilityIdentifier("native-user-editor-password")
                  }
                  .padding(.horizontal, 15).padding(.vertical, 12)
                }
              }
            }

            VStack(alignment: .leading, spacing: 7) {
              Text("状态与角色")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  Toggle("启用账号", isOn: $isActive)
                    .font(.subheadline)
                    .tint(appearance.accentColor)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .accessibilityIdentifier("native-user-editor-active")
                  CinematicFormDivider()
                  Toggle("超级管理员", isOn: $isSuperuser)
                    .font(.subheadline)
                    .tint(appearance.accentColor)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .accessibilityIdentifier("native-user-editor-superuser")
                }
              }
            }

            if !isSuperuser {
              VStack(alignment: .leading, spacing: 7) {
                Text("功能权限")
                  .font(.footnote.weight(.medium))
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 6)
                CinematicPanel(padding: 0) {
                  VStack(spacing: 0) {
                    Toggle("发现与媒体浏览", isOn: $permDiscovery)
                      .font(.subheadline).tint(appearance.accentColor)
                      .padding(.horizontal, 15).padding(.vertical, 10)
                    CinematicFormDivider()
                    Toggle("站点资源搜索", isOn: $permSearch)
                      .font(.subheadline).tint(appearance.accentColor)
                      .padding(.horizontal, 15).padding(.vertical, 10)
                    CinematicFormDivider()
                    Toggle("订阅管理", isOn: $permSubscribe)
                      .font(.subheadline).tint(appearance.accentColor)
                      .padding(.horizontal, 15).padding(.vertical, 10)
                    CinematicFormDivider()
                    Toggle("下载与整理管理", isOn: $permManage)
                      .font(.subheadline).tint(appearance.accentColor)
                      .padding(.horizontal, 15).padding(.vertical, 10)
                  }
                }
              }
            }

            if canDelete, let onDelete {
              CinematicPanel(padding: 0) {
                Button(role: .destructive, action: onDelete) {
                  Text("删除此用户")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NativeTheme.danger)
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-user-editor-delete")
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle(isCreate ? "新增用户" : "编辑用户")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
            .accessibilityIdentifier("native-user-editor-cancel")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await submit() }
          } label: {
            if isSubmitting {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Text("保存").fontWeight(.semibold)
            }
          }
          .tint(.primary)
          .disabled(!canSubmit)
          .accessibilityIdentifier("native-user-editor-save")
        }
      }
      .onAppear {
        if let existing {
          name = existing.name
          email = existing.email ?? ""
          isActive = existing.isActive
          isSuperuser = existing.isSuperuser
          permDiscovery = existing.permissions?.discovery ?? true
          permSearch = existing.permissions?.search ?? true
          permSubscribe = existing.permissions?.subscribe ?? true
          permManage = existing.permissions?.manage ?? false
        }
      }
    }
    .nativeGlassSheet()
  }

  private func submit() async {
    isSubmitting = true
    errorMessage = nil
    defer {
      isSubmitting = false
      password = ""
    }
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    var payload: [String: JSONValue] = [
      "name": .string(trimmedName),
      "email": trimmedEmail.isEmpty ? .null : .string(trimmedEmail),
      "is_active": .bool(isActive),
      "is_superuser": .bool(isSuperuser),
      "permissions": .object([
        "discovery": .bool(isSuperuser || permDiscovery),
        "search": .bool(isSuperuser || permSearch),
        "subscribe": .bool(isSuperuser || permSubscribe),
        "manage": .bool(isSuperuser || permManage),
      ]),
    ]
    if let existing {
      payload["id"] = .number(Double(existing.id))
    }
    if !password.isEmpty {
      payload["password"] = .string(password)
    }
    do {
      let body = try JSONEncoder().encode(payload)
      let endpoint = try APIEndpoint(
        path: ["user"],
        method: isCreate ? .post : .put,
        body: body,
        trailingSlash: true)
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      onSaved(isCreate ? "已新增用户「\(trimmedName)」。" : "已更新用户「\(trimmedName)」。")
      dismiss()
    } catch is CancellationError {
      return
    } catch {
      errorMessage = "保存用户失败，请检查用户名是否重复后重试。"
    }
  }
}
