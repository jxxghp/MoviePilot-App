import AVFoundation
import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 按当前认证会话作用域常驻的智能助手对话状态存储：关闭弹窗时保持 SSE 流与消息队列存活，再次打开或切回历史会话时无缝恢复；登出/切服自动重置。
@MainActor
final class NativeAgentChatStore: ObservableObject {
  private static var current: NativeAgentChatStore?

  static func shared(for session: NativeSession) -> NativeAgentChatStore {
    if let existing = current, existing.session.scope == session.scope {
      return existing
    }
    current?.cancelTasks()
    let created = NativeAgentChatStore(session: session)
    current = created
    return created
  }

  static func resetAll() {
    current?.cancelTasks()
    current = nil
  }

  let session: NativeSession

  @Published fileprivate var activeSessionID = "ios-\(UUID().uuidString.prefix(12).lowercased())"
  @Published fileprivate var messages: [NativeAgentMessage] = []
  @Published fileprivate var sessions: [NativeAgentSessionSummary] = []
  @Published fileprivate var commands: [NativeAgentCommandItem] = []
  @Published fileprivate var isSending = false
  @Published fileprivate var isLoadingInitialSession = true
  @Published fileprivate var isLoadingSessions = false
  @Published fileprivate var feedback: NativeAgentFeedback?

  private var sendTask: Task<Void, Never>?
  private var processingPollTask: Task<Void, Never>?
  private var hasBootstrapped = false

  private init(session: NativeSession) {
    self.session = session
  }

  private var lastSessionStorageKey: String {
    "nativeV2.agent.lastSession|\(session.scope.instanceID.uuidString)|\(session.scope.userID)"
  }

  func cancelTasks() {
    sendTask?.cancel()
    sendTask = nil
    processingPollTask?.cancel()
    processingPollTask = nil
    isSending = false
  }

  func loadBootstrap() async {
    if hasBootstrapped && (!messages.isEmpty || isSending) {
      isLoadingInitialSession = false
      async let cmds: () = loadCommands()
      async let sess: () = loadSessions()
      _ = await (cmds, sess)
      return
    }
    hasBootstrapped = true
    defer { isLoadingInitialSession = false }
    async let cmds: () = loadCommands()
    async let sess: () = loadSessions()
    _ = await (cmds, sess)
    guard messages.isEmpty && !isSending else { return }
    let savedID = UserDefaults.standard.string(forKey: lastSessionStorageKey)
    let targetID: String? =
      if let savedID, !savedID.isEmpty, sessions.contains(where: { $0.sessionID == savedID }) {
        savedID
      } else {
        sessions.first?.sessionID
      }
    if let targetID {
      await openSession(targetID, silentOnFailure: true)
    }
  }

  func loadCommands() async {
    do {
      let endpoint = try APIEndpoint(path: ["message", "agent", "commands"])
      commands = try await session.request(endpoint, as: [NativeAgentCommandItem].self).value
    } catch {
      return
    }
  }

