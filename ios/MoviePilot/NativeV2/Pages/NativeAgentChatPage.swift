import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生 AI Agent 对话页：支持历史会话管理、斜杠命令提示、快捷提问、SSE 响应解析与任务停止，零 WebView。
@MainActor
struct NativeAgentChatPage: View {
  let session: NativeSession

  @State private var activeSessionID = "ios-\(UUID().uuidString.prefix(12).lowercased())"
  @State private var messages: [NativeAgentMessage] = []
  @State private var sessions: [NativeAgentSessionSummary] = []
  @State private var commands: [NativeAgentCommandItem] = []
  @State private var draftText = ""
  @State private var isSending = false
  @State private var sendTask: Task<Void, Never>?
  @State private var showsSessionsSheet = false
  @State private var isLoadingSessions = false
  @State private var feedback: NativeAgentFeedback?
  @State private var pendingDeleteSession: NativeAgentSessionSummary?

  /// 连续深色紫玫瑰渐变、对话消息流、快捷指令与底部悬浮毛玻璃输入框。
  var body: some View {
    ZStack {
      CinematicBackground()
      VStack(spacing: 0) {
        if let feedback {
          feedbackBanner(feedback)
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.top, 8)
        }
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              if messages.isEmpty {
                welcomeSection
              } else {
                ForEach(messages) { message in
                  messageRow(message)
                    .id(message.id)
                }
              }
              if isSending {
                HStack(spacing: 8) {
                  ProgressView().controlSize(.small).tint(.primary)
                  Text("智能助手正在思考与执行…")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.72))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                  Capsule().fill(.primary.opacity(0.09))
                }
                .id("native-agent-thinking")
              }
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
          }
          .scrollIndicators(.hidden)
          .scrollDismissesKeyboard(.interactively)
          .modifier(NativeSoftTopScrollEdge())
          .accessibilityIdentifier("native-agent-scroll")
          .onChange(of: messages.count) { _ in
            if let last = messages.last {
              withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
              }
            }
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      composerBar
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
    .navigationTitle("智能助手")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          startNewSession()
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .accessibilityLabel("新建对话")
        .accessibilityIdentifier("native-agent-new")

        Button {
          showsSessionsSheet = true
          Task { await loadSessions() }
        } label: {
          Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel("历史会话")
        .accessibilityIdentifier("native-agent-sessions")
      }
    }
    .sheet(isPresented: $showsSessionsSheet) {
      sessionsSheet
    }
    .task {
      await loadBootstrap()
    }
    .onDisappear {
      sendTask?.cancel()
    }
  }

  /// 欢迎引导与快捷提问卡片。
  private var welcomeSection: some View {
    VStack(spacing: 18) {
      VStack(spacing: 10) {
        ZStack {
          Circle()
            .fill(
              LinearGradient(
                colors: [
                  Color(red: 0.62, green: 0.44, blue: 0.96).opacity(0.65),
                  Color(red: 0.84, green: 0.44, blue: 0.72).opacity(0.45),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
          Image(systemName: "sparkles")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.primary)
        }
        .frame(width: 68, height: 68)
        .overlay { Circle().strokeBorder(.primary.opacity(0.24), lineWidth: 0.8) }
        .shadow(color: Color(red: 0.54, green: 0.36, blue: 0.86).opacity(0.42), radius: 18, y: 6)

        Text("MoviePilot 智能助手")
          .font(.title3.bold())
          .foregroundStyle(.primary)
        Text("直接用自然语言搜索影视、管理订阅、查看下载或触发媒体整理。")
          .font(.subheadline)
          .foregroundStyle(.primary.opacity(0.68))
          .multilineTextAlignment(.center)
      }
      .padding(.top, 18)

      VStack(alignment: .leading, spacing: 10) {
        Text("快捷提问")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary.opacity(0.60))
        ForEach(Self.quickPrompts, id: \.self) { prompt in
          Button {
            sendMessage(prompt)
          } label: {
            CinematicPanel(padding: 12) {
              HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                  .font(.subheadline)
                  .foregroundStyle(Color(red: 0.82, green: 0.70, blue: 1.0))
                Text(prompt)
                  .font(.subheadline)
                  .foregroundStyle(.primary.opacity(0.92))
                  .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.primary.opacity(0.48))
              }
            }
          }
          .buttonStyle(.plain)
          .disabled(isSending)
        }
      }

      if !commands.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("可用斜杠命令")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.60))
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(commands.prefix(12)) { cmd in
                Button {
                  draftText = cmd.command + " "
                } label: {
                  Text(cmd.command)
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(.primary.opacity(0.88))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                      Capsule()
                        .fill(.primary.opacity(0.10))
                        .overlay { Capsule().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6) }
                    }
                }
                .buttonStyle(.plain)
              }
            }
          }
          .scrollIndicators(.hidden)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// 单条用户或助手消息气泡。
  @ViewBuilder
  private func messageRow(_ message: NativeAgentMessage) -> some View {
    if message.isUser {
      HStack {
        Spacer(minLength: 48)
        Text(message.content)
          .font(.subheadline)
          .foregroundStyle(.primary)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(Color(red: 0.54, green: 0.38, blue: 0.86).opacity(0.76))
              .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .strokeBorder(.primary.opacity(0.22), lineWidth: 0.6)
              }
          }
      }
    } else {
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          Circle().fill(Color(red: 0.46, green: 0.34, blue: 0.72).opacity(0.60))
          Image(systemName: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
        }
        .frame(width: 28, height: 28)

        CinematicPanel(padding: 12) {
          VStack(alignment: .leading, spacing: 8) {
            if !message.tools.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                ForEach(message.tools, id: \.self) { tool in
                  HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                      .font(.caption2)
                      .foregroundStyle(Color(red: 0.80, green: 0.68, blue: 1.0))
                    Text(tool)
                      .font(.caption)
                      .foregroundStyle(.primary.opacity(0.76))
                      .lineLimit(1)
                  }
                }
              }
              .padding(.bottom, 2)
            }
            if !message.content.isEmpty {
              Text(message.content)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.95))
                .textSelection(.enabled)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        Spacer(minLength: 24)
      }
    }
  }

  /// 悬浮液态玻璃胶囊输入栏，浮于对话流底部并随键盘平滑升起，支持发送与中断停止。
  private var composerBar: some View {
    HStack(spacing: 10) {
      TextField(
        "向智能助手提问或输入 / 命令…",
        text: $draftText,
        prompt: Text("向智能助手提问或输入 / 命令…").foregroundColor(.secondary)
      )
      .font(.subheadline)
      .foregroundStyle(.primary)
      .submitLabel(.send)
      .onSubmit {
        if !isSending { sendMessage(draftText) }
      }
      .padding(.leading, 12)
      .padding(.vertical, 8)
      .accessibilityIdentifier("native-agent-input")

      if isSending {
        Button {
          Task { await stopCurrentTask() }
        } label: {
          Image(systemName: "stop.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.58))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("停止生成")
        .accessibilityIdentifier("native-agent-stop")
      } else {
        let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Button {
          sendMessage(draftText)
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(
              canSend
                ? NativeAppearanceStore.shared.accentColor
                : .primary.opacity(0.26))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("发送消息")
        .accessibilityIdentifier("native-agent-send")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .modifier(NativeLiquidGlassPopoverSurface(cornerRadius: 28))
    .frame(maxWidth: 760)
  }

  /// 历史会话管理弹层。
  private var sessionsSheet: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if isLoadingSessions && sessions.isEmpty {
              ProgressView("正在读取历史会话…")
                .tint(.primary)
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if sessions.isEmpty {
              CinematicPanel {
                VStack(spacing: 8) {
                  Image(systemName: "bubble.left.and.bubble.right")
                    .font(.largeTitle)
                    .foregroundStyle(.primary.opacity(0.55))
                  Text("暂无历史会话").font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
              }
            } else {
              ForEach(sessions) { item in
                CinematicPanel(padding: 12) {
                  Button {
                    showsSessionsSheet = false
                    Task { await openSession(item.sessionID) }
                  } label: {
                    HStack(spacing: 10) {
                      VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayTitle)
                          .font(.subheadline.weight(.semibold))
                          .foregroundStyle(.primary)
                          .lineLimit(1)
                        Text("\(item.messageCount) 条消息")
                          .font(.caption)
                          .foregroundStyle(.primary.opacity(0.60))
                      }
                      Spacer(minLength: 0)
                      Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.40))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .accessibilityIdentifier("native-agent-session-\(item.sessionID)")
                }
                .contextMenu {
                  Button(role: .destructive) {
                    pendingDeleteSession = item
                  } label: {
                    Label("删除会话", systemImage: "trash")
                  }
                }
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("历史会话")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            showsSessionsSheet = false
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityIdentifier("native-agent-sessions-close")
        }
      }
      .alert(
        "删除会话",
        isPresented: Binding(
          get: { pendingDeleteSession != nil }, set: { if !$0 { pendingDeleteSession = nil } }),
        presenting: pendingDeleteSession
      ) { item in
        Button("确认删除", role: .destructive) {
          Task { await deleteSession(item) }
        }
        Button("取消", role: .cancel) {}
      } message: { item in
        Text("确认删除会话「\(item.displayTitle)」吗？")
      }
    }
    .nativeAppearanceRoot()
  }

  /// 错误/状态横幅。
  private func feedbackBanner(_ feedback: NativeAgentFeedback) -> some View {
    CinematicPanel(padding: 10) {
      HStack(spacing: 8) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : Color(red: 0.56, green: 0.92, blue: 0.72))
        Text(feedback.message).font(.caption).foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption2.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.65)).frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-agent-feedback")
  }

  /// 初始化加载可用斜杠命令与历史会话列表。
  private func loadBootstrap() async {
    async let commandsTask: Void = loadCommands()
    async let sessionsTask: Void = loadSessions()
    _ = await (commandsTask, sessionsTask)
  }

  /// 加载斜杠命令列表（失败静默降级，不阻断对话）。
  private func loadCommands() async {
    do {
      let endpoint = try APIEndpoint(path: ["agent", "commands"])
      commands = try await session.request(endpoint, as: [NativeAgentCommandItem].self).value
    } catch {
      return
    }
  }

  /// 拉取当前用户的 Agent 历史会话列表。
  private func loadSessions() async {
    isLoadingSessions = true
    defer { isLoadingSessions = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["agent", "sessions"],
        query: [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "count", value: "30")])
      sessions = try await session.request(endpoint, as: [NativeAgentSessionSummary].self).value
    } catch {
      return
    }
  }

  /// 打开指定历史会话并载入其消息记录。
  private func openSession(_ sessionID: String) async {
    do {
      let endpoint = try APIEndpoint(path: ["agent", "sessions", sessionID])
      let detail = try await session.request(endpoint, as: NativeAgentSessionDetailRaw.self).value
      activeSessionID = detail.sessionID
      messages = detail.messages.map {
        NativeAgentMessage(
          id: $0.id,
          isUser: $0.role.lowercased() == "user",
          content: $0.content,
          tools: ($0.tools ?? []).map(\.message).filter { !$0.isEmpty }
        )
      }
    } catch {
      feedback = NativeAgentFeedback(isError: true, message: "读取历史会话失败，请稍后重试。")
    }
  }

  /// 删除指定历史会话。
  private func deleteSession(_ item: NativeAgentSessionSummary) async {
    do {
      let endpoint = try APIEndpoint(path: ["agent", "sessions", item.sessionID], method: .delete)
      try await session.perform(endpoint)
      sessions.removeAll { $0.sessionID == item.sessionID }
      if activeSessionID == item.sessionID { startNewSession() }
      feedback = NativeAgentFeedback(isError: false, message: "已删除历史会话。")
    } catch {
      feedback = NativeAgentFeedback(isError: true, message: "删除会话失败，请稍后重试。")
    }
  }

  /// 开启新会话并重置本地消息流。
  private func startNewSession() {
    sendTask?.cancel()
    isSending = false
    activeSessionID = "ios-\(UUID().uuidString.prefix(12).lowercased())"
    messages = []
    feedback = nil
  }

  /// 停止当前正在执行的 Agent 会话任务。
  private func stopCurrentTask() async {
    sendTask?.cancel()
    isSending = false
    do {
      let endpoint = try APIEndpoint(
        path: ["agent", "sessions", activeSessionID, "stop"], method: .post)
      try await session.perform(endpoint)
    } catch {
      return
    }
  }

  /// 发送用户消息至 `POST /api/v1/agent/stream` 并解析 SSE 事件流填充助手回复与工具调用记录。
  private func sendMessage(_ rawText: String) {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isSending else { return }
    draftText = ""
    feedback = nil
    messages.append(
      NativeAgentMessage(id: UUID().uuidString, isUser: true, content: trimmed, tools: []))
    isSending = true
    let targetSession = activeSessionID

    sendTask = Task {
      defer { isSending = false }
      let payload: [String: Any] = [
        "text": trimmed,
        "display_text": trimmed,
        "session_id": targetSession,
      ]
      do {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let endpoint = try APIEndpoint(
          path: ["agent", "stream"],
          method: .post,
          body: body,
          responseContract: .eventStream,
          timeout: 120)
        let rawData = try await session.requestPayload(endpoint).value
        try Task.checkCancellation()
        let parsed = Self.parseSSEPayload(rawData)
        if let resolvedSession = parsed.sessionID, !resolvedSession.isEmpty {
          activeSessionID = resolvedSession
        }
        if let errorText = parsed.errorMessage, !errorText.isEmpty, parsed.content.isEmpty {
          feedback = NativeAgentFeedback(isError: true, message: errorText)
        } else {
          let reply = parsed.content.isEmpty ? "任务已处理完成。" : parsed.content
          messages.append(
            NativeAgentMessage(
              id: UUID().uuidString, isUser: false, content: reply, tools: parsed.tools))
        }
      } catch is CancellationError {
        return
      } catch {
        feedback = NativeAgentFeedback(isError: true, message: "智能助手服务暂不可用或未配置大模型。")
      }
    }
  }

  /// 解析标准 `data: {...}` SSE 帧文本，聚合增量内容、工具提示、会话 ID 与错误提示。
  private static func parseSSEPayload(_ data: Data) -> (
    content: String, tools: [String], sessionID: String?, errorMessage: String?
  ) {
    guard let text = String(data: data, encoding: .utf8) else { return ("", [], nil, nil) }
    var content = ""
    var tools: [String] = []
    var sessionID: String?
    var errorMessage: String?

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard line.hasPrefix("data:") else { continue }
      let jsonPart = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
      guard !jsonPart.isEmpty, jsonPart != "[DONE]",
        let bytes = jsonPart.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
      else { continue }

      if let sid = object["session_id"] as? String, !sid.isEmpty { sessionID = sid }
      let eventType = (object["type"] as? String ?? "").lowercased()
      if eventType == "error",
        let msg = object["message"] as? String ?? object["content"] as? String
      {
        errorMessage = msg
      } else if eventType == "tool" || eventType == "tool_call" || eventType == "status",
        let msg = object["message"] as? String ?? object["tool_name"] as? String, !msg.isEmpty
      {
        if !tools.contains(msg) { tools.append(msg) }
      } else if let delta = object["delta"] as? String, !delta.isEmpty {
        content += delta
      } else if let piece = object["content"] as? String, !piece.isEmpty {
        if eventType == "final" || eventType == "message" || eventType == "done" {
          content = piece
        } else {
          content += piece
        }
      } else if let messageText = object["message"] as? String, !messageText.isEmpty,
        eventType != "status"
      {
        content += messageText
      }
    }
    return (content.trimmingCharacters(in: .whitespacesAndNewlines), tools, sessionID, errorMessage)
  }

  private static let quickPrompts = [
    "帮我推荐几部近期高分科幻电影",
    "查看当前正在下载的任务进度",
    "检查我的订阅有哪些缺集",
  ]
}

