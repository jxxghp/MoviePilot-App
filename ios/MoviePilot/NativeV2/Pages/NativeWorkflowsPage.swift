import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生工作流管理页（十.6）：默认直接显示我的工作流、去除页内过滤栏；右上角提供新增工作流与社区分享入口；长按支持编辑、删除、从头/继续运行、启停、分享与重置。
@MainActor
struct NativeWorkflowsPage: View {
  let session: NativeSession

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var workflows: [NativeWorkflowItem] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var mutatingID: Int?
  @State private var showsCreateSheet = false
  @State private var editingWorkflow: NativeWorkflowItem?
  @State private var canvasWorkflow: NativeWorkflowItem?
  @State private var pendingReset: NativeWorkflowItem?
  @State private var pendingDelete: NativeWorkflowItem?
  @State private var feedback: NativeWorkflowFeedback?
  @State private var containerWidth: CGFloat = 0
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && workflows.isEmpty {
            NativeCardListSkeletonView(count: 4, style: .workflowCard)
              .transition(.opacity)
          } else if loadFailed && workflows.isEmpty {
            failureCard
          } else if workflows.isEmpty {
            emptyCard
          } else {
            let columnCount = NativeDeviceLayout.cardGridCount(
              for: containerWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            let gridColumns = Array(
              repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columnCount)
            LazyVGrid(columns: gridColumns, spacing: 12) {
              ForEach(workflows) { workflow in
                workflowCard(workflow)
              }
            }
          }
        }
        .frame(maxWidth: containerWidth >= 740 ? 1180 : 840)
        .padding(.horizontal, NativeDeviceLayout.horizontalMargin(for: containerWidth))
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .refreshable { await load(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-workflows-scroll")
    }
    .navigationTitle("我的工作流")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        NavigationLink {
          NativeWorkflowCommunityPage(session: session) { msg in
            feedback = NativeWorkflowFeedback(isError: false, message: msg)
            NativePageDataCache.shared.remove("workflows|mine", session: session)
            attempt += 1
          }
        } label: {
          Image(systemName: "square.stack.3d.up")
        }
        .tint(.primary)
        .accessibilityLabel("社区分享")
        .accessibilityIdentifier("native-workflows-switch-mode")

        Button {
          showsCreateSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .tint(.primary)
        .accessibilityLabel("新增工作流")
        .accessibilityIdentifier("native-workflows-add")
      }
    }
    .task(id: attempt) { await load(forceRefresh: attempt > 0) }
    .navigationDestination(
      isPresented: Binding(
        get: { canvasWorkflow != nil },
        set: { if !$0 { canvasWorkflow = nil } })
    ) {
      if let target = canvasWorkflow {
        NativeWorkflowCanvasPage(
          session: session, workflowID: target.id, workflowTitle: target.name)
      }
    }
    .sheet(isPresented: $showsCreateSheet) {
      NativeWorkflowEditorSheet(session: session, existing: nil) { msg in
        feedback = NativeWorkflowFeedback(isError: false, message: msg)
        NativePageDataCache.shared.remove("workflows|mine", session: session)
        attempt += 1
      }
    }
    .sheet(item: $editingWorkflow) { target in
      NativeWorkflowEditorSheet(session: session, existing: target) { msg in
        feedback = NativeWorkflowFeedback(isError: false, message: msg)
        NativePageDataCache.shared.remove("workflows|mine", session: session)
        attempt += 1
      }
    }
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
      "删除工作流",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { workflow in
      Button("确认删除", role: .destructive) {
        Task { await deleteWorkflow(workflow) }
      }
      Button("取消", role: .cancel) {}
    } message: { workflow in
      Text("确认删除工作流「\(workflow.name)」吗？删除后无法恢复。")
    }
  }

  private func workflowCard(_ workflow: NativeWorkflowItem) -> some View {
    let isMutating = mutatingID == workflow.id
    return CinematicPanel(padding: 14) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            Text(workflow.name)
              .font(.headline)
              .foregroundStyle(.primary)
            if let desc = workflow.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !desc.isEmpty
            {
              Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          Spacer(minLength: 4)
          HStack(spacing: 6) {
            stateBadge(workflow)
            Image(systemName: "chevron.right")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary.opacity(0.6))
          }
        }
        HStack(spacing: 12) {
          if let trigger = workflow.triggerDisplayText {
            Label(trigger, systemImage: workflow.triggerSymbol)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Label("\(workflow.actionCount) 个动作", systemImage: "square.grid.2x2")
            .font(.caption)
            .foregroundStyle(.secondary)
          Label("已运行 \(workflow.runCount ?? 0) 次", systemImage: "bolt.horizontal")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let result = workflow.result?.trimmingCharacters(in: .whitespacesAndNewlines),
          !result.isEmpty
        {
          Text(result)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        HStack(spacing: 8) {
          Button {
            Task { await performRun(workflow, fromBegin: true) }
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(NativeTheme.info, in: Capsule())
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
              .foregroundStyle(NativeTheme.chipText)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(NativeTheme.chipFill)
                  .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
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
    .contentShape(RoundedRectangle(cornerRadius: CinematicStyle.radius, style: .continuous))
    .onTapGesture {
      canvasWorkflow = workflow
    }
    .accessibilityIdentifier("native-workflow-card-\(workflow.id)")
    .contextMenu {
      Button {
        canvasWorkflow = workflow
      } label: {
        Label("进入画布", systemImage: "flowchart")
      }
      Button {
        editingWorkflow = workflow
      } label: {
        Label("编辑工作流", systemImage: "pencil")
      }
      Button {
        Task { await performRun(workflow, fromBegin: true) }
      } label: {
        Label("从头运行", systemImage: "play.fill")
      }
      Button {
        Task { await performRun(workflow, fromBegin: false) }
      } label: {
        Label("继续运行", systemImage: "forward.end.fill")
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
      Button {
        Task { await shareWorkflow(workflow) }
      } label: {
        Label("分享到社区", systemImage: "square.and.arrow.up")
      }
      Divider()
      Button {
        pendingReset = workflow
      } label: {
        Label("重置状态", systemImage: "arrow.counterclockwise")
      }
      Button(role: .destructive) {
        pendingDelete = workflow
      } label: {
        Label("删除工作流", systemImage: "trash")
      }
    }
  }

  private func stateBadge(_ workflow: NativeWorkflowItem) -> some View {
    switch (workflow.state ?? "W").uppercased() {
    case "R": NativeAdaptiveBadge("运行中", tint: NativeTheme.info)
    case "S": NativeAdaptiveBadge("已完成", tint: NativeTheme.success)
    case "F": NativeAdaptiveBadge("失败", tint: NativeTheme.danger)
    case "P": NativeAdaptiveBadge("已停用")
    default: NativeAdaptiveBadge("待触发", tint: NativeTheme.brand)
    }
  }

  private func feedbackBanner(_ feedback: NativeWorkflowFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
        Text(feedback.message).font(.subheadline).foregroundStyle(.primary)
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-workflows-feedback")
  }

  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "flowchart").font(.largeTitle).foregroundStyle(.secondary)
        Text("暂无已配置的工作流，点击右上角「+」新建").font(.subheadline).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入工作流", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }.frame(minHeight: 44)
          .accessibilityIdentifier("native-workflows-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func load(forceRefresh: Bool = false) async {
    let cacheKey = "workflows|mine"
    if !forceRefresh,
      let cached: [NativeWorkflowItem] = NativePageDataCache.shared.get(cacheKey, session: session)
    {
      workflows = cached
      isLoading = false
      loadFailed = false
      return
    }
    if workflows.isEmpty { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["workflow"], trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeWorkflowItem].self, requiring: .init(category: .manage)
      ).value
      try Task.checkCancellation()
      workflows = loaded
      NativePageDataCache.shared.set(loaded, for: cacheKey, session: session)
    } catch is CancellationError {
      return
    } catch {
      if workflows.isEmpty { loadFailed = true }
    }
  }

  private func performRun(_ workflow: NativeWorkflowItem, fromBegin: Bool) async {
    mutatingID = workflow.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["workflow", String(workflow.id), "run"],
        method: .post,
        query: [URLQueryItem(name: "from_begin", value: fromBegin ? "true" : "false")])
      try await session.perform(endpoint, requiring: .init(category: .manage))
      feedback = NativeWorkflowFeedback(
        isError: false,
        message: fromBegin ? "已触发从头运行「\(workflow.name)」。" : "已触发继续运行「\(workflow.name)」。")
      await load(forceRefresh: true)
    } catch {
      feedback = NativeWorkflowFeedback(isError: true, message: "触发运行失败，请稍后重试。")
    }
  }

  private func performAction(
    _ workflow: NativeWorkflowItem, action: String, label: String
  ) async {
    mutatingID = workflow.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["workflow", String(workflow.id), action], method: .post)
      try await session.perform(endpoint, requiring: .init(category: .manage))
      feedback = NativeWorkflowFeedback(isError: false, message: label)
      await load(forceRefresh: true)
    } catch {
      feedback = NativeWorkflowFeedback(isError: true, message: "更新工作流状态失败。")
    }
  }

  private func deleteWorkflow(_ workflow: NativeWorkflowItem) async {
    mutatingID = workflow.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(path: ["workflow", String(workflow.id)], method: .delete)
      try await session.perform(endpoint, requiring: .init(category: .manage))
      workflows.removeAll { $0.id == workflow.id }
      NativePageDataCache.shared.remove("workflows|mine", session: session)
      feedback = NativeWorkflowFeedback(isError: false, message: "已删除工作流「\(workflow.name)」。")
    } catch {
      feedback = NativeWorkflowFeedback(isError: true, message: "删除工作流失败。")
    }
  }

  private func shareWorkflow(_ workflow: NativeWorkflowItem) async {
    mutatingID = workflow.id
    defer { mutatingID = nil }
    do {
      let payload: [String: JSONValue] = [
        "workflow_id": .number(Double(workflow.id)),
        "share_title": .string(workflow.name),
        "share_comment": .string(workflow.description ?? ""),
      ]
      let body = try JSONEncoder().encode(payload)
      let ep = try APIEndpoint(path: ["workflow", "share"], method: .post, body: body)
      try await session.perform(ep, requiring: .init(category: .manage))
      feedback = NativeWorkflowFeedback(isError: false, message: "已分享工作流「\(workflow.name)」到社区。")
    } catch {
      feedback = NativeWorkflowFeedback(isError: true, message: "分享工作流失败，请稍后重试。")
    }
  }
}

