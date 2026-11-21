import AVFoundation
import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 原生 AI Agent 对话页（八.1 全量对标 Web）：修复 `/api/v1/message/agent/*` 路由，支持真流式 SSE、工具调用进度、思考计时、Markdown/代码块渲染、交互选择卡、敏感保护交付、图片/文件上传与下载及原生语音录制与播放。
@MainActor
struct NativeAgentChatPage: View {
  let session: NativeSession

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @StateObject private var audioBridge = NativeAgentAudioController()
  @State private var activeSessionID = "ios-\(UUID().uuidString.prefix(12).lowercased())"
  @State private var messages: [NativeAgentMessage] = []
  @State private var sessions: [NativeAgentSessionSummary] = []
  @State private var commands: [NativeAgentCommandItem] = []
  @State private var draftText = ""
  @State private var pendingUploads: [NativeAgentUploadedAttachment] = []
  @State private var isUploadingAttachment = false
  @State private var isSending = false
  @State private var thinkingStartedAt: Date?
  @State private var thinkingSeconds: Int = 0
  @State private var sendTask: Task<Void, Never>?
  @State private var showsSessionsSheet = false
  @State private var isLoadingSessions = false
  @State private var feedback: NativeAgentFeedback?
  @State private var pendingDeleteSession: NativeAgentSessionSummary?

