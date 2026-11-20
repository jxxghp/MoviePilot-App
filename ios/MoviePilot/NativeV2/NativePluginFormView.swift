import Combine
import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotPluginUI
import SwiftUI

/// JSON 配置的真实原生编辑页面，展示与保存验证使用完全相同的计划。
@MainActor
struct NativePluginFormView: View {
  let plugin: NativeInstalledPlugin
  @StateObject private var form: NativePluginForm
  @State private var selected: NativeFormElement?
  @State private var localFailure = false
  @State private var showsDiscard = false
  @State private var saveTask: Task<Void, Never>?
  @Environment(\.dismiss) private var dismiss

  /// 草稿所有者只归属本次导航，不放入跨实例的全局状态。
  init(plugin: NativeInstalledPlugin, form: NativePluginForm) {
    self.plugin = plugin
    _form = StateObject(wrappedValue: form)
  }

  /// 读取失败和未支持配置都保留清楚状态，不开放空配置保存。
  var body: some View {
    let plan = self.plan
    return ZStack {
      CinematicBackground()
      Form {
        if busy {
          CinematicFormSection {
            CinematicFormRow {
              ProgressView()
              Text(L10n.text(form.phase == .saving ? "正在保存…" : "正在加载…"))
            }
          }
        }
        if form.failure != nil || localFailure {
          CinematicFormSection {
            CinematicFormRow(symbol: "exclamationmark.triangle") {
              Text(L10n.text(form.saveOutcome == .unconfirmed ? "保存结果未确认，修改已保留。" : "操作失败，请重试。"))
                .accessibilityIdentifier("native-plugin-form-error")
            }
            if form.document == nil {
              CinematicFormDivider()
              CinematicFormRow { Button(L10n.text("重试")) { loadAgain() }.frame(minHeight: 44) }
            }
          }
        }
        if form.document?.renderMode == .vue {
          CinematicFormSection {
            CinematicFormRow(symbol: "puzzlepiece.extension") {
              Text(L10n.text("此插件使用 Web 界面，兼容入口正在迁移。"))
            }
          }
        } else if let plan {
          if !plan.issues.isEmpty {
            CinematicFormSection {
              CinematicFormRow(symbol: "info.circle") {
                Text(
                  L10n.text(
                    plan.issues.contains(where: { $0.code == .unsupported })
                      ? "部分配置暂不支持原生编辑，保存已停用。" : "请检查标记的配置项。")
                )
                .accessibilityIdentifier("native-plugin-form-blocked")
              }
            }
          }
          if plan.groups.isEmpty {
            CinematicFormSection { CinematicFormRow { Text(L10n.text("此插件没有配置项")) } }
          }
          ForEach(plan.groups) { group in
            CinematicFormSection {
              ForEach(Array(group.elements.enumerated()), id: \.element.id) { index, element in
                if index > 0 { CinematicFormDivider() }
                NativePluginControlView(
                  element: element, issues: plan.issues, read: read, update: update,
                  select: { selected = $0 })
              }
            }.disabled(busy)
          }
          if form.lastSave != nil {
            CinematicFormSection {
              CinematicFormRow(symbol: "checkmark.circle.fill") {
                Text(L10n.text("配置已保存")).accessibilityIdentifier("native-plugin-form-saved")
              }
            }
          }
        }
      }
      .scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively).frame(maxWidth: 680)
    }
    .navigationTitle(plugin.name).navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(form.draft?.hasChanges == true || busy)
    .toolbar {
      if form.draft?.hasChanges == true || busy {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            if form.draft?.hasChanges == true { showsDiscard = true } else { dismiss() }
          } label: {
            Image(systemName: "chevron.left")
          }
          .accessibilityLabel(L10n.text("返回")).accessibilityIdentifier("native-plugin-form-back")
        }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(L10n.text("保存")) { save() }
          .disabled(busy || plan == nil || plan?.issues.isEmpty != true)
          .accessibilityIdentifier("native-plugin-form-save")
      }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(L10n.text("完成")) { endEditing() }
      }
    }
    .sheet(item: $selected) { element in
      Group {
        if case .cron(let field) = element.control {
          NativePluginCronEditor(field: field, value: read(field.key)) { expression in
            update(.string(expression), field.key)
          }
        } else if case .combobox(let field, let draft) = element.control {
          NativePluginComboboxEditor(field: field, draft: draft) { value in
            update(value, field.key)
            return !localFailure
          }
        } else {
          NativePluginSelectionView(element: element, read: read, update: update)
        }
      }.preferredColorScheme(.dark)
    }
    .alert(L10n.text("放弃未保存的修改？"), isPresented: $showsDiscard) {
      Button(L10n.text("放弃修改"), role: .destructive) { dismiss() }
      Button(L10n.text("取消"), role: .cancel) {}
    }
    .task { do { try await form.load() } catch {} }
    .onDisappear {
      saveTask?.cancel()
      form.close()
    }
  }

  /// 计划计算失败本身也必须阻止保存，不转换为空白成功。
  private var plan: NativeFormPlan? {
    guard let document = form.document, let draft = form.draft else { return nil }
    return try? NativeFormPlan(document: document, draft: draft)
  }

  /// 读取/保存期间禁用编辑，单次草稿修订与网络提交一一对应。
  private var busy: Bool { form.phase == .loading || form.phase == .saving }

  /// 每次更新都经过完整草稿预算/会话检查，失败不改变其它字段。
  private func update(_ value: PluginJSONValue, _ field: String) {
    do {
      try form.setValue(value, forExactField: field)
      localFailure = false
    } catch { localFailure = true }
  }

  /// 原生连续输入/多选直接读当前完整草稿，不返回上一帧控件中的值快照。
  private func read(_ field: String) -> PluginJSONValue? { form.draft?.value(forExactField: field) }

  /// 保存只由显式按钮触发，不把字段变化接到网络。
  private func save() {
    endEditing()
    localFailure = false
    saveTask = Task { do { try await form.save() } catch {} }
  }

  /// 只在尚无草稿时显示读取重试，避免覆盖用户修改。
  private func loadAgain() {
    saveTask = Task { do { try await form.load() } catch {} }
  }

  /// 键盘完成与保存都结束当前原生第一响应者。
  private func endEditing() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}

