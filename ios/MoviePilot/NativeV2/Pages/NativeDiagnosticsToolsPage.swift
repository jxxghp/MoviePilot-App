import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生捷径与诊断工具集：涵盖系统健康检查、网络连通测试、名称识别与过滤规则测试、实时日志查看及定时服务手动触发。
@MainActor
struct NativeDiagnosticsToolsPage: View {
  /// 诊断与快捷工具分区。
  enum Tool: String, CaseIterable, Identifiable {
    case health = "系统检查"
    case nettest = "网络测试"
    case ruleTest = "识别与规则"
    case liveLog = "实时日志"
    case scheduler = "定时服务"

    /// 稳定工具标识。
    var id: String { rawValue }

    /// 对应 SF Symbol 图标。
    var symbol: String {
      switch self {
      case .health: "checkmark.shield"
      case .nettest: "network"
      case .ruleTest: "text.magnifyingglass"
      case .liveLog: "terminal"
      case .scheduler: "clock.arrow.2.circlepath"
      }
    }
  }

  /// 识别与规则测试的子模式。
  private enum TestMode: String, CaseIterable, Identifiable {
    case recognize = "名称识别"
    case rule = "规则测试"
    var id: String { rawValue }
  }

  /// 实时日志级别筛选。
  private enum LogLevel: String, CaseIterable, Identifiable {
    case all = "全部"
    case error = "ERROR"
    case warning = "WARNING"
    case info = "INFO"
    var id: String { rawValue }
  }

  let session: NativeSession
  let initialTool: Tool

  @State private var tool: Tool

  // 系统检查
  @State private var modules: [NativeHealthModuleRow] = []
  @State private var isCheckingHealth = false
  @State private var healthProgress: Double = 0

  // 网络测试
  @State private var netTargets: [NativeDiagNetTarget] = []
  @State private var netResults: [String: NativeDiagNetResult] = [:]
  @State private var testingNetID: String?
  @State private var isLoadingNet = false

  // 识别与规则测试
  @State private var testMode: TestMode = .recognize
  @State private var testTitle = ""
  @State private var testSubtitle = ""
  @State private var ruleGroups: [String] = []
  @State private var selectedRuleGroup = ""
  @State private var isRunningTest = false
  @State private var testVerdict: NativeRuleTestVerdict?

  // 实时日志
  @State private var logLines: [String] = []
  @State private var logFilter = ""
  @State private var logLevel: LogLevel = .all
  @State private var liveFollow = true
  @State private var isLoadingLog = false

  // 定时服务
  @State private var schedules: [NativeDiagSchedule] = []
  @State private var isLoadingSchedules = false
  @State private var runningJobID: String?

  @State private var feedback: String?

  /// 指定初始进入的诊断工具标签。
  init(session: NativeSession, initialTool: Tool = .health) {
    self.session = session
    self.initialTool = initialTool
    _tool = State(initialValue: initialTool)
  }

