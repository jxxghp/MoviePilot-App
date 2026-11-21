import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生工作流清单、社区分享复用与执行控制页：查看自动化工作流状态与调度，支持进入原生节点画布、手动运行、启用/停用、重置确认及社区复用。
@MainActor
struct NativeWorkflowsPage: View {
  /// 顶部模式切换。
  enum Mode: String, CaseIterable, Identifiable {
    case mine = "我的工作流"
    case shares = "社区分享"

    /// 稳定标识。
    var id: String { rawValue }
  }

  let session: NativeSession

  @State private var mode: Mode = .mine
  @State private var workflows: [NativeWorkflowItem] = []
  @State private var shares: [NativeWorkflowShareItem] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var mutatingID: Int?
  @State private var pendingReset: NativeWorkflowItem?
  @State private var pendingFork: NativeWorkflowShareItem?
  @State private var feedback: NativeWorkflowFeedback?

  /// 统一深色紫玫瑰渐变背景、透色工作流卡片与原生工具栏刷新。
  var body: some View {
    mainContent
      .navigationTitle("工作流")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button {
              mode = mode == .mine ? .shares : .mine
            } label: {
              Label(
                mode == .mine ? "浏览社区分享" : "返回我的工作流",
                systemImage: mode == .mine ? "square.stack.3d.up" : "flowchart")
            }
            Button {
              attempt += 1
            } label: {
              Label("刷新工作流", systemImage: "arrow.clockwise")
            }
          } label: {
            Image(systemName: "ellipsis")
          }
          .accessibilityLabel("更多工作流操作")
          .accessibilityIdentifier("native-workflows-refresh")
        }
      }
      .task(id: "\(mode.rawValue)|\(attempt)") { await load() }
      .alert(
        "重置工作流",
        isPresented: Binding(
          get: { pendingReset != nil },
          set: { if !$0 { pendingReset = nil } }
        ),
        presenting: pendingReset
      ) { workflow in
        Button("确认重置", role: .destructive) {
          Task { await performAction(workflow, action: "reset", label: "已重置工作流状态。") }
        }
        Button("取消", role: .cancel) {}
      } message: { workflow in
        Text("确认重置「\(workflow.name)」的执行状态与上下文吗？")
      }
      .alert(
        "复用工作流",
        isPresented: Binding(
          get: { pendingFork != nil },
          set: { if !$0 { pendingFork = nil } }
        ),
        presenting: pendingFork
      ) { share in
        Button("确认复用") {
          Task { await forkShare(share) }
        }
        Button("取消", role: .cancel) {}
      } message: { share in
        Text("确认将社区分享「\(share.displayTitle)」复制到本地工作流吗？")
      }
  }

  /// 主滚动区与模式切换条。
  private var mainContent: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          modeBar
          if let feedback {
            feedbackBanner(feedback)
          }
          listSection
        }
        .frame(maxWidth: 840)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-workflows-scroll")
    }
  }

  /// 顶部模式切换胶囊。
  private var modeBar: some View {
    HStack(spacing: 8) {
      ForEach(Mode.allCases) { option in
        let active = mode == option
        Button {
          mode = option
        } label: {
          Text(option.rawValue)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? .white : .white.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
              Capsule()
                .fill(
                  active
                    ? Color(red: 0.58, green: 0.42, blue: 0.88).opacity(0.78)
                    : .white.opacity(0.08)
                )
                .overlay {
                  Capsule().strokeBorder(.white.opacity(active ? 0.32 : 0.14), lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-workflow-mode-\(option.rawValue)")
      }
      Spacer(minLength: 0)
    }
  }

  /// 按当前模式渲染本地工作流或社区分享列表。
  @ViewBuilder
  private var listSection: some View {
    if mode == .mine {
      if isLoading && workflows.isEmpty {
        ProgressView("正在载入工作流…")
          .tint(.white)
          .frame(maxWidth: .infinity, minHeight: 220)
      } else if loadFailed && workflows.isEmpty {
        failureCard
      } else if workflows.isEmpty {
        emptyCard
      } else {
        LazyVStack(spacing: 12) {
          ForEach(workflows) { workflow in
            workflowCard(workflow)
          }
        }
      }
    } else {
      if isLoading && shares.isEmpty {
        ProgressView("正在载入社区工作流分享…")
          .tint(.white)
          .frame(maxWidth: .infinity, minHeight: 220)
      } else if loadFailed && shares.isEmpty {
        failureCard
      } else if shares.isEmpty {
        CinematicPanel {
          VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
              .font(.largeTitle)
              .foregroundStyle(.white.opacity(0.55))
            Text("暂无社区工作流分享").font(.headline)
          }
          .frame(maxWidth: .infinity, minHeight: 150)
        }
      } else {
        LazyVStack(spacing: 12) {
          ForEach(shares) { share in
            shareCard(share)
          }
        }
      }
    }
  }

  /// 单条工作流玻璃卡片：名称、状态徽标、定时计划、执行次数与运行/启停/重置动作。
  private func workflowCard(_ workflow: NativeWorkflowItem) -> some View {
    let isMutating = mutatingID == workflow.id
    return CinematicPanel(padding: 14) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            Text(workflow.name)
              .font(.headline)
              .foregroundStyle(.white)
            if let desc = workflow.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !desc.isEmpty
            {
              Text(desc)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
            }
          }
          Spacer(minLength: 4)
          stateBadge(workflow)
        }
        HStack(spacing: 12) {
          if let timer = workflow.timer, !timer.isEmpty {
            Label(timer, systemImage: "clock")
              .font(.caption.monospaced())
              .foregroundStyle(.white.opacity(0.76))
          }
          Label("已运行 \(workflow.runCount ?? 0) 次", systemImage: "bolt.horizontal")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.66))
        }
        if let result = workflow.result?.trimmingCharacters(in: .whitespacesAndNewlines),
          !result.isEmpty
        {
          Text(result)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(2)
        }
        HStack(spacing: 8) {
          NavigationLink {
            NativeWorkflowCanvasPage(
              session: session, workflowID: workflow.id, workflowTitle: workflow.name)
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "flowchart").font(.caption2.weight(.semibold))
              Text("画布").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
              Capsule()
                .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.75))
                .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.6) }
            }
            .frame(minHeight: 34)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-workflow-canvas-\(workflow.id)")

          Button {
            Task { await performRun(workflow) }
          } label: {
            HStack(spacing: 5) {
              if isMutating {
                ProgressView().controlSize(.mini).tint(.white)
              } else {
                Image(systemName: "play.fill").font(.caption2.weight(.semibold))
              }
              Text("运行").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
              Capsule()
                .fill(Color(red: 0.45, green: 0.34, blue: 0.68).opacity(0.72))
                .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.6) }
            }
            .frame(minHeight: 34)
          }
          .buttonStyle(.plain)
          .disabled(mutatingID != nil)
          .accessibilityIdentifier("native-workflow-run-\(workflow.id)")

          Button {
            let nextAction = workflow.isPaused ? "start" : "pause"
            let label = workflow.isPaused ? "已启用工作流。" : "已停用工作流。"
            Task { await performAction(workflow, action: nextAction, label: label) }
          } label: {
            Text(workflow.isPaused ? "启用" : "停用")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(.white.opacity(0.14))
                  .overlay { Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.6) }
              }
              .frame(minHeight: 34)
          }
          .buttonStyle(.plain)
          .disabled(mutatingID != nil)
          .accessibilityIdentifier("native-workflow-toggle-\(workflow.id)")

          Spacer()
        }
      }
    }
    .contextMenu {
      Button {
        Task { await performRun(workflow) }
      } label: {
        Label("立即运行", systemImage: "play.fill")
      }
      Button {
        let nextAction = workflow.isPaused ? "start" : "pause"
        let label = workflow.isPaused ? "已启用工作流。" : "已停用工作流。"
        Task { await performAction(workflow, action: nextAction, label: label) }
      } label: {
        Label(
          workflow.isPaused ? "启用工作流" : "停用工作流",
          systemImage: workflow.isPaused ? "checkmark.circle" : "pause.circle")
      }
      Button(role: .destructive) {
        pendingReset = workflow
      } label: {
        Label("重置状态", systemImage: "arrow.counterclockwise")
      }
    }
  }

  /// 单条社区工作流分享玻璃卡片。
  private func shareCard(_ share: NativeWorkflowShareItem) -> some View {
    CinematicPanel(padding: 14) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            Text(share.displayTitle)
              .font(.headline)
              .foregroundStyle(.white)
            if let comment = share.displaySummary {
              Text(comment)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(3)
            }
          }
          Spacer(minLength: 4)
          if share.count > 0 {
            Label("\(share.count)", systemImage: "arrow.triangle.branch")
              .font(.caption2.monospacedDigit().weight(.semibold))
              .foregroundStyle(Color(red: 0.84, green: 0.72, blue: 1.0))
              .padding(.horizontal, 8)
              .padding(.vertical, 3.5)
              .background {
                Capsule().fill(.white.opacity(0.10))
              }
          }
        }
        HStack(spacing: 10) {
          if let user = share.shareUser, !user.isEmpty {
            Label(user, systemImage: "person.circle")
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.62))
          }
          if let timer = share.timer, !timer.isEmpty {
            Label(timer, systemImage: "clock")
              .font(.caption2.monospaced())
              .foregroundStyle(.white.opacity(0.62))
          }
          Spacer()
          Button {
            pendingFork = share
          } label: {
            Label("复用", systemImage: "square.and.arrow.down")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.76))
                  .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.6) }
              }
              .frame(minHeight: 34)
          }
          .buttonStyle(.plain)
          .disabled(mutatingID != nil)
          .accessibilityIdentifier("native-workflow-fork-\(share.id)")
        }
      }
    }
  }

  /// 工作流状态胶囊。
  private func stateBadge(_ workflow: NativeWorkflowItem) -> some View {
    let (text, tint): (String, Color) =
      switch (workflow.state ?? "W").uppercased() {
      case "R": ("运行中", Color(red: 0.52, green: 0.80, blue: 1.0))
      case "S": ("已完成", Color(red: 0.56, green: 0.92, blue: 0.72))
      case "F": ("失败", Color(red: 1.0, green: 0.52, blue: 0.52))
      case "P": ("已停用", Color.white.opacity(0.55))
      default: ("待触发", Color(red: 0.82, green: 0.70, blue: 1.0))
      }
    return Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 3.5)
      .background {
        Capsule()
          .fill(.white.opacity(0.10))
          .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.6) }
      }
  }

  /// 操作反馈条。
  private func feedbackBanner(_ feedback: NativeWorkflowFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : Color(red: 0.56, green: 0.92, blue: 0.72))
        Text(feedback.message).font(.subheadline).foregroundStyle(.white.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65)).frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-workflows-feedback")
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "flowchart")
          .font(.largeTitle)
          .foregroundStyle(.white.opacity(0.55))
        Text("暂无已配置的工作流").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 失败回退卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入工作流", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-workflows-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 按模式读取本地工作流或社区分享列表。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      if mode == .mine {
        let endpoint = try APIEndpoint(path: ["workflow"], trailingSlash: true)
        let loaded = try await session.request(endpoint, as: [NativeWorkflowItem].self).value
        try Task.checkCancellation()
        workflows = loaded
      } else {
        let endpoint = try APIEndpoint(
          path: ["workflow", "shares"],
          query: [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "count", value: "30"),
          ])
        let loaded = try await session.request(endpoint, as: [NativeWorkflowShareItem].self).value
        try Task.checkCancellation()
        shares = loaded
      }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 确认后单次复用社区分享工作流（`POST /api/v1/workflow/fork`）。
  private func forkShare(_ share: NativeWorkflowShareItem) async {
    mutatingID = share.id
    defer { mutatingID = nil }
    do {
      let body = try JSONEncoder().encode(share)
      let endpoint = try APIEndpoint(path: ["workflow", "fork"], method: .post, body: body)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      feedback = NativeWorkflowFeedback(
        isError: false, message: "已复用社区工作流「\(share.displayTitle)」。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeWorkflowFeedback(isError: true, message: "复用社区工作流失败，请稍后重试。")
    }
  }

  /// 单次手动触发执行工作流（`POST /api/v1/workflow/{id}/run?from_begin=true`）。
  private func performRun(_ workflow: NativeWorkflowItem) async {
    mutatingID = workflow.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["workflow", String(workflow.id), "run"],
        method: .post,
        query: [URLQueryItem(name: "from_begin", value: "true")])
      try await session.perform(endpoint)
      try Task.checkCancellation()
      feedback = NativeWorkflowFeedback(isError: false, message: "已触发工作流「\(workflow.name)」运行。")
      await load()
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeWorkflowFeedback(isError: true, message: "触发工作流失败，请稍后重试。")
    }
  }

  /// 单次执行工作流启停或重置动作。
  private func performAction(_ workflow: NativeWorkflowItem, action: String, label: String) async {
    mutatingID = workflow.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["workflow", String(workflow.id), action], method: .post)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      feedback = NativeWorkflowFeedback(isError: false, message: label)
      await load()
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeWorkflowFeedback(isError: true, message: "工作流操作失败，请稍后重试。")
    }
  }
}