  func loadSessions() async {
    isLoadingSessions = true
    defer { isLoadingSessions = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["message", "agent", "sessions"],
        query: [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "count", value: "30")])
      sessions = try await session.request(endpoint, as: [NativeAgentSessionSummary].self).value
    } catch {
      return
    }
  }

  func openSession(_ sessionID: String, silentOnFailure: Bool = false) async {
    let isSameActiveSession = sessionID == activeSessionID
    if isSameActiveSession && isSending && sendTask != nil && !messages.isEmpty {
      feedback = nil
      return
    }
    do {
      let endpoint = try APIEndpoint(path: ["message", "agent", "sessions", sessionID])
      let detail = try await session.request(endpoint, as: NativeAgentSessionDetailRaw.self).value
      let resolvedID = detail.sessionID ?? sessionID
      let sameSession = resolvedID == activeSessionID || sessionID == activeSessionID
      let fetched = detail.messages.map { $0.toDisplayMessage() }.filter {
        $0.isUser || $0.hasVisibleContent
      }

      if !sameSession {
        sendTask?.cancel()
        sendTask = nil
        processingPollTask?.cancel()
        processingPollTask = nil
        isSending = false
      }

      activeSessionID = resolvedID
      UserDefaults.standard.set(activeSessionID, forKey: lastSessionStorageKey)

      if !fetched.isEmpty || !sameSession || (!isSending && !detail.isProcessing) {
        messages = fetched
      }
      feedback = nil

      if detail.isProcessing {
        isSending = true
        if sendTask == nil {
          startProcessingPoll(for: resolvedID)
        }
      } else if sendTask == nil {
        processingPollTask?.cancel()
        processingPollTask = nil
        isSending = false
      }
    } catch {
      if !silentOnFailure {
        feedback = NativeAgentFeedback(isError: true, message: "读取会话记录失败。")
      }
    }
  }

  private func startProcessingPoll(for sessionID: String) {
    processingPollTask?.cancel()
    processingPollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled, let self, self.activeSessionID == sessionID else { break }
        guard self.sendTask == nil else { break }
        guard
          let endpoint = try? APIEndpoint(path: ["message", "agent", "sessions", sessionID]),
          let detail = try? await self.session.request(
            endpoint, as: NativeAgentSessionDetailRaw.self
          ).value
        else { continue }
        guard !Task.isCancelled, self.activeSessionID == sessionID else { break }
        let fetched = detail.messages.map { $0.toDisplayMessage() }.filter {
          $0.isUser || $0.hasVisibleContent
        }
        if !fetched.isEmpty {
          self.messages = fetched
        }
        if !detail.isProcessing {
          self.isSending = false
          self.processingPollTask = nil
          await self.loadSessions()
          break
        }
      }
    }
  }

  fileprivate func deleteSession(_ item: NativeAgentSessionSummary) async {
    do {
      let endpoint = try APIEndpoint(
        path: ["message", "agent", "sessions", item.sessionID], method: .delete)
      try await session.perform(endpoint)
      sessions.removeAll { $0.sessionID == item.sessionID }
      if activeSessionID == item.sessionID { startNewSession() }
      feedback = NativeAgentFeedback(isError: false, message: "已删除会话。")
    } catch {
      feedback = NativeAgentFeedback(isError: true, message: "删除会话失败。")
    }
  }

  func startNewSession() {
    sendTask?.cancel()
    sendTask = nil
    processingPollTask?.cancel()
    processingPollTask = nil
    isSending = false
    activeSessionID = "ios-\(UUID().uuidString.prefix(12).lowercased())"
    UserDefaults.standard.removeObject(forKey: lastSessionStorageKey)
    messages = []
    feedback = nil
  }

  func stopCurrentTask() async {
    sendTask?.cancel()
    sendTask = nil
    processingPollTask?.cancel()
    processingPollTask = nil
    isSending = false
    do {
      let endpoint = try APIEndpoint(
        path: ["message", "agent", "sessions", activeSessionID, "stop"], method: .post)
      try await session.perform(endpoint)
      feedback = NativeAgentFeedback(isError: false, message: "已停止当前助手任务。")
    } catch {
      return
    }
  }

  fileprivate func sendMessage(
    _ rawText: String,
    uploads: [NativeAgentUploadedAttachment],
    displayText: String? = nil,
    choiceSelection: JSONValue? = nil,
    originalMessageID: String? = nil
  ) {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty || !uploads.isEmpty else { return }

    let isSteeringFollowUp = isSending
    feedback = nil

    let userAttachments = uploads.map {
      NativeAgentAttachmentItem(
        kind: $0.kind, url: $0.url, downloadURL: $0.downloadURL, name: $0.name,
        mimeType: $0.mimeType, size: $0.size)
    }
    let userDisplay = displayText ?? (text.isEmpty ? "（已发送附件）" : text)
    messages.append(
      NativeAgentMessage(
        id: UUID().uuidString,
        isUser: true,
        content: userDisplay,
        tools: [],
        segments: userDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? [] : [.text(userDisplay)],
        attachments: userAttachments,
        choices: [],
        isProtected: false
      ))

    var payload: [String: JSONValue] = [
      "text": .string(text),
      "display_text": .string(userDisplay),
      "session_id": .string(activeSessionID),
      "echo_user": .bool(true),
    ]
    let imageRefs = uploads.filter { $0.kind == "image" }.map(\.ref)
    if !imageRefs.isEmpty {
      payload["images"] = .array(imageRefs.map(JSONValue.string))
    }
    let audioRefs = uploads.filter { $0.kind == "audio" }.map(\.ref)
    if !audioRefs.isEmpty {
      payload["audio_refs"] = .array(audioRefs.map(JSONValue.string))
    }
    let fileObjs: [JSONValue] = uploads.filter { $0.kind != "image" && $0.kind != "audio" }.map {
      u in
      var obj: [String: JSONValue] = ["ref": .string(u.ref)]
      if let n = u.name { obj["name"] = .string(n) }
      if let m = u.mimeType { obj["mime_type"] = .string(m) }
      if let s = u.size { obj["size"] = .number(Double(s)) }
      if let lp = u.localPath { obj["local_path"] = .string(lp) }
      obj["status"] = .string("ready")
      return .object(obj)
    }
    if !fileObjs.isEmpty { payload["files"] = .array(fileObjs) }
    if let choiceSelection { payload["choice_selection"] = choiceSelection }
    if let originalMessageID { payload["original_message_id"] = .string(originalMessageID) }

    if isSteeringFollowUp {
      Task { [weak self] in
        await self?.sendSteeringRequest(payload: payload)
      }
      return
    }

    let assistantID = UUID().uuidString
    messages.append(
      NativeAgentMessage(
        id: assistantID,
        isUser: false,
        content: "",
        tools: [],
        segments: [],
        attachments: [],
        choices: [],
        isProtected: false
      ))
    isSending = true
    processingPollTask?.cancel()
    processingPollTask = nil

    sendTask?.cancel()
    sendTask = Task { [weak self] in
      await self?.consumeAgentStream(payload: payload, assistantID: assistantID)
    }
  }

  private func sendSteeringRequest(payload: [String: JSONValue]) async {
    do {
      let body = try JSONEncoder().encode(payload)
      let ep = try APIEndpoint(
        path: ["message", "agent", "stream"], method: .post, body: body,
        responseContract: .eventStream, timeout: 60)
      let stream = try session.streamEvents(
        ep, extraHeaders: ["X-MoviePilot-Agent-Interaction": "1"])
      for try await evt in stream {
        if evt.event == "steering" || evt.controlHeader == "steering" {
          feedback = NativeAgentFeedback(isError: false, message: "已将追问补充传达给正在执行的智能助手。")
          break
        }
      }
    } catch {
      feedback = NativeAgentFeedback(isError: true, message: "发送追问补充失败。")
    }
  }

  private func consumeAgentStream(payload: [String: JSONValue], assistantID: String) async {
    defer {
      isSending = false
      sendTask = nil
    }
    do {
      let body = try JSONEncoder().encode(payload)
      let endpoint = try APIEndpoint(
        path: ["message", "agent", "stream"],
        method: .post,
        body: body,
        responseContract: .eventStream,
        maximumResponseBytes: 8 * 1024 * 1024,
        timeout: 120)
      let stream = try session.streamEvents(
        endpoint,
        extraHeaders: ["X-MoviePilot-Agent-Interaction": "1"])

      for try await sse in stream {
        guard !Task.isCancelled else { break }
        applySSEEvent(sse, assistantID: assistantID)
      }

      if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
        for ti in messages[idx].tools.indices where messages[idx].tools[ti].status == "running" {
          messages[idx].tools[ti].status = messages[idx].tools[ti].structured ? "error" : "done"
        }
        let msg = messages[idx]
        if msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && msg.attachments.isEmpty && msg.choices.isEmpty
        {
          NativeAgentChatPage.appendTextSegment(to: &messages[idx], delta: "已完成处理。")
        }
      }
      await saveDisplaySnapshotToServer()
      await loadSessions()
    } catch is CancellationError {
      return
    } catch let apiError as APIError {
      handleStreamError(apiError.userVisibleDescription, assistantID: assistantID)
    } catch {
      handleStreamError("智能助手连接中断，请检查服务状态或大模型配置。", assistantID: assistantID)
    }
  }

  /// 对齐 Web `AgentAssistantPanel.vue`：将当前会话的展示消息同步到服务端，确保冷重启或切回历史会话时消息列表完整。
  private func saveDisplaySnapshotToServer() async {
    let visibleMessages = messages.filter { ($0.isUser || $0.hasVisibleContent) && !$0.isProtected }
    guard !activeSessionID.isEmpty, !visibleMessages.isEmpty else { return }
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let serialized: [JSONValue] = visibleMessages.enumerated().map { index, msg in
      let toolsJSON: [JSONValue] = msg.tools.map { tool in
        var obj: [String: JSONValue] = [
          "id": .string(tool.id),
          "message": .string(tool.message),
          "status": .string(tool.status),
          "structured": .bool(tool.structured),
        ]
        if let name = tool.toolName, !name.isEmpty {
          obj["tool_name"] = .string(name)
        }
        return .object(obj)
      }
      let segmentsJSON: [JSONValue] = msg.segments.map { seg in
        switch seg {
        case .text(let text):
          return .object(["type": .string("text"), "content": .string(text)])
        case .tool(let idx):
          return .object([
            "type": .string("tool"), "content": .string(""), "toolIndex": .number(Double(idx)),
          ])
        }
      }
      let attachmentsJSON: [JSONValue] = msg.attachments.map { att in
        var obj: [String: JSONValue] = [
          "kind": .string(att.kind),
          "url": .string(att.url),
        ]
        if let d = att.downloadURL { obj["download_url"] = .string(d) }
        if let n = att.name { obj["name"] = .string(n) }
        if let m = att.mimeType { obj["mime_type"] = .string(m) }
        if let s = att.size { obj["size"] = .number(Double(s)) }
        return .object(obj)
      }
      return .object([
        "id": .string(msg.id),
        "role": .string(msg.isUser ? "user" : "assistant"),
        "content": .string(msg.content),
        "createdAt": .number(Double(nowMs - Int64((visibleMessages.count - index) * 1000))),
        "status": .string("done"),
        "tools": .array(toolsJSON),
        "segments": .array(segmentsJSON),
        "attachments": .array(attachmentsJSON),
      ])
    }
    let firstUserText =
      visibleMessages.first(where: {
        $0.isUser && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })?
      .content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "新会话"
    let title = String(firstUserText.prefix(40))
    let bodyObj: [String: JSONValue] = [
      "title": .string(title),
      "messages": .array(serialized),
    ]
    guard let body = try? JSONEncoder().encode(bodyObj),
      let endpoint = try? APIEndpoint(
        path: ["message", "agent", "sessions", activeSessionID, "display"],
        method: .put,
        body: body)
    else { return }
    try? await session.perform(endpoint)
  }

  private func handleStreamError(_ text: String, assistantID: String) {
    if let idx = messages.firstIndex(where: { $0.id == assistantID }),
      messages[idx].content.isEmpty && messages[idx].tools.isEmpty
    {
      messages.remove(at: idx)
    }
    feedback = NativeAgentFeedback(isError: true, message: text)
  }

  private func applySSEEvent(_ sse: APISSEEvent, assistantID: String) {
    guard let idx = messages.firstIndex(where: { $0.id == assistantID }) else { return }
    let obj = (try? JSONSerialization.jsonObject(with: Data(sse.data.utf8))) as? [String: Any]
    let eventName = (obj?["type"] as? String ?? sse.event).lowercased()

    switch eventName {
    case "start":
      if let sid = obj?["session_id"] as? String, !sid.isEmpty {
        activeSessionID = sid
        UserDefaults.standard.set(sid, forKey: lastSessionStorageKey)
        Task { [weak self] in
          await self?.saveDisplaySnapshotToServer()
        }
      }
    case "thinking":
      break
    case "tool":
      let rawToolID =
        NativeAgentChatPage.nonEmptyString(obj?["tool_id"])
        ?? NativeAgentChatPage.nonEmptyString(obj?["tool_call_id"])
        ?? NativeAgentChatPage.nonEmptyString(obj?["id"])
      let toolName = NativeAgentChatPage.nonEmptyString(obj?["tool_name"])
      let rawStatus = (obj?["status"] as? String ?? "").lowercased()
      let normalizedMessage = NativeAgentChatPage.normalizeToolMessage(
        NativeAgentChatPage.nonEmptyString(obj?["message"]) ?? toolName ?? "")

      if let toolID = rawToolID {
        let targetIdx =
          messages.firstIndex(where: { $0.tools.contains(where: { $0.id == toolID }) }) ?? idx
        let status = rawStatus == "error" ? "error" : (rawStatus == "done" ? "done" : "running")
        if let ti = messages[targetIdx].tools.firstIndex(where: { $0.id == toolID }) {
          if status == "running" {
            if messages[targetIdx].tools[ti].message.isEmpty && !normalizedMessage.isEmpty {
              messages[targetIdx].tools[ti].message = normalizedMessage
            }
          } else {
            messages[targetIdx].tools[ti].status = status
          }
        } else if status == "running" {
          let entry = NativeAgentToolEntry(
            id: toolID,
            toolName: toolName,
            message: normalizedMessage.isEmpty ? "调用工具" : normalizedMessage,
            structured: true,
            status: "running"
          )
          messages[targetIdx].tools.append(entry)
          messages[targetIdx].segments.append(.tool(messages[targetIdx].tools.count - 1))
        }
      } else {
        if rawStatus == "done" || rawStatus == "error" { break }
        for ti in messages[idx].tools.indices where messages[idx].tools[ti].status == "running" {
          messages[idx].tools[ti].status = "done"
        }
        guard !normalizedMessage.isEmpty else { break }
        let entry = NativeAgentToolEntry(
          id: "tool-\(UUID().uuidString)",
          toolName: toolName,
          message: normalizedMessage,
          structured: false,
          status: "running"
        )
        messages[idx].tools.append(entry)
        messages[idx].segments.append(.tool(messages[idx].tools.count - 1))
      }
    case "delta":
      for ti in messages[idx].tools.indices
      where messages[idx].tools[ti].status == "running" && !messages[idx].tools[ti].structured {
        messages[idx].tools[ti].status = "done"
      }
      if let delta = (obj?["content"] as? String) ?? (obj?["delta"] as? String)
        ?? (obj?["text"] as? String),
        !delta.isEmpty
      {
        NativeAgentChatPage.appendTextSegment(to: &messages[idx], delta: delta)
      }
    case "message_update":
      let targetObj = (obj?["target_message"] as? [String: Any]) ?? obj
      if let full = (targetObj?["content"] as? String) ?? (targetObj?["message"] as? String) {
        messages[idx].content = full
        messages[idx].segments = messages[idx].segments.filter {
          if case .tool = $0 { return true }
          return false
        }
        if !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          messages[idx].segments.append(.text(full))
        }
      }
    case "attachment":
      let rawAtt = (obj?["attachment"] as? [String: Any]) ?? obj
      if let rawAtt, let url = rawAtt["url"] as? String, !url.isEmpty {
        let item = NativeAgentAttachmentItem(
          kind: (rawAtt["kind"] as? String) ?? "file",
          url: url,
          downloadURL: rawAtt["download_url"] as? String,
          name: rawAtt["name"] as? String,
          mimeType: rawAtt["mime_type"] as? String,
          size: rawAtt["size"] as? Int)
        if !messages[idx].attachments.contains(where: { $0.url == item.url }) {
          messages[idx].attachments.append(item)
        }
      }
    case "choice":
      let rawChoice = (obj?["choice"] as? [String: Any]) ?? obj
      if let rawChoice,
        let rawData = try? JSONSerialization.data(withJSONObject: rawChoice),
        let decoded = try? JSONDecoder().decode(NativeAgentChoiceCard.self, from: rawData)
      {
        if let ci = messages[idx].choices.firstIndex(where: { $0.id == decoded.id }) {
          messages[idx].choices[ci] = decoded
        } else {
          messages[idx].choices.append(decoded)
        }
      }
    case "interaction-protected":
      messages[idx].isProtected = true
      if let secret = (obj?["content"] as? String) ?? (obj?["message"] as? String), !secret.isEmpty
      {
        let prefix = messages[idx].content.isEmpty ? "" : "\n\n"
        NativeAgentChatPage.appendTextSegment(to: &messages[idx], delta: prefix + secret)
      }
    case "steering":
      feedback = NativeAgentFeedback(isError: false, message: "智能助手已接收你的实时补充指令。")
    case "error":
      let msg = (obj?["message"] as? String) ?? (obj?["error"] as? String) ?? "智能助手执行出错"
      feedback = NativeAgentFeedback(isError: true, message: msg)
      for ti in messages[idx].tools.indices where messages[idx].tools[ti].status == "running" {
        messages[idx].tools[ti].status = "error"
      }
    case "done":
      for ti in messages[idx].tools.indices where messages[idx].tools[ti].status == "running" {
        messages[idx].tools[ti].status = messages[idx].tools[ti].structured ? "error" : "done"
      }
      if let finalMsg = (obj?["message"] as? String) ?? (obj?["content"] as? String),
        !finalMsg.isEmpty, messages[idx].content.isEmpty
      {
        NativeAgentChatPage.appendTextSegment(to: &messages[idx], delta: finalMsg)
      }
    default:
      if let content = obj?["content"] as? String, !content.isEmpty {
        NativeAgentChatPage.appendTextSegment(to: &messages[idx], delta: content)
      }
    }
  }

  fileprivate func triggerChoiceCallback(
    card: NativeAgentChoiceCard, button: NativeAgentChoiceButton, messageID: String
  ) async {
    do {
      let body = try JSONEncoder().encode([
        "session_id": activeSessionID,
        "callback_data": button.callbackData,
        "original_message_id": messageID,
      ])
      let ep = try APIEndpoint(
        path: ["message", "agent", "callback"], method: .post, body: body)
      let res = try await session.request(ep, as: NativeAgentCallbackResponse.self).value
      if let mi = messages.firstIndex(where: { $0.id == messageID }),
        let ci = messages[mi].choices.firstIndex(where: { $0.id == card.id })
      {
        messages[mi].choices[ci].selectedLabel = res.feedback?.selectedLabel ?? button.label
      }
      if !res.alreadySelected && !res.message.isEmpty {
        let display = res.displayMessage.isEmpty ? "选择：\(button.label)" : res.displayMessage
        sendMessage(
          res.message,
          uploads: [],
          displayText: display,
          choiceSelection: res.choiceSelection,
          originalMessageID: messageID)
      }
    } catch {
      feedback = NativeAgentFeedback(isError: true, message: "提交选择项失败，请稍后重试。")
    }
  }
}

