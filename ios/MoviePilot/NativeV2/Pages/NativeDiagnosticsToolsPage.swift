import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生捷径与诊断工具集：覆盖系统检查、网络测试、名称识别与规则测试、词表管理、结构化实时日志与定时服务。
@MainActor
struct NativeDiagnosticsToolsPage: View {
  /// 诊断与快捷工具分区。
  enum Tool: String, CaseIterable, Identifiable {
    case health = "系统检查"
    case nettest = "网络测试"
    case ruleTest = "识别与规则"
    case words = "词表"
    case liveLog = "实时日志"
    case scheduler = "定时服务"

    var id: String { rawValue }

    var symbol: String {
      switch self {
      case .health: "checkmark.shield"
      case .nettest: "network"
      case .ruleTest: "text.magnifyingglass"
      case .words: "character.book.closed"
      case .liveLog: "terminal"
      case .scheduler: "clock.arrow.2.circlepath"
      }
    }
  }

  private enum TestMode: String, CaseIterable, Identifiable {
    case recognize = "名称识别"
    case rule = "规则测试"
    var id: String { rawValue }
  }

  private enum HealthFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case failed = "异常"
    case ok = "正常"
    case disabled = "未启用"
    var id: String { rawValue }
  }

  /// 系统日志与插件日志共用的严格级别筛选。
  private enum LogLevel: String, CaseIterable, Identifiable {
    case all = "全部"
    case error = "ERROR"
    case warning = "WARNING"
    case info = "INFO"
    case debug = "DEBUG"
    var id: String { rawValue }
  }

  private enum SchedulerCategoryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case system = "系统任务"
    case plugin = "插件任务"
    case automation = "工作流/助手"
    var id: String { rawValue }
  }

  private enum WordsTab: String, CaseIterable, Identifiable {
    case identifiers = "识别词"
    case releaseGroups = "制作组"
    case customization = "占位符"
    case excludeWords = "屏蔽词"
    case episodeRules = "剧集规则"
    var id: String { rawValue }
  }

  let session: NativeSession
  let initialTool: Tool
  private let logfile: String
  private let logTitle: String?

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var tool: Tool

  // 1. 系统检查
  @State private var modules: [NativeHealthModuleRow] = []
  @State private var isCheckingHealth = false
  @State private var healthProgress: Double = 0
  @State private var healthFilter: HealthFilter = .all

  // 2. 网络测试
  @State private var netTargets: [NativeDiagNetTarget] = []
  @State private var netResults: [String: NativeDiagNetResult] = [:]
  @State private var testingNetID: String?
  @State private var isTestingAllNet = false
  @State private var isLoadingNet = false

  // 3. 识别与规则测试
  @State private var testMode: TestMode = .recognize
  @State private var testTitle = ""
  @State private var testSubtitle = ""
  @State private var testCustomWords = ""
  @State private var showCustomWordsField = false
  @State private var mediaSources: [NativeDiagMediaSource] = []
  @State private var selectedMediaSource = ""
  @State private var ruleGroups: [NativeDiagRuleGroup] = []
  @State private var selectedRuleGroup = ""
  @State private var isRunningTest = false
  @State private var recognizeResult: NativeRecognizeDisplayResult?
  @State private var ruleTestResult: NativeRuleTestDisplayResult?
  @State private var testErrorMessage: String?

  // 4. 词表
  @State private var wordsTab: WordsTab = .identifiers
  @State private var showIdentifiersGuide = true
  @State private var showEpisodeRulesGuide = true
  @State private var identifiersText = ""
  @State private var originalIdentifiers: [String] = []
  @State private var releaseGroupsText = ""
  @State private var customizationText = ""
  @State private var excludeWordsText = ""
  @State private var episodeRules: [NativeEpisodeFormatRule] = []
  @State private var isLoadingWords = false
  @State private var isSavingWords = false
  @State private var editingEpisodeRule: NativeEpisodeFormatRule?
  @State private var showsAddEpisodeRule = false

  // 5. 实时日志
  @State private var logEntries: [NativeStructuredLogEntry] = []
  @State private var logFilter = ""
  @State private var logLevel: LogLevel = .all
  @State private var liveFollow = true
  @State private var isLoadingLog = false

  // 6. 定时服务
  @State private var schedules: [NativeDiagSchedule] = []
  @State private var schedulerFilter: SchedulerCategoryFilter = .all
  @State private var isLoadingSchedules = false
  @State private var runningJobID: String?

  @State private var feedback: (isError: Bool, text: String)?

  /// 日志工具允许指定插件日志文件与标题，其余解析、筛选、跟随和布局全部复用。
  init(
    session: NativeSession, initialTool: Tool = .health,
    logfile: String = "moviepilot.log", logTitle: String? = nil
  ) {
    self.session = session
    self.initialTool = initialTool
    self.logfile = logfile
    self.logTitle = logTitle
    _tool = State(initialValue: initialTool)
  }

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            CinematicPanel(padding: 11) {
              HStack(spacing: 8) {
                Image(
                  systemName: feedback.isError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.text)
                  .font(.caption.weight(.medium))
                  .foregroundStyle(.primary.opacity(0.92))
                Spacer(minLength: 0)
                Button {
                  self.feedback = nil
                } label: {
                  Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
      .refreshable {
        await Task { @MainActor in
          await loadCurrentTool()
        }.value
      }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-diag-scroll")
    }
    .navigationTitle(tool == .liveLog ? (logTitle ?? tool.rawValue) : tool.rawValue)
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      if tool == .liveLog {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await fetchLiveLog(silent: false) }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .tint(.primary)
          .disabled(isLoadingLog)
          .accessibilityLabel("刷新日志")
          .accessibilityIdentifier("native-diag-log-refresh")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        trailingAction
          .tint(.primary)
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
    .sheet(item: $editingEpisodeRule) { rule in
      NativeEpisodeRuleEditorSheet(rule: rule) { updated in
        if let idx = episodeRules.firstIndex(where: { $0.id == updated.id }) {
          episodeRules[idx] = updated
        }
      }
    }
    .sheet(isPresented: $showsAddEpisodeRule) {
      NativeEpisodeRuleEditorSheet(
        rule: NativeEpisodeFormatRule(
          name: "", enabled: true, order: episodeRules.count + 1, pattern: "", minFileSizeMB: 0)
      ) { created in
        episodeRules.append(created)
      }
    }
  }

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
    case .nettest:
      Button {
        Task { await runAllNetTests() }
      } label: {
        Text(isTestingAllNet ? "测试中" : "测试全部").fontWeight(.semibold)
      }
      .disabled(isTestingAllNet || netTargets.isEmpty)
      .accessibilityIdentifier("native-diag-nettest-all")
    case .words:
      Button {
        Task { await saveCurrentWordsTab() }
      } label: {
        if isSavingWords {
          ProgressView().controlSize(.small)
        } else {
          Text("保存").fontWeight(.semibold)
        }
      }
      .disabled(isSavingWords || isLoadingWords)
      .accessibilityIdentifier("native-diag-words-save")
    case .liveLog:
      Button {
        liveFollow.toggle()
      } label: {
        Image(systemName: liveFollow ? "pause.circle" : "play.circle")
      }
      .accessibilityLabel(liveFollow ? "暂停实时跟随" : "恢复实时跟随")
      .accessibilityIdentifier("native-diag-log-follow")
    case .scheduler:
      Button {
        Task { await loadSchedules() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .disabled(isLoadingSchedules)
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var toolContent: some View {
    switch tool {
    case .health: healthContent
    case .nettest: nettestContent
    case .ruleTest: ruleTestContent
    case .words: wordsContent
    case .liveLog: liveLogContent
    case .scheduler: schedulerContent
    }
  }

  // MARK: - 1. 系统检查（进度条 + 总数/正常/未启用/异常统计 + 状态筛选）

  private var filteredHealthModules: [NativeHealthModuleRow] {
    switch healthFilter {
    case .all: modules
    case .failed: modules.filter { $0.state == .failed }
    case .ok: modules.filter { $0.state == .ok }
    case .disabled: modules.filter { $0.state == .disabled }
    }
  }

  private var healthContent: some View {
    let okCount = modules.filter { $0.state == .ok }.count
    let failedCount = modules.filter { $0.state == .failed }.count
    let disabledCount = modules.filter { $0.state == .disabled }.count
    let testedCount = okCount + failedCount + disabledCount
    return VStack(alignment: .leading, spacing: 12) {
      CinematicPanel(padding: 15) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .center, spacing: 10) {
            Image(
              systemName: isCheckingHealth
                ? "waveform.path.ecg"
                : (failedCount > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(
              isCheckingHealth
                ? appearance.accentColor
                : (failedCount > 0 ? NativeTheme.danger : NativeTheme.success)
            )
            VStack(alignment: .leading, spacing: 2) {
              Text(
                isCheckingHealth
                  ? "正在检测系统模块 (\(testedCount)/\(modules.count))"
                  : (failedCount > 0 ? "发现 \(failedCount) 项模块异常" : "全部已启用模块正常")
              )
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              Text(isCheckingHealth ? "逐项连通性与依赖健康校验中…" : "共检测 \(modules.count) 个系统模块")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int((healthProgress * 100).rounded()))%")
              .font(.subheadline.monospacedDigit().weight(.bold))
              .foregroundStyle(appearance.accentColor)
          }

          GeometryReader { bar in
            let w = max(bar.size.width, 1)
            ZStack(alignment: .leading) {
              Capsule().fill(NativeTheme.chipFill)
              Capsule()
                .fill(
                  LinearGradient(
                    colors: failedCount > 0
                      ? [appearance.accentColor, NativeTheme.danger]
                      : [appearance.accentColor, NativeTheme.success],
                    startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: w * min(max(healthProgress, 0.02), 1))
                .animation(.easeOut(duration: 0.25), value: healthProgress)
            }
          }
          .frame(height: 7)

          HStack(spacing: 8) {
            healthStatTile(title: "总计", count: modules.count, tint: NativeTheme.info)
            healthStatTile(title: "正常", count: okCount, tint: NativeTheme.success)
            healthStatTile(title: "异常", count: failedCount, tint: NativeTheme.danger)
            healthStatTile(title: "未启用", count: disabledCount, tint: NativeTheme.badgeMutedText)
          }
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          ForEach(HealthFilter.allCases) { option in
            Button {
              healthFilter = option
            } label: {
              NativeAdaptivePill(option.rawValue, isSelected: healthFilter == option)
            }
            .buttonStyle(.plain)
          }
        }
      }

      if modules.isEmpty && isCheckingHealth {
        NativeCardListSkeletonView(count: 5, style: .iconRow)
          .transition(.opacity)
      } else if filteredHealthModules.isEmpty {
        emptyCard("当前筛选状态下暂无模块")
      } else {
        ForEach(filteredHealthModules) { mod in
          CinematicPanel(padding: 13) {
            HStack(spacing: 11) {
              healthIcon(mod)
              VStack(alignment: .leading, spacing: 3) {
                Text(mod.displayName)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                if !mod.errorMessage.isEmpty {
                  Text(mod.errorMessage)
                    .font(.caption)
                    .foregroundStyle(NativeTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                } else if mod.state == .disabled {
                  Text("当前未配置或未启用此模块")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

  private func healthStatTile(title: String, count: Int, tint: Color) -> some View {
    VStack(spacing: 2) {
      Text("\(count)")
        .font(.subheadline.monospacedDigit().weight(.bold))
        .foregroundStyle(tint)
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 7)
    .background(NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private func healthIcon(_ mod: NativeHealthModuleRow) -> some View {
    let (symbol, color): (String, Color) =
      switch mod.state {
      case .pending: ("ellipsis.circle", NativeTheme.badgeMutedText)
      case .ok: ("checkmark.circle.fill", NativeTheme.success)
      case .disabled: ("minus.circle.fill", NativeTheme.badgeMutedText)
      case .failed: ("xmark.octagon.fill", NativeTheme.danger)
      }
    return Image(systemName: symbol)
      .font(.body.weight(.semibold))
      .foregroundStyle(color)
      .frame(width: 28, height: 28)
      .background(color.opacity(0.14), in: Circle())
  }

  private func healthBadge(_ state: NativeHealthState) -> some View {
    switch state {
    case .pending: NativeAdaptiveBadge("等待中")
    case .ok: NativeAdaptiveBadge("正常", tint: NativeTheme.success)
    case .disabled: NativeAdaptiveBadge("未启用")
    case .failed: NativeAdaptiveBadge("异常", tint: NativeTheme.danger)
    }
  }

  // MARK: - 2. 网络测试

  private var nettestContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      if isLoadingNet && netTargets.isEmpty {
        NativeCardListSkeletonView(count: 5, style: .iconRow, showsIcon: false)
          .transition(.opacity)
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
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                if let result {
                  Text(result.summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(result.success ? NativeTheme.success : NativeTheme.danger)
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
                .foregroundStyle(NativeTheme.chipText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                  Capsule()
                    .fill(NativeTheme.chipFill)
                    .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
                }
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

  // MARK: - 3. 名称识别与过滤规则测试（对标 Web 英雄卡与解析明细）

  private var ruleTestContent: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 8) {
        ForEach(TestMode.allCases) { option in
          Button {
            testMode = option
            testErrorMessage = nil
          } label: {
            NativeAdaptivePill(
              option.rawValue,
              symbol: option == .recognize
                ? "sparkle.magnifyingglass" : "line.3.horizontal.decrease.circle",
              isSelected: testMode == option
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-diag-testmode-\(option.rawValue)")
        }
        Spacer(minLength: 0)
      }

      formGroupedSection("测试内容") {
        formInputRow(
          "标题 / 种子名",
          text: $testTitle,
          placeholder: "如 The.Matrix.1999.2160p",
          accessibilityID: "native-diag-test-title"
        )
        CinematicFormDivider()
        formInputRow(
          "副标题",
          text: $testSubtitle,
          placeholder: "可选描述或中文译名",
          accessibilityID: "native-diag-test-subtitle"
        )
      }

      if testMode == .recognize {
        formGroupedSection("识别选项") {
          if !mediaSources.isEmpty {
            HStack(spacing: 12) {
              Text("识别数据源")
                .font(.subheadline)
                .foregroundStyle(.primary)
              Spacer(minLength: 8)
              Picker("识别数据源", selection: $selectedMediaSource) {
                Text("系统默认").tag("")
                ForEach(mediaSources) { src in
                  Text(src.displayName).tag(src.mediaSource)
                }
              }
              .pickerStyle(.menu)
              .tint(appearance.accentColor)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            CinematicFormDivider()
          }

          DisclosureGroup(isExpanded: $showCustomWordsField) {
            VStack(alignment: .leading, spacing: 8) {
              TextEditor(text: $testCustomWords)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 88)
                .padding(10)
                .background(
                  Color.primary.opacity(0.05),
                  in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
              Text("支持正则表达式，特殊字符需要 \\ 转义，一行为一组（如：屏蔽词、被替换词 => 替换词、前定位词 <> 后定位词 >> 集偏移量）。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
          } label: {
            HStack(spacing: 8) {
              Text("临时自定义识别词")
                .font(.subheadline)
                .foregroundStyle(.primary)
              Spacer(minLength: 8)
              let lines =
                testCustomWords
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .count
              Text(lines > 0 ? "已填 \(lines) 行" : "可选")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .tint(appearance.accentColor)
          .padding(.horizontal, 15)
          .padding(.vertical, 13)
        }
      } else {
        formGroupedSection("优先级规则组") {
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
              Text("目标规则组")
                .font(.subheadline)
                .foregroundStyle(.primary)
              Spacer(minLength: 8)
              if ruleGroups.isEmpty {
                Text("未检测到规则组")
                  .font(.caption)
                  .foregroundStyle(NativeTheme.warning)
              } else {
                Picker("规则组", selection: $selectedRuleGroup) {
                  ForEach(ruleGroups) { group in
                    Text(group.name).tag(group.name)
                  }
                }
                .pickerStyle(.menu)
                .tint(appearance.accentColor)
              }
            }
            if let current = ruleGroups.first(where: { $0.name == selectedRuleGroup }),
              let ruleStr = current.ruleString, !ruleStr.isEmpty
            {
              Text(ruleStr)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                  NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
          }
          .padding(.horizontal, 15)
          .padding(.vertical, 12)
        }
      }

      Button {
        Task { await executeRecognitionOrRuleTest() }
      } label: {
        HStack(spacing: 8) {
          if isRunningTest {
            ProgressView().controlSize(.small).tint(.white)
          } else {
            Image(systemName: testMode == .recognize ? "text.viewfinder" : "checkmark.seal")
              .font(.subheadline.weight(.semibold))
          }
          Text(testMode == .recognize ? "开始名称识别" : "开始规则测试")
            .font(.subheadline.weight(.bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(appearance.accentColor, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(
        isRunningTest || testTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || (testMode == .rule && selectedRuleGroup.isEmpty)
      )
      .accessibilityIdentifier("native-diag-test-run")

      if let testErrorMessage {
        CinematicPanel(padding: 13) {
          Label(testErrorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(NativeTheme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      if testMode == .recognize, let rec = recognizeResult {
        recognizeResultCard(rec)
      } else if testMode == .rule, let ruleRes = ruleTestResult {
        ruleResultCard(ruleRes)
      }
    }
  }

  /// 对齐订阅编辑弹层的分组表单容器。
  private func formGroupedSection<Content: View>(
    _ header: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(header)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) { content() }
      }
    }
  }

  /// 对齐订阅编辑弹层的宽松单行输入行，保留充足呼吸感与一键清空操作。
  private func formInputRow(
    _ label: String,
    text: Binding<String>,
    placeholder: String,
    accessibilityID: String
  ) -> some View {
    HStack(spacing: 12) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .layoutPriority(1)
      Spacer(minLength: 8)
      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityIdentifier(accessibilityID)
      if !text.wrappedValue.isEmpty {
        Button {
          text.wrappedValue = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary.opacity(0.65))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清空\(label)")
      }
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 13)
  }

  /// 对标 Web `NameTestView.vue` 的识别英雄卡 + 多维解析链路 + 应用识别词。
  private func recognizeResultCard(_ result: NativeRecognizeDisplayResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 12) {
            if let poster = result.posterPath, !poster.isEmpty {
              NativeMediaArtwork(
                session: session, reference: poster, role: .poster, maximumWidth: 320
              )
              .frame(width: 78, height: 112)
              .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
              HStack(spacing: 6) {
                Image(
                  systemName: result.matched
                    ? "checkmark.seal.fill" : "questionmark.circle.fill"
                )
                .foregroundStyle(result.matched ? NativeTheme.success : NativeTheme.warning)
                Text(result.headline)
                  .font(.headline)
                  .foregroundStyle(.primary)
                  .lineLimit(2)
              }

              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                  if let type = result.mediaType, !type.isEmpty {
                    NativeAdaptiveBadge(type, tint: appearance.accentColor, filled: true)
                  }
                  if let source = result.mediaSource, !source.isEmpty {
                    NativeAdaptiveBadge(source, tint: NativeTheme.info)
                  }
                  if let rating = result.voteAverage, rating > 0 {
                    NativeAdaptiveBadge(
                      "★ \(String(format: "%.1f", rating))", tint: NativeTheme.warning)
                  }
                  if let category = result.category, !category.isEmpty {
                    NativeAdaptiveBadge(category, tint: NativeTheme.brand)
                  }
                }
              }

              if let overview = result.overview, !overview.isEmpty {
                Text(overview)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(3)
              }

              if let identity = result.detailIdentity {
                NavigationLink {
                  NativeMediaDetailPage(session: session, identity: identity)
                } label: {
                  Label("查看媒体详情", systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appearance.accentColor)
                }
                .padding(.top, 2)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          if !result.metaFields.isEmpty {
            Divider().overlay(NativeTheme.divider)
            Text("元信息解析链路")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            LazyVGrid(
              columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
              spacing: 8
            ) {
              ForEach(result.metaFields, id: \.label) { field in
                VStack(alignment: .leading, spacing: 2) {
                  Text(field.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                  Text(field.value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(
                  NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              }
            }
          }

          if !result.applyWords.isEmpty {
            Divider().overlay(NativeTheme.divider)
            VStack(alignment: .leading, spacing: 6) {
              Text("已命中识别词（\(result.applyWords.count)）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              ForEach(result.applyWords, id: \.self) { word in
                Text(word)
                  .font(.system(size: 11, design: .monospaced))
                  .foregroundStyle(NativeTheme.brand)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(
                    NativeTheme.brand.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
              }
            }
          }
        }
      }
      .accessibilityIdentifier("native-diag-test-result")
    }
  }

  /// 对标 Web `RuleTestView.vue` 的过滤规则测试结果卡（突出命中优先级徽标与解析标签）。
  private func ruleResultCard(_ result: NativeRuleTestDisplayResult) -> some View {
    CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 11) {
        HStack(spacing: 10) {
          Image(
            systemName: result.matched ? "checkmark.seal.fill" : "xmark.circle.fill"
          )
          .font(.title2)
          .foregroundStyle(result.matched ? NativeTheme.success : NativeTheme.danger)
          VStack(alignment: .leading, spacing: 2) {
            Text(result.matched ? "命中优先级过滤规则" : "未命中过滤规则")
              .font(.headline)
              .foregroundStyle(.primary)
            Text(result.subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if let priority = result.priority, result.matched {
            NativeAdaptiveBadge("优先级 P\(priority)", tint: NativeTheme.success, filled: true)
          }
        }

        if !result.tags.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              ForEach(result.tags, id: \.self) { tag in
                NativeAdaptiveBadge(tag, tint: NativeTheme.brand)
              }
            }
          }
        }

        if let detail = result.ruleDetail, !detail.isEmpty {
          Text(detail)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityIdentifier("native-diag-test-result")
  }

  // MARK: - 4. 词表管理（5 大板块，对标 Web WordsView.vue）

  private var wordsContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          ForEach(WordsTab.allCases) { tab in
            Button {
              wordsTab = tab
            } label: {
              NativeAdaptivePill(tab.rawValue, isSelected: wordsTab == tab)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-diag-words-tab-\(tab.rawValue)")
          }
        }
      }

      if isLoadingWords {
        wordsSkeleton
          .transition(.opacity)
      } else {
        switch wordsTab {
        case .identifiers:
          wordsTextEditorCard(
            title: "自定义识别词",
            description: "添加规则对种子名或者文件名进行预处理以校正识别",
            inlineHint: "支持正则表达式，特殊字符需要 \\ 转义，一行为一组",
            placeholder: "每行输入一组识别规则",
            text: $identifiersText
          )
          wordsGuidePanel(
            title: "支持的配置格式（注意空格）：",
            isExpanded: $showIdentifiersGuide,
            codeLines: [
              "屏蔽词",
              "被替换词 => 替换词",
              "前定位词 <> 后定位词 >> 集偏移量（EP）",
              "被替换词 => 替换词 && 前定位词 <> 后定位词 >> 集偏移量（EP）",
            ],
            notes: [
              "其中替换词支持格式：{[tmdbid/doubanid/bangumiid/anilistid=xxx;type=movie/tv;g=xxx;s=xxx;e=xxx]} 直接指定媒体数据源 ID 识别，其中 g 为剧集组编号，s、e 为季数和集数（均可选）。"
            ]
          )
        case .releaseGroups:
          wordsTextEditorCard(
            title: "自定义制作组 / 字幕组",
            description: "添加无法识别的制作组/字幕组。",
            inlineHint: "支持正则表达式，特殊字符需要 \\ 转义，一行代表一个制作组/字幕组",
            placeholder: "每行输入一个制作组/字幕组",
            text: $releaseGroupsText
          )
        case .customization:
          wordsTextEditorCard(
            title: "自定义占位符",
            description: "添加自定义占位符识别正则，重命名格式中添加 {customization} 使用。",
            inlineHint: "支持正则表达式，特殊字符需要 \\ 转义，多个匹配对象请换行分隔",
            placeholder: "每行输入一个占位符识别正则",
            text: $customizationText
          )
        case .excludeWords:
          wordsTextEditorCard(
            title: "文件整理屏蔽词",
            description: "目录名或文件名中包含屏蔽词时不进行整理。",
            inlineHint: "支持正则表达式，特殊字符需要 \\ 转义，一行代表一个屏蔽词",
            placeholder: "每行输入一个屏蔽词",
            text: $excludeWordsText
          )
        case .episodeRules:
          episodeRulesSection
        }
      }
    }
  }

  /// 词表加载期间与 `wordsTextEditorCard` 等高（`minHeight: 220`）的等宽编辑框占位骨架。
  @ViewBuilder
  private var wordsSkeleton: some View {
    if wordsTab == .episodeRules {
      VStack(alignment: .leading, spacing: 10) {
        CinematicPanel(padding: 14) {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              NativeSkeletonBlock(width: 148, height: 15, cornerRadius: 5)
              Spacer()
              NativeSkeletonBlock(width: 44, height: 18, cornerRadius: 9)
            }
            NativeSkeletonBlock(width: 236, height: 12, cornerRadius: 4)
          }
        }
        NativeCardListSkeletonView(count: 2, style: .iconRow, showsIcon: false)
      }
      .nativeSkeletonShimmer()
    } else {
      VStack(alignment: .leading, spacing: 12) {
        CinematicPanel(padding: 15) {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              NativeSkeletonBlock(width: 118, height: 15, cornerRadius: 5)
              Spacer()
              NativeSkeletonBlock(width: 44, height: 18, cornerRadius: 9)
            }
            NativeSkeletonBlock(width: 228, height: 12, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 9) {
              NativeSkeletonBlock(width: 186, height: 12, cornerRadius: 4)
              NativeSkeletonBlock(width: 242, height: 12, cornerRadius: 4)
              NativeSkeletonBlock(width: 154, height: 12, cornerRadius: 4)
              Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(
              NativeTheme.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.7)
            }
            NativeSkeletonBlock(width: 248, height: 12, cornerRadius: 4)
          }
        }
        CinematicPanel(padding: 14) {
          HStack {
            NativeSkeletonBlock(width: 156, height: 15, cornerRadius: 5)
            Spacer()
            NativeSkeletonBlock(width: 12, height: 12, cornerRadius: 4)
          }
        }
      }
      .nativeSkeletonShimmer()
    }
  }

  private func wordsTextEditorCard(
    title: String,
    description: String,
    inlineHint: String,
    placeholder: String,
    text: Binding<String>
  ) -> some View {
    let lineCount = text.wrappedValue
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }.count
    return CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Spacer()
          NativeAdaptiveBadge("\(lineCount) 条", tint: NativeTheme.info)
        }
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
        ZStack(alignment: .topLeading) {
          if text.wrappedValue.isEmpty {
            Text(placeholder)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary.opacity(0.7))
              .padding(.horizontal, 12)
              .padding(.vertical, 12)
          }
          TextEditor(text: text)
            .font(.system(.caption, design: .monospaced))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 220)
            .padding(6)
        }
        .background(
          NativeTheme.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.7)
        }
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 1)
          Text(inlineHint)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  /// 对标 Web `WordsView.vue` 的可折叠格式/规则提示面板，完整保留语法示例与注意事项。
  private func wordsGuidePanel(
    title: String,
    isExpanded: Binding<Bool>,
    codeLines: [String],
    notes: [String]
  ) -> some View {
    CinematicPanel(padding: 14) {
      DisclosureGroup(isExpanded: isExpanded) {
        VStack(alignment: .leading, spacing: 8) {
          if !codeLines.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
              ForEach(codeLines, id: \.self) { line in
                Text(line)
                  .font(.system(.caption, design: .monospaced))
                  .foregroundStyle(.primary.opacity(0.92))
                  .textSelection(.enabled)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
              NativeTheme.fieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
          }
          ForEach(notes, id: \.self) { note in
            Text(note)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.top, 8)
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "info.circle")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
        }
      }
      .tint(.primary)
    }
  }

  private static let episodeRuleGuideNotes: [String] = [
    "从上到下依次匹配，第一个匹配的则使用该规则。",
    "按文件名实际结构编写匹配规则：",
    "• 固定文本直接匹配，集数必须使用命名分组 (?<ep>...) 标记；",
    "• 其余不固定但需要保留位置的内容，可使用 (?<a>...)、(?<b>...) 等命名分组承接。",
    "• 如需按字面量匹配 [](). 等特殊字符，请进行转义；",
    "• 建议使用 ^ 和 $ 完整约束整条文件名，其中 $ 尤其重要，可避免只匹配前半段就被误判为命中。",
  ]

  private var episodeRulesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("手动整理集数定位规则")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
            Spacer()
            NativeAdaptiveBadge("\(episodeRules.count) 条", tint: NativeTheme.info)
          }
          Text("用于匹配媒体文件名，命中后自动生成对应的集数定位正则。")
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack {
            Spacer()
            Button {
              showsAddEpisodeRule = true
            } label: {
              Label("新增规则", systemImage: "plus.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appearance.accentColor)
            }
            .buttonStyle(.plain)
          }
          .padding(.top, 2)
        }
      }

      if episodeRules.isEmpty {
        emptyCard("暂无集数定位规则，可点击上方「新增规则」创建后保存。")
      } else {
        ForEach($episodeRules) { $rule in
          CinematicPanel(padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $rule.enabled)
                  .labelsHidden()
                  .tint(appearance.accentColor)
              }
              Text(rule.pattern)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
              HStack {
                NativeAdaptiveBadge("排序 #\(rule.order)", tint: NativeTheme.info)
                if rule.minFileSizeMB > 0 {
                  NativeAdaptiveBadge("≥ \(rule.minFileSizeMB) MB", tint: NativeTheme.brand)
                }
                Spacer()
                Button("编辑") { editingEpisodeRule = rule }
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(appearance.accentColor)
                Button("删除", role: .destructive) {
                  episodeRules.removeAll { $0.id == rule.id }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.danger)
              }
            }
          }
        }
      }

      wordsGuidePanel(
        title: "规则编写提示",
        isExpanded: $showEpisodeRulesGuide,
        codeLines: [],
        notes: Self.episodeRuleGuideNotes
      )
    }
  }

  // MARK: - 5. 实时日志（Web 4 类正则结构化解析 + 严格级别筛选）

  private var filteredLogEntries: [NativeStructuredLogEntry] {
    let keyword = logFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return logEntries.filter { entry in
      if logLevel != .all {
        if logLevel == .error {
          guard entry.level == "ERROR" || entry.level == "CRITICAL" else { return false }
        } else {
          guard entry.level == logLevel.rawValue else { return false }
        }
      }
      if !keyword.isEmpty {
        return entry.searchableText.contains(keyword)
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
            .foregroundStyle(.secondary)
          TextField("过滤模块或日志关键字", text: $logFilter)
            .textFieldStyle(.plain)
            .font(.caption)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("native-diag-log-filter")
          if !logFilter.isEmpty {
            Button {
              logFilter = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-diag-log-clear-filter")
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
          NativeTheme.fieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.6)
        }

        Button {
          liveFollow.toggle()
        } label: {
          Label(
            liveFollow ? "跟随中" : "已暂停",
            systemImage: liveFollow ? "dot.radiowaves.left.and.right" : "pause.circle"
          )
          .font(.caption2.weight(.semibold))
          .foregroundStyle(liveFollow ? NativeTheme.success : NativeTheme.chipText)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(NativeTheme.chipFill, in: Capsule())
          .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
        }
        .buttonStyle(.plain)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(LogLevel.allCases) { level in
            Button {
              logLevel = level
            } label: {
              NativeAdaptivePill(
                level.rawValue,
                isSelected: logLevel == level,
                tint: logLevelTint(level.rawValue)
              )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-diag-log-level-\(level.rawValue)")
          }
          Text("\(filteredLogEntries.count) 条")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        }
      }

      if isLoadingLog && logEntries.isEmpty {
        NativeCardListSkeletonView(count: 6, style: .logLines)
          .transition(.opacity)
      } else if filteredLogEntries.isEmpty {
        emptyCard("暂无匹配的日志记录")
      } else {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(Array(filteredLogEntries.suffix(150).reversed())) { entry in
            let tint = logLevelTint(entry.level)
            CinematicPanel(padding: 11) {
              VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                  NativeAdaptiveBadge(entry.level, tint: tint)
                  if !entry.source.isEmpty {
                    Text(entry.source)
                      .font(.system(size: 11, weight: .semibold, design: .monospaced))
                      .foregroundStyle(NativeTheme.brand)
                      .lineLimit(1)
                  }
                  Spacer(minLength: 4)
                  if !entry.timestamp.isEmpty {
                    Text(entry.timestamp)
                      .font(.system(size: 10, design: .monospaced))
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }
                Text(entry.message)
                  .font(.system(size: 11.5, design: .monospaced))
                  .foregroundStyle(.primary.opacity(0.90))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .textSelection(.enabled)
              }
            }
          }
        }
        .accessibilityIdentifier("native-diag-log-output")
      }
    }
  }

  private func logLevelTint(_ level: String) -> Color {
    switch level.uppercased() {
    case "ERROR", "CRITICAL": NativeTheme.danger
    case "WARNING", "WARN": NativeTheme.warning
    case "INFO": NativeTheme.info
    case "DEBUG": NativeTheme.badgeMutedText
    default: appearance.accentColor
    }
  }

  // MARK: - 6. 定时服务（Web 图标色彩映射 + 系统/插件/工作流分类）

  private var filteredSchedules: [NativeDiagSchedule] {
    schedules.filter { item in
      let visual = NativeSchedulerVisualResolver.resolve(
        id: item.id, name: item.rawName, provider: item.provider ?? "")
      switch schedulerFilter {
      case .all: return true
      case .system: return visual.category == .system
      case .plugin: return visual.category == .plugin
      case .automation: return visual.category == .workflow || visual.category == .agent
      }
    }
  }

  private var schedulerContent: some View {
    VStack(alignment: .leading, spacing: 11) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          ForEach(SchedulerCategoryFilter.allCases) { option in
            Button {
              schedulerFilter = option
            } label: {
              NativeAdaptivePill(option.rawValue, isSelected: schedulerFilter == option)
            }
            .buttonStyle(.plain)
          }
        }
      }

      if isLoadingSchedules && schedules.isEmpty {
        NativeCardListSkeletonView(count: 5, style: .iconRow)
          .transition(.opacity)
      } else if filteredSchedules.isEmpty {
        emptyCard("暂无定时服务任务")
      } else {
        ForEach(filteredSchedules) { item in
          let isTriggering = runningJobID == item.id
          let visual = NativeSchedulerVisualResolver.resolve(
            id: item.id, name: item.rawName, provider: item.provider ?? "")
          CinematicPanel(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
              HStack(spacing: 12) {
                Image(systemName: item.isRunningNow ? "arrow.triangle.2.circlepath" : visual.symbol)
                  .font(.system(size: 20, weight: .medium))
                  .foregroundStyle(item.isRunningNow ? NativeTheme.success : visual.tint)
                  .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                  HStack(spacing: 6) {
                    Text(item.displayName)
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                    if let badge = visual.providerBadge {
                      NativeAdaptiveBadge(badge, tint: visual.tint)
                    }
                  }
                  HStack(spacing: 8) {
                    HStack(spacing: 4) {
                      Circle()
                        .fill(item.isRunningNow ? NativeTheme.success : NativeTheme.badgeMutedText)
                        .frame(width: 6, height: 6)
                      Text(item.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.isRunningNow ? NativeTheme.success : .secondary)
                    }
                    if let next = item.nextRunLabel, !next.isEmpty, !item.isRunningNow {
                      Text("下次：\(next)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }
                }
                Spacer(minLength: 4)

                Button {
                  Task { await triggerSchedule(item) }
                } label: {
                  HStack(spacing: 4) {
                    if isTriggering {
                      ProgressView().controlSize(.mini).tint(.white)
                    } else {
                      Image(systemName: "play.fill").font(.caption2)
                    }
                    Text("运行").font(.caption.weight(.semibold))
                  }
                  .foregroundStyle(.white)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 7)
                  .background(appearance.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(runningJobID != nil)
                .accessibilityIdentifier("native-diag-scheduler-\(item.id)")
              }

              if let frac = item.runningFraction {
                VStack(alignment: .leading, spacing: 4) {
                  ProgressView(value: frac)
                    .tint(NativeTheme.success)
                  if let txt = item.runningDetailText, !txt.isEmpty {
                    Text(txt)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  private func emptyCard(_ text: String) -> some View {
    CinematicPanel(padding: 16) {
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 80)
    }
  }

  // MARK: - 网络请求实现

  private func loadCurrentTool() async {
    switch tool {
    case .health:
      if modules.isEmpty { await runHealthCheck() }
    case .nettest:
      await loadNetTargets()
    case .ruleTest:
      async let groups: () = loadRuleGroups()
      async let sources: () = loadMediaSources()
      _ = await (groups, sources)
    case .words:
      await loadAllWords()
    case .liveLog:
      await fetchLiveLog(silent: false)
    case .scheduler:
      await loadSchedules()
    }
  }

  private func runHealthCheck() async {
    guard !isCheckingHealth else { return }
    isCheckingHealth = true
    healthProgress = 0
    healthFilter = .all
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
          modules[index].errorMessage = "模块检测请求失败"
        }
        modules[index].isTesting = false
        healthProgress = Double(index + 1) / Double(modules.count)
      }
    } catch {
      feedback = (true, "无法获取系统模块清单，请稍后重试。")
    }
  }

  private func loadNetTargets() async {
    isLoadingNet = true
    defer { isLoadingNet = false }
    do {
      let ep = try APIEndpoint(path: ["system", "nettest", "targets"])
      netTargets = try await session.request(
        ep, as: [NativeDiagNetTarget].self, requiring: PermissionRequirement(category: .admin)
      ).value
      if !netTargets.isEmpty, netResults.isEmpty {
        await runAllNetTests()
      }
    } catch is CancellationError {
      return
    } catch let urlError as URLError where urlError.code == .cancelled {
      return
    } catch {
      feedback = (true, "暂时无法载入网络测试目标。")
    }
  }

  private func runAllNetTests() async {
    guard !isTestingAllNet, !netTargets.isEmpty else { return }
    isTestingAllNet = true
    defer { isTestingAllNet = false }
    let targets = netTargets
    netResults = [:]
    for target in targets {
      if Task.isCancelled { break }
      await runNetTest(target)
    }
  }

  private func runNetTest(_ target: NativeDiagNetTarget) async {
    testingNetID = target.id
    defer { testingNetID = nil }
    do {
      let ep = try APIEndpoint(
        path: ["system", "nettest"],
        query: [URLQueryItem(name: "target_id", value: target.id)])
      let payload = try await session.request(
        ep, as: NativeDiagNetTime.self, requiring: PermissionRequirement(category: .admin)
      ).value
      let ms = Int((payload.time ?? 0).rounded())
      netResults[target.id] = NativeDiagNetResult(success: true, summary: "连通正常 · \(ms) ms")
    } catch {
      netResults[target.id] = NativeDiagNetResult(success: false, summary: "连接失败或超时")
    }
  }

  /// 加载识别数据源清单（`GET /api/v1/media/source`）。
  private func loadMediaSources() async {
    guard mediaSources.isEmpty else { return }
    do {
      let ep = try APIEndpoint(path: ["media", "source"])
      mediaSources = try await session.request(
        ep, as: [NativeDiagMediaSource].self, requiring: PermissionRequirement(category: .discovery)
      ).value
    } catch {
      return
    }
  }

  /// 优先通过 V3 `GET /api/v1/rule/groups?include_usage=false` 读取优先级规则组，兼容回退旧设置项。
  private func loadRuleGroups() async {
    if !ruleGroups.isEmpty { return }
    do {
      let ep = try APIEndpoint(
        path: ["rule", "groups"],
        query: [URLQueryItem(name: "include_usage", value: "false")])
      let payload = try await session.request(
        ep, as: NativeRuleGroupsQueryPayload.self,
        requiring: PermissionRequirement(category: .discovery)
      ).value
      let loaded = (payload.ruleGroups ?? []).filter { !$0.name.isEmpty }
      if !loaded.isEmpty {
        ruleGroups = loaded
        if selectedRuleGroup.isEmpty { selectedRuleGroup = loaded[0].name }
        return
      }
    } catch {
      // 回退到旧接口
    }
    do {
      let fallbackEp = try APIEndpoint(path: ["system", "setting", "UserFilterRuleGroups"])
      let wrapper = try await session.request(
        fallbackEp, as: NativeDiagSettingWrapper<[NativeDiagRuleGroup]>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      let loaded = (wrapper.value ?? []).filter { !$0.name.isEmpty }
      ruleGroups = loaded
      if selectedRuleGroup.isEmpty, let first = loaded.first {
        selectedRuleGroup = first.name
      }
    } catch {
      return
    }
  }

  /// 执行名称识别（`GET /api/v1/media/recognize`）或过滤规则测试（`GET /api/v1/system/ruletest`）。
  private func executeRecognitionOrRuleTest() async {
    let title = testTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let subtitle = testSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let customWords = testCustomWords.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    isRunningTest = true
    testErrorMessage = nil
    defer { isRunningTest = false }
    do {
      if testMode == .recognize {
        var query = [URLQueryItem(name: "title", value: title)]
        if !subtitle.isEmpty { query.append(URLQueryItem(name: "subtitle", value: subtitle)) }
        if !customWords.isEmpty {
          query.append(URLQueryItem(name: "custom_words", value: customWords))
        }
        if !selectedMediaSource.isEmpty {
          query.append(URLQueryItem(name: "media_source", value: selectedMediaSource))
        }
        let ep = try APIEndpoint(path: ["media", "recognize"], query: query, timeout: 60)
        let data = try await session.request(
          ep, as: NativeRecognizeContextPayload.self,
          requiring: PermissionRequirement(category: .discovery)
        ).value
        recognizeResult = NativeRecognizeDisplayResult(from: data)
      } else {
        var query = [
          URLQueryItem(name: "title", value: title),
          URLQueryItem(name: "rulegroup_name", value: selectedRuleGroup),
        ]
        if !subtitle.isEmpty { query.append(URLQueryItem(name: "subtitle", value: subtitle)) }
        let ep = try APIEndpoint(
          path: ["system", "ruletest"], query: query, responseContract: .payload, timeout: 45)
        let reply = try await session.request(
          ep, as: NativeDiagRawEnvelope<NativeRuleTestPayload>.self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        let data = reply.data
        let isMatched = (reply.success == true) && (data?.matched == true)
        var tags: [String] = []
        if let g = data?.rulegroupName, !g.isEmpty { tags.append("规则组：\(g)") }
        if let t = data?.metaInfo?.type, !t.isEmpty { tags.append(t) }
        if let se = data?.metaInfo?.seasonEpisode, !se.isEmpty { tags.append(se) }
        if let pix = data?.metaInfo?.resourcePix, !pix.isEmpty { tags.append(pix) }
        if let ed = data?.metaInfo?.edition, !ed.isEmpty { tags.append(ed) }
        if let team = data?.metaInfo?.resourceTeam, !team.isEmpty { tags.append(team) }
        ruleTestResult = NativeRuleTestDisplayResult(
          matched: isMatched,
          priority: data?.priority,
          subtitle: isMatched
            ? (data?.mediaInfo?.titleYear ?? data?.mediaInfo?.title ?? data?.metaInfo?.name ?? title)
            : (reply.message?.isEmpty == false ? reply.message! : "当前标题未通过所选优先级规则组"),
          tags: tags,
          ruleDetail: data?.rulegroup?.ruleString
        )
      }
    } catch {
      testErrorMessage = "测试请求失败或超时，请检查标题与服务连接状态。"
    }
  }

  /// 加载词表 5 大板块数据。
  private func loadAllWords() async {
    isLoadingWords = true
    defer { isLoadingWords = false }

    async let idResult: [String]? = {
      guard let ep = try? APIEndpoint(path: ["system", "identifiers"]) else { return nil }
      return try? await session.request(
        ep, as: NativeIdentifiersPayload.self, requiring: .init(category: .admin)
      ).value.identifiers
    }()
    async let rgResult: [String]? = readSettingList("CustomReleaseGroups")
    async let cuResult: [String]? = readSettingList("Customization")
    async let exResult: [String]? = readSettingList("TransferExcludeWords")
    async let epRulesResult: [NativeEpisodeFormatRule]? = {
      guard
        let ep = try? APIEndpoint(path: ["system", "setting", "public", "EpisodeFormatRuleTable"])
      else { return nil }
      return try? await session.request(
        ep, as: NativeDiagSettingWrapper<[NativeEpisodeFormatRule]>.self,
        requiring: .init(category: .admin)
      ).value.value
    }()

    let (ids, rgs, cus, exs, rules) = await (idResult, rgResult, cuResult, exResult, epRulesResult)
    if let ids {
      originalIdentifiers = ids
      identifiersText = ids.joined(separator: "\n")
    }
    if let rgs { releaseGroupsText = rgs.joined(separator: "\n") }
    if let cus { customizationText = cus.joined(separator: "\n") }
    if let exs { excludeWordsText = exs.joined(separator: "\n") }
    if let rules { episodeRules = rules }
  }

  private func readSettingList(_ key: String) async -> [String]? {
    guard let ep = try? APIEndpoint(path: ["system", "setting", key]) else { return nil }
    guard
      let raw = try? await session.request(
        ep, as: NativeDiagSettingWrapper<JSONValue>.self, requiring: .init(category: .admin)
      ).value.value
    else { return nil }
    switch raw {
    case .array(let items):
      return items.compactMap {
        if case .string(let s) = $0 { return s }
        return nil
      }
    case .string(let text):
      return text.split(whereSeparator: \.isNewline).map(String.init)
    default:
      return []
    }
  }

  private func saveCurrentWordsTab() async {
    isSavingWords = true
    defer { isSavingWords = false }
    do {
      switch wordsTab {
      case .identifiers:
        let lines = Self.nonEmptyLines(identifiersText)
        let payload = NativeIdentifiersUpdateRequest(
          identifiers: lines, expectedIdentifiers: originalIdentifiers)
        let body = try JSONEncoder().encode(payload)
        let ep = try APIEndpoint(path: ["system", "identifiers"], method: .post, body: body)
        try await session.perform(ep, requiring: .init(category: .admin))
        originalIdentifiers = lines
        feedback = (false, "已保存自定义识别词（\(lines.count) 条）。")
      case .releaseGroups:
        let lines = Self.nonEmptyLines(releaseGroupsText)
        let body = try JSONEncoder().encode(lines)
        let ep = try APIEndpoint(
          path: ["system", "setting", "CustomReleaseGroups"], method: .post, body: body)
        try await session.perform(ep, requiring: .init(category: .admin))
        feedback = (false, "已保存自定义制作组（\(lines.count) 条）。")
      case .customization:
        let lines = Self.nonEmptyLines(customizationText)
        let body = try JSONEncoder().encode(lines)
        let ep = try APIEndpoint(
          path: ["system", "setting", "Customization"], method: .post, body: body)
        try await session.perform(ep, requiring: .init(category: .admin))
        feedback = (false, "已保存自定义占位符（\(lines.count) 条）。")
      case .excludeWords:
        let lines = Self.nonEmptyLines(excludeWordsText)
        let body = try JSONEncoder().encode(lines)
        let ep = try APIEndpoint(
          path: ["system", "setting", "TransferExcludeWords"], method: .post, body: body)
        try await session.perform(ep, requiring: .init(category: .admin))
        feedback = (false, "已保存整理屏蔽词（\(lines.count) 条）。")
      case .episodeRules:
        let body = try JSONEncoder().encode(episodeRules)
        let ep = try APIEndpoint(
          path: ["system", "setting", "EpisodeFormatRuleTable"], method: .post, body: body)
        try await session.perform(ep, requiring: .init(category: .admin))
        feedback = (false, "已保存剧集识别规则（\(episodeRules.count) 条）。")
      }
    } catch {
      feedback = (true, "保存词表失败，请检查格式或权限后重试。")
    }
  }

  private static func nonEmptyLines(_ text: String) -> [String] {
    text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// 拉取实时日志并通过 4 类正则结构化解析时间戳、级别、来源模块与正文。
  private func fetchLiveLog(silent: Bool) async {
    if !silent {
      isLoadingLog = true
      feedback = nil
    }
    defer { if !silent { isLoadingLog = false } }
    do {
      let ep = try APIEndpoint(
        path: ["system", "logging"],
        query: [
          URLQueryItem(name: "length", value: "-1"),
          URLQueryItem(name: "logfile", value: logfile),
        ],
        responseContract: .plainText,
        maximumResponseBytes: 16 * 1024 * 1024)
      let raw = try await session.requestResourcePayload(
        ep, requiring: PermissionRequirement(category: .admin)
      ).value
      let text = String(decoding: raw, as: UTF8.self)
      let rawLines = text.split(whereSeparator: \.isNewline).map(String.init)
      // 全文快照已倒序，取最新行后还原时间顺序，供解析器归并多行日志。
      logEntries = NativeLogParser.parse(Array(rawLines.prefix(400).reversed()))
    } catch is CancellationError {
      return
    } catch let urlError as URLError where urlError.code == .cancelled {
      return
    } catch {
      if !silent { feedback = (true, "无法读取实时日志，请确认管理员权限与日志文件状态。") }
    }
  }

  private func loadSchedules() async {
    isLoadingSchedules = true
    defer { isLoadingSchedules = false }
    do {
      let ep = try APIEndpoint(path: ["dashboard", "schedule"])
      schedules = try await session.request(
        ep, as: [NativeDiagSchedule].self, requiring: PermissionRequirement(category: .admin)
      ).value
      if feedback?.isError == true {
        feedback = nil
      }
    } catch is CancellationError {
      return
    } catch let urlError as URLError where urlError.code == .cancelled {
      return
    } catch {
      feedback = (true, "无法读取定时服务清单。")
    }
  }

  private func triggerSchedule(_ item: NativeDiagSchedule) async {
    runningJobID = item.id
    defer { runningJobID = nil }
    do {
      let ep = try APIEndpoint(
        path: ["system", "runscheduler"],
        query: [URLQueryItem(name: "jobid", value: item.id)])
      try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
      feedback = (false, "已触发定时服务「\(item.displayName)」。")
      await loadSchedules()
    } catch {
      feedback = (true, "触发定时服务失败，请稍后重试。")
    }
  }
}

// MARK: - 剧集识别规则编辑弹窗

@MainActor
private struct NativeEpisodeRuleEditorSheet: View {
  @State private var rule: NativeEpisodeFormatRule
  let onSave: (NativeEpisodeFormatRule) -> Void
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  init(rule: NativeEpisodeFormatRule, onSave: @escaping (NativeEpisodeFormatRule) -> Void) {
    _rule = State(initialValue: rule)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
              Text("规则参数")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  settingRow(
                    "规则名称",
                    placeholder: "输入规则名称",
                    text: $rule.name
                  )
                  CinematicFormDivider()
                  settingRow(
                    "正则表达式",
                    placeholder: "^.*\\[(?<ep>\\d{2,3})\\].*$",
                    text: $rule.pattern,
                    monospaced: true
                  )
                  CinematicFormDivider()
                  HStack {
                    Text("排序优先级")
                      .font(.subheadline)
                      .foregroundStyle(.primary)
                    Spacer()
                    Stepper("\(rule.order)", value: $rule.order, in: 1...999)
                      .font(.subheadline.monospacedDigit())
                      .fixedSize()
                  }
                  .padding(.horizontal, 15)
                  .padding(.vertical, 9)
                  CinematicFormDivider()
                  HStack {
                    Text("最小大小")
                      .font(.subheadline)
                      .foregroundStyle(.primary)
                    Spacer()
                    Stepper(
                      "\(rule.minFileSizeMB) MB",
                      value: $rule.minFileSizeMB,
                      in: 0...10000,
                      step: 10
                    )
                    .font(.subheadline.monospacedDigit())
                    .fixedSize()
                  }
                  .padding(.horizontal, 15)
                  .padding(.vertical, 9)
                  CinematicFormDivider()
                  Toggle("启用此规则", isOn: $rule.enabled)
                    .font(.subheadline)
                    .tint(appearance.accentColor)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                }
              }

              Text("正则表达式必须包含 (?<ep>...) 命名组；小于最小大小的文件将不参与匹配。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            CinematicPanel(padding: 14) {
              VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                  Image(systemName: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                  Text("规则编写提示")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                }
                Text("从上到下依次匹配，第一个匹配的则使用该规则。")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text("固定文本直接匹配，集数必须使用命名分组 (?<ep>...) 标记；其余不固定但需保留位置的内容可用 (?<a>...)、(?<b>...) 承接。")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text("如需按字面量匹配 [](). 等特殊字符，请进行转义；建议使用 ^ 和 $ 完整约束整条文件名，其中 $ 尤其重要，可避免只匹配前半段就被误判为命中。")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
      }
      .navigationTitle(rule.name.isEmpty ? "新增剧集规则" : "编辑剧集规则")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("确定") {
            onSave(rule)
            dismiss()
          }
          .fontWeight(.semibold)
          .tint(.primary)
          .disabled(
            rule.name.trimmingCharacters(in: .whitespaces).isEmpty
              || rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .nativeGlassSheet()
  }

  private func settingRow(
    _ label: String,
    placeholder: String,
    text: Binding<String>,
    monospaced: Bool = false
  ) -> some View {
    HStack(spacing: 12) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .layoutPriority(1)
      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(monospaced)
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 12)
  }
}

// MARK: - 结构化日志解析器（严格对标 Web LoggingView.vue 4 类格式）

private struct NativeStructuredLogEntry: Identifiable {
  let id: Int
  let level: String
  let timestamp: String
  let source: String
  var message: String

  var searchableText: String {
    "\(level) \(timestamp) \(source) \(message)".lowercased()
  }
}

private enum NativeLogParser {
  private static let supportedLevels: Set<String> = [
    "TRACE", "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL",
  ]
  private static let ansiRegex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[a-zA-Z]")
  private static let timestampRegex = try? NSRegularExpression(
    pattern: #"\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?)?"#)

  // 1) Python 风格：INFO:     [MoviePilot] 2026-11-21 17:30:12,123 system.py - 消息
  private static let pythonPrefixRegex = try? NSRegularExpression(
    pattern: #"^([A-Za-z]+):\s+(.*)$"#)
  // 2) 中文方括号风格：【INFO】2026-11-21 17:30:12,123 system.py - 消息
  private static let cnBracketPrefixRegex = try? NSRegularExpression(
    pattern: #"^【([^】]+)】\s*(.*)$"#)
  // 1/2 通用结构化正文：可选 [appName] + 严格 YYYY-MM-DD HH:MM:SS(,mmm) + 可选 [correlation_id] (如 [-]) + 可选 "- " + 非括号模块来源 + " - " + 消息
  private static let structuredBodyRegex = try? NSRegularExpression(
    pattern:
      #"^(?:\[([^\]]+)\]\s+)?(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d{3})?)\s+(?:\[[^\]]+\]\s+)?(?:-\s+)?([^\s\[\]]+)\s+-\s+(.*)$"#
  )
  // 3) 时间戳开头：2026-11-21 17:30:12,123 [INFO] [-] - system.py - 消息
  private static let timestampFirstRegex = try? NSRegularExpression(
    pattern:
      #"^(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?)?)\s+\[?([A-Za-z]+)\]?\s*(.*)$"#
  )
  // 4) 内联级别开头：[INFO] 2026-11-21 17:30:12 [-] - system.py - 消息
  private static let inlineLevelRegex = try? NSRegularExpression(
    pattern: #"^\[?([A-Za-z]+)\]?:?\s+(.*)$"#)
  // 3/4 去时间戳后正文：可选 [appName/cid] + 可选 "- " + 非括号模块来源 + " - " + 消息
  private static let sourceDashBodyRegex = try? NSRegularExpression(
    pattern: #"^(?:\[([^\]]+)\]\s+)?(?:-\s+)?([^\s\[\]]+)\s+-\s+(.*)$"#)
  // 去除回退正文前导的关联 ID 占位符（如 [-] - ）
  private static let leadingCidPrefixRegex = try? NSRegularExpression(
    pattern: #"^(?:\[[^\]]+\]\s+)?(?:-\s+)?"#)
  // 非结构化正文的 " - " 分隔回退（对标 Web extractMessage）
  private static let dashSeparatorRegex = try? NSRegularExpression(pattern: #"\s+-\s+"#)

  static func parse(_ rawLines: [String]) -> [NativeStructuredLogEntry] {
    var entries: [NativeStructuredLogEntry] = []
    var nextID = 0
    for raw in rawLines {
      let cleaned = stripANSI(raw).replacingOccurrences(of: "\r", with: "")
      let trimmedEnd = cleaned.replacingOccurrences(
        of: #"\s+$"#, with: "", options: .regularExpression)
      if trimmedEnd.trimmingCharacters(in: .whitespaces).isEmpty { continue }
      if let parsed = parseSingleLine(trimmedEnd, id: nextID) {
        entries.append(parsed)
        nextID += 1
      } else if !entries.isEmpty {
        // 堆栈或 Agent 多行消息续行归并到上一条日志
        entries[entries.count - 1].message += "\n" + trimmedEnd
      } else {
        entries.append(
          NativeStructuredLogEntry(
            id: nextID, level: "INFO", timestamp: extractTimestamp(trimmedEnd), source: "",
            message: trimmedEnd))
        nextID += 1
      }
    }
    return entries
  }

  private static func stripANSI(_ s: String) -> String {
    guard let ansiRegex else { return s }
    let range = NSRange(s.startIndex..<s.endIndex, in: s)
    return ansiRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
  }

  private static func normalizeLevel(_ raw: String) -> String {
    let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ":", with: "")
      .uppercased()
    switch upper {
    case "WARN", "WARNING": return "WARNING"
    case "FATAL", "CRITICAL": return "CRITICAL"
    case "ERR", "ERROR": return "ERROR"
    case "DEBUG": return "DEBUG"
    case "INFO": return "INFO"
    case "TRACE": return "TRACE"
    default: return upper
    }
  }

  private static func extractTimestamp(_ text: String) -> String {
    guard let timestampRegex else { return "" }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = timestampRegex.firstMatch(in: text, range: range) else { return "" }
    return shortTimestamp(ns.substring(with: match.range))
  }

  private static func extractFallbackMessage(_ text: String) -> String {
    guard let dashSeparatorRegex else { return text }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = dashSeparatorRegex.firstMatch(in: text, range: range) else { return text }
    let after = match.range.location + match.range.length
    guard after < ns.length else { return text }
    let rest = ns.substring(from: after).trimmingCharacters(in: .whitespaces)
    return rest.isEmpty ? text : rest
  }

  private static func matchGroups(_ regex: NSRegularExpression?, in text: String) -> [String]? {
    guard let regex else { return nil }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    return (1..<match.numberOfRanges).map { idx in
      let r = match.range(at: idx)
      return r.location != NSNotFound
        ? ns.substring(with: r).trimmingCharacters(in: .whitespaces) : ""
    }
  }

  private static func parseSingleLine(_ line: String, id: Int) -> NativeStructuredLogEntry? {
    if let entry = parsePythonStyle(line, id: id) { return entry }
    if let entry = parseBracketStyle(line, id: id) { return entry }
    if let entry = parseTimestampFirst(line, id: id) { return entry }
    if let entry = parseInlineLevel(line, id: id) { return entry }
    return nil
  }

  private static func parsePythonStyle(_ line: String, id: Int) -> NativeStructuredLogEntry? {
    guard let g = matchGroups(pythonPrefixRegex, in: line), g.count >= 2 else { return nil }
    let level = normalizeLevel(g[0])
    guard supportedLevels.contains(level) else { return nil }
    return buildFromStructuredRemainder(level: level, remainder: g[1], id: id)
  }

  private static func parseBracketStyle(_ line: String, id: Int) -> NativeStructuredLogEntry? {
    guard let g = matchGroups(cnBracketPrefixRegex, in: line), g.count >= 2 else { return nil }
    let level = normalizeLevel(g[0])
    return buildFromStructuredRemainder(level: level, remainder: g[1], id: id)
  }

  private static func stripLeadingCidPrefix(_ text: String) -> String {
    guard let leadingCidPrefixRegex else { return text }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return leadingCidPrefixRegex.stringByReplacingMatches(
      in: text, range: range, withTemplate: ""
    ).trimmingCharacters(in: .whitespaces)
  }

  private static func formatSource(appName: String, source: String) -> String {
    let cleanApp = appName.trimmingCharacters(in: .whitespaces)
    let cleanSource = source.trimmingCharacters(in: .whitespaces)
    // 忽略无意义的关联 ID 占位符（如 [-]）
    guard !cleanApp.isEmpty, cleanApp != "-" else { return cleanSource }
    return cleanSource.isEmpty ? "[\(cleanApp)]" : "[\(cleanApp)] \(cleanSource)"
  }

  private static func buildFromStructuredRemainder(
    level: String, remainder: String, id: Int
  ) -> NativeStructuredLogEntry {
    let body = remainder.trimmingCharacters(in: .whitespaces)
    if let bg = matchGroups(structuredBodyRegex, in: body), bg.count >= 4 {
      let ts = shortTimestamp(bg[1])
      let source = formatSource(appName: bg[0], source: bg[2])
      return NativeStructuredLogEntry(
        id: id, level: level, timestamp: ts, source: source, message: bg[3])
    }
    let ts = extractTimestamp(body)
    let withoutTS =
      ts.isEmpty
      ? body
      : body.replacingOccurrences(
        of: #"\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?)?"#,
        with: "", options: .regularExpression
      ).trimmingCharacters(in: .whitespaces)
    if let sg = matchGroups(sourceDashBodyRegex, in: withoutTS), sg.count >= 3 {
      let source = formatSource(appName: sg[0], source: sg[1])
      return NativeStructuredLogEntry(
        id: id, level: level, timestamp: ts, source: source, message: sg[2])
    }
    let cleanedFallback = stripLeadingCidPrefix(withoutTS.isEmpty ? body : withoutTS)
    return NativeStructuredLogEntry(
      id: id, level: level, timestamp: ts, source: "",
      message: extractFallbackMessage(cleanedFallback.isEmpty ? body : cleanedFallback))
  }

  private static func parseTimestampFirst(_ line: String, id: Int) -> NativeStructuredLogEntry? {
    guard let g = matchGroups(timestampFirstRegex, in: line), g.count >= 3 else { return nil }
    let level = normalizeLevel(g[1])
    guard supportedLevels.contains(level) else { return nil }
    let ts = shortTimestamp(g[0])
    let body = g[2].trimmingCharacters(in: .whitespaces)
    if let sg = matchGroups(sourceDashBodyRegex, in: body), sg.count >= 3 {
      let source = formatSource(appName: sg[0], source: sg[1])
      return NativeStructuredLogEntry(
        id: id, level: level, timestamp: ts, source: source, message: sg[2])
    }
    let cleaned = stripLeadingCidPrefix(body)
    return NativeStructuredLogEntry(
      id: id, level: level, timestamp: ts, source: "",
      message: extractFallbackMessage(cleaned.isEmpty ? body : cleaned))
  }

  private static func parseInlineLevel(_ line: String, id: Int) -> NativeStructuredLogEntry? {
    guard let g = matchGroups(inlineLevelRegex, in: line), g.count >= 2 else { return nil }
    let level = normalizeLevel(g[0])
    guard supportedLevels.contains(level) else { return nil }
    return buildFromStructuredRemainder(level: level, remainder: g[1], id: id)
  }

  private static func shortTimestamp(_ raw: String) -> String {
    var trimmed = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "T", with: " ")
    if let comma = trimmed.firstIndex(of: ",") {
      trimmed = String(trimmed[..<comma])
    } else if let dot = trimmed.firstIndex(of: ".") {
      trimmed = String(trimmed[..<dot])
    }
    return trimmed
  }
}

// MARK: - 解码与展示模型

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

private struct NativeDiagMediaSource: Decodable, Sendable, Identifiable {
  let name: String?
  let mediaSource: String

  var id: String { mediaSource }
  var displayName: String { (name?.isEmpty == false ? name! : mediaSource) }

  private enum CodingKeys: String, CodingKey {
    case name
    case mediaSource = "media_source"
  }
}

private struct NativeRuleGroupsQueryPayload: Decodable, Sendable {
  let ruleGroups: [NativeDiagRuleGroup]?
  private enum CodingKeys: String, CodingKey {
    case ruleGroups = "rule_groups"
  }
}

private struct NativeDiagRuleGroup: Decodable, Sendable, Identifiable {
  let name: String
  let ruleString: String?
  let mediaType: String?
  let category: String?

  var id: String { name }

  private enum CodingKeys: String, CodingKey {
    case name, category
    case ruleString = "rule_string"
    case mediaType = "media_type"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    ruleString = try? c.decode(String.self, forKey: .ruleString)
    mediaType = try? c.decode(String.self, forKey: .mediaType)
    category = try? c.decode(String.self, forKey: .category)
  }
}

private struct NativeDiagMetaBrief: Decodable, Sendable {
  let name: String?
  let cnName: String?
  let enName: String?
  let type: String?
  let year: String?
  let seasonEpisode: String?
  let resourcePix: String?
  let resourceType: String?
  let edition: String?
  let videoEncode: String?
  let audioEncode: String?
  let resourceTeam: String?
  let applyWords: [String]?

  private enum CodingKeys: String, CodingKey {
    case name, type, year, edition
    case cnName = "cn_name"
    case enName = "en_name"
    case seasonEpisode = "season_episode"
    case resourcePix = "resource_pix"
    case resourceType = "resource_type"
    case videoEncode = "video_encode"
    case audioEncode = "audio_encode"
    case resourceTeam = "resource_team"
    case applyWords = "apply_words"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try? c.decode(String.self, forKey: .name)
    cnName = try? c.decode(String.self, forKey: .cnName)
    enName = try? c.decode(String.self, forKey: .enName)
    type = try? c.decode(String.self, forKey: .type)
    year =
      (try? c.decode(String.self, forKey: .year))
      ?? (try? String(c.decode(Int.self, forKey: .year)))
    seasonEpisode = try? c.decode(String.self, forKey: .seasonEpisode)
    resourcePix = try? c.decode(String.self, forKey: .resourcePix)
    resourceType = try? c.decode(String.self, forKey: .resourceType)
    edition = try? c.decode(String.self, forKey: .edition)
    videoEncode = try? c.decode(String.self, forKey: .videoEncode)
    audioEncode = try? c.decode(String.self, forKey: .audioEncode)
    resourceTeam = try? c.decode(String.self, forKey: .resourceTeam)
    applyWords = try? c.decode([String].self, forKey: .applyWords)
  }
}

private struct NativeDiagMediaBrief: Decodable, Sendable {
  let title: String?
  let titleYear: String?
  let type: String?
  let category: String?
  let mediaSource: String?
  let mediaID: String?
  let tmdbID: String?
  let overview: String?
  let posterPath: String?
  let voteAverage: Double?

  private enum CodingKeys: String, CodingKey {
    case title, type, category, overview
    case titleYear = "title_year"
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdb_id"
    case posterPath = "poster_path"
    case voteAverage = "vote_average"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = try? c.decode(String.self, forKey: .title)
    titleYear = try? c.decode(String.self, forKey: .titleYear)
    type = try? c.decode(String.self, forKey: .type)
    category = try? c.decode(String.self, forKey: .category)
    mediaSource = try? c.decode(String.self, forKey: .mediaSource)
    mediaID =
      (try? c.decode(String.self, forKey: .mediaID))
      ?? (try? String(c.decode(Int64.self, forKey: .mediaID)))
    tmdbID =
      (try? c.decode(String.self, forKey: .tmdbID))
      ?? (try? String(c.decode(Int64.self, forKey: .tmdbID)))
    overview = try? c.decode(String.self, forKey: .overview)
    posterPath = try? c.decode(String.self, forKey: .posterPath)
    voteAverage = try? c.decode(Double.self, forKey: .voteAverage)
  }
}

private struct NativeRecognizeContextPayload: Decodable, Sendable {
  let metaInfo: NativeDiagMetaBrief?
  let mediaInfo: NativeDiagMediaBrief?

  private enum CodingKeys: String, CodingKey {
    case metaInfo = "meta_info"
    case mediaInfo = "media_info"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    metaInfo = try? c.decode(NativeDiagMetaBrief.self, forKey: .metaInfo)
    mediaInfo = try? c.decode(NativeDiagMediaBrief.self, forKey: .mediaInfo)
  }
}

private struct NativeRecognizeDisplayResult {
  struct MetaField {
    let label: String
    let value: String
  }

  let matched: Bool
  let headline: String
  let mediaType: String?
  let mediaSource: String?
  let category: String?
  let voteAverage: Double?
  let overview: String?
  let posterPath: String?
  let detailIdentity: NativeMediaIdentity?
  let metaFields: [MetaField]
  let applyWords: [String]

  init(from payload: NativeRecognizeContextPayload) {
    let media = payload.mediaInfo
    let meta = payload.metaInfo
    matched = media != nil && (media?.title?.isEmpty == false || media?.titleYear?.isEmpty == false)
    headline =
      media?.titleYear ?? media?.title ?? meta?.name ?? meta?.cnName ?? meta?.enName ?? "未识别到匹配媒体"
    mediaType = media?.type ?? meta?.type
    mediaSource = media?.mediaSource
    category = media?.category
    voteAverage = media?.voteAverage
    overview = media?.overview
    posterPath = media?.posterPath
    if let src = media?.mediaSource, !src.isEmpty,
      let mid = (media?.mediaID?.isEmpty == false ? media?.mediaID : media?.tmdbID),
      let typ = media?.type, typ != "音乐"
    {
      detailIdentity = NativeMediaIdentity(source: src, mediaID: mid, type: typ)
    } else {
      detailIdentity = nil
    }
    var fields: [MetaField] = []
    if let v = meta?.name, !v.isEmpty { fields.append(.init(label: "提取名称", value: v)) }
    if let v = meta?.cnName, !v.isEmpty { fields.append(.init(label: "中文名", value: v)) }
    if let v = meta?.enName, !v.isEmpty { fields.append(.init(label: "英文名", value: v)) }
    if let v = meta?.year, !v.isEmpty { fields.append(.init(label: "年份", value: v)) }
    if let v = meta?.seasonEpisode, !v.isEmpty { fields.append(.init(label: "季 / 集", value: v)) }
    if let v = meta?.resourcePix, !v.isEmpty { fields.append(.init(label: "分辨率", value: v)) }
    if let v = meta?.edition ?? meta?.resourceType, !v.isEmpty {
      fields.append(.init(label: "质量版本", value: v))
    }
    if let v = meta?.videoEncode, !v.isEmpty { fields.append(.init(label: "视频编码", value: v)) }
    if let v = meta?.audioEncode, !v.isEmpty { fields.append(.init(label: "音频编码", value: v)) }
    if let v = meta?.resourceTeam, !v.isEmpty { fields.append(.init(label: "制作组", value: v)) }
    metaFields = fields
    applyWords = meta?.applyWords ?? []
  }
}

private struct NativeRuleTestPayload: Decodable, Sendable {
  let matched: Bool?
  let priority: Int?
  let rulegroupName: String?
  let rulegroup: NativeDiagRuleGroup?
  let metaInfo: NativeDiagMetaBrief?
  let mediaInfo: NativeDiagMediaBrief?

  private enum CodingKeys: String, CodingKey {
    case matched, priority, rulegroup
    case rulegroupName = "rulegroup_name"
    case metaInfo = "meta_info"
    case mediaInfo = "media_info"
  }
}

private struct NativeRuleTestDisplayResult {
  let matched: Bool
  let priority: Int?
  let subtitle: String
  let tags: [String]
  let ruleDetail: String?
}

private struct NativeIdentifiersPayload: Decodable, Sendable {
  let identifiers: [String]?
}

private struct NativeIdentifiersUpdateRequest: Encodable, Sendable {
  let identifiers: [String]
  let expectedIdentifiers: [String]?

  private enum CodingKeys: String, CodingKey {
    case identifiers
    case expectedIdentifiers = "expected_identifiers"
  }
}

private struct NativeEpisodeFormatRule: Codable, Sendable, Identifiable {
  var id: String { "\(name)|\(pattern)|\(order)" }
  var name: String
  var enabled: Bool
  var order: Int
  var pattern: String
  var minFileSizeMB: Int

  private enum CodingKeys: String, CodingKey {
    case name, enabled, order, pattern
    case minFileSizeMB = "min_file_size_mb"
  }

  init(name: String, enabled: Bool, order: Int, pattern: String, minFileSizeMB: Int) {
    self.name = name
    self.enabled = enabled
    self.order = order
    self.pattern = pattern
    self.minFileSizeMB = minFileSizeMB
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    order = (try? c.decode(Int.self, forKey: .order)) ?? 1
    pattern = (try? c.decode(String.self, forKey: .pattern)) ?? ""
    minFileSizeMB = (try? c.decode(Int.self, forKey: .minFileSizeMB)) ?? 0
  }
}

private struct NativeDiagSchedule: Decodable, Sendable, Identifiable {
  struct ProgressDetail: Decodable, Sendable {
    let enable: Bool?
    let status: String?
    let value: Double?
    let text: String?
    let textI18n: String?
    private enum CodingKeys: String, CodingKey {
      case enable, status, value, text
      case textI18n = "text_i18n"
    }
  }

  let id: String
  let name: String?
  let nameI18n: String?
  let provider: String?
  let status: String?
  let statusI18n: String?
  let nextRun: String?
  let nextRunI18n: String?
  let progress: Double?
  let progressEnable: Bool?
  let progressText: String?
  let progressTextI18n: String?
  let progressDetail: ProgressDetail?

  var rawName: String { name ?? id }

  var displayName: String {
    if let nameI18n, !nameI18n.isEmpty { return nameI18n }
    if let name, !name.isEmpty { return name }
    return id
  }

  var isRunningNow: Bool {
    (status ?? "").lowercased().contains("run") || (status ?? "").contains("运行")
      || progressEnable == true || progressDetail?.enable == true
      || progressDetail?.status == "running"
  }

  var statusLabel: String {
    if let statusI18n, !statusI18n.isEmpty { return statusI18n }
    if let status, !status.isEmpty { return status }
    return "等待"
  }

  var nextRunLabel: String? {
    if let nextRunI18n, !nextRunI18n.isEmpty { return nextRunI18n }
    return nextRun
  }

  var runningFraction: Double? {
    guard isRunningNow, let val = progressDetail?.value ?? progress, val.isFinite else {
      return nil
    }
    return min(100, max(0, val)) / 100
  }

  var runningDetailText: String? {
    progressDetail?.textI18n ?? progressDetail?.text ?? progressTextI18n ?? progressText
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, provider, status, progress
    case nameI18n = "name_i18n"
    case statusI18n = "status_i18n"
    case nextRun = "next_run"
    case nextRunI18n = "next_run_i18n"
    case progressEnable = "progress_enable"
    case progressText = "progress_text"
    case progressTextI18n = "progress_text_i18n"
    case progressDetail = "progress_detail"
  }
}
