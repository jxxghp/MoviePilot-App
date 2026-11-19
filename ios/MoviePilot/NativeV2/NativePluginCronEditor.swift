import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotPluginUI
import SwiftUI

/// Cron 仍是可直接输入的原生文本字段，计划按钮打开独立草稿，不触发网络保存。
@MainActor
struct NativePluginCronField: View {
  let field: NativeFormField
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void
  let edit: () -> Void

  /// 说明/清除/计划动作与现有表单共享一块玻璃，不堆叠额外重玻璃层。
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(field.label).font(.subheadline).foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 6) {
        TextField(
          field.label, text: binding,
          prompt: Text(field.placeholder).foregroundColor(.white.opacity(0.70))
        )
        .font(.system(.body, design: .monospaced))
        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
        .accessibilityIdentifier("native-plugin-field-" + field.key)
        if !field.suffix.isEmpty { Text(field.suffix).foregroundStyle(.secondary) }
        if field.clearable, !field.text.isEmpty {
          Button {
            update(.null, field.key)
          } label: {
            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
          }.buttonStyle(.plain).accessibilityLabel(L10n.text("清除"))
            .accessibilityIdentifier("native-plugin-cron-clear-" + field.key)
        }
        Button(action: edit) {
          Image(systemName: "calendar.badge.clock").frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(L10n.text("编辑计划"))
          .accessibilityIdentifier("native-plugin-cron-edit-" + field.key)
      }
      if !field.hint.isEmpty { Text(field.hint).font(.caption).foregroundStyle(.secondary) }
    }.padding(.vertical, 3).disabled(field.disabled)
  }

  /// 连续输入始终读取最新完整草稿，保留数字/空值直到用户真正编辑。
  private var binding: Binding<String> {
    Binding(
      get: { NativeFormField.text(from: read(field.key)) }, set: { update(.string($0), field.key) })
  }
}

/// 原生计划弹层只编辑内存中的原文，应用才回写父表单，取消完全不影响父草稿。
@MainActor
struct NativePluginCronEditor: View {
  let field: NativeFormField
  let apply: (String) -> Void
  private let initialText: String
  @State private var expression: String
  @State private var path: [NativeCronUnit] = []
  @Environment(\.dismiss) private var dismiss

  /// 保留调用时的确切文本；原样应用不会把 nil/null/数字转换成空字符串或默认值。
  init(field: NativeFormField, value: PluginJSONValue?, apply: @escaping (String) -> Void) {
    self.field = field
    self.apply = apply
    let text = NativeFormField.text(from: value)
    initialText = text
    _expression = State(initialValue: text)
  }

  /// 五字段编辑、预设与自定义输入都承载在同一 Rex 渐变和原生导航中。
  var body: some View {
    NavigationStack(path: $path) {
      ZStack {
        CinematicBackground()
        Form {
          CinematicFormSection(L10n.text("表达式"), footer: guidance) {
            CinematicFormRow {
              TextField(
                L10n.text("完整表达式"), text: $expression,
                prompt: Text(field.placeholder).foregroundColor(.white.opacity(0.70))
              )
              .font(.system(.body, design: .monospaced))
              .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(
                .asciiCapable
              )
              .accessibilityIdentifier("native-cron-expression")
            }
          }
          CinematicFormSection {
            CinematicFormRow {
              Menu {
                ForEach(NativeCronPreset.allCases) { preset in
                  Button(NativeCronLabels.preset(preset)) {
                    expression = preset.expression
                    NativeCronLabels.endEditing()
                  }
                  .accessibilityIdentifier("native-cron-preset-" + preset.id)
                }
              } label: {
                Label(L10n.text("常用计划"), systemImage: "clock.arrow.circlepath")
                  .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(
                    Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("native-cron-presets")
            }
          }
          if let fields = NativeCronExpression(expression).fields {
            CinematicFormSection(L10n.text("字段"), footer: L10n.text("执行时间以服务器和插件的时区为准。")) {
              ForEach(NativeCronUnit.allCases) { unit in
                if unit != .minute { CinematicFormDivider() }
                CinematicFormRow {
                  Button {
                    NativeCronLabels.endEditing()
                    path.append(unit)
                  } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                      Text(NativeCronLabels.unit(unit))
                      Spacer(minLength: 8)
                      Text(fields[unit.index]).font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary).multilineTextAlignment(.trailing).lineLimit(2)
                      Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                  }.buttonStyle(.plain).accessibilityIdentifier("native-cron-unit-" + unit.id)
                }
              }
            }
          }
          if field.clearable {
            CinematicFormSection {
              CinematicFormRow {
                Button(L10n.text("清空表达式")) { expression = "" }.frame(minHeight: 44)
                  .accessibilityIdentifier("native-cron-empty")
              }
            }
          }
        }.scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
          .frame(maxWidth: 680).accessibilityIdentifier("native-cron-form")
      }
      .navigationTitle(field.label).navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationDestination(for: NativeCronUnit.self) { unit in
        if let fields = NativeCronExpression(expression).fields {
          NativeCronFieldEditor(unit: unit, token: fields[unit.index]) { token in
            if let changed = try? NativeCronExpression(expression).replacing(unit, with: token) {
              expression = changed
            }
          }.id(unit)
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("取消")) { dismiss() }.accessibilityIdentifier("native-cron-cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("应用")) {
            NativeCronLabels.endEditing()
            if !expression.utf8.elementsEqual(initialText.utf8) { apply(expression) }
            dismiss()
          }.accessibilityIdentifier("native-cron-apply")
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(L10n.text("完成")) { NativeCronLabels.endEditing() }
        }
      }
    }.tint(.white)
  }

  /// 格式说明不是全局保存校验，不将合法插件自定义值误判为不可保存。
  private var guidance: String {
    switch NativeCronExpression(expression).format {
    case .empty: L10n.text("留空时由插件决定执行规则。")
    case .fiveFields: L10n.text("五段顺序：分、时、日、月、周。")
    case .custom: L10n.text("自定义值会原样交给插件处理。")
    }
  }
}