/// 原生 AI Agent 对话页（八.1 全量对标 Web）：修复 `/api/v1/message/agent/*` 路由，支持真流式 SSE、工具调用进度、思考计时、Markdown/代码块渲染、交互选择卡、敏感保护交付、图片/文件上传与下载及原生语音录制与播放。
@MainActor
struct NativeAgentChatPage: View {
  let session: NativeSession

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @ObservedObject private var store: NativeAgentChatStore
  @StateObject private var audioBridge = NativeAgentAudioController()
  @State private var draftText: String
  @State private var pendingUploads: [NativeAgentUploadedAttachment] = []
  @State private var isUploadingAttachment = false
  @State private var showsSessionsSheet = false
  @State private var pendingDeleteSession: NativeAgentSessionSummary?

  // 多模态输入与附件预览
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var showsPhotoPicker = false
  @State private var showsFileImporter = false
  @State private var previewImageItem: NativeAgentImagePreviewItem?
  @State private var shareFileItem: NativeAgentShareFileItem?
  @State private var downloadingAttachmentURL: String?

  private var activeSessionID: String { store.activeSessionID }
  private var messages: [NativeAgentMessage] { store.messages }
  private var sessions: [NativeAgentSessionSummary] { store.sessions }
  private var commands: [NativeAgentCommandItem] { store.commands }
  private var isSending: Bool { store.isSending }
  private var isLoadingInitialSession: Bool { store.isLoadingInitialSession }
  private var isLoadingSessions: Bool { store.isLoadingSessions }
  private var feedback: NativeAgentFeedback? { store.feedback }