/// 工作流提示载体。
private struct NativeWorkflowFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/workflow/` 单条工作流投影。
private struct NativeWorkflowItem: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let description: String?
  let timer: String?
  let state: String?
  let runCount: Int?
  let result: String?

  /// `P` 表示当前已停用。
  var isPaused: Bool { (state ?? "").uppercased() == "P" }

  /// 对应 `_SchemaWorkflow` 字段。
  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case description
    case timer
    case state
    case runCount = "run_count"
    case result
  }
}

/// `GET /api/v1/workflow/shares` 社区分享工作流模型。
private struct NativeWorkflowShareItem: Codable, Sendable, Identifiable {
  let id: Int
  let shareTitle: String?
  let shareComment: String?
  let shareUser: String?
  let name: String?
  let description: String?
  let timer: String?
  let triggerType: String?
  let eventType: String?
  let eventConditions: String?
  let actions: String?
  let flows: String?
  let count: Int

  var displayTitle: String {
    if let shareTitle, !shareTitle.isEmpty { return shareTitle }
    if let name, !name.isEmpty { return name }
    return "工作流 #\(id)"
  }

  var displaySummary: String? {
    let raw = (shareComment?.isEmpty == false ? shareComment : description)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return raw?.isEmpty == false ? raw : nil
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
    shareTitle = try? c.decodeIfPresent(String.self, forKey: .shareTitle)
    shareComment = try? c.decodeIfPresent(String.self, forKey: .shareComment)
    shareUser = try? c.decodeIfPresent(String.self, forKey: .shareUser)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    timer = try? c.decodeIfPresent(String.self, forKey: .timer)
    triggerType = try? c.decodeIfPresent(String.self, forKey: .triggerType)
    eventType = try? c.decodeIfPresent(String.self, forKey: .eventType)
    eventConditions = try? c.decodeIfPresent(String.self, forKey: .eventConditions)
    actions = try? c.decodeIfPresent(String.self, forKey: .actions)
    flows = try? c.decodeIfPresent(String.self, forKey: .flows)
    count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, timer, actions, flows, count
    case shareTitle = "share_title"
    case shareComment = "share_comment"
    case shareUser = "share_user"
    case triggerType = "trigger_type"
    case eventType = "event_type"
    case eventConditions = "event_conditions"
  }
}
