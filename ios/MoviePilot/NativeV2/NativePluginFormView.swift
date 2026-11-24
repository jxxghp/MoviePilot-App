import Combine
import MoviePilotAPI
import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotPluginUI
import MoviePilotSession
import SwiftUI

/// JSON 配置的真实原生编辑页面，展示与保存验证使用完全相同的计划；
/// 若插件为 Vue 远程组件模式（`renderMode == .vue`），自动在免登隔离 WebView 中直接呈现插件配置界面。
@MainActor
struct NativePluginFormView: View {
  let plugin: NativeInstalledPlugin
  @StateObject private var form: NativePluginForm
  @State private var selected: NativeFormElement?
  @State private var localFailure = false
  @State private var showsDiscard = false
  @State private var showsVueSheet = false
  @State private var dismissAfterVueSheet = false
  @State private var saveTask: Task<Void, Never>?
  @State private var actionFeedback: String?
  @Environment(\.dismiss) private var dismiss

  /// 草稿所有者只归属本次导航，不放入跨实例的全局状态。
  init(plugin: NativeInstalledPlugin, form: NativePluginForm) {
    self.plugin = plugin
    _form = StateObject(wrappedValue: form)
  }

  var body: some View {
    let plan = self.plan
    let isVuePlugin = form.document?.renderMode == .vue
    return ZStack {
      CinematicBackground()
      if isVuePlugin {
        VStack(spacing: 14) {
          ProgressView("正在打开插件配置弹窗…")
            .tint(.primary)
          Button("打开插件配置") {
            showsVueSheet = true
          }
          .buttonStyle(.borderedProminent)
          .tint(NativeTheme.brand)
        }
      } else {
        Form {
          if form.phase == .loading && form.document == nil {
            Section {
              NativeCardListSkeletonView(count: 3, style: .formPanel)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
          } else if busy {
            CinematicFormSection {
              CinematicFormRow {
                ProgressView()
                Text(L10n.text(form.phase == .saving ? "正在保存…" : "正在加载…"))
              }
            }
          }
          if let actionFeedback {
            CinematicFormSection {
              CinematicFormRow(symbol: "info.circle") {
                Text(actionFeedback).font(.callout)
              }
            }
          }
          if form.failure != nil || localFailure {
            CinematicFormSection {
              CinematicFormRow(symbol: "exclamationmark.triangle") {
                Text(
                  L10n.text(
                    form.saveOutcome == .unconfirmed ? "保存结果未确认，修改已保留。" : "操作失败，请重试。")
                )
                .accessibilityIdentifier("native-plugin-form-error")
              }
              if form.document == nil {
                CinematicFormDivider()
                CinematicFormRow {
                  HStack(spacing: 16) {
                    Button(L10n.text("重试")) { loadAgain() }.frame(minHeight: 44)
                    Spacer()
                    Button("兼容弹窗配置") {
                      dismissAfterVueSheet = false
                      showsVueSheet = true
                    }
                    .frame(minHeight: 44)
                  }
                }
              }
            }
          } else if !busy && form.document == nil {
            CinematicFormSection {
              CinematicFormRow(symbol: "arrow.clockwise.circle") {
                HStack(spacing: 16) {
                  Button(L10n.text("重试")) { loadAgain() }.frame(minHeight: 44)
                  Spacer()
                  Button("兼容弹窗配置") {
                    dismissAfterVueSheet = false
                    showsVueSheet = true
                  }
                  .frame(minHeight: 44)
                }
              }
            }
          }
          if let plan {
            if !plan.issues.isEmpty {
              let hasUnsupported = plan.issues.contains(where: { $0.code == .unsupported })
              CinematicFormSection {
                CinematicFormRow(symbol: "info.circle") {
                  Text(
                    L10n.text(
                      hasUnsupported
                        ? "部分配置含自定义组件，可使用兼容弹窗完整编辑保存。" : "请检查标记的配置项。")
                  )
                  .accessibilityIdentifier("native-plugin-form-blocked")
                }
                if hasUnsupported {
                  CinematicFormDivider()
                  CinematicFormRow(symbol: "rectangle.portrait.and.arrow.right") {
                    Button("打开兼容配置弹窗") {
                      dismissAfterVueSheet = false
                      showsVueSheet = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NativeTheme.brand)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                  }
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
                    element: element,
                    issues: plan.issues,
                    read: read,
                    update: update,
                    select: { selected = $0 },
                    onAction: { api, method in
                      Task { await invokeButtonAction(api: api, method: method) }
                    })
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
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 680)
      }
    }
    .navigationTitle(plugin.name)
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .navigationBarBackButtonHidden(!isVuePlugin && (form.draft?.hasChanges == true || busy))
    .toolbar {
      if !isVuePlugin && (form.draft?.hasChanges == true || busy) {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            if form.draft?.hasChanges == true { showsDiscard = true } else { dismiss() }
          } label: {
            Image(systemName: "chevron.left")
          }
          .tint(.primary)
          .accessibilityLabel(L10n.text("返回")).accessibilityIdentifier("native-plugin-form-back")
        }
      }
      if !isVuePlugin {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(L10n.text("保存")) { save() }
            .tint(.primary)
            .disabled(busy || plan == nil || plan?.issues.isEmpty != true)
            .accessibilityIdentifier("native-plugin-form-save")
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(L10n.text("完成")) { endEditing() }
        }
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
      }.nativeGlassSheet()
    }
    .alert(L10n.text("放弃未保存的修改？"), isPresented: $showsDiscard) {
      Button(L10n.text("放弃修改"), role: .destructive) { dismiss() }
      Button(L10n.text("取消"), role: .cancel) {}
    }
    .sheet(
      isPresented: $showsVueSheet,
      onDismiss: {
        if dismissAfterVueSheet {
          dismiss()
        } else {
          loadAgain()
        }
      }
    ) {
      NativeVuePluginSheet(
        session: form.activeSession,
        pluginID: plugin.id,
        pluginName: plugin.name,
        surface: .config,
        pluginHasPage: plugin.hasPage
      )
    }
    .onChange(of: form.document?.renderMode) { mode in
      if mode == .vue {
        dismissAfterVueSheet = true
        showsVueSheet = true
      }
    }
    .task { do { try await form.load() } catch {} }
    .onAppear {
      // 若导航转场或快捷菜单收起动画曾中断首次 .task，自动补拉一次避免留白。
      if form.phase == .idle, form.document == nil, form.failure == nil {
        loadAgain()
      }
    }
  }

  private var plan: NativeFormPlan? {
    guard let document = form.document, let draft = form.draft else { return nil }
    return try? NativeFormPlan(document: document, draft: draft)
  }

  private var busy: Bool { form.phase == .loading || form.phase == .saving }

  private func update(_ value: PluginJSONValue, _ field: String) {
    do {
      try form.setValue(value, forExactField: field)
      localFailure = false
    } catch { localFailure = true }
  }

  private func read(_ field: String) -> PluginJSONValue? { form.draft?.value(forExactField: field) }

  private func save() {
    endEditing()
    localFailure = false
    saveTask = Task { do { try await form.save() } catch {} }
  }

  private func loadAgain() {
    saveTask = Task { do { try await form.load() } catch {} }
  }

  private func invokeButtonAction(api: String, method: String?) async {
    let cleaned = api.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let segments = cleaned.split(separator: "/").map(String.init)
    guard !segments.isEmpty else { return }
    let apiSegments: [String]
    if segments.count >= 3, segments[0] == "api", segments[1] == "v1" {
      apiSegments = Array(segments.dropFirst(2))
    } else {
      apiSegments = segments
    }
    let httpMethod: APIMethod =
      switch (method ?? "GET").uppercased() {
      case "POST": .post
      case "PUT": .put
      case "DELETE": .delete
      default: .get
      }
    do {
      let endpoint = try APIEndpoint(path: apiSegments, method: httpMethod, timeout: 30)
      try await form.activeSession.perform(endpoint)
      actionFeedback = "插件操作已执行。"
    } catch {
      actionFeedback = "插件操作失败：\(error.localizedDescription)"
    }
  }

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
  let onAction: (String, String?) -> Void

  @Environment(\.openURL) private var openURL

  var body: some View {
    CinematicFormRow {
      VStack(alignment: .leading, spacing: 8) {
        control
        if issues.contains(where: { $0.pointer == element.id && $0.code != .unsupported }) {
          Text(L10n.text("请检查此项的值")).font(.caption).foregroundStyle(NativeTheme.warning)
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
      .tint(NativeTheme.success)
      .disabled(field.disabled)
      .accessibilityIdentifier("native-plugin-field-" + field.key)
      hint(field)

    case .toggleValue(let field, let itemValue):
      Toggle(
        field.label,
        isOn: Binding(
          get: {
            let current = read(field.key)?.array ?? []
            return current.contains { $0 == itemValue }
          },
          set: { enabled in
            var current = read(field.key)?.array ?? []
            if enabled {
              if !current.contains(where: { $0 == itemValue }) { current.append(itemValue) }
            } else {
              current.removeAll { $0 == itemValue }
            }
            update(.array(current), field.key)
          })
      )
      .tint(NativeTheme.brand)
      .disabled(field.disabled)
      hint(field)

    case .input(let field, let kind):
      NativePluginInputView(field: field, kind: kind, read: read, update: update)

    case .codeEditor(let field, let language):
      NativePluginCodeEditorView(field: field, language: language, read: read, update: update)

    case .cron(let field):
      NativePluginCronField(field: field, read: read, update: update) { select(element) }

    case .colorPicker(let field):
      NativePluginColorPickerView(field: field, read: read, update: update)

    case .select(let field, let options, let multiple, _):
      Button {
        select(element)
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(field.label).multilineTextAlignment(.leading)
          Spacer(minLength: 4)
          Text(selectionText(field, options: options, multiple: multiple))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
          Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(field.disabled)
      .accessibilityIdentifier("native-plugin-field-" + field.key)
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
          )
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.trailing)
          .lineLimit(2)
          Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(field.disabled)
      .accessibilityIdentifier("native-plugin-field-" + field.key)
      hint(field)

    case .slider(let field, let minVal, let maxVal, let stepVal):
      NativePluginSliderView(
        field: field, min: minVal, max: maxVal, step: stepVal, read: read, update: update)

    case .rangeSlider(let field, let minVal, let maxVal, let stepVal):
      NativePluginRangeSliderView(
        field: field, min: minVal, max: maxVal, step: stepVal, read: read, update: update)

    case .chipGroup(let field, let options, let multiple):
      VStack(alignment: .leading, spacing: 8) {
        Text(field.label).font(.subheadline).foregroundStyle(.secondary)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(options) { option in
              let currentValues: [PluginJSONValue] =
                multiple
                ? (read(field.key)?.array ?? [])
                : (read(field.key).map { [$0] } ?? [])
              let isSelected = currentValues.contains(where: option.matches)
              Button {
                if multiple {
                  var arr = read(field.key)?.array ?? []
                  if arr.contains(where: option.matches) {
                    arr.removeAll(where: option.matches)
                  } else {
                    arr.append(option.value)
                  }
                  update(.array(arr), field.key)
                } else {
                  update(option.value, field.key)
                }
              } label: {
                NativeAdaptivePill(option.title, isSelected: isSelected)
              }
              .buttonStyle(.plain)
              .disabled(field.disabled)
            }
          }
        }
        hint(field)
      }

    case .expansion(let title, let children):
      NativePluginFormExpansionView(
        title: title,
        elements: children,
        issues: issues,
        read: read,
        update: update,
        select: select,
        onAction: onAction)

    case .notice(let title, let text, let kind):
      HStack(alignment: .top, spacing: 12) {
        Image(
          systemName: kind == .error || kind == .warning
            ? "exclamationmark.triangle" : kind == .success ? "checkmark.circle" : "info.circle"
        )
        .foregroundStyle(
          kind == .error
            ? NativeTheme.danger
            : (kind == .warning
              ? NativeTheme.warning
              : (kind == .success ? NativeTheme.success : NativeTheme.info))
        )
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          if !title.isEmpty { Text(title).font(.headline) }
          if !text.isEmpty { Text(text).font(.callout).foregroundStyle(.secondary) }
        }
      }.padding(.vertical, 4).accessibilityElement(children: .combine)

    case .link(let label, let url):
      Button {
        openURL(url)
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "safari")
          Text(label).fontWeight(.medium)
          Spacer(minLength: 0)
          Image(systemName: "arrow.up.right").font(.caption)
        }
        .foregroundStyle(NativeTheme.brand)
        .frame(minHeight: 40)
      }
      .buttonStyle(.plain)

    case .button(let label, let api, let method, let color, let webOnly):
      VStack(alignment: .leading, spacing: 4) {
        Button {
          if let api { onAction(api, method) }
        } label: {
          Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
              api != nil ? NativePluginJSONRenderer.tintColor(color ?? "primary") : .secondary
            )
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                  api != nil
                    ? NativePluginJSONRenderer.tintColor(color ?? "primary").opacity(0.15)
                    : NativeTheme.chipFill)
            }
        }
        .buttonStyle(.plain)
        .disabled(api == nil)
        if webOnly {
          Text("此快捷操作需在 Web 端使用").font(.caption2).foregroundStyle(.secondary)
        }
      }

    case .chip(let text, let color):
      let tint = NativePluginJSONRenderer.tintColor(color)
      Text(text)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background { Capsule().fill(tint.opacity(0.15)) }

    case .presetChip(let text, let color, let field, let presetValue):
      let isSelected = read(field) == presetValue
      let tint = color.map { NativePluginJSONRenderer.tintColor($0) } ?? NativeTheme.brand
      Button {
        update(presetValue, field)
      } label: {
        Text(text)
          .font(.caption.weight(.semibold))
          .foregroundStyle(isSelected ? .white : tint)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background {
            Capsule().fill(isSelected ? tint : tint.opacity(0.15))
          }
      }
      .buttonStyle(.plain)

    case .table(let headers, let rows):
      ScrollView(.horizontal, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 6) {
          if !headers.isEmpty {
            HStack(spacing: 10) {
              ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                Text(h).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                  .frame(minWidth: 72, alignment: .leading)
              }
            }
          }
          ForEach(Array(rows.prefix(30).enumerated()), id: \.offset) { _, row in
            Divider().overlay(NativeTheme.divider)
            HStack(spacing: 10) {
              ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                Text(cell).font(.caption).foregroundStyle(.primary)
                  .frame(minWidth: 72, alignment: .leading)
              }
            }
          }
        }
      }

    case .text(let text):
      Text(text)

    case .divider:
      Divider()

    case .unsupported:
      Label(L10n.text("暂不支持的配置组件"), systemImage: "puzzlepiece.extension").font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private func hint(_ field: NativeFormField) -> some View {
    if !field.hint.isEmpty { Text(field.hint).font(.caption).foregroundStyle(.secondary) }
  }

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