// MARK: - 工作流新增 / 编辑弹窗（保留已有 actions/flows）

@MainActor
private struct NativeWorkflowEditorSheet: View {
  let session: NativeSession
  let existing: NativeWorkflowItem?
  let onSaved: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var name = ""
  @State private var description = ""
  @State private var triggerType = "timer"
  @State private var timer = "0 */6 * * *"
  @State private var eventType = ""
  @State private var isSubmitting = false
  @State private var errorMsg: String?

  private var isCreate: Bool { existing == nil }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if let errorMsg {
              CinematicPanel(padding: 11) {
                Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                  .font(.caption).foregroundStyle(NativeTheme.danger)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("工作流名称", placeholder: "必填", text: $name)
                CinematicFormDivider()
                rowField("描述说明", placeholder: "可选", text: $description)
                CinematicFormDivider()
                HStack {
                  Text("触发方式").font(.subheadline)
                  Spacer()
                  Picker("触发方式", selection: $triggerType) {
                    Text("定时任务").tag("timer")
                    Text("事件触发").tag("event")
                    Text("手动触发").tag("manual")
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                }
                .padding(.horizontal, 15).padding(.vertical, 10)
                if triggerType == "timer" {
                  CinematicFormDivider()
                  rowField("Cron 周期", placeholder: "0 */6 * * *", text: $timer)
                } else if triggerType == "event" {
                  CinematicFormDivider()
                  rowField("触发事件名", placeholder: "如 transfer.complete", text: $eventType)
                }
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
        }
      }
      .navigationTitle(isCreate ? "新增工作流" : "编辑工作流")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("保存") { Task { await submit() } }
            .fontWeight(.semibold)
            .tint(.primary)
            .disabled(isSubmitting || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear {
        if let existing {
          name = existing.name
          description = existing.description ?? ""
          triggerType =
            existing.triggerType ?? (existing.timer?.isEmpty == false ? "timer" : "manual")
          timer = existing.timer ?? "0 */6 * * *"
          eventType = existing.eventType ?? ""
        }
      }
    }
    .nativeGlassSheet()
  }