/// 单个真实控件；枚举的穷尽分支使新增计划能力不能漏掉 UI。
@MainActor
private struct NativePluginControlView: View {
  let element: NativeFormElement
  let issues: [PluginFormValidationIssue]
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void
  let select: (NativeFormElement) -> Void

  /// 每个控件保留系统交互/辅助功能，错误说明随原生布局换行。
  var body: some View {
    CinematicFormRow {
      VStack(alignment: .leading, spacing: 8) {
        control
        if issues.contains(where: { $0.pointer == element.id && $0.code != .unsupported }) {
          Text(L10n.text("请检查此项的值")).font(.caption).foregroundStyle(.orange)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 仅渲染计划声明的原生组件；没有字符串到类名的动态调用。
  @ViewBuilder private var control: some View {
    switch element.control {
    case .toggle(let field):
      Toggle(
        field.label,
        isOn: Binding(
          get: { read(field.key) == .bool(true) }, set: { update(.bool($0), field.key) })
      )
      .tint(.green).disabled(field.disabled).accessibilityIdentifier(
        "native-plugin-field-" + field.key)
      hint(field)
    case .input(let field, let kind):
      NativePluginInputView(field: field, kind: kind, read: read, update: update)
    case .cron(let field):
      NativePluginCronField(field: field, read: read, update: update) { select(element) }
    case .select(let field, let options, let multiple, _):
      Button {
        select(element)
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(field.label).multilineTextAlignment(.leading)
          Spacer(minLength: 4)
          Text(selectionText(field, options: options, multiple: multiple)).foregroundStyle(
            .secondary
          ).multilineTextAlignment(.trailing)
          Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle())
      }.buttonStyle(.plain).disabled(field.disabled).accessibilityIdentifier(
        "native-plugin-field-" + field.key)
      hint(field)
    case .combobox(let field, let draft):
      Button {
        select(element)
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(field.label).multilineTextAlignment(.leading)
          Spacer(minLength: 4)
          Text(
            draft.selected.isEmpty
              ? (field.placeholder.isEmpty ? L10n.text("选择或输入") : field.placeholder)
              : draft.selected.map(\.title).joined(separator: "、")
          ).foregroundStyle(.secondary).multilineTextAlignment(.trailing).lineLimit(2)
          Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle())
      }.buttonStyle(.plain).disabled(field.disabled).accessibilityIdentifier(
        "native-plugin-field-" + field.key)
      hint(field)
    case .notice(let title, let text, let kind):
      HStack(alignment: .top, spacing: 12) {
        Image(
          systemName: kind == .error || kind == .warning
            ? "exclamationmark.triangle" : kind == .success ? "checkmark.circle" : "info.circle"
        )
        .foregroundStyle(kind == .error || kind == .warning ? Color.orange : Color.secondary)
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          if !title.isEmpty { Text(title).font(.headline) }
          Text(text).font(.callout).foregroundStyle(.secondary)
        }
      }.padding(.vertical, 4).accessibilityElement(children: .combine)
    case .text(let text): Text(text)
    case .divider: Divider()
    case .unsupported:
      Label(L10n.text("暂不支持的配置组件"), systemImage: "puzzlepiece.extension").font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  /// 说明使用原始内容；不在表单里加入开发者实现细节。
  @ViewBuilder private func hint(_ field: NativeFormField) -> some View {
    if !field.hint.isEmpty { Text(field.hint).font(.caption).foregroundStyle(.secondary) }
  }

  /// 未匹配当前值明确保留，不擅自选择第一个选项。
  private func selectionText(_ field: NativeFormField, options: [NativeFormOption], multiple: Bool)
    -> String
  {
    let values = multiple ? field.value?.array ?? [] : field.value.map { [$0] } ?? []
    if values.isEmpty { return field.placeholder.isEmpty ? L10n.text("选择") : field.placeholder }
    return values.map { value in
      options.first(where: { $0.matches(value) })?.title ?? L10n.text("当前值（不在选项中）")
    }.joined(separator: "、")
  }
}

/// 文本、数字、密码和多行输入共享原生标签/焦点及渐变上的可读提示。
@MainActor
private struct NativePluginInputView: View {
  let field: NativeFormField
  let kind: NativeFormInputKind
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void
  @State private var showsSecret = false
  @ScaledMetric(relativeTo: .body) private var editorHeight = 120.0

  /// 不固定文字行高；密码显隐动作至少 44pt，离开前台后恢复遮盖。
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(field.label).font(.subheadline).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
      HStack(alignment: .top, spacing: 8) {
        input.accessibilityLabel(field.label).accessibilityIdentifier(
          "native-plugin-field-" + field.key)
        if !field.suffix.isEmpty { Text(field.suffix).foregroundStyle(.secondary) }
        if case .password = kind {
          Button {
            showsSecret.toggle()
          } label: {
            Image(systemName: showsSecret ? "eye.slash" : "eye").frame(width: 44, height: 44)
          }
          .buttonStyle(.plain).accessibilityLabel(L10n.text(showsSecret ? "隐藏密码" : "显示密码"))
        }
        if field.clearable, !field.text.isEmpty {
          Button {
            update(.null, field.key)
          } label: {
            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
          }
          .buttonStyle(.plain).accessibilityLabel(L10n.text("清除"))
        }
      }
      if !field.hint.isEmpty { Text(field.hint).font(.caption).foregroundStyle(.secondary) }
    }.padding(.vertical, 3).disabled(field.disabled)
      .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) {
        _ in showsSecret = false
      }
  }