  /// 连续深色紫玫瑰渐变与当前诊断工具主内容（由设置主菜单直接进入，不展示横向一级跳转条）。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            CinematicPanel(padding: 10) {
              HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                  .foregroundStyle(Color(red: 0.78, green: 0.68, blue: 1.0))
                Text(feedback)
                  .font(.caption.weight(.medium))
                  .foregroundStyle(.primary.opacity(0.92))
                Spacer(minLength: 0)
              }
            }
            .accessibilityIdentifier("native-diag-feedback")
          }
          toolContent
        }
        .frame(maxWidth: 860)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await loadCurrentTool() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-diag-scroll")
    }
    .navigationTitle(tool.rawValue)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        trailingAction
      }
    }
    .task(id: tool) { await loadCurrentTool() }
    .task(id: "\(tool.rawValue)|\(liveFollow)") {
      guard tool == .liveLog && liveFollow else { return }
      while !Task.isCancelled && tool == .liveLog && liveFollow {
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        guard !Task.isCancelled && tool == .liveLog && liveFollow else { break }
        await fetchLiveLog(silent: true)
      }
    }
  }

  /// 右上角场景化工具按钮。
  @ViewBuilder
  private var trailingAction: some View {
    switch tool {
    case .health:
      Button {
        Task { await runHealthCheck() }
      } label: {
        Text(isCheckingHealth ? "检查中" : "重检").fontWeight(.semibold)
      }
      .disabled(isCheckingHealth)
      .accessibilityIdentifier("native-diag-health-rerun")
    case .liveLog:
      Button {
        liveFollow.toggle()
      } label: {
        Image(systemName: liveFollow ? "pause.circle" : "play.circle")
      }
      .accessibilityLabel(liveFollow ? "暂停实时跟随" : "恢复实时跟随")
    default:
      EmptyView()
    }
  }

  /// 根据当前工具展示对应的原生功能界面。
  @ViewBuilder
  private var toolContent: some View {
    switch tool {
    case .health:
      healthContent
    case .nettest:
      nettestContent
    case .ruleTest:
      ruleTestContent
    case .liveLog:
      liveLogContent
    case .scheduler:
      schedulerContent
    }
  }

  // MARK: - 1. 系统健康检查

  private var healthContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(isCheckingHealth ? "正在逐项检查系统模块…" : "系统模块健康检查")
              .font(.headline)
              .foregroundStyle(.primary)
            Spacer()
            Text("\(Int(healthProgress * 100))%")
              .font(.caption.monospacedDigit().weight(.semibold))
              .foregroundStyle(Color(red: 0.82, green: 0.72, blue: 1.0))
          }
          ProgressView(value: healthProgress)
            .tint(Color(red: 0.64, green: 0.48, blue: 0.96))
        }
      }

      if modules.isEmpty && isCheckingHealth {
        ProgressView("正在读取模块清单…")
          .tint(.primary)
          .frame(maxWidth: .infinity, minHeight: 160)
      } else {
        ForEach(modules) { mod in
          CinematicPanel(padding: 12) {
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 3) {
                Text(mod.displayName)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                if !mod.errorMessage.isEmpty {
                  Text(mod.errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                }
              }
              Spacer(minLength: 6)
              if mod.isTesting {
                ProgressView().controlSize(.mini).tint(.primary)
              } else {
                healthBadge(mod.state)
              }
            }
          }
        }
      }
    }
  }

  /// 模块健康状态徽标。
  private func healthBadge(_ state: NativeHealthState) -> some View {
    let (label, color): (String, Color) =
      switch state {
      case .pending: ("等待中", .white.opacity(0.55))
      case .ok: ("正常", Color(red: 0.48, green: 0.90, blue: 0.66))
      case .disabled: ("未启用", .white.opacity(0.50))
      case .failed: ("异常", Color(red: 1.0, green: 0.56, blue: 0.58))
      }
    return Text(label)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background {
        Capsule()
          .fill(.primary.opacity(0.08))
          .overlay { Capsule().strokeBorder(color.opacity(0.32), lineWidth: 0.6) }
      }
  }

  // MARK: - 2. 网络测试

  private var nettestContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      if isLoadingNet && netTargets.isEmpty {
        ProgressView("正在加载测试节点…")
          .tint(.primary)
          .frame(maxWidth: .infinity, minHeight: 160)
      } else if netTargets.isEmpty {
        emptyCard("暂无网络测试目标")
      } else {
        ForEach(netTargets) { target in
          let result = netResults[target.id]
          let running = testingNetID == target.id
          CinematicPanel(padding: 13) {
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(target.name)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                Text(target.address)
                  .font(.caption2.monospaced())
                  .foregroundStyle(.primary.opacity(0.58))
                  .lineLimit(1)
                if let result {
                  Text(result.summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                      result.success ? Color(red: 0.56, green: 0.92, blue: 0.72) : .orange)
                }
              }
              Spacer(minLength: 6)
              Button {
                Task { await runNetTest(target) }
              } label: {
                HStack(spacing: 5) {
                  if running {
                    ProgressView().controlSize(.mini).tint(.primary)
                  } else {
                    Image(systemName: "bolt.horizontal.fill").font(.caption2)
                  }
                  Text("测速").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { Capsule().fill(.primary.opacity(0.14)) }
              }
              .buttonStyle(.plain)
              .disabled(testingNetID != nil)
              .accessibilityIdentifier("native-diag-nettest-\(target.id)")
            }
          }
        }
      }
    }
  }

  // MARK: - 3. 名称识别与过滤规则测试

  private var ruleTestContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        ForEach(TestMode.allCases) { option in
          let active = testMode == option
          Button {
            testMode = option
            testVerdict = nil
          } label: {
            Text(option.rawValue)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(active ? .white : .white.opacity(0.72))
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background {
                Capsule().fill(
                  active
                    ? Color(red: 0.56, green: 0.40, blue: 0.88).opacity(0.80) : .white.opacity(0.08)
                )
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-diag-testmode-\(option.rawValue)")
        }
        Spacer(minLength: 0)
      }

      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("标题 / 文件名 / 种子名称")
              .font(.caption.weight(.medium))
              .foregroundStyle(.primary.opacity(0.70))
            TextField("例如：The.Matrix.1999.2160p.BluRay.x265", text: $testTitle)
              .textFieldStyle(.plain)
              .font(.subheadline)
              .foregroundStyle(.primary)
              .padding(10)
              .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
              .accessibilityIdentifier("native-diag-test-title")
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("副标题 / 种子描述（可选）")
              .font(.caption.weight(.medium))
              .foregroundStyle(.primary.opacity(0.70))
            TextField("可选补充描述或中文译名", text: $testSubtitle)
              .textFieldStyle(.plain)
              .font(.subheadline)
              .foregroundStyle(.primary)
              .padding(10)
              .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
          }

          if testMode == .rule {
            HStack {
              Text("优先级规则组")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary.opacity(0.70))
              Spacer()
              if ruleGroups.isEmpty {
                Text("未配置规则组")
                  .font(.caption)
                  .foregroundStyle(.primary.opacity(0.50))
              } else {
                Picker("规则组", selection: $selectedRuleGroup) {
                  ForEach(ruleGroups, id: \.self) { name in
                    Text(name).tag(name)
                  }
                }
                .pickerStyle(.menu)
                .tint(Color(red: 0.84, green: 0.74, blue: 1.0))
              }
            }
          }

          Button {
            Task { await executeRecognitionOrRuleTest() }
          } label: {
            HStack(spacing: 8) {
              if isRunningTest {
                ProgressView().controlSize(.small).tint(Color(red: 0.12, green: 0.10, blue: 0.16))
              }
              Text(testMode == .recognize ? "开始识别测试" : "开始过滤规则测试")
                .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.16))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(
            isRunningTest || testTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || (testMode == .rule && selectedRuleGroup.isEmpty)
          )
          .accessibilityIdentifier("native-diag-test-run")
        }
      }

      if let verdict = testVerdict {
        CinematicPanel(padding: 14) {
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
              Image(
                systemName: verdict.matched
                  ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
              )
              .foregroundStyle(
                verdict.matched ? Color(red: 0.48, green: 0.90, blue: 0.66) : .orange)
              Text(verdict.headline)
                .font(.headline)
                .foregroundStyle(.primary)
            }
            if !verdict.detail.isEmpty {
              Text(verdict.detail)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.84))
            }
            if !verdict.tags.isEmpty {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                  ForEach(verdict.tags, id: \.self) { tag in
                    Text(tag)
                      .font(.caption2.weight(.semibold))
                      .foregroundStyle(Color(red: 0.86, green: 0.76, blue: 1.0))
                      .padding(.horizontal, 8)
                      .padding(.vertical, 3)
                      .background { Capsule().fill(.primary.opacity(0.10)) }
                  }
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("native-diag-test-result")
      }
    }
  }

  // MARK: - 4. 实时日志

  private var filteredLogLines: [String] {
    let keyword = logFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return logLines.filter { line in
      switch logLevel {
      case .all: break
      case .error: guard line.localizedCaseInsensitiveContains("ERROR") else { return false }
      case .warning: guard line.localizedCaseInsensitiveContains("WARN") else { return false }
      case .info: guard line.localizedCaseInsensitiveContains("INFO") else { return false }
      }
      if !keyword.isEmpty {
        return line.lowercased().contains(keyword)
      }
      return true
    }
  }

  private var liveLogContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.58))
          TextField("过滤日志关键字", text: $logFilter)
            .textFieldStyle(.plain)
            .font(.caption)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

        Button {
          liveFollow.toggle()
        } label: {
          Label(
            liveFollow ? "跟随中" : "已暂停",
            systemImage: liveFollow ? "dot.radiowaves.left.and.right" : "pause.circle"
          )
          .font(.caption2.weight(.semibold))
          .foregroundStyle(
            liveFollow ? Color(red: 0.48, green: 0.90, blue: 0.66) : .white.opacity(0.75)
          )
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
      }

      HStack(spacing: 6) {
        ForEach(LogLevel.allCases) { level in
          let active = logLevel == level
          Button {
            logLevel = level
          } label: {
            Text(level.rawValue)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(active ? .white : .white.opacity(0.68))
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background {
                Capsule().fill(
                  active
                    ? Color(red: 0.56, green: 0.40, blue: 0.88).opacity(0.78) : .white.opacity(0.07)
                )
              }
          }
          .buttonStyle(.plain)
        }
        Spacer(minLength: 0)
        Text("\(filteredLogLines.count) 行")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.primary.opacity(0.55))
      }

      if isLoadingLog && logLines.isEmpty {
        ProgressView("正在载入实时日志…")
          .tint(.primary)
          .frame(maxWidth: .infinity, minHeight: 180)
      } else if filteredLogLines.isEmpty {
        emptyCard("暂无匹配的日志记录")
      } else {
        CinematicPanel(padding: 10) {
          LazyVStack(alignment: .leading, spacing: 5) {
            ForEach(Array(filteredLogLines.suffix(120).enumerated()), id: \.offset) { _, line in
              Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(logColor(for: line))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
          }
        }
        .accessibilityIdentifier("native-diag-log-output")
      }
    }
  }

  /// 按日志级别着色。
  private func logColor(for line: String) -> Color {
    if line.localizedCaseInsensitiveContains("ERROR") {
      return Color(red: 1.0, green: 0.54, blue: 0.58)
    }
    if line.localizedCaseInsensitiveContains("WARN") {
      return Color(red: 1.0, green: 0.80, blue: 0.42)
    }
    if line.localizedCaseInsensitiveContains("DEBUG") {
      return .white.opacity(0.55)
    }
    return .white.opacity(0.88)
  }

  // MARK: - 5. 定时服务

  private var schedulerContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      if isLoadingSchedules && schedules.isEmpty {
        ProgressView("正在读取定时服务…")
          .tint(.primary)
          .frame(maxWidth: .infinity, minHeight: 160)
      } else if schedules.isEmpty {
        emptyCard("暂无定时服务任务")
      } else {
        ForEach(schedules) { item in
          let isRunning = runningJobID == item.id
          CinematicPanel(padding: 13) {
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                HStack(spacing: 8) {
                  Text(item.statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                      item.isRunningNow
                        ? Color(red: 0.48, green: 0.90, blue: 0.66) : .white.opacity(0.65))
                  if let next = item.nextRun, !next.isEmpty {
                    Text("下次：\(next)")
                      .font(.caption2)
                      .foregroundStyle(.primary.opacity(0.55))
                  }
                }
              }
              Spacer(minLength: 6)
              Button {
                Task { await triggerSchedule(item) }
              } label: {
                HStack(spacing: 5) {
                  if isRunning {
                    ProgressView().controlSize(.mini).tint(.primary)
                  } else {
                    Image(systemName: "play.fill").font(.caption2)
                  }
                  Text("运行").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { Capsule().fill(.primary.opacity(0.14)) }
              }
              .buttonStyle(.plain)
              .disabled(runningJobID != nil)
              .accessibilityIdentifier("native-diag-scheduler-\(item.id)")
            }
          }
        }
      }
    }
  }

  /// 通用空态卡片。
  private func emptyCard(_ text: String) -> some View {
    CinematicPanel {
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.primary.opacity(0.68))
        .frame(maxWidth: .infinity, minHeight: 90)
    }
  }

  // MARK: - 网络请求

  private func loadCurrentTool() async {
    switch tool {
    case .health:
      if modules.isEmpty { await runHealthCheck() }
    case .nettest:
      await loadNetTargets()
    case .ruleTest:
      await loadRuleGroups()
    case .liveLog:
      await fetchLiveLog(silent: false)
    case .scheduler:
      await loadSchedules()
    }
  }

  /// 读取模块清单并逐项执行 `GET /api/v1/system/moduletest/{id}`。
  private func runHealthCheck() async {
    guard !isCheckingHealth else { return }
    isCheckingHealth = true
    healthProgress = 0
    defer { isCheckingHealth = false }
    do {
      let endpoint = try APIEndpoint(path: ["system", "modulelist"])
      let wrapper = try await session.request(
        endpoint, as: NativeModuleListPayload.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      let list = wrapper.modules ?? []
      modules = list.map {
        NativeHealthModuleRow(
          id: $0.id,
          displayName: ($0.nameI18n?.isEmpty == false ? $0.nameI18n : $0.name) ?? $0.id,
          state: .pending, errorMessage: "", isTesting: false)
      }
      guard !modules.isEmpty else {
        healthProgress = 1
        return
      }
      for index in modules.indices {
        guard !Task.isCancelled else { return }
        modules[index].isTesting = true
        let id = modules[index].id
        do {
          let testEp = try APIEndpoint(
            path: ["system", "moduletest", id], responseContract: .payload)
          let reply = try await session.request(
            testEp, as: NativeDiagRawEnvelope<JSONValue>.self,
            requiring: PermissionRequirement(category: .admin)
          ).value
          if reply.success == true {
            modules[index].state = .ok
            modules[index].errorMessage = ""
          } else if let msg = reply.message, !msg.isEmpty {
            modules[index].state = .failed
            modules[index].errorMessage = msg
          } else {
            modules[index].state = .disabled
            modules[index].errorMessage = ""
          }
        } catch {
          modules[index].state = .failed
          modules[index].errorMessage = "模块检查请求失败"
        }
        modules[index].isTesting = false
        healthProgress = Double(index + 1) / Double(modules.count)
      }
    } catch {
      feedback = "无法获取系统模块清单，请稍后重试。"
    }
  }

  /// 加载网络诊断目标。
  private func loadNetTargets() async {
    isLoadingNet = true
    defer { isLoadingNet = false }
    do {
      let ep = try APIEndpoint(path: ["system", "nettest", "targets"])
      netTargets = try await session.request(
        ep, as: [NativeDiagNetTarget].self, requiring: PermissionRequirement(category: .admin)
      ).value
    } catch {
      feedback = "暂时无法载入网络测试目标。"
    }
  }

  /// 单节点网络连通测速。
  private func runNetTest(_ target: NativeDiagNetTarget) async {
    testingNetID = target.id
    defer { testingNetID = nil }
    do {
      let ep = try APIEndpoint(
        path: ["system", "nettest"],
        query: [
          URLQueryItem(name: "url", value: target.address),
          URLQueryItem(name: "proxy", value: "true"),
          URLQueryItem(name: "include", value: ""),
        ])
      let payload = try await session.request(
        ep, as: NativeDiagNetTime.self, requiring: PermissionRequirement(category: .admin)
      ).value
      let ms = Int((payload.time ?? 0).rounded())
      netResults[target.id] = NativeDiagNetResult(success: true, summary: "连通正常 · \(ms) ms")
    } catch {
      netResults[target.id] = NativeDiagNetResult(success: false, summary: "连接失败或超时")
    }
  }

  /// 读取过滤规则组清单供规则测试使用。
  private func loadRuleGroups() async {
    guard ruleGroups.isEmpty else { return }
    do {
      let ep = try APIEndpoint(path: ["system", "setting", "UserFilterRuleGroups"])
      let wrapper = try await session.request(
        ep, as: NativeDiagSettingWrapper<[NativeDiagRuleGroup]>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      let names = (wrapper.value ?? []).compactMap(\.name).filter { !$0.isEmpty }
      ruleGroups = names
      if selectedRuleGroup.isEmpty, let first = names.first {
        selectedRuleGroup = first
      }
    } catch {
      return
    }
  }

  /// 执行名称识别（`GET /api/v1/media/recognize`）或过滤规则测试（`GET /api/v1/system/ruletest`）。
  private func executeRecognitionOrRuleTest() async {
    let title = testTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let subtitle = testSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    isRunningTest = true
    defer { isRunningTest = false }
    do {
      if testMode == .recognize {
        var query = [URLQueryItem(name: "title", value: title)]
        if !subtitle.isEmpty { query.append(URLQueryItem(name: "subtitle", value: subtitle)) }
        let ep = try APIEndpoint(path: ["media", "recognize"], query: query)
        let data = try await session.request(
          ep, as: NativeRecognizeContextPayload.self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        let mediaTitle = data.mediaInfo?.titleYear ?? data.mediaInfo?.title ?? data.metaInfo?.name
        var tags: [String] = []
        if let type = data.mediaInfo?.type ?? data.metaInfo?.type, !type.isEmpty {
          tags.append(type)
        }
        if let se = data.metaInfo?.seasonEpisode, !se.isEmpty { tags.append(se) }
        if let pix = data.metaInfo?.resourcePix, !pix.isEmpty { tags.append(pix) }
        if let edition = data.metaInfo?.edition, !edition.isEmpty { tags.append(edition) }
        if let team = data.metaInfo?.resourceTeam, !team.isEmpty { tags.append(team) }
        testVerdict = NativeRuleTestVerdict(
          matched: data.mediaInfo != nil,
          headline: mediaTitle.map { "识别成功：\($0)" } ?? "未识别到匹配媒体",
          detail: data.mediaInfo?.overview ?? "已解析基础元信息，可继续调整识别词。",
          tags: tags)
      } else {
        var query = [
          URLQueryItem(name: "title", value: title),
          URLQueryItem(name: "rulegroup_name", value: selectedRuleGroup),
        ]
        if !subtitle.isEmpty { query.append(URLQueryItem(name: "subtitle", value: subtitle)) }
        let ep = try APIEndpoint(
          path: ["system", "ruletest"], query: query, responseContract: .payload)
        let reply = try await session.request(
          ep, as: NativeDiagRawEnvelope<NativeRuleTestPayload>.self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        if let data = reply.data, reply.success == true, data.matched == true {
          let priority = data.priority.map { " · 优先级 \($0)" } ?? ""
          var tags: [String] = []
          if let group = data.rulegroupName, !group.isEmpty { tags.append("规则组：\(group)") }
          if let pix = data.metaInfo?.resourcePix, !pix.isEmpty { tags.append(pix) }
          if let team = data.metaInfo?.resourceTeam, !team.isEmpty { tags.append(team) }
          testVerdict = NativeRuleTestVerdict(
            matched: true,
            headline: "命中过滤规则\(priority)",
            detail: data.mediaInfo?.titleYear ?? data.mediaInfo?.title ?? title,
            tags: tags)
        } else {
          testVerdict = NativeRuleTestVerdict(
            matched: false,
            headline: "未命中过滤规则",
            detail: reply.message?.isEmpty == false ? reply.message! : "当前标题未通过所选优先级规则组。",
            tags: ["规则组：\(selectedRuleGroup)"])
        }
      }
    } catch {
      feedback = "执行测试失败，请稍后重试。"
    }
  }

  /// 拉取最近实时日志文本并保留尾部 250 行（`GET /api/v1/system/logging?length=-1`）。
  private func fetchLiveLog(silent: Bool) async {
    if !silent { isLoadingLog = true }
    defer { if !silent { isLoadingLog = false } }
    do {
      let ep = try APIEndpoint(
        path: ["system", "logging"],
        query: [
          URLQueryItem(name: "length", value: "-1"),
          URLQueryItem(name: "logfile", value: "moviepilot.log"),
        ],
        responseContract: .plainText,
        maximumResponseBytes: 4 * 1024 * 1024)
      let raw = try await session.requestPayload(
        ep, requiring: PermissionRequirement(category: .admin)
      ).value
      let text = String(decoding: raw, as: UTF8.self)
      let all = text.split(whereSeparator: \.isNewline).map(String.init)
      logLines = Array(all.suffix(250))
    } catch {
      if !silent { feedback = "无法读取实时日志，请确认管理员权限与日志文件状态。" }
    }
  }

  /// 读取后台定时服务清单（`GET /api/v1/dashboard/schedule`）。
  private func loadSchedules() async {
    isLoadingSchedules = true
    defer { isLoadingSchedules = false }
    do {
      let ep = try APIEndpoint(path: ["dashboard", "schedule"])
      schedules = try await session.request(
        ep, as: [NativeDiagSchedule].self, requiring: PermissionRequirement(category: .admin)
      ).value
    } catch {
      feedback = "无法读取定时服务清单。"
    }
  }

  /// 手动触发单条定时服务（`GET /api/v1/system/runscheduler?jobid={id}`）。
  private func triggerSchedule(_ item: NativeDiagSchedule) async {
    runningJobID = item.id
    defer { runningJobID = nil }
    do {
      let ep = try APIEndpoint(
        path: ["system", "runscheduler"],
        query: [URLQueryItem(name: "jobid", value: item.id)])
      try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
      feedback = "已触发定时服务「\(item.displayName)」。"
      await loadSchedules()
    } catch {
      feedback = "触发定时服务失败，请稍后重试。"
    }
  }
}

// MARK: - 解码模型

private enum NativeHealthState {
  case pending, ok, disabled, failed
}

private struct NativeHealthModuleRow: Identifiable {
  let id: String
  let displayName: String
  var state: NativeHealthState
  var errorMessage: String
  var isTesting: Bool
}

private struct NativeModuleListPayload: Decodable, Sendable {
  struct Item: Decodable, Sendable {
    let id: String
    let name: String?
    let nameI18n: String?
    private enum CodingKeys: String, CodingKey {
      case id, name
      case nameI18n = "name_i18n"
    }
  }
  let modules: [Item]?
}

private struct NativeDiagNetTarget: Decodable, Sendable, Identifiable {
  let id: String
  let name: String
  let address: String
}

private struct NativeDiagNetTime: Decodable, Sendable {
  let time: Double?
}

private struct NativeDiagNetResult {
  let success: Bool
  let summary: String
}

private struct NativeDiagSettingWrapper<Value: Decodable & Sendable>: Decodable, Sendable {
  let value: Value?
}

private struct NativeDiagRawEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
  let success: Bool?
  let message: String?
  let data: Value?
}

private struct NativeDiagRuleGroup: Decodable, Sendable {
  let name: String?
}

private struct NativeDiagMetaBrief: Decodable, Sendable {
  let name: String?
  let type: String?
  let seasonEpisode: String?
  let resourcePix: String?
  let edition: String?
  let resourceTeam: String?

  private enum CodingKeys: String, CodingKey {
    case name, type, edition
    case seasonEpisode = "season_episode"
    case resourcePix = "resource_pix"
    case resourceTeam = "resource_team"
  }
}

private struct NativeDiagMediaBrief: Decodable, Sendable {
  let title: String?
  let titleYear: String?
  let type: String?
  let overview: String?

  private enum CodingKeys: String, CodingKey {
    case title, type, overview
    case titleYear = "title_year"
  }
}

private struct NativeRecognizeContextPayload: Decodable, Sendable {
  let metaInfo: NativeDiagMetaBrief?
  let mediaInfo: NativeDiagMediaBrief?

  private enum CodingKeys: String, CodingKey {
    case metaInfo = "meta_info"
    case mediaInfo = "media_info"
  }
}

private struct NativeRuleTestPayload: Decodable, Sendable {
  let matched: Bool?
  let priority: Int?
  let rulegroupName: String?
  let metaInfo: NativeDiagMetaBrief?
  let mediaInfo: NativeDiagMediaBrief?

  private enum CodingKeys: String, CodingKey {
    case matched, priority
    case rulegroupName = "rulegroup_name"
    case metaInfo = "meta_info"
    case mediaInfo = "media_info"
  }
}

private struct NativeRuleTestVerdict {
  let matched: Bool
  let headline: String
  let detail: String
  let tags: [String]
}

private struct NativeDiagSchedule: Decodable, Sendable, Identifiable {
  let id: String
  let name: String?
  let nameI18n: String?
  let status: String?
  let nextRun: String?

  var displayName: String {
    if let nameI18n, !nameI18n.isEmpty { return nameI18n }
    if let name, !name.isEmpty { return name }
    return id
  }

  var isRunningNow: Bool {
    (status ?? "").lowercased().contains("run") || (status ?? "").contains("运行")
  }

  var statusLabel: String {
    if let status, !status.isEmpty { return status }
    return "等待"
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, status
    case nameI18n = "name_i18n"
    case nextRun = "next_run"
  }
}