  private func rowField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
    HStack(spacing: 12) {
      Text(label).font(.subheadline).frame(width: 86, alignment: .leading)
      TextField(placeholder, text: text)
        .font(.subheadline).multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }

  private func submit() async {
    isSubmitting = true
    errorMsg = nil
    defer { isSubmitting = false }
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    var payload: [String: JSONValue] = [
      "name": .string(trimmedName),
      "description": .string(description.trimmingCharacters(in: .whitespacesAndNewlines)),
      "trigger_type": .string(triggerType),
    ]
    if triggerType == "timer" {
      payload["timer"] = .string(timer.trimmingCharacters(in: .whitespacesAndNewlines))
    } else if triggerType == "event" {
      payload["event_type"] = .string(eventType.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if let existing {
      payload["id"] = .number(Double(existing.id))
      if let state = existing.state { payload["state"] = .string(state) }
      if let actions = existing.actions { payload["actions"] = actions }
      if let flows = existing.flows { payload["flows"] = flows }
    }
    do {
      let body = try JSONEncoder().encode(payload)
      let ep: APIEndpoint
      if let existing {
        ep = try APIEndpoint(path: ["workflow", String(existing.id)], method: .put, body: body)
      } else {
        ep = try APIEndpoint(path: ["workflow"], method: .post, body: body, trailingSlash: true)
      }
      try await session.perform(ep, requiring: .init(category: .manage))
      onSaved(isCreate ? "已新增工作流「\(trimmedName)」。" : "已保存工作流「\(trimmedName)」。")
      dismiss()
    } catch {
      errorMsg = "保存工作流失败，请检查名称或 Cron 表达式。"
    }
  }
}

// MARK: - 社区工作流分享页（与订阅广场/插件市场统一的推入导航）

@MainActor
private struct NativeWorkflowCommunityPage: View {
  let session: NativeSession
  let onForked: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var shares: [NativeWorkflowShareItem] = []
  @State private var isLoading = true
  @State private var pendingFork: NativeWorkflowShareItem?

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if isLoading && shares.isEmpty {
            NativeCardListSkeletonView(count: 4, style: .workflowCard)
              .transition(.opacity)
          } else if shares.isEmpty {
            CinematicPanel {
              Text("暂无社区工作流分享").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
            }
          } else {
            ForEach(shares) { share in
              Button {
                pendingFork = share
              } label: {
                CinematicPanel(padding: 14) {
                  VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 8) {
                      VStack(alignment: .leading, spacing: 4) {
                        Text(share.displayTitle)
                          .font(.headline)
                          .foregroundStyle(.primary)
                          .multilineTextAlignment(.leading)
                        if let comment = share.displaySummary {
                          Text(comment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        }
                      }
                      Spacer(minLength: 6)
                      if share.count > 0 {
                        NativeAdaptiveBadge("\(share.count) 复用", tint: NativeTheme.brand)
                      }
                    }

                    HStack(spacing: 12) {
                      if let trigger = share.triggerDisplayText {
                        Label(trigger, systemImage: share.triggerSymbol)
                          .font(.caption.monospaced())
                          .foregroundStyle(.secondary)
                          .lineLimit(1)
                      }
                      if share.actionCount > 0 {
                        Label("\(share.actionCount) 个动作", systemImage: "square.grid.2x2")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }

                    HStack(spacing: 10) {
                      if let user = share.shareUser, !user.isEmpty {
                        Label(user, systemImage: "person.circle")
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                      }
                      Spacer()
                      if let date = share.date, !date.isEmpty {
                        Text(date)
                          .font(.caption2.monospacedDigit())
                          .foregroundStyle(.secondary)
                      }
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-workflow-share-\(share.id)")
            }
          }
        }
        .frame(maxWidth: 840, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await loadShares() }
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("社区分享")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .alert(
      "复用工作流",
      isPresented: Binding(
        get: { pendingFork != nil }, set: { if !$0 { pendingFork = nil } }),
      presenting: pendingFork
    ) { share in
      Button("确认复用") { Task { await forkShare(share) } }
      Button("取消", role: .cancel) {}
    } message: { share in
      Text("确认将「\(share.displayTitle)」复制到我的工作流吗？")
    }
    .task { await loadShares() }
  }

  private func loadShares() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let ep = try APIEndpoint(
        path: ["workflow", "shares"],
        query: [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "count", value: "30")])
      shares = try await session.request(
        ep, as: [NativeWorkflowShareItem].self, requiring: .init(category: .manage)
      ).value
    } catch {
      return
    }
  }

  private func forkShare(_ share: NativeWorkflowShareItem) async {
    do {
      let body = try JSONEncoder().encode(share)
      let ep = try APIEndpoint(path: ["workflow", "fork"], method: .post, body: body)
      try await session.perform(ep, requiring: .init(category: .manage))
      onForked("已复用社区工作流「\(share.displayTitle)」。")
      dismiss()
    } catch {
      return
    }
  }
}

// MARK: - 模型

private struct NativeWorkflowFeedback {
  let isError: Bool
  let message: String
}

private struct NativeWorkflowItem: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let description: String?
  let timer: String?
  let triggerType: String?
  let eventType: String?
  let state: String?
  let runCount: Int?
  let result: String?
  let actions: JSONValue?
  let flows: JSONValue?