  /// 任何编辑都返回字符串，未编辑的数值/空值仍留在完整草稿原类型中。
  private var binding: Binding<String> {
    Binding(
      get: { NativeFormField.text(from: read(field.key)) }, set: { update(.string($0), field.key) })
  }

  /// 使用原生输入组件，TextEditor 透出共用玻璃表面。
  @ViewBuilder private var input: some View {
    switch kind {
    case .multiline:
      ZStack(alignment: .topLeading) {
        if field.text.isEmpty {
          Text(field.placeholder).foregroundStyle(.white.opacity(0.70)).padding(.top, 8).padding(
            .leading, 5
          ).allowsHitTesting(false).accessibilityHidden(true)
        }
        TextEditor(text: binding).scrollContentBackground(.hidden).frame(minHeight: editorHeight)
      }
    case .password where !showsSecret:
      SecureField(field.label, text: binding, prompt: prompt).textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    default:
      TextField(field.label, text: binding, prompt: prompt).textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(kind == .number ? .numbersAndPunctuation : .default)
    }
  }

  /// 占位内容与文字/背景保持足够对比度，不依赖系统浅色主题。
  private var prompt: Text { Text(field.placeholder).foregroundColor(.white.opacity(0.70)) }
}

/// 单/多选共用原生弹层，单选选中即返回，多选保留完成动作和未知旧值。
@MainActor
private struct NativePluginSelectionView: View {
  let element: NativeFormElement
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void
  @Environment(\.dismiss) private var dismiss