/// Agent 页面提示载体。
private struct NativeAgentFeedback {
  let isError: Bool
  let message: String
}

/// 本地渲染对话消息条目。
private struct NativeAgentMessage: Identifiable, Equatable {
  let id: String
  let isUser: Bool
  let content: String
  let tools: [String]
}

/// `GET /api/v1/agent/commands` 单条斜杠命令。
private struct NativeAgentCommandItem: Decodable, Sendable, Identifiable {
  let command: String
  let description: String?

  /// 使用规范命令名作为标识。
  var id: String { command }
}

/// `GET /api/v1/agent/sessions` 单条历史会话摘要。
private struct NativeAgentSessionSummary: Decodable, Sendable, Identifiable {
  let sessionID: String
  let title: String?
  let messageCount: Int

  /// 使用服务端 session_id 作为标识。
  var id: String { sessionID }

  /// 缺省标题回退显示会话短 ID。
  var displayTitle: String {
    if let title, !title.isEmpty { return title }
    return "会话 \(sessionID.prefix(8))"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sessionID = try container.decode(String.self, forKey: .sessionID)
    title = try? container.decodeIfPresent(String.self, forKey: .title)
    messageCount = (try? container.decodeIfPresent(Int.self, forKey: .messageCount)) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case title
    case messageCount = "message_count"
  }
}

/// `GET /api/v1/agent/sessions/{id}` 详情解码结构体。
private struct NativeAgentSessionDetailRaw: Decodable, Sendable {
  struct ToolRaw: Decodable, Sendable {
    let message: String
  }

  struct MessageRaw: Decodable, Sendable {
    let id: String
    let role: String
    let content: String
    let tools: [ToolRaw]?
  }

  let sessionID: String
  let messages: [MessageRaw]

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case messages
  }
}