  var isPaused: Bool { (state ?? "").uppercased() == "P" }

  var actionCount: Int {
    if case .array(let list) = actions { return list.count }
    return 0
  }

  var triggerSymbol: String {
    switch (triggerType ?? "").lowercased() {
    case "event": "bolt.circle"
    case "manual": "hand.tap"
    default: "clock"
    }
  }

  var triggerDisplayText: String? {
    switch (triggerType ?? "").lowercased() {
    case "event":
      if let eventType, !eventType.isEmpty { return eventType }
      return "事件触发"
    case "manual":
      return "手动触发"
    default:
      if let timer, !timer.isEmpty { return timer }
      return (triggerType ?? "").lowercased() == "timer" ? "定时任务" : nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, timer, state, result, actions, flows
    case triggerType = "trigger_type"
    case eventType = "event_type"
    case runCount = "run_count"
  }
}

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
  let date: String?
  let actions: JSONValue?
  let flows: JSONValue?
  let context: JSONValue?
  let count: Int

  var displayTitle: String {
    if let shareTitle, !shareTitle.isEmpty { return shareTitle }
    if let name, !name.isEmpty { return name }
    return "工作流分享 #\(id)"
  }

  var displaySummary: String? {
    if let shareComment, !shareComment.isEmpty { return shareComment }
    if let description, !description.isEmpty { return description }
    return nil
  }