  /// 弹层的背景和表单继续采用同一 Rex 风格，按钮不再嵌套额外玻璃层。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        if case .select(let field, let options, let multiple, let clearable) = element.control {
          Form {
            CinematicFormSection {
              ForEach(options) { option in
                if option.id > 0 { CinematicFormDivider() }
                CinematicFormRow {
                  Button {
                    choose(option, field: field, multiple: multiple)
                  } label: {
                    HStack {
                      Text(option.title).multilineTextAlignment(.leading)
                      Spacer()
                      if values(multiple).contains(where: option.matches) {
                        Image(systemName: "checkmark").accessibilityLabel(L10n.text("已选择"))
                      }
                    }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                  }.buttonStyle(.plain).accessibilityIdentifier(
                    "native-plugin-option-" + String(option.id))
                }
              }
            }
            if values(multiple).contains(where: { value in
              !options.contains(where: { $0.matches(value) })
            }) {
              CinematicFormSection {
                CinematicFormRow(symbol: "info.circle") { Text(L10n.text("已保留不在选项中的当前值。")) }
              }
            }
            if clearable {
              CinematicFormSection {
                CinematicFormRow {
                  Button(L10n.text("清除选择")) {
                    update(multiple ? .array([]) : .null, field.key)
                    if !multiple { dismiss() }
                  }.frame(minHeight: 44).accessibilityIdentifier("native-plugin-clear-selection")
                }
              }
            }
          }.scrollContentBackground(.hidden).frame(maxWidth: 680)
            .navigationTitle(field.label).navigationBarTitleDisplayMode(.inline)
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("完成")) { dismiss() }.accessibilityIdentifier(
            "native-plugin-selection-done")
        }
      }
    }.tint(.white)
  }

  /// 当前模型的缺失/null 不自动变成新的空配置值。
  private func values(_ multiple: Bool) -> [PluginJSONValue] {
    guard case .select(let field, _, _, _) = element.control else { return [] }
    let current = read(field.key)
    return multiple ? current?.array ?? [] : current.map { [$0] } ?? []
  }

  /// 多选只修改明确选择的值，其它未知旧选项继续保留。
  private func choose(_ option: NativeFormOption, field: NativeFormField, multiple: Bool) {
    if multiple {
      var values = values(true)
      if values.contains(where: option.matches) {
        values.removeAll(where: option.matches)
      } else {
        values.append(option.value)
      }
      update(.array(values), field.key)
    } else {
      update(option.value, field.key)
      dismiss()
    }
  }
}