/// 五字段共用的原生规则页，选值/范围/间隔都是本地草稿，返回取消不改变表达式。
@MainActor
private struct NativeCronFieldEditor: View {
  let apply: (String) -> Void
  @State private var draft: NativeCronFieldDraft
  @State private var selectingMode = false
  @Environment(\.dismiss) private var dismiss
  @ScaledMetric(relativeTo: .body) private var choiceWidth = 72.0

  /// 原始 token 和初始规则一起保存，不因显示可视化而规范化已有文本。
  init(unit: NativeCronUnit, token: String, apply: @escaping (String) -> Void) {
    self.apply = apply
    _draft = State(initialValue: NativeCronFieldDraft(unit: unit, token: token))
  }

  /// 输入自然随大字增高，值网格保留 44pt 点击区域并在 iPad 阅读宽度内重排。
  var body: some View {
    ZStack {
      CinematicBackground()
      Form {
        CinematicFormSection {
          CinematicFormRow {
            Button {
              selectingMode = true
            } label: {
              HStack(spacing: 12) {
                Text(L10n.text("方式"))
                Spacer(minLength: 8)
                Text(NativeCronLabels.mode(NativeCronMode(draft.rule))).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary).accessibilityHidden(true)
              }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("native-cron-mode")
          }
        }
        controls
        CinematicFormSection(L10n.text("字段表达式")) {
          CinematicFormRow {
            Text((try? draft.token()) ?? "—").font(.system(.body, design: .monospaced))
              .textSelection(.enabled).accessibilityIdentifier("native-cron-field-preview")
          }
          if (try? draft.token()) == nil {
            CinematicFormRow(symbol: "info.circle") {
              Text(L10n.text("请选择范围内的值，至少选择一项。"))
                .font(.callout).foregroundStyle(.orange).accessibilityIdentifier(
                  "native-cron-field-invalid")
            }
          }
        }
      }.scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 680).accessibilityIdentifier("native-cron-field-form")
    }
    .navigationTitle(NativeCronLabels.unit(draft.unit)).navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationDestination(isPresented: $selectingMode) {
      NativeCronModePicker(modes: modes, selection: modeBinding)
    }
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(L10n.text("应用")) {
          if let token = try? draft.token() {
            apply(token)
            dismiss()
          }
        }
        .disabled((try? draft.token()) == nil).accessibilityIdentifier("native-cron-field-apply")
      }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(L10n.text("完成")) { NativeCronLabels.endEditing() }
      }
    }
  }

  /// 只在支持的日期字段显示“月底”，其它单位不提供无法生成的规则。
  private var modes: [NativeCronMode] {
    [.every, .values, .range, .step] + (draft.unit == .day ? [.lastDay] : []) + [.custom]
  }

  /// 选择同一模式不重置原有值；显式切换才建立该模式的初始草稿。
  private var modeBinding: Binding<NativeCronMode> {
    Binding(
      get: { NativeCronMode(draft.rule) },
      set: { mode in
        guard mode != NativeCronMode(draft.rule) else { return }
        switch mode {
        case .every: draft.rule = .every
        case .values: draft.rule = .values([draft.unit.bounds.lowerBound])
        case .range: draft.rule = .range(draft.unit.bounds.lowerBound, draft.unit.bounds.upperBound)
        case .step: draft.rule = .step(start: nil, every: 1)
        case .lastDay: draft.rule = .lastDay
        case .custom: draft.rule = .custom((try? draft.token()) ?? draft.source)
        }
      })
  }

  /// 控件直接编辑受限纯值模型，不存在字符串到函数或脚本的动态调用。
  @ViewBuilder private var controls: some View {
    switch draft.rule {
    case .every:
      CinematicFormSection { CinematicFormRow { Text(L10n.text("匹配此字段的全部值")) } }
    case .lastDay:
      CinematicFormSection { CinematicFormRow { Text(L10n.text("每月最后一天")) } }
    case .values(let values):
      CinematicFormSection(L10n.text("选择值")) {
        CinematicFormRow {
          LazyVGrid(columns: [.init(.adaptive(minimum: choiceWidth), spacing: 8)], spacing: 8) {
            ForEach(Array(draft.unit.bounds), id: \.self) { value in
              Button {
                guard case .values(let current) = draft.rule else { return }
                var chosen = Set(current)
                if chosen.contains(value) { chosen.remove(value) } else { chosen.insert(value) }
                draft.rule = .values(chosen.sorted())
              } label: {
                Text(NativeCronLabels.value(value, unit: draft.unit))
                  .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 6).padding(
                    .vertical, 3
                  )
                  .background(
                    .white.opacity(values.contains(value) ? 0.17 : 0.035),
                    in: RoundedRectangle(cornerRadius: 12)
                  )
                  .contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityAddTraits(
                values.contains(value) ? .isSelected : []
              )
              .accessibilityIdentifier("native-cron-choice-" + draft.unit.id + "-" + String(value))
            }
          }
        }
      }
    case .range(let first, let last):
      CinematicFormSection {
        CinematicFormRow {
          Stepper(
            L10n.text("开始") + " · " + NativeCronLabels.value(first, unit: draft.unit),
            value: rangeStart, in: draft.unit.bounds
          )
          .accessibilityIdentifier("native-cron-range-start")
        }
        CinematicFormDivider()
        CinematicFormRow {
          Stepper(
            L10n.text("结束") + " · " + NativeCronLabels.value(last, unit: draft.unit),
            value: rangeEnd, in: first...draft.unit.bounds.upperBound
          )
          .accessibilityIdentifier("native-cron-range-end")
        }
      }
    case .step(let start, let every):
      CinematicFormSection {
        CinematicFormRow {
          Toggle(L10n.text("指定起点"), isOn: usesStepStart)
            .tint(.green).accessibilityIdentifier("native-cron-step-start-enabled")
        }
        if let start {
          CinematicFormDivider()
          CinematicFormRow {
            Stepper(
              L10n.text("起点") + " · " + NativeCronLabels.value(start, unit: draft.unit),
              value: stepStart,
              in: draft.unit.bounds.lowerBound...(draft.unit.bounds.upperBound - 1)
            )
            .accessibilityIdentifier("native-cron-step-start")
          }
        }
        CinematicFormDivider()
        CinematicFormRow {
          Stepper(
            L10n.text("间隔") + " · " + String(every), value: stepInterval,
            in: 1...(draft.unit.bounds.upperBound - (start ?? draft.unit.bounds.lowerBound))
          )
          .accessibilityIdentifier("native-cron-step-interval")
        }
      }
    case .custom:
      CinematicFormSection(footer: L10n.text("此处只编辑一个字段；完整自定义值可在上一页输入。")) {
        CinematicFormRow {
          TextField(L10n.text("字段表达式"), text: customToken)
            .font(.system(.body, design: .monospaced)).textInputAutocapitalization(.never)
            .autocorrectionDisabled().keyboardType(.asciiCapable).accessibilityIdentifier(
              "native-cron-custom-field")
        }
      }
    }
  }

  /// 连续点击/输入的 getter 都读当前草稿，不捕获上一帧的关联值。
  private var customToken: Binding<String> {
    Binding(
      get: {
        if case .custom(let text) = draft.rule { return text }
        return ""
      }, set: { draft.rule = .custom($0) })
  }

  /// 调整范围开始时仅在当前本地草稿中扩大结束值，不产生无序范围。
  private var rangeStart: Binding<Int> {
    Binding(
      get: {
        if case .range(let first, _) = draft.rule { return first }
        return draft.unit.bounds.lowerBound
      },
      set: { value in
        guard case .range(_, let last) = draft.rule else { return }
        draft.rule = .range(value, max(value, last))
      })
  }

  /// 范围结束使用最新开始值，避免快速点击写回过时的起点。
  private var rangeEnd: Binding<Int> {
    Binding(
      get: {
        if case .range(_, let last) = draft.rule { return last }
        return draft.unit.bounds.upperBound
      },
      set: { value in
        guard case .range(let first, _) = draft.rule else { return }
        draft.rule = .range(first, value)
      })
  }

  /// 起点开关只改变本地增量规则，范围始终由当前单位约束。
  private var usesStepStart: Binding<Bool> {
    Binding(
      get: {
        if case .step(let start, _) = draft.rule { return start != nil }
        return false
      },
      set: { enabled in
        guard case .step(_, let every) = draft.rule else { return }
        draft.rule = .step(start: enabled ? draft.unit.bounds.lowerBound : nil, every: every)
      })
  }

  /// 起点靠近上限时收窄步长，保证构造器不产生超范围增量。
  private var stepStart: Binding<Int> {
    Binding(
      get: {
        if case .step(let start, _) = draft.rule { return start ?? draft.unit.bounds.lowerBound }
        return draft.unit.bounds.lowerBound
      },
      set: { value in
        guard case .step(_, let every) = draft.rule else { return }
        draft.rule = .step(start: value, every: min(every, draft.unit.bounds.upperBound - value))
      })
  }

  /// 步长保留当前最新起点，结束编辑时再由纯模型复核边界。
  private var stepInterval: Binding<Int> {
    Binding(
      get: {
        if case .step(_, let every) = draft.rule { return every }
        return 1
      },
      set: { value in
        guard case .step(let start, _) = draft.rule else { return }
        draft.rule = .step(start: start, every: value)
      })
  }
}