  var actionCount: Int {
    if case .array(let list) = actions { return list.count }
    return 0
  }

  var triggerSymbol: String {
    switch (triggerType ?? "").lowercased() {
    case "event": "bolt.circle"
    case "manual": "hand.tap"
    default: "clock"
    }
  }

  var triggerDisplayText: String? {
    switch (triggerType ?? "").lowercased() {
    case "event":
      if let eventType, !eventType.isEmpty { return eventType }
      return "事件触发"
    case "manual":
      return "手动触发"
    default:
      if let timer, !timer.isEmpty { return timer }
      return (triggerType ?? "").lowercased() == "timer" ? "定时任务" : nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, timer, date, actions, flows, context, count
    case shareTitle = "share_title"
    case shareComment = "share_comment"
    case shareUser = "share_user"
    case triggerType = "trigger_type"
    case eventType = "event_type"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(Int.self, forKey: .id)) ?? 0
    shareTitle = try? c.decodeIfPresent(String.self, forKey: .shareTitle)
    shareComment = try? c.decodeIfPresent(String.self, forKey: .shareComment)
    shareUser = try? c.decodeIfPresent(String.self, forKey: .shareUser)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    timer = try? c.decodeIfPresent(String.self, forKey: .timer)
    triggerType = try? c.decodeIfPresent(String.self, forKey: .triggerType)
    eventType = try? c.decodeIfPresent(String.self, forKey: .eventType)
    date = try? c.decodeIfPresent(String.self, forKey: .date)
    actions = try? c.decodeIfPresent(JSONValue.self, forKey: .actions)
    flows = try? c.decodeIfPresent(JSONValue.self, forKey: .flows)
    context = try? c.decodeIfPresent(JSONValue.self, forKey: .context)
    count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
  }
}