  /// 初始化智能助手对话页；外部链接仅可预填输入草稿，绝不自动替用户发送消息。
  init(session: NativeSession, initialPrompt: String = "") {
    self.session = session
    _store = ObservedObject(wrappedValue: NativeAgentChatStore.shared(for: session))
    _draftText = State(initialValue: initialPrompt)
  }

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
              if isLoadingInitialSession && messages.isEmpty && !isSending {
                NativeCardListSkeletonView(style: .chatBubbles)
                  .transition(.opacity)
              } else if messages.isEmpty && !isSending {
                welcomeSection
              } else {
                ForEach(messages) { message in
                  if message.isUser || message.hasVisibleContent {
                    messageRow(message)
                      .id(message.id)
                  }
                }
              }
              if isSending {
                HStack(spacing: 8) {
                  ProgressView().controlSize(.small).tint(appearance.accentColor)
                  Text("思考中")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(NativeTheme.chipFill, in: Capsule())
                .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
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
          .onChange(of: messages.last?.content.count ?? 0) { _ in
            if isSending, let last = messages.last {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 6) {
        if draftText.hasPrefix("/") && !matchedSlashCommands.isEmpty {
          slashSuggestStrip
            .padding(.horizontal, CinematicStyle.margin)
        }
        if !pendingUploads.isEmpty || audioBridge.isRecording || isUploadingAttachment {
          pendingAttachmentsStrip
            .padding(.horizontal, CinematicStyle.margin)
        }
        composerBar
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.top, 2)
          .padding(.bottom, 10)
      }
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
        .tint(.primary)
        .accessibilityLabel("新建对话")
        .accessibilityIdentifier("native-agent-new")

        Button {
          showsSessionsSheet = true
          Task { await loadSessions() }
        } label: {
          Image(systemName: "clock.arrow.circlepath")
        }
        .tint(.primary)
        .accessibilityLabel("历史会话")
        .accessibilityIdentifier("native-agent-sessions")
      }
    }
    .photosPicker(isPresented: $showsPhotoPicker, selection: $selectedPhotoItem, matching: .images)
    .onChange(of: selectedPhotoItem) { newItem in
      guard let newItem else { return }
      selectedPhotoItem = nil
      Task { await handleSelectedPhoto(newItem) }
    }
    .fileImporter(
      isPresented: $showsFileImporter,
      allowedContentTypes: [.item],
      allowsMultipleSelection: false
    ) { result in
      if case .success(let urls) = result, let url = urls.first {
        Task { await handleImportedFile(url) }
      }
    }
    .sheet(isPresented: $showsSessionsSheet) {
      sessionsSheet
    }
    .sheet(item: $previewImageItem) { item in
      NativeAgentImagePreviewSheet(item: item)
    }
    .sheet(item: $shareFileItem) { item in
      NativeAgentActivityShareView(activityItems: [item.url])
    }
    .task {
      await store.loadBootstrap()
    }
    .onDisappear {
      audioBridge.stopAll()
    }
  }

  // MARK: - 欢迎区与斜杠命令建议

  private var matchedSlashCommands: [NativeAgentCommandItem] {
    let prefix = draftText.trimmingCharacters(in: .whitespaces).lowercased()
    guard prefix.hasPrefix("/") else { return [] }
    return commands.filter { $0.command.lowercased().hasPrefix(prefix) }.prefix(8).map { $0 }
  }

  private var slashSuggestStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(matchedSlashCommands) { cmd in
          Button {
            draftText = cmd.command + " "
          } label: {
            VStack(alignment: .leading, spacing: 1) {
              Text(cmd.command)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(appearance.accentColor)
              if !cmd.description.isEmpty {
                Text(cmd.description)
                  .font(.system(size: 10))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
              NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6)
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var welcomeSection: some View {
    VStack(spacing: 18) {
      VStack(spacing: 10) {
        ZStack {
          Circle()
            .fill(
              LinearGradient(
                colors: [appearance.accentColor.opacity(0.85), NativeTheme.pink.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
          Image(systemName: "sparkles")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(width: 66, height: 66)
        .shadow(color: appearance.accentColor.opacity(0.32), radius: 14, y: 6)

        Text("MoviePilot 智能助手")
          .font(.title3.bold())
          .foregroundStyle(.primary)
        Text("支持语音、图片、文件交互与工具调用，帮你搜索影视、订阅追剧、查看下载或触发整理。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.top, 16)

      VStack(alignment: .leading, spacing: 10) {
        Text("快捷提问")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        ForEach(Self.quickPrompts, id: \.self) { prompt in
          Button {
            sendMessage(prompt)
          } label: {
            CinematicPanel(padding: 12) {
              HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                  .font(.subheadline)
                  .foregroundStyle(NativeTheme.brand)
                Text(prompt)
                  .font(.subheadline)
                  .foregroundStyle(.primary)
                  .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(commands.prefix(12)) { cmd in
                Button {
                  draftText = cmd.command + " "
                } label: {
                  NativeAdaptivePill(cmd.command, isSelected: false)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - 消息气泡（Markdown / 工具调用 / 附件图片音频文件 / 选择卡 / 敏感保护）

  @ViewBuilder
  private func messageRow(_ message: NativeAgentMessage) -> some View {
    if message.isUser {
      HStack {
        Spacer(minLength: 44)
        VStack(alignment: .trailing, spacing: 6) {
          if !message.attachments.isEmpty {
            attachmentsBlock(message.attachments, isUser: true)
          }
          if !message.content.isEmpty {
            Text(message.content)
              .font(.subheadline)
              .foregroundStyle(.white)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .background(
                appearance.accentColor,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
              )
              .textSelection(.enabled)
          }
        }
      }
    } else {
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          Circle().fill(appearance.accentColor.opacity(0.18))
          Image(systemName: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(appearance.accentColor)
        }
        .frame(width: 28, height: 28)

        CinematicPanel(padding: 13) {
          VStack(alignment: .leading, spacing: 10) {
            if message.isProtected {
              HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                  .font(.caption)
                  .foregroundStyle(NativeTheme.warning)
                Text("受保护敏感结果（仅本次会话内存显示）")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(NativeTheme.warning)
                Spacer()
                Button {
                  UIPasteboard.general.string = message.content
                  store.feedback = NativeAgentFeedback(isError: false, message: "已复制受保护内容。")
                } label: {
                  Label("复制", systemImage: "doc.on.doc")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(appearance.accentColor)
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 9).padding(.vertical, 6)
              .background(
                NativeTheme.warning.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            let segments = Self.renderableSegments(for: message)
            if !segments.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                  switch segment {
                  case .text(_, let content):
                    NativeAgentMarkdownView(markdown: content)
                  case .tool(_, let tool):
                    HStack(spacing: 7) {
                      if tool.status == "running" {
                        ProgressView().controlSize(.mini).tint(appearance.accentColor)
                      } else {
                        Image(
                          systemName: tool.status == "error"
                            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(
                          tool.status == "error" ? NativeTheme.danger : NativeTheme.success)
                      }
                      Text(tool.displayText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(
                      NativeTheme.chipFill,
                      in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                  }
                }
              }
            } else if !message.content.isEmpty {
              NativeAgentMarkdownView(markdown: message.content)
            }

            if !message.attachments.isEmpty {
              attachmentsBlock(message.attachments, isUser: false)
            }

            if !message.choices.isEmpty {
              ForEach(message.choices) { card in
                choiceCardView(card, messageID: message.id)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        Spacer(minLength: 14)
      }
    }
  }

  /// 渲染图片、语音音频与文档下载附件。
  private func attachmentsBlock(
    _ attachments: [NativeAgentAttachmentItem], isUser: Bool
  ) -> some View {
    VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
      ForEach(attachments) { att in
        if att.isImage {
          NativeAgentAttachmentImageTile(
            session: session,
            attachment: att,
            onTapImage: { uiImage in
              previewImageItem = NativeAgentImagePreviewItem(
                title: att.displayName, image: uiImage)
            }
          )
        } else if att.isAudio {
          let playing = audioBridge.playingURL == att.url
          Button {
            Task { await togglePlayAudioAttachment(att) }
          } label: {
            HStack(spacing: 8) {
              if downloadingAttachmentURL == att.url {
                ProgressView().controlSize(.mini).tint(isUser ? .white : appearance.accentColor)
              } else {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                  .font(.title3)
                  .foregroundStyle(isUser ? .white : appearance.accentColor)
              }
              VStack(alignment: .leading, spacing: 1) {
                Text(att.displayName)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(isUser ? .white : .primary)
                  .lineLimit(1)
                Text(playing ? "播放中…" : "点击播放语音")
                  .font(.caption2)
                  .foregroundStyle(isUser ? .white.opacity(0.8) : .secondary)
              }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
              isUser ? appearance.accentColor : NativeTheme.chipFill,
              in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .buttonStyle(.plain)
        } else {
          Button {
            Task { await downloadAndShareAttachment(att) }
          } label: {
            HStack(spacing: 9) {
              Image(systemName: "doc.fill")
                .font(.body)
                .foregroundStyle(isUser ? .white : NativeTheme.info)
              VStack(alignment: .leading, spacing: 2) {
                Text(att.displayName)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(isUser ? .white : .primary)
                  .lineLimit(1)
                if let sizeText = att.formattedSize {
                  Text(sizeText)
                    .font(.caption2)
                    .foregroundStyle(isUser ? .white.opacity(0.75) : .secondary)
                }
              }
              Spacer(minLength: 6)
              if downloadingAttachmentURL == att.url {
                ProgressView().controlSize(.mini).tint(isUser ? .white : .primary)
              } else {
                Image(systemName: "arrow.down.circle")
                  .font(.subheadline)
                  .foregroundStyle(isUser ? .white : appearance.accentColor)
              }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
              isUser ? appearance.accentColor : NativeTheme.chipFill,
              in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  /// 交互选择卡片（点击按钮触发 `POST /api/v1/message/agent/callback` 并派发续对话）。
  private func choiceCardView(_ card: NativeAgentChoiceCard, messageID: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title = card.title, !title.isEmpty {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
      }
      if !card.prompt.isEmpty {
        Text(card.prompt).font(.caption).foregroundStyle(.secondary)
      }
      if let selected = card.selectedLabel, !selected.isEmpty {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(NativeTheme.success)
          Text("已选择：\(selected)").font(.caption.weight(.semibold)).foregroundStyle(
            NativeTheme.success)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(NativeTheme.success.opacity(0.12), in: Capsule())
      } else {
        let rows: [[NativeAgentChoiceButton]] =
          card.buttonRows.isEmpty ? card.buttons.map { [$0] } : card.buttonRows
        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            HStack(spacing: 7) {
              ForEach(row, id: \.callbackData) { btn in
                Button {
                  Task {
                    await triggerChoiceCallback(card: card, button: btn, messageID: messageID)
                  }
                } label: {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(btn.label)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(appearance.accentColor)
                    if let desc = btn.description, !desc.isEmpty {
                      Text(desc).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 11).padding(.vertical, 8)
                  .background(
                    appearance.accentColor.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                  )
                  .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                      .strokeBorder(appearance.accentColor.opacity(0.32), lineWidth: 0.7)
                  }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
              }
            }
          }
        }
      }
    }
    .padding(10)
    .background(NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  // MARK: - 底部多模态输入栏

  private var pendingAttachmentsStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        if audioBridge.isRecording {
          HStack(spacing: 7) {
            Circle().fill(NativeTheme.danger).frame(width: 8, height: 8)
            Text("正在录音 \(audioBridge.recordingDurationText)")
              .font(.caption.monospacedDigit().weight(.semibold))
              .foregroundStyle(NativeTheme.danger)
            Button("取消") { audioBridge.cancelRecording() }
              .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
          }
          .padding(.horizontal, 11).padding(.vertical, 7)
          .background(NativeTheme.danger.opacity(0.12), in: Capsule())
        }
        if isUploadingAttachment {
          HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("上传附件中…").font(.caption2).foregroundStyle(.secondary)
          }
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(NativeTheme.chipFill, in: Capsule())
        }
        ForEach(pendingUploads) { item in
          HStack(spacing: 6) {
            Image(
              systemName: item.kind == "image"
                ? "photo" : (item.kind == "audio" ? "waveform" : "doc")
            )
            .font(.caption2)
            .foregroundStyle(appearance.accentColor)
            Text(item.name ?? "附件")
              .font(.caption2.weight(.medium))
              .lineLimit(1)
              .frame(maxWidth: 120)
            Button {
              pendingUploads.removeAll { $0.ref == item.ref }
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(NativeTheme.chipFill, in: Capsule())
          .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
        }
      }
    }
  }

  private var composerBar: some View {
    let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    let canSend = !trimmed.isEmpty || !pendingUploads.isEmpty
    return HStack(spacing: 6) {
      Menu {
        Button {
          showsPhotoPicker = true
        } label: {
          Label("发送图片", systemImage: "photo.on.rectangle")
        }
        Button {
          showsFileImporter = true
        } label: {
          Label("发送文件", systemImage: "doc")
        }
      } label: {
        Image(systemName: "plus.circle.fill")
          .font(.system(size: 26))
          .foregroundStyle(.secondary)
          .frame(width: 34, height: 34)
      }
      .accessibilityLabel("添加图片或文件")

      TextField(
        "输入消息或 / 命令…",
        text: $draftText,
        prompt: Text(isSending ? "输入内容可实时追问补充…" : "输入消息或 / 命令…").foregroundColor(.secondary)
      )
      .font(.subheadline)
      .foregroundStyle(.primary)
      .submitLabel(.send)
      .onSubmit {
        if canSend { sendMessage(draftText) }
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 8)
      .accessibilityIdentifier("native-agent-input")

      Button {
        Task { await toggleVoiceRecording() }
      } label: {
        Image(systemName: audioBridge.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
          .font(.system(size: 28))
          .foregroundStyle(audioBridge.isRecording ? NativeTheme.danger : .secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(audioBridge.isRecording ? "停止并发送语音" : "语音输入")

      if isSending && !canSend {
        Button {
          Task { await stopCurrentTask() }
        } label: {
          Image(systemName: "stop.circle.fill")
            .font(.system(size: 31))
            .foregroundStyle(NativeTheme.danger)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("停止生成")
        .accessibilityIdentifier("native-agent-stop")
      } else {
        Button {
          sendMessage(draftText)
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 31))
            .foregroundStyle(canSend ? appearance.accentColor : .primary.opacity(0.24))
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

  // MARK: - 历史会话弹层

  private var sessionsSheet: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if isLoadingSessions && sessions.isEmpty {
              NativeCardListSkeletonView(count: 4, style: .iconRow)
                .transition(.opacity)
            } else if sessions.isEmpty {
              CinematicPanel {
                VStack(spacing: 8) {
                  Image(systemName: "bubble.left.and.bubble.right")
                    .font(.largeTitle).foregroundStyle(.secondary)
                  Text("暂无历史会话").font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
              }
            } else {
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { CinematicFormDivider() }
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
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if item.sessionID == activeSessionID {
                          NativeAdaptiveBadge("当前", tint: appearance.accentColor)
                        }
                        Image(systemName: "chevron.right")
                          .font(.caption2.weight(.semibold))
                          .foregroundStyle(.secondary.opacity(0.55))
                      }
                      .padding(.horizontal, 15).padding(.vertical, 11)
                      .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                      Button(role: .destructive) {
                        pendingDeleteSession = item
                      } label: {
                        Label("删除会话", systemImage: "trash")
                      }
                    }
                    .accessibilityIdentifier("native-agent-session-\(item.sessionID)")
                  }
                }
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
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
          .tint(.primary)
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-agent-sessions-close")
        }
      }
      .alert(
        "删除会话",
        isPresented: Binding(
          get: { pendingDeleteSession != nil }, set: { if !$0 { pendingDeleteSession = nil } }),
        presenting: pendingDeleteSession
      ) { item in
        Button("确认删除", role: .destructive) { Task { await deleteSession(item) } }
        Button("取消", role: .cancel) {}
      } message: { item in
        Text("确认删除会话「\(item.displayTitle)」吗？")
      }
    }
    .nativeGlassSheet()
  }

  private func feedbackBanner(_ feedback: NativeAgentFeedback) -> some View {
    CinematicPanel(padding: 10) {
      HStack(spacing: 8) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
        Text(feedback.message).font(.caption).foregroundStyle(.primary)
        Spacer(minLength: 0)
        Button {
          store.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary).frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-agent-feedback")
  }

  // MARK: - 代理至会话常驻 Store（关闭弹窗不中断正在运行的 SSE 流与历史消息状态）

  private func loadSessions() async {
    await store.loadSessions()
  }

  private func openSession(_ sessionID: String, silentOnFailure: Bool = false) async {
    await store.openSession(sessionID, silentOnFailure: silentOnFailure)
  }

  private func deleteSession(_ item: NativeAgentSessionSummary) async {
    await store.deleteSession(item)
  }

  private func startNewSession() {
    store.startNewSession()
    pendingUploads = []
    draftText = ""
  }

  private func stopCurrentTask() async {
    await store.stopCurrentTask()
  }

  private func sendMessage(
    _ rawText: String,
    displayText: String? = nil,
    choiceSelection: JSONValue? = nil,
    originalMessageID: String? = nil
  ) {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    let uploads = pendingUploads
    guard !text.isEmpty || !uploads.isEmpty else { return }
    draftText = ""
    pendingUploads = []
    store.sendMessage(
      rawText,
      uploads: uploads,
      displayText: displayText,
      choiceSelection: choiceSelection,
      originalMessageID: originalMessageID
    )
  }

  /// 对标 Web `AgentAssistantPanel.vue`：提取非空字符串。
  fileprivate static func nonEmptyString(_ raw: Any?) -> String? {
    guard let s = raw as? String else { return nil }
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// 清理后端工具提示前缀 `=> `。
  nonisolated fileprivate static func normalizeToolMessage(_ raw: String) -> String {
    raw.replacingOccurrences(of: #"^=>\s*"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 追加文本增量到消息正文及有序片段，保留与工具调用之间的时间线边界。
  fileprivate static func appendTextSegment(to message: inout NativeAgentMessage, delta: String) {
    guard !delta.isEmpty else { return }
    message.content += delta
    if case .text(let existing) = message.segments.last {
      message.segments[message.segments.count - 1] = .text(existing + delta)
    } else if !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      message.segments.append(.text(delta))
    }
  }

  /// 解析非啰嗦模式的工具汇总，例如 `（查询媒体 1 次，搜索站点 2 次）`。
  private static func parseToolSummary(
    _ message: String
  ) -> [(prefix: String, count: Int, suffix: String)]? {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    let inner: String
    if trimmed.hasPrefix("（") && trimmed.hasSuffix("）") {
      inner = String(trimmed.dropFirst().dropLast())
    } else if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
      inner = String(trimmed.dropFirst().dropLast())
    } else {
      return nil
    }
    guard !inner.isEmpty else { return nil }
    guard let countRegex = try? NSRegularExpression(pattern: #"^(.*?\D)(\d+)(\D.*)$"#) else {
      return nil
    }
    let rawParts = inner.split(whereSeparator: { $0 == "，" || $0 == "," }).map {
      String($0).trimmingCharacters(in: .whitespaces)
    }
    guard !rawParts.isEmpty else { return nil }
    var parsed: [(prefix: String, count: Int, suffix: String)] = []
    for part in rawParts {
      let ns = part as NSString
      let range = NSRange(location: 0, length: ns.length)
      guard let match = countRegex.firstMatch(in: part, range: range), match.numberOfRanges == 4,
        let count = Int(ns.substring(with: match.range(at: 2)))
      else { return nil }
      parsed.append(
        (
          prefix: ns.substring(with: match.range(at: 1)),
          count: count,
          suffix: ns.substring(with: match.range(at: 3))
        ))
    }
    return parsed
  }

  /// 合并相邻非啰嗦工具汇总（对标 Web `mergeToolSummaries`）。
  private static func mergeToolSummaries(_ currentMessage: String, _ nextMessage: String) -> String?
  {
    guard let currentParts = parseToolSummary(currentMessage),
      let nextParts = parseToolSummary(nextMessage)
    else { return nil }
    var merged = currentParts
    var indexes: [String: Int] = [:]
    for (idx, part) in merged.enumerated() {
      indexes["\(part.prefix)\u{0}\(part.suffix)"] = idx
    }
    for part in nextParts {
      let key = "\(part.prefix)\u{0}\(part.suffix)"
      if let existingIdx = indexes[key] {
        merged[existingIdx].count += part.count
      } else {
        indexes[key] = merged.count
        merged.append(part)
      }
    }
    let joined = merged.map { "\($0.prefix)\($0.count)\($0.suffix)" }.joined(separator: "，")
    return "（\(joined)）"
  }

  /// 按事件顺序生成可渲染片段，自动合并相邻的非啰嗦工具汇总条目（对标 Web `getRenderableMessageSegments`）。
  private static func renderableSegments(
    for message: NativeAgentMessage
  ) -> [NativeAgentRenderableSegment] {
    var result: [NativeAgentRenderableSegment] = []
    for (index, segment) in message.segments.enumerated() {
      switch segment {
      case .text(let content):
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          result.append(.text(key: "text-\(index)", content: content))
        }
      case .tool(let toolIndex):
        guard toolIndex >= 0, toolIndex < message.tools.count else { continue }
        let tool = message.tools[toolIndex]
        if case .tool(let prevKey, var prevTool) = result.last,
          let mergedText = mergeToolSummaries(prevTool.message, tool.message)
        {
          prevTool.message = mergedText
          prevTool.status =
            (prevTool.status == "running" || tool.status == "running")
            ? "running"
            : ((prevTool.status == "error" || tool.status == "error") ? "error" : "done")
          result[result.count - 1] = .tool(key: prevKey, entry: prevTool)
        } else {
          result.append(.tool(key: "tool-\(tool.id)-\(index)", entry: tool))
        }
      }
    }
    return result
  }

  /// 点击交互选择卡片按钮 -> `POST /api/v1/message/agent/callback` -> 自动续发对话流。
  private func triggerChoiceCallback(
    card: NativeAgentChoiceCard, button: NativeAgentChoiceButton, messageID: String
  ) async {
    await store.triggerChoiceCallback(card: card, button: button, messageID: messageID)
  }

  // MARK: - 图片 / 文件 / 语音上传与下载

  private func handleSelectedPhoto(_ item: PhotosPickerItem) async {
    isUploadingAttachment = true
    defer { isUploadingAttachment = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
        return
      }
      let compressed = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
      await uploadAttachmentData(
        compressed, fileName: "photo_\(Int(Date().timeIntervalSince1970)).jpg",
        mimeType: "image/jpeg")
    } catch {
      store.feedback = NativeAgentFeedback(isError: true, message: "读取相册图片失败。")
    }
  }

  private func handleImportedFile(_ url: URL) async {
    isUploadingAttachment = true
    defer { isUploadingAttachment = false }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try Data(contentsOf: url)
      let mime =
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        ?? "application/octet-stream"
      await uploadAttachmentData(data, fileName: url.lastPathComponent, mimeType: mime)
    } catch {
      store.feedback = NativeAgentFeedback(isError: true, message: "读取本地文件失败。")
    }
  }

  private func toggleVoiceRecording() async {
    if audioBridge.isRecording {
      guard let fileURL = audioBridge.finishRecording() else { return }
      isUploadingAttachment = true
      defer {
        isUploadingAttachment = false
        try? FileManager.default.removeItem(at: fileURL)
      }
      if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
        await uploadAttachmentData(
          data, fileName: "voice_\(Int(Date().timeIntervalSince1970)).m4a", mimeType: "audio/mp4")
        if !pendingUploads.isEmpty && draftText.trimmingCharacters(in: .whitespaces).isEmpty {
          sendMessage("", displayText: "🎤 语音消息")
        }
      }
    } else {
      let ok = await audioBridge.startRecording()
      if !ok {
        store.feedback = NativeAgentFeedback(isError: true, message: "无法启动麦克风录音，请在系统设置中授权麦克风权限。")
      }
    }
  }

  private func uploadAttachmentData(_ data: Data, fileName: String, mimeType: String) async {
    do {
      let ep = try APIEndpoint(path: ["message", "agent", "upload"], method: .post, timeout: 60)
      let uploaded = try await session.uploadMultipart(
        ep,
        fieldName: "file",
        fileName: fileName,
        mimeType: mimeType,
        fileData: data,
        formFields: ["session_id": activeSessionID],
        as: NativeAgentUploadedAttachment.self
      ).value
      pendingUploads.append(uploaded)
    } catch {
      store.feedback = NativeAgentFeedback(isError: true, message: "上传附件「\(fileName)」失败。")
    }
  }

  private func fetchAttachmentBytes(_ att: NativeAgentAttachmentItem) async throws -> Data {
    let rawURL = att.downloadURL ?? att.url
    guard let fileID = Self.extractAgentFileID(from: rawURL) else {
      throw APIError.invalidEndpoint
    }
    let ep = try APIEndpoint(
      path: ["message", "agent", "file", fileID],
      responseContract: .payload,
      maximumResponseBytes: 16 * 1024 * 1024)
    return try await session.requestResourcePayload(ep).value
  }

  private func togglePlayAudioAttachment(_ att: NativeAgentAttachmentItem) async {
    if audioBridge.playingURL == att.url {
      audioBridge.stopPlayback()
      return
    }
    downloadingAttachmentURL = att.url
    defer { downloadingAttachmentURL = nil }
    do {
      let data = try await fetchAttachmentBytes(att)
      audioBridge.playAudioData(data, urlKey: att.url)
    } catch {
      store.feedback = NativeAgentFeedback(isError: true, message: "加载语音附件失败。")
    }
  }

  private func downloadAndShareAttachment(_ att: NativeAgentAttachmentItem) async {
    downloadingAttachmentURL = att.url
    defer { downloadingAttachmentURL = nil }
    do {
      let data = try await fetchAttachmentBytes(att)
      let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("AgentDownloads", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let safeName = att.displayName.replacingOccurrences(of: "/", with: "_")
      let fileURL = dir.appendingPathComponent(safeName)
      try data.write(to: fileURL, options: .atomic)
      shareFileItem = NativeAgentShareFileItem(url: fileURL)
    } catch {
      store.feedback = NativeAgentFeedback(isError: true, message: "下载附件失败。")
    }
  }

  fileprivate static func extractAgentFileID(from urlString: String) -> String? {
    let clean = urlString.split(separator: "?").first.map(String.init) ?? urlString
    let parts = clean.split(separator: "/")
    guard let idx = parts.lastIndex(of: "file"), idx + 1 < parts.endIndex else {
      return parts.last.map(String.init)
    }
    return String(parts[idx + 1])
  }

  private static let quickPrompts: [String] = [
    "看看我当前有哪些正在下载的任务",
    "列出我最近添加的订阅状态",
    "搜索最近热门的高分科幻电影",
    "检查站点连通性与今日整理记录",
  ]
}

// MARK: - 原生 Markdown 与代码块渲染视图

private struct NativeAgentMarkdownView: View {
  let markdown: String
  @Environment(\.colorScheme) private var colorScheme

  private struct IndexedBlock: Identifiable {
    let id: Int
    let block: AgentMarkdownBlock
  }

  private var blocks: [IndexedBlock] {
    AgentMarkdownParser.parse(markdown).enumerated().map {
      IndexedBlock(id: $0.offset, block: $0.element)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(blocks) { item in
        switch item.block {
        case .text(let raw):
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(raw.components(separatedBy: .newlines).enumerated()), id: \.offset) {
              _, line in
              markdownLineView(line)
            }
          }
        case .code(let lang, let code):
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text(lang.isEmpty ? "CODE" : lang.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
              Spacer()
              Button {
                UIPasteboard.general.string = code
              } label: {
                Label("复制", systemImage: "doc.on.doc")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(NativeTheme.brand)
              }
              .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(NativeTheme.chipFill)
            ScrollView(.horizontal, showsIndicators: false) {
              Text(code)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(10)
            }
          }
          .background(
            NativeTheme.fieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.6)
          }
        case .table(let table):
          markdownTableView(table)
        }
      }
    }
  }

  /// 原生玻璃 GFM 表格卡片：支持横向滚动、列对齐、平滑整行表头、斑马纹与单元格内联 Markdown，仅外框保留圆角避免单元格出现独立圆角伪影。
  private func markdownTableView(_ table: AgentMarkdownTable) -> some View {
    let dividerColor = Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.11)
    let headerFill = Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
    let zebraColor = Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03)
    let columnCount = max(
      table.headers.count,
      table.rows.map(\.count).max() ?? 0
    )
    return ScrollView(.horizontal, showsIndicators: true) {
      Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow {
          ForEach(0..<columnCount, id: \.self) { colIndex in
            let header = table.headers.indices.contains(colIndex) ? table.headers[colIndex] : ""
            let alignment =
              table.alignments.indices.contains(colIndex)
              ? table.alignments[colIndex] : .leading
            inlineMarkdownText(header)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.primary)
              .multilineTextAlignment(textAlignment(for: alignment))
              .frame(
                minWidth: 56,
                maxWidth: 220,
                alignment: frameAlignment(for: alignment)
              )
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 10)
              .padding(.vertical, 9)
              .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: frameAlignment(for: alignment)
              )
              .background { Rectangle().fill(headerFill) }
              .overlay(alignment: .trailing) {
                if colIndex < columnCount - 1 {
                  Rectangle().fill(dividerColor).frame(width: 0.5)
                }
              }
          }
        }

        ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
          Rectangle()
            .fill(dividerColor)
            .frame(height: 0.5)
          GridRow {
            ForEach(0..<columnCount, id: \.self) { colIndex in
              let cell = row.indices.contains(colIndex) ? row[colIndex] : ""
              let alignment =
                table.alignments.indices.contains(colIndex)
                ? table.alignments[colIndex] : .leading
              let rowFill = rowIndex.isMultiple(of: 2) ? Color.clear : zebraColor
              inlineMarkdownText(cell)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.92))
                .multilineTextAlignment(textAlignment(for: alignment))
                .textSelection(.enabled)
                .frame(
                  minWidth: 56,
                  maxWidth: 220,
                  alignment: frameAlignment(for: alignment)
                )
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(
                  maxWidth: .infinity,
                  maxHeight: .infinity,
                  alignment: frameAlignment(for: alignment)
                )
                .background { Rectangle().fill(rowFill) }
                .overlay(alignment: .trailing) {
                  if colIndex < columnCount - 1 {
                    Rectangle().fill(dividerColor).frame(width: 0.5)
                  }
                }
            }
          }
        }
      }
    }
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(NativeTheme.fieldFill)
    }
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.6)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-agent-markdown-table")
  }

  private func frameAlignment(for alignment: AgentMarkdownColumnAlignment) -> Alignment {
    switch alignment {
    case .leading: .leading
    case .center: .center
    case .trailing: .trailing
    }
  }

  private func textAlignment(for alignment: AgentMarkdownColumnAlignment) -> TextAlignment {
    switch alignment {
    case .leading: .leading
    case .center: .center
    case .trailing: .trailing
    }
  }

  @ViewBuilder
  private func markdownLineView(_ raw: String) -> some View {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty {
      Spacer().frame(height: 3)
    } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
      Rectangle()
        .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12))
        .frame(height: 0.6)
        .padding(.vertical, 4)
    } else if trimmed.hasPrefix("#### ") {
      inlineMarkdownText(String(trimmed.dropFirst(5)))
        .font(.footnote.bold())
        .foregroundStyle(.primary)
    } else if trimmed.hasPrefix("### ") {
      inlineMarkdownText(String(trimmed.dropFirst(4)))
        .font(.subheadline.bold())
        .foregroundStyle(.primary)
    } else if trimmed.hasPrefix("## ") {
      inlineMarkdownText(String(trimmed.dropFirst(3)))
        .font(.headline)
        .foregroundStyle(.primary)
    } else if trimmed.hasPrefix("# ") {
      inlineMarkdownText(String(trimmed.dropFirst(2)))
        .font(.title3.bold())
        .foregroundStyle(.primary)
    } else if trimmed.hasPrefix("> ") {
      HStack(alignment: .top, spacing: 8) {
        RoundedRectangle(cornerRadius: 2).fill(NativeTheme.brand).frame(width: 3)
        inlineMarkdownText(String(trimmed.dropFirst(2)))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
      HStack(alignment: .top, spacing: 6) {
        Text("•").font(.subheadline.bold()).foregroundStyle(NativeTheme.brand)
        inlineMarkdownText(String(trimmed.dropFirst(2)))
          .font(.subheadline)
          .foregroundStyle(.primary)
      }
    } else {
      inlineMarkdownText(raw)
        .font(.subheadline)
        .foregroundStyle(.primary)
    }
  }

  private func inlineMarkdownText(_ raw: String) -> Text {
    if let attr = try? AttributedString(
      markdown: raw,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    {
      return Text(attr)
    }
    return Text(raw)
  }
}

// MARK: - 附件图片加载组件与全屏预览 / 分享

@MainActor
private struct NativeAgentAttachmentImageTile: View {
  let session: NativeSession
  let attachment: NativeAgentAttachmentItem
  let onTapImage: (UIImage) -> Void

  @State private var image: UIImage?
  @State private var loading = false

  var body: some View {
    Group {
      if let image {
        Button {
          onTapImage(image)
        } label: {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: 220, maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
      } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(NativeTheme.chipFill)
          .frame(width: 160, height: 110)
          .overlay {
            if loading {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "photo").foregroundStyle(.secondary)
            }
          }
      }
    }
    .task(id: attachment.url) { await load() }
  }

  private func load() async {
    guard image == nil else { return }
    loading = true
    defer { loading = false }
    if let fileID = NativeAgentChatPage.extractAgentFileID(from: attachment.url),
      let ep = try? APIEndpoint(
        path: ["message", "agent", "file", fileID],
        responseContract: .payload,
        maximumResponseBytes: 12 * 1024 * 1024),
      let data = try? await session.requestResourcePayload(ep).value,
      let img = UIImage(data: data)
    {
      image = img
    }
  }
}

private struct NativeAgentImagePreviewItem: Identifiable {
  let id = UUID()
  let title: String
  let image: UIImage
}

@MainActor
private struct NativeAgentImagePreviewSheet: View {
  let item: NativeAgentImagePreviewItem
  @Environment(\.dismiss) private var dismiss
  @State private var saved = false

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        Image(uiImage: item.image)
          .resizable()
          .scaledToFit()
          .padding()
      }
      .navigationTitle(item.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(saved ? "已保存" : "保存相册") {
            UIImageWriteToSavedPhotosAlbum(item.image, nil, nil, nil)
            saved = true
          }
          .tint(.primary)
          .disabled(saved)
        }
      }
    }
  }
}

private struct NativeAgentShareFileItem: Identifiable {
  let id = UUID()
  let url: URL
}

private struct NativeAgentActivityShareView: UIViewControllerRepresentable {
  let activityItems: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 原生录音与 TTS 语音播放控制器

@MainActor
private final class NativeAgentAudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published var isRecording = false
  @Published var recordingSeconds = 0
  @Published var playingURL: String?

  private var recorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var recordingTimer: Timer?
  private var player: AVAudioPlayer?

  var recordingDurationText: String {
    let m = recordingSeconds / 60
    let s = recordingSeconds % 60
    return String(format: "%02d:%02d", m, s)
  }

  func startRecording() async -> Bool {
    stopPlayback()
    let audioSession = AVAudioSession.sharedInstance()
    let granted: Bool = await withCheckedContinuation { cont in
      audioSession.requestRecordPermission { ok in cont.resume(returning: ok) }
    }
    guard granted else { return false }
    do {
      try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try audioSession.setActive(true)
      let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      let url = dir.appendingPathComponent("agent_voice_\(UUID().uuidString).m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 24000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
      let rec = try AVAudioRecorder(url: url, settings: settings)
      rec.record()
      recorder = rec
      recordingURL = url
      recordingSeconds = 0
      isRecording = true
      recordingTimer?.invalidate()
      recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.recordingSeconds += 1 }
      }
      return true
    } catch {
      return false
    }
  }

  func finishRecording() -> URL? {
    recordingTimer?.invalidate()
    recordingTimer = nil
    recorder?.stop()
    recorder = nil
    isRecording = false
    let url = recordingURL
    recordingURL = nil
    return url
  }

  func cancelRecording() {
    if let url = finishRecording() {
      try? FileManager.default.removeItem(at: url)
    }
  }

  func playAudioData(_ data: Data, urlKey: String) {
    stopPlayback()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      let p = try AVAudioPlayer(data: data)
      p.delegate = self
      p.play()
      player = p
      playingURL = urlKey
    } catch {
      playingURL = nil
    }
  }

  func stopPlayback() {
    player?.stop()
    player = nil
    playingURL = nil
  }

  func stopAll() {
    cancelRecording()
    stopPlayback()
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      self.playingURL = nil
      self.player = nil
    }
  }
}

// MARK: - 模型定义

private struct NativeAgentFeedback {
  let isError: Bool
  let message: String
}

private struct NativeAgentToolEntry: Identifiable, Sendable {
  let id: String
  let toolName: String?
  var message: String
  var structured: Bool
  var status: String

  var displayText: String {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return toolName ?? "调用工具"
  }
}

private enum NativeAgentMessageSegment: Sendable {
  case text(String)
  case tool(Int)
}

private enum NativeAgentRenderableSegment: Identifiable {
  case text(key: String, content: String)
  case tool(key: String, entry: NativeAgentToolEntry)

  var id: String {
    switch self {
    case .text(let key, _): key
    case .tool(let key, _): key
    }
  }
}

private struct NativeAgentAttachmentItem: Identifiable, Sendable {
  var id: String { url }
  let kind: String
  let url: String
  let downloadURL: String?
  let name: String?
  let mimeType: String?
  let size: Int?

  var isImage: Bool {
    kind.lowercased() == "image" || (mimeType?.lowercased().hasPrefix("image/") == true)
  }

  var isAudio: Bool {
    kind.lowercased() == "audio" || (mimeType?.lowercased().hasPrefix("audio/") == true)
  }

  var displayName: String {
    if let name, !name.isEmpty { return name }
    return isImage ? "图片" : (isAudio ? "语音消息" : "文件附件")
  }

  var formattedSize: String? {
    guard let size, size > 0 else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
  }
}

private struct NativeAgentChoiceButton: Decodable, Sendable {
  let label: String
  let callbackData: String
  let description: String?

  private enum CodingKeys: String, CodingKey {
    case label, text, description
    case callbackData = "callback_data"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    label =
      (try? c.decode(String.self, forKey: .label))
      ?? (try? c.decode(String.self, forKey: .text))
      ?? ""
    callbackData = (try? c.decode(String.self, forKey: .callbackData)) ?? ""
    description = try? c.decode(String.self, forKey: .description)
  }
}

private struct NativeAgentChoiceCard: Decodable, Sendable, Identifiable {
  let id: String
  let title: String?
  let prompt: String
  let buttons: [NativeAgentChoiceButton]
  let buttonRows: [[NativeAgentChoiceButton]]
  var selectedLabel: String?

  private enum CodingKeys: String, CodingKey {
    case id, title, prompt, buttons
    case buttonRows = "button_rows"
    case selectedLabel = "selected_label"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
    title = try? c.decode(String.self, forKey: .title)
    prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
    buttons = (try? c.decode([NativeAgentChoiceButton].self, forKey: .buttons)) ?? []
    buttonRows = (try? c.decode([[NativeAgentChoiceButton]].self, forKey: .buttonRows)) ?? []
    selectedLabel = try? c.decode(String.self, forKey: .selectedLabel)
  }
}

private struct NativeAgentMessage: Identifiable {
  let id: String
  let isUser: Bool
  var content: String
  var tools: [NativeAgentToolEntry]
  var segments: [NativeAgentMessageSegment]
  var attachments: [NativeAgentAttachmentItem]
  var choices: [NativeAgentChoiceCard]
  var isProtected: Bool

  var hasVisibleContent: Bool {
    !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !tools.isEmpty
      || !attachments.isEmpty
      || !choices.isEmpty
      || isProtected
  }
}

private struct NativeAgentUploadedAttachment: Decodable, Sendable, Identifiable {
  var id: String { ref }
  let ref: String
  let kind: String
  let url: String
  let downloadURL: String?
  let name: String?
  let mimeType: String?
  let size: Int?
  let localPath: String?

  private enum CodingKeys: String, CodingKey {
    case ref, kind, url, name, size
    case downloadURL = "download_url"
    case mimeType = "mime_type"
    case localPath = "local_path"
  }
}

private struct NativeAgentCallbackResponse: Decodable, Sendable {
  struct Feedback: Decodable, Sendable {
    let selectedLabel: String?
    private enum CodingKeys: String, CodingKey { case selectedLabel = "selected_label" }
  }
  let message: String
  let alreadySelected: Bool
  let displayMessage: String
  let choiceSelection: JSONValue?
  let feedback: Feedback?

  private enum CodingKeys: String, CodingKey {
    case message, feedback
    case alreadySelected = "already_selected"
    case displayMessage = "display_message"
    case choiceSelection = "choice_selection"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    message = (try? c.decode(String.self, forKey: .message)) ?? ""
    alreadySelected = (try? c.decode(Bool.self, forKey: .alreadySelected)) ?? false
    displayMessage = (try? c.decode(String.self, forKey: .displayMessage)) ?? ""
    choiceSelection = try? c.decode(JSONValue.self, forKey: .choiceSelection)
    feedback = try? c.decode(Feedback.self, forKey: .feedback)
  }
}

private struct NativeAgentCommandItem: Decodable, Sendable, Identifiable {
  let command: String
  let description: String

  var id: String { command }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    command = (try? c.decode(String.self, forKey: .command)) ?? ""
    description = (try? c.decode(String.self, forKey: .description)) ?? ""
  }

  private enum CodingKeys: String, CodingKey { case command, description }
}

private struct NativeAgentSessionSummary: Decodable, Sendable, Identifiable {
  let sessionID: String
  let title: String?
  let preview: String?
  let messageCount: Int

  var id: String { sessionID }
  var displayTitle: String {
    if let title, !title.isEmpty { return title }
    if let preview, !preview.isEmpty { return preview }
    return "对话 \(sessionID.prefix(8))"
  }

  private enum CodingKeys: String, CodingKey {
    case title, preview
    case sessionID = "session_id"
    case messageCount = "message_count"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sessionID = (try? c.decode(String.self, forKey: .sessionID)) ?? UUID().uuidString
    title = try? c.decode(String.self, forKey: .title)
    preview = try? c.decode(String.self, forKey: .preview)
    messageCount = (try? c.decode(Int.self, forKey: .messageCount)) ?? 0
  }
}

private struct NativeAgentSessionDetailRaw: Decodable, Sendable {
  struct RawTool: Decodable, Sendable {
    let id: String?
    let toolName: String?
    let message: String?
    let structured: Bool?
    let status: String?
    private enum CodingKeys: String, CodingKey {
      case id, message, text, status, structured
      case toolID = "tool_id"
      case toolCallID = "tool_call_id"
      case toolName = "tool_name"
      case toolNameCamel = "toolName"
    }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      id =
        (try? c.decodeIfPresent(String.self, forKey: .id))
        ?? (try? c.decodeIfPresent(String.self, forKey: .toolID))
        ?? (try? c.decodeIfPresent(String.self, forKey: .toolCallID))
      toolName =
        (try? c.decodeIfPresent(String.self, forKey: .toolName))
        ?? (try? c.decodeIfPresent(String.self, forKey: .toolNameCamel))
      message =
        (try? c.decodeIfPresent(String.self, forKey: .message))
        ?? (try? c.decodeIfPresent(String.self, forKey: .text))
      structured = try? c.decodeIfPresent(Bool.self, forKey: .structured)
      status = try? c.decodeIfPresent(String.self, forKey: .status)
    }
  }
  struct RawAttachment: Decodable, Sendable {
    let kind: String?
    let url: String?
    let downloadURL: String?
    let name: String?
    let mimeType: String?
    let size: Int?
    private enum CodingKeys: String, CodingKey {
      case kind, url, name, size
      case downloadURL = "download_url"
      case mimeType = "mime_type"
    }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      kind = try? c.decodeIfPresent(String.self, forKey: .kind)
      url = try? c.decodeIfPresent(String.self, forKey: .url)
      downloadURL = try? c.decodeIfPresent(String.self, forKey: .downloadURL)
      name = try? c.decodeIfPresent(String.self, forKey: .name)
      mimeType = try? c.decodeIfPresent(String.self, forKey: .mimeType)
      size = try? c.decodeIfPresent(Int.self, forKey: .size)
    }
  }
  struct RawSegment: Decodable, Sendable {
    let type: String?
    let content: String?
    let toolIndex: Int?
    private enum CodingKeys: String, CodingKey {
      case type, content, toolIndex
      case toolIndexSnake = "tool_index"
    }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      type = try? c.decodeIfPresent(String.self, forKey: .type)
      content = try? c.decodeIfPresent(String.self, forKey: .content)
      toolIndex =
        (try? c.decodeIfPresent(Int.self, forKey: .toolIndex))
        ?? (try? c.decodeIfPresent(Int.self, forKey: .toolIndexSnake))
    }
  }
  struct RawMessage: Decodable, Sendable {
    let id: String?
    let role: String?
    let content: String?
    let tools: [RawTool]
    let segments: [RawSegment]
    let attachments: [RawAttachment]
    let choices: [NativeAgentChoiceCard]

    private enum CodingKeys: String, CodingKey {
      case id, role, content, tools, segments, attachments, choices
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      id = try? c.decodeIfPresent(String.self, forKey: .id)
      role = try? c.decodeIfPresent(String.self, forKey: .role)
      content = try? c.decodeIfPresent(String.self, forKey: .content)
      tools = (try? c.decodeIfPresent([RawTool].self, forKey: .tools)) ?? []
      segments = (try? c.decodeIfPresent([RawSegment].self, forKey: .segments)) ?? []
      attachments = (try? c.decodeIfPresent([RawAttachment].self, forKey: .attachments)) ?? []
      choices = (try? c.decodeIfPresent([NativeAgentChoiceCard].self, forKey: .choices)) ?? []
    }

    func toDisplayMessage() -> NativeAgentMessage {
      let normalizedTools: [NativeAgentToolEntry] = tools.enumerated().compactMap { index, t in
        let rawMsg = NativeAgentChatPage.normalizeToolMessage(t.message ?? t.toolName ?? "")
        guard !rawMsg.isEmpty else { return nil }
        let rawStatus = (t.status ?? "").lowercased()
        let status = rawStatus == "error" ? "error" : (rawStatus == "running" ? "running" : "done")
        return NativeAgentToolEntry(
          id: t.id ?? "tool-\(index)",
          toolName: t.toolName,
          message: rawMsg,
          structured: t.structured == true || (t.toolName?.isEmpty == false),
          status: status)
      }
      let primaryContent = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let resolvedContent: String
      if !primaryContent.isEmpty {
        resolvedContent = content ?? ""
      } else {
        resolvedContent =
          segments
          .filter { ($0.type ?? "").lowercased() == "text" }
          .compactMap(\.content)
          .joined()
      }
      var resolvedSegments: [NativeAgentMessageSegment] = []
      for seg in segments {
        let kind = (seg.type ?? "").lowercased()
        if kind == "text", let text = seg.content,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          resolvedSegments.append(.text(text))
        } else if kind == "tool", let idx = seg.toolIndex, idx >= 0, idx < normalizedTools.count {
          resolvedSegments.append(.tool(idx))
        }
      }
      if resolvedSegments.isEmpty {
        for idx in normalizedTools.indices {
          resolvedSegments.append(.tool(idx))
        }
        if !resolvedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          resolvedSegments.append(.text(resolvedContent))
        }
      }
      return NativeAgentMessage(
        id: id ?? UUID().uuidString,
        isUser: (role ?? "").lowercased() == "user",
        content: resolvedContent,
        tools: normalizedTools,
        segments: resolvedSegments,
        attachments: attachments.compactMap { a in
          guard let url = a.url, !url.isEmpty else { return nil }
          return NativeAgentAttachmentItem(
            kind: a.kind ?? "file", url: url, downloadURL: a.downloadURL, name: a.name,
            mimeType: a.mimeType, size: a.size)
        },
        choices: choices,
        isProtected: false
      )
    }
  }

  let sessionID: String?
  let messages: [RawMessage]
  let isProcessing: Bool

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case messages
    case isProcessing = "is_processing"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sessionID = try? c.decodeIfPresent(String.self, forKey: .sessionID)
    messages = (try? c.decodeIfPresent([RawMessage].self, forKey: .messages)) ?? []
    isProcessing = (try? c.decodeIfPresent(Bool.self, forKey: .isProcessing)) ?? false
  }
}

extension APIError {
  fileprivate var userVisibleDescription: String {
    switch self {
    case .notFound: "服务端未启用智能助手接口，请检查 MoviePilot 版本与配置。"
    case .forbidden: "当前账号无权访问智能助手。"
    case .unauthorized: "登录会话已过期，请重新登录。"
    case .timedOut: "智能助手响应超时，请稍后重试。"
    case .rateLimited: "请求过于频繁，请稍后再试。"
    default: "智能助手服务暂不可用，请检查大模型配置或网络连接。"
    }
  }
}