/// 模式使用完整原生选择页，避免最大字号横屏时系统弹出菜单超出可用高度。
@MainActor
private struct NativeCronModePicker: View {
  let modes: [NativeCronMode]
  @Binding var selection: NativeCronMode
  @Environment(\.dismiss) private var dismiss

  /// 选择本地规则后返回字段页，返回手势不改动原规则或外层草稿。
  var body: some View {
    ZStack {
      CinematicBackground()
      Form {
        CinematicFormSection {
          ForEach(modes, id: \.self) { mode in
            if mode != modes.first { CinematicFormDivider() }
            CinematicFormRow {
              Button {
                selection = mode
                dismiss()
              } label: {
                HStack(spacing: 12) {
                  Text(NativeCronLabels.mode(mode))
                  Spacer(minLength: 8)
                  if selection == mode {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                  }
                }.frame(minHeight: 44).contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
          }
        }
      }.scrollContentBackground(.hidden).frame(maxWidth: 680)
        .accessibilityIdentifier("native-cron-mode-form")
    }
    .navigationTitle(L10n.text("方式")).navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(L10n.text("完成")) { dismiss() }
      }
    }
  }
}

/// 模式只用于原生控件选择，不能把它解释为新的插件协议。
private enum NativeCronMode: CaseIterable, Hashable {
  case every, values, range, step, lastDay, custom