/// 原生颜色选择控件（对应 `VColorPicker`），支持系统取色器与 Hex 色值双向编辑。
@MainActor
private struct NativePluginColorPickerView: View {
  let field: NativeFormField
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void

  var body: some View {
    let hexText = NativeFormField.text(from: read(field.key))
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        ColorPicker(
          field.label,
          selection: Binding(
            get: { Self.color(fromHex: hexText) ?? NativeTheme.brand },
            set: { newColor in
              if let hex = Self.hexString(from: newColor) {
                update(.string(hex), field.key)
              }
            }
          ),
          supportsOpacity: false
        )
        .disabled(field.disabled)
      }
      TextField(
        "#FFFFFF",
        text: Binding(
          get: { NativeFormField.text(from: read(field.key)) },
          set: { update(.string($0), field.key) }
        )
      )
      .font(.caption.monospaced())
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .disabled(field.disabled)
      if !field.hint.isEmpty {
        Text(field.hint).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private static func color(fromHex raw: String) -> Color? {
    let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard cleaned.count == 6 || cleaned.count == 8, let value = UInt64(cleaned, radix: 16) else {
      return nil
    }
    let shift = cleaned.count == 8 ? 8 : 0
    let r = Double((value >> (16 + shift)) & 0xFF) / 255.0
    let g = Double((value >> (8 + shift)) & 0xFF) / 255.0
    let b = Double((value >> shift) & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
  }

  private static func hexString(from color: Color) -> String? {
    let uiColor = UIColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return String(
      format: "#%02X%02X%02X",
      Int(max(0, min(255, round(r * 255)))),
      Int(max(0, min(255, round(g * 255)))),
      Int(max(0, min(255, round(b * 255))))
    )
  }
}

/// 折叠子配置区（`VExpansionPanel` / `VDialog`）。
@MainActor
private struct NativePluginFormExpansionView: View {
  let title: String
  let elements: [NativeFormElement]
  let issues: [PluginFormValidationIssue]
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void
  let select: (NativeFormElement) -> Void
  let onAction: (String, String?) -> Void

  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(elements.enumerated()), id: \.element.id) { index, child in
          if index > 0 { Divider().overlay(NativeTheme.divider) }
          NativePluginControlView(
            element: child,
            issues: issues,
            read: read,
            update: update,
            select: select,
            onAction: onAction)
        }
      }
      .padding(.top, 8)
    } label: {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
    }
    .tint(NativeTheme.brand)
  }
}

