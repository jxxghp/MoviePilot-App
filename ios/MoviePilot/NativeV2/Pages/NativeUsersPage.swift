import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生用户与权限管理页：展示账号角色、启用状态、MFA 标记与四类权限徽标，仅超级管理员可见。
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
  @State private var feedback: String?

  /// 统一深色紫玫瑰渐变背景、用户透色玻璃卡与原生刷新按钮。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            CinematicPanel(padding: 10) {
              HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(NativeTheme.success)
                Text(feedback).font(.subheadline).foregroundStyle(.primary.opacity(0.92))
                Spacer(minLength: 0)
              }
            }
            .accessibilityIdentifier("native-users-feedback")
          }
          if isLoading && users.isEmpty {
            ProgressView("正在载入用户列表…")
              .tint(.primary)
              .frame(maxWidth: .infinity, minHeight: 220)
          } else if loadFailed && users.isEmpty {
            failureCard
          } else if filteredUsers.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 12) {
              ForEach(filteredUsers) { user in
                userCard(user)
              }
            }
          }
        }
        .frame(maxWidth: 820)
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
    .toolbarBackground(.hidden, for: .navigationBar)
    .searchable(text: $searchText, prompt: "按用户名或邮箱筛选")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsCreateSheet = true
        } label: {
          Image(systemName: "person.badge.plus")
        }
        .accessibilityLabel("新增用户")
        .accessibilityIdentifier("native-users-add")
      }
    }
    .sheet(isPresented: $showsCreateSheet) {
      NativeUserEditorSheet(session: session, existing: nil) { message in
        feedback = message
        attempt += 1
      }
    }
    .sheet(item: $editingUser) { target in
      NativeUserEditorSheet(session: session, existing: target) { message in
        feedback = message
        attempt += 1
      }
    }
    .task(id: attempt) { await load(forceRefresh: attempt > 0) }
  }

  /// 按关键词筛选后的用户清单。
  private var filteredUsers: [NativeUserRecord] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return users }
    return users.filter { user in
      user.name.lowercased().contains(trimmed)
        || (user.email ?? "").lowercased().contains(trimmed)
    }
  }

  /// 单条用户资料与权限玻璃卡片（显示真实用户头像，编辑操作收纳进长按菜单）。
  private func userCard(_ user: NativeUserRecord) -> some View {
    let isCurrent = user.id == session.user.id
    return CinematicPanel(padding: 14) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          NativeUserAvatarView(
            session: session,
            avatar: user.avatar,
            name: user.name,
            isSuperuser: user.isSuperuser,
            size: 44
          )
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Text(user.name)
                .font(.headline)
                .foregroundStyle(.primary)
              if isCurrent {
                tagPill("当前账号", tint: Color(red: 0.62, green: 0.86, blue: 1.0))
              }
              tagPill(
                user.isSuperuser ? "超级管理员" : "普通用户",
                tint: user.isSuperuser
                  ? NativeTheme.brand : NativeTheme.chipText)
            }
            if let email = user.email, !email.isEmpty {
              Text(email)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.64))
            }
          }
          Spacer(minLength: 0)
          VStack(alignment: .trailing, spacing: 4) {
            tagPill(
              user.isActive ? "正常" : "已停用",
              tint: user.isActive ? NativeTheme.success : .orange)
            if user.isOTP {
              Text("已启用 2FA")
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.60))
            }
          }
        }
        let perms = user.permissionLabels
        if !perms.isEmpty {
          HStack(spacing: 6) {
            ForEach(perms, id: \.self) { label in
              Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary.opacity(0.84))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                  Capsule()
                    .fill(.primary.opacity(0.10))
                    .overlay { Capsule().strokeBorder(.primary.opacity(0.14), lineWidth: 0.5) }
                }
            }
            Spacer(minLength: 0)
          }
        }
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .onTapGesture {
      editingUser = user
    }
    .contextMenu {
      Button {
        editingUser = user
      } label: {
        Label("编辑用户", systemImage: "pencil")
      }
    }
    .accessibilityIdentifier("native-user-card-\(user.id)")
  }

  /// 紧凑角色/状态徽标胶囊。
  private func tagPill(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 7)
      .padding(.vertical, 2.5)
      .background {
        Capsule()
          .fill(.primary.opacity(0.10))
          .overlay { Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6) }
      }
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "person.2")
          .font(.largeTitle)
          .foregroundStyle(.primary.opacity(0.55))
        Text("暂无匹配的用户").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 载入失败卡片。
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

  /// 从 `GET /api/v1/user/` 拉取非敏感账号与权限快照；命中页面缓存时静默复用，下拉刷新强制重拉。
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
}