  // 多模态输入与附件预览
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var showsPhotoPicker = false
  @State private var showsFileImporter = false
  @State private var previewImageItem: NativeAgentImagePreviewItem?
  @State private var shareFileItem: NativeAgentShareFileItem?
  @State private var downloadingAttachmentURL: String?

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
                  ProgressView().controlSize(.small).tint(appearance.accentColor)
                  Text(
                    thinkingSeconds > 0
                      ? "智能助手思考与执行中 (\(thinkingSeconds)s)…" : "智能助手正在思考与执行…"
                  )
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
      await loadBootstrap()
    }
    .task(id: isSending) {
      guard isSending else {
        thinkingStartedAt = nil
        thinkingSeconds = 0
        return
      }
      let start = thinkingStartedAt ?? Date()
      thinkingStartedAt = start
      while !Task.isCancelled && isSending {
        thinkingSeconds = max(0, Int(Date().timeIntervalSince(start)))
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    .onDisappear {
      sendTask?.cancel()
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
                  feedback = NativeAgentFeedback(isError: false, message: "已复制受保护内容。")
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

            if !message.tools.isEmpty {
              VStack(alignment: .leading, spacing: 5) {
                ForEach(message.tools) { tool in
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
                      .lineLimit(2)
                  }
                  .padding(.horizontal, 9).padding(.vertical, 5)
                  .background(
                    NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
              }
            }

            if !message.content.isEmpty {
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
              ProgressView("正在读取历史会话…").tint(.primary)
                .frame(maxWidth: .infinity, minHeight: 160)
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
    .nativeAppearanceRoot()
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
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary).frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-agent-feedback")
  }

  // MARK: - 网络与多模态流式逻辑（全部修复为 `/api/v1/message/agent/*`）

  private func loadBootstrap() async {
    async let cmds: () = loadCommands()
    async let sess: () = loadSessions()
    _ = await (cmds, sess)
  }

  private func loadCommands() async {
    do {
      let endpoint = try APIEndpoint(path: ["message", "agent", "commands"])
      commands = try await session.request(endpoint, as: [NativeAgentCommandItem].self).value
    } catch {
      return
    }
  }

  private func loadSessions() async {
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

  private func openSession(_ sessionID: String) async {
    do {
      let endpoint = try APIEndpoint(path: ["message", "agent", "sessions", sessionID])
      let detail = try await session.request(endpoint, as: NativeAgentSessionDetailRaw.self).value
      activeSessionID = detail.sessionID
      messages = detail.messages.map { $0.toDisplayMessage() }
      feedback = nil
    } catch {
      feedback = NativeAgentFeedback(isError: true, message: "读取会话记录失败。")
    }
  }

  private func deleteSession(_ item: NativeAgentSessionSummary) async {
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

  private func startNewSession() {
    sendTask?.cancel()
    isSending = false
    activeSessionID = "ios-\(UUID().uuidString.prefix(12).lowercased())"
    messages = []
    pendingUploads = []
    draftText = ""
    feedback = nil
  }

  private func stopCurrentTask() async {
    sendTask?.cancel()
    isSending = false
    do {
      let body = try JSONEncoder().encode(["session_id": activeSessionID])
      let endpoint = try APIEndpoint(path: ["message", "agent", "stop"], method: .post, body: body)
      try await session.perform(endpoint)
      feedback = NativeAgentFeedback(isError: false, message: "已停止当前助手任务。")
    } catch {
      return
    }
  }

  /// 发起真流式 SSE 对话（支持图片、语音、文件附件及运行中实时追问 steering）。
  private func sendMessage(
    _ rawText: String,
    displayText: String? = nil,
    choiceSelection: JSONValue? = nil,
    originalMessageID: String? = nil
  ) {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    let uploads = pendingUploads
    guard !text.isEmpty || !uploads.isEmpty else { return }

    let isSteeringFollowUp = isSending
    draftText = ""
    pendingUploads = []
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
        attachments: userAttachments,
        choices: [],
        isProtected: false
      ))

    var payload: [String: JSONValue] = [
      "text": .string(text),
      "session_id": .string(activeSessionID),
    ]
    if let displayText, !displayText.isEmpty {
      payload["display_text"] = .string(displayText)
    }
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

    // 如果当前正在运行，发起并发 steering 请求而不打断主 SSE 流
    if isSteeringFollowUp {
      Task {
        await sendSteeringRequest(payload: payload)
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
        attachments: [],
        choices: [],
        isProtected: false
      ))
    isSending = true
    thinkingStartedAt = Date()

    sendTask?.cancel()
    sendTask = Task {
      await consumeAgentStream(payload: payload, assistantID: assistantID)
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
    defer { isSending = false }
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
        let msg = messages[idx]
        if msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && msg.attachments.isEmpty && msg.choices.isEmpty
        {
          messages[idx].content = "已完成处理。"
        }
      }
      await loadSessions()
    } catch is CancellationError {
      return
    } catch let apiError as APIError {
      handleStreamError(apiError.userVisibleDescription, assistantID: assistantID)
    } catch {
      handleStreamError("智能助手连接中断，请检查服务状态或大模型配置。", assistantID: assistantID)
    }
  }

  private func handleStreamError(_ text: String, assistantID: String) {
    if let idx = messages.firstIndex(where: { $0.id == assistantID }),
      messages[idx].content.isEmpty && messages[idx].tools.isEmpty
    {
      messages.remove(at: idx)
    }
    feedback = NativeAgentFeedback(isError: true, message: text)
  }

  /// 完整处理后端全部 10+ 种 SSE 事件（start/thinking/tool/delta/message_update/attachment/choice/steering/interaction-protected/error/done）。
  private func applySSEEvent(_ sse: APISSEEvent, assistantID: String) {
    guard let idx = messages.firstIndex(where: { $0.id == assistantID }) else { return }
    let obj = (try? JSONSerialization.jsonObject(with: Data(sse.data.utf8))) as? [String: Any]
    let eventName = (obj?["type"] as? String ?? sse.event).lowercased()

    switch eventName {
    case "start":
      if let sid = obj?["session_id"] as? String, !sid.isEmpty {
        activeSessionID = sid
      }
    case "thinking":
      if let msg = obj?["message"] as? String, !msg.isEmpty {
        let toolID = "thinking"
        if let ti = messages[idx].tools.firstIndex(where: { $0.id == toolID }) {
          messages[idx].tools[ti].message = msg
        } else {
          messages[idx].tools.append(
            NativeAgentToolEntry(id: toolID, toolName: "思考", message: msg, status: "running"))
        }
      }
    case "tool":
      let tid = (obj?["id"] as? String) ?? (obj?["tool_name"] as? String) ?? UUID().uuidString
      let toolName = obj?["tool_name"] as? String
      let msg = (obj?["message"] as? String) ?? toolName ?? "调用工具"
      let status = (obj?["status"] as? String) ?? "done"
      if let ti = messages[idx].tools.firstIndex(where: { $0.id == tid }) {
        messages[idx].tools[ti].message = msg
        messages[idx].tools[ti].status = status
      } else {
        messages[idx].tools.append(
          NativeAgentToolEntry(id: tid, toolName: toolName, message: msg, status: status))
      }
    case "delta":
      // 收到正文增量时把正在思考的占位标记置为完成
      for ti in messages[idx].tools.indices where messages[idx].tools[ti].status == "running" {
        messages[idx].tools[ti].status = "done"
      }
      if let delta = (obj?["content"] as? String) ?? (obj?["delta"] as? String)
        ?? (obj?["text"] as? String)
      {
        messages[idx].content += delta
      }
    case "message_update":
      if let full = (obj?["content"] as? String) ?? (obj?["message"] as? String) {
        messages[idx].content = full
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
        if !messages[idx].content.isEmpty { messages[idx].content += "\n\n" }
        messages[idx].content += secret
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
        messages[idx].tools[ti].status = "done"
      }
      if let finalMsg = (obj?["message"] as? String) ?? (obj?["content"] as? String),
        !finalMsg.isEmpty, messages[idx].content.isEmpty
      {
        messages[idx].content = finalMsg
      }
    default:
      if let content = obj?["content"] as? String, !content.isEmpty {
        messages[idx].content += content
      }
    }
  }

  /// 点击交互选择卡片按钮 -> `POST /api/v1/message/agent/callback` -> 自动续发对话流。
  private func triggerChoiceCallback(
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
          displayText: display,
          choiceSelection: res.choiceSelection,
          originalMessageID: messageID)
      }
    } catch {
      feedback = NativeAgentFeedback(isError: true, message: "提交选择项失败，请稍后重试。")
    }
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
      feedback = NativeAgentFeedback(isError: true, message: "读取相册图片失败。")
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
      feedback = NativeAgentFeedback(isError: true, message: "读取本地文件失败。")
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
        feedback = NativeAgentFeedback(isError: true, message: "无法启动麦克风录音，请在系统设置中授权麦克风权限。")
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
      feedback = NativeAgentFeedback(isError: true, message: "上传附件「\(fileName)」失败。")
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
      feedback = NativeAgentFeedback(isError: true, message: "加载语音附件失败。")
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
      feedback = NativeAgentFeedback(isError: true, message: "下载附件失败。")
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

  private enum Block: Identifiable {
    case text(id: Int, content: String)
    case code(id: Int, language: String, content: String)
    var id: Int {
      switch self {
      case .text(let i, _): i
      case .code(let i, _, _): i
      }
    }
  }

  private var blocks: [Block] {
    var result: [Block] = []
    var currentText: [String] = []
    var currentCode: [String] = []
    var inCode = false
    var codeLang = ""
    var nextID = 0

    func flushText() {
      let joined = currentText.joined(separator: "\n").trimmingCharacters(
        in: .whitespacesAndNewlines)
      if !joined.isEmpty {
        result.append(.text(id: nextID, content: joined))
        nextID += 1
      }
      currentText.removeAll()
    }

    for line in markdown.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        if inCode {
          result.append(
            .code(id: nextID, language: codeLang, content: currentCode.joined(separator: "\n")))
          nextID += 1
          currentCode.removeAll()
          codeLang = ""
          inCode = false
        } else {
          flushText()
          codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
          inCode = true
        }
      } else if inCode {
        currentCode.append(line)
      } else {
        currentText.append(line)
      }
    }
    if inCode {
      result.append(
        .code(id: nextID, language: codeLang, content: currentCode.joined(separator: "\n")))
    } else {
      flushText()
    }
    return result
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(blocks) { block in
        switch block {
        case .text(_, let raw):
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(raw.components(separatedBy: .newlines).enumerated()), id: \.offset) {
              _, line in
              markdownLineView(line)
            }
          }
        case .code(_, let lang, let code):
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
        }
      }
    }
  }

  @ViewBuilder
  private func markdownLineView(_ raw: String) -> some View {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty {
      Spacer().frame(height: 3)
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
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(saved ? "已保存" : "保存相册") {
            UIImageWriteToSavedPhotosAlbum(item.image, nil, nil, nil)
            saved = true
          }
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
  var status: String

  var displayText: String {
    if let toolName, !toolName.isEmpty, !message.contains(toolName) {
      return "\(toolName) · \(message)"
    }
    return message
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
    case label, description
    case callbackData = "callback_data"
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
  var attachments: [NativeAgentAttachmentItem]
  var choices: [NativeAgentChoiceCard]
  var isProtected: Bool
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
    let status: String?
    private enum CodingKeys: String, CodingKey {
      case id, message, status
      case toolName = "tool_name"
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
  }
  struct RawMessage: Decodable, Sendable {
    let id: String?
    let role: String?
    let content: String?
    let tools: [RawTool]?
    let attachments: [RawAttachment]?
    let choices: [NativeAgentChoiceCard]?

    func toDisplayMessage() -> NativeAgentMessage {
      NativeAgentMessage(
        id: id ?? UUID().uuidString,
        isUser: (role ?? "").lowercased() == "user",
        content: content ?? "",
        tools: (tools ?? []).compactMap { t in
          guard let msg = t.message, !msg.isEmpty else { return nil }
          return NativeAgentToolEntry(
            id: t.id ?? UUID().uuidString, toolName: t.toolName, message: msg,
            status: t.status ?? "done")
        },
        attachments: (attachments ?? []).compactMap { a in
          guard let url = a.url, !url.isEmpty else { return nil }
          return NativeAgentAttachmentItem(
            kind: a.kind ?? "file", url: url, downloadURL: a.downloadURL, name: a.name,
            mimeType: a.mimeType, size: a.size)
        },
        choices: choices ?? [],
        isProtected: false
      )
    }
  }

  let sessionID: String
  let messages: [RawMessage]

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case messages
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