/// 等宽代码编辑控件（`VAceEditor`）。
@MainActor
private struct NativePluginCodeEditorView: View {
  let field: NativeFormField
  let language: String
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(field.label)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer()
        Text(language.uppercased())
          .font(.caption2.monospaced().weight(.semibold))
          .foregroundStyle(NativeTheme.brand)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background { Capsule().fill(NativeTheme.brand.opacity(0.14)) }
      }
      TextEditor(
        text: Binding(
          get: { NativeFormField.text(from: read(field.key)) },
          set: { update(.string($0), field.key) })
      )
      .font(.caption.monospaced())
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .scrollContentBackground(.hidden)
      .frame(minHeight: 160)
      .padding(8)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(NativeTheme.fieldFill)
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.6)
          }
      }
      .disabled(field.disabled)
      if !field.hint.isEmpty {
        Text(field.hint).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 3)
  }
}

/// 原生数值滑块控件（`VSlider`）。
@MainActor
private struct NativePluginSliderView: View {
  let field: NativeFormField
  let min: Double
  let max: Double
  let step: Double
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void

  private var currentDouble: Double {
    let raw = Double(NativeFormField.text(from: read(field.key))) ?? min
    return Swift.min(Swift.max(raw, min), max)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(field.label).font(.subheadline).foregroundStyle(.primary)
        Spacer()
        Text(formatValue(currentDouble))
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(NativeTheme.brand)
      }
      Slider(
        value: Binding(
          get: { currentDouble },
          set: { val in
            let text = formatValue(val)
            if let num = try? PluginJSONNumber(text) {
              update(.number(num), field.key)
            } else {
              update(.string(text), field.key)
            }
          }),
        in: min...Swift.max(max, min + step),
        step: step
      )
      .tint(NativeTheme.brand)
      .disabled(field.disabled)
      if !field.hint.isEmpty {
        Text(field.hint).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func formatValue(_ val: Double) -> String {
    abs(val.rounded() - val) < 0.0001 ? String(Int(val.rounded())) : String(format: "%.2f", val)
  }
}

/// 原生区间滑块控件（`VRangeSlider`）。
@MainActor
private struct NativePluginRangeSliderView: View {
  let field: NativeFormField
  let min: Double
  let max: Double
  let step: Double
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void