/// `GET /api/v1/user/` 单条非敏感用户投影。
private struct NativeUserRecord: Decodable, Sendable, Identifiable {
  /// 用户四类权限布尔映射。
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

  /// 汇总可读权限标签。
  var permissionLabels: [String] {
    if isSuperuser { return ["全部管理权限"] }
    var labels: [String] = []
    if permissions?.discovery ?? true { labels.append("发现") }
    if permissions?.search ?? true { labels.append("搜索") }
    if permissions?.subscribe ?? true { labels.append("订阅") }
    if permissions?.manage ?? false { labels.append("管理") }
    return labels
  }

  /// 解码后端用户非敏感字段，绝不解码密码哈希或密钥。
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

  /// 对应 `_SchemaUser` 字段。
  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case email
    case avatar
    case isActive = "is_active"
    case isSuperuser = "is_superuser"
    case isOTP = "is_otp"
    case permissions
  }
}

/// 原生用户新增与编辑弹层：单次提交 `POST /api/v1/user/` 或 `PUT /api/v1/user/`，密码字段仅作一次性提交且不落盘留存。
@MainActor
private struct NativeUserEditorSheet: View {
  let session: NativeSession
  let existing: NativeUserRecord?
  let onSaved: (String) -> Void
  @Environment(\.dismiss) private var dismiss

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
          VStack(alignment: .leading, spacing: 14) {
            if let errorMessage {
              CinematicPanel(padding: 10) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                  .font(.subheadline)
                  .foregroundStyle(.orange)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            CinematicPanel(padding: 14) {
              VStack(alignment: .leading, spacing: 12) {
                Text("账号信息").font(.headline).foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 4) {
                  Text("用户名").font(.caption).foregroundStyle(.primary.opacity(0.72))
                  TextField(
                    "", text: $name,
                    prompt: Text("输入用户名").foregroundColor(.secondary)
                  )
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .foregroundStyle(.primary)
                  .padding(10)
                  .background(NativeTheme.fieldFill, in: RoundedRectangle(cornerRadius: 10))
                  .accessibilityIdentifier("native-user-editor-name")
                }
                VStack(alignment: .leading, spacing: 4) {
                  Text("邮箱（可选）").font(.caption).foregroundStyle(.primary.opacity(0.72))
                  TextField(
                    "", text: $email,
                    prompt: Text("name@example.com").foregroundColor(.secondary)
                  )
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .keyboardType(.emailAddress)
                  .foregroundStyle(.primary)
                  .padding(10)
                  .background(NativeTheme.fieldFill, in: RoundedRectangle(cornerRadius: 10))
                  .accessibilityIdentifier("native-user-editor-email")
                }
                VStack(alignment: .leading, spacing: 4) {
                  Text(isCreate ? "初始密码" : "重置密码（留空不修改）")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.72))
                  SecureField(
                    "", text: $password,
                    prompt: Text(isCreate ? "输入初始密码" : "留空保持原密码").foregroundColor(
                      .white.opacity(0.45))
                  )
                  .foregroundStyle(.primary)
                  .padding(10)
                  .background(NativeTheme.fieldFill, in: RoundedRectangle(cornerRadius: 10))
                  .accessibilityIdentifier("native-user-editor-password")
                }
              }
            }
            CinematicPanel(padding: 14) {
              VStack(spacing: 12) {
                Toggle("账号启用", isOn: $isActive)
                  .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
                  .accessibilityIdentifier("native-user-editor-active")
                Divider().overlay(.primary.opacity(0.08))
                Toggle("超级管理员", isOn: $isSuperuser)
                  .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
                  .accessibilityIdentifier("native-user-editor-superuser")
                if !isSuperuser {
                  Divider().overlay(.primary.opacity(0.08))
                  Toggle("发现权限", isOn: $permDiscovery)
                    .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
                  Toggle("搜索权限", isOn: $permSearch)
                    .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
                  Toggle("订阅权限", isOn: $permSubscribe)
                    .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
                  Toggle("管理权限", isOn: $permManage)
                    .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
                }
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
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
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
    .nativeAppearanceRoot()
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