  /// 从已识别规则恢复原生模式，未实现方言留在自定义输入。
  init(_ rule: NativeCronRule) {
    switch rule {
    case .every: self = .every
    case .values: self = .values
    case .range: self = .range
    case .step: self = .step
    case .lastDay: self = .lastDay
    case .custom: self = .custom
    }
  }
}

/// 本地化仅改变标签；表达式里的星期和值不受手机语言或第一天偏好影响。
@MainActor
private enum NativeCronLabels {
  /// 字段标题按当前 App 语言展示，顺序来自稳定的原生字段枚举。
  static func unit(_ unit: NativeCronUnit) -> String {
    let key =
      switch unit {
      case .minute: "分钟"
      case .hour: "小时"
      case .day: "日期"
      case .month: "月份"
      case .weekday: "星期"
      }
    return L10n.text(key)
  }

  /// 常用计划的标题不包含执行结果承诺，最终时区由服务端决定。
  static func preset(_ preset: NativeCronPreset) -> String {
    let key =
      switch preset {
      case .quarterHourly: "每 15 分钟"
      case .hourly: "每小时"
      case .daily: "每天 09:00"
      case .weekdays: "工作日 09:00"
      case .monthly: "每月 1 日"
      case .yearly: "每年 1 月 1 日"
      }
    return L10n.text(key)
  }

  /// 可视化模式共享简短标签，避免表单堆积实现说明。
  static func mode(_ mode: NativeCronMode) -> String {
    let key =
      switch mode {
      case .every: "全部"
      case .values: "指定值"
      case .range: "范围"
      case .step: "间隔"
      case .lastDay: "月底"
      case .custom: "自定义"
      }
    return L10n.text(key)
  }

  /// 星期标签由系统本地化，明确把后端的 Monday=0 映射到 Foundation 的 Sunday=0。
  static func value(_ value: Int, unit: NativeCronUnit) -> String {
    guard unit.bounds.contains(value) else { return "—" }
    guard unit == .weekday || unit == .month else { return String(value) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: AppLanguage.current.rawValue)
    formatter.calendar = Calendar(identifier: .gregorian)
    if unit == .weekday { return formatter.shortWeekdaySymbols[(value + 1) % 7] }
    if unit == .month { return formatter.shortMonthSymbols[value - 1] }
    return String(value)
  }

  /// 应用/完成结束原生第一响应者，避免键盘遮挡确认操作。
  static func endEditing() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}