  private var bounds: (Double, Double) {
    let arr = read(field.key)?.array ?? []
    let low = arr.first.flatMap { Double(NativeFormField.text(from: $0)) } ?? min
    let high = arr.dropFirst().first.flatMap { Double(NativeFormField.text(from: $0)) } ?? max
    return (Swift.min(Swift.max(low, min), max), Swift.min(Swift.max(high, min), max))
  }

  var body: some View {
    let current = bounds
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(field.label).font(.subheadline).foregroundStyle(.primary)
        Spacer()
        Text("\(formatValue(current.0)) - \(formatValue(current.1))")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(NativeTheme.brand)
      }
      HStack(spacing: 12) {
        Stepper(
          "下限 \(formatValue(current.0))",
          value: Binding(
            get: { current.0 },
            set: { saveBounds($0, Swift.max($0, current.1)) }),
          in: min...max, step: step
        )
        .font(.caption)
      }
      HStack(spacing: 12) {
        Stepper(
          "上限 \(formatValue(current.1))",
          value: Binding(
            get: { current.1 },
            set: { saveBounds(Swift.min(current.0, $0), $0) }),
          in: min...max, step: step
        )
        .font(.caption)
      }
      if !field.hint.isEmpty {
        Text(field.hint).font(.caption).foregroundStyle(.secondary)
      }
    }
    .disabled(field.disabled)
  }

  private func saveBounds(_ low: Double, _ high: Double) {
    let a =
      (try? PluginJSONNumber(formatValue(low))).map(PluginJSONValue.number)
      ?? .string(formatValue(low))
    let b =
      (try? PluginJSONNumber(formatValue(high))).map(PluginJSONValue.number)
      ?? .string(formatValue(high))
    update(.array([a, b]), field.key)
  }

  private func formatValue(_ val: Double) -> String {
    abs(val.rounded() - val) < 0.0001 ? String(Int(val.rounded())) : String(format: "%.2f", val)
  }
}

/// 文本、数字、URL、邮箱、密码和多行输入共享原生标签/焦点及自适应可读提示。
@MainActor
private struct NativePluginInputView: View {
  let field: NativeFormField
  let kind: NativeFormInputKind
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void
  @State private var showsSecret = false
  @ScaledMetric(relativeTo: .body) private var editorHeight = 120.0

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

  private var binding: Binding<String> {
    Binding(
      get: { NativeFormField.text(from: read(field.key)) }, set: { update(.string($0), field.key) })
  }

  @ViewBuilder private var input: some View {
    switch kind {
    case .multiline:
      ZStack(alignment: .topLeading) {
        if field.text.isEmpty {
          Text(field.placeholder).foregroundStyle(.secondary).padding(.top, 8).padding(
            .leading, 5
          ).allowsHitTesting(false).accessibilityHidden(true)
        }
        TextEditor(text: binding).scrollContentBackground(.hidden).frame(minHeight: editorHeight)
      }
    case .password where !showsSecret:
      SecureField(field.label, text: binding, prompt: prompt).textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    default:
      TextField(field.label, text: binding, prompt: prompt)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(
          kind == .number
            ? .numbersAndPunctuation
            : (kind == .url ? .URL : (kind == .email ? .emailAddress : .default)))
    }
  }

  private var prompt: Text { Text(field.placeholder).foregroundColor(.secondary) }
}

/// 单/多选共用原生弹层（选项较多时自动提供搜索筛选，兼容 `VSelect` 与 `VAutocomplete`）。
@MainActor
private struct NativePluginSelectionView: View {
  let element: NativeFormElement
  let read: (String) -> PluginJSONValue?
  let update: (PluginJSONValue, String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var searchQuery = ""

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        if case .select(let field, let options, let multiple, let clearable) = element.control {
          let filtered = filterOptions(options)
          Form {
            CinematicFormSection {
              ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, option in
                if idx > 0 { CinematicFormDivider() }
                CinematicFormRow {
                  Button {
                    choose(option, field: field, multiple: multiple)
                  } label: {
                    HStack {
                      Text(option.title).multilineTextAlignment(.leading)
                      Spacer()
                      if values(multiple).contains(where: option.matches) {
                        Image(systemName: "checkmark")
                          .foregroundStyle(NativeTheme.brand)
                          .accessibilityLabel(L10n.text("已选择"))
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
          }
          .scrollContentBackground(.hidden)
          .frame(maxWidth: 680)
          .navigationTitle(field.label)
          .navigationBarTitleDisplayMode(.inline)
          .modifier(ConditionalSearchableModifier(enabled: options.count > 8, text: $searchQuery))
        }
      }
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel(L10n.text("关闭"))
          .accessibilityIdentifier("native-plugin-selection-done")
        }
      }
    }.tint(.primary)
  }

  private func filterOptions(_ options: [NativeFormOption]) -> [NativeFormOption] {
    let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return options }
    return options.filter { $0.title.lowercased().contains(q) }
  }

  private func values(_ multiple: Bool) -> [PluginJSONValue] {
    guard case .select(let field, _, _, _) = element.control else { return [] }
    let current = read(field.key)
    return multiple ? current?.array ?? [] : current.map { [$0] } ?? []
  }

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

/// 选项列表超过阈值时动态挂载原生搜索框。
private struct ConditionalSearchableModifier: ViewModifier {
  let enabled: Bool
  @Binding var text: String

  func body(content: Content) -> some View {
    if enabled {
      content.searchable(text: $text, prompt: "搜索选项")
    } else {
      content
    }
  }
}
