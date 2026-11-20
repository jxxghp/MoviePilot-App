import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotPluginUI
import SwiftUI

/// 组合框编辑器只操作局部选择；应用后写回父草稿，网络仍由父页面显式保存。
@MainActor
struct NativePluginComboboxEditor: View {
  let field: NativeFormField
  let apply: (PluginJSONValue) -> Bool
  @State private var draft: NativeComboboxDraft
  @State private var input = ""
  @State private var failed = false
  @State private var showsSelectionLimit = false
  @FocusState private var inputFocused: Bool
  @Environment(\.dismiss) private var dismiss

  /// 由实际计划传入已检查的状态，不从标题反推值，也不在显示时更新父模型。
  init(
    field: NativeFormField, draft: NativeComboboxDraft, apply: @escaping (PluginJSONValue) -> Bool
  ) {
    self.field = field
    self.apply = apply
    _draft = State(initialValue: draft)
  }

  /// 复用 Rex 连续渐变和轻薄玻璃分组，长列表及最大字号由原生 Form 自适应。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        Form {
          CinematicFormSection(footer: field.hint) {
            CinematicFormRow {
              TextField(
                L10n.text("搜索或输入自定义值"), text: $input,
                prompt: Text(L10n.text("搜索或输入自定义值")).foregroundColor(.white.opacity(0.70))
              )
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .focused($inputFocused).submitLabel(.done).onSubmit(addInput)
              .accessibilityIdentifier("native-combobox-input")
              if !input.isEmpty {
                Button(action: addInput) {
                  Image(systemName: "plus.circle.fill").frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("添加"))
                  .accessibilityIdentifier("native-combobox-add")
              }
            }
          }
          if !draft.selected.isEmpty {
            CinematicFormSection(L10n.text("已选择")) {
              ForEach(Array(draft.selected.enumerated()), id: \.offset) { index, item in
                if index > 0 { CinematicFormDivider() }
                CinematicFormRow {
                  Text(title(item)).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("native-combobox-current-\(index)")
                  Button {
                    draft.remove(at: index)
                    failed = false
                  } label: {
                    Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                  }.buttonStyle(.plain).disabled(item.disabled)
                    .accessibilityLabel(L10n.text("移除") + " " + title(item))
                    .accessibilityIdentifier("native-combobox-remove-\(index)")
                }
              }
            }
          }
          if !draft.options.isEmpty {
            CinematicFormSection(L10n.text("预设选项")) {
              ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                if index > 0 { CinematicFormDivider() }
                CinematicFormRow {
                  Button {
                    guard draft.choose(item.id) else {
                      showsSelectionLimit = true
                      return
                    }
                    input = ""
                    inputFocused = false
                    failed = false
                  } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                      Text(title(item)).multilineTextAlignment(.leading)
                      Spacer(minLength: 4)
                      if draft.isSelected(item) {
                        Image(systemName: "checkmark").accessibilityLabel(L10n.text("已选择"))
                      }
                    }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                  }.buttonStyle(.plain).disabled(item.disabled)
                    .accessibilityIdentifier("native-combobox-option-\(item.id)")
                }
              }
              if filtered.isEmpty {
                CinematicFormRow {
                  Text(L10n.text("没有匹配项，可直接添加输入值。")).foregroundStyle(.secondary)
                }
              }
            }
          }
          if draft.clearable {
            CinematicFormSection {
              CinematicFormRow {
                Button(L10n.text("清除选择")) {
                  draft.clear()
                  input = ""
                  inputFocused = false
                  failed = false
                }.frame(minHeight: 44).accessibilityIdentifier("native-combobox-clear")
              }
            }
          }
          if failed {
            CinematicFormSection {
              CinematicFormRow(symbol: "exclamationmark.triangle") {
                Text(L10n.text("无法应用，修改已保留。"))
                  .accessibilityIdentifier("native-combobox-error")
              }
            }
          }
        }.scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
          .frame(maxWidth: 680).accessibilityIdentifier("native-combobox-form")
          .disabled(field.disabled)
      }
      .navigationTitle(field.label).navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("取消")) { dismiss() }.accessibilityIdentifier("native-combobox-cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("应用"), action: confirm).disabled(field.disabled)
            .accessibilityIdentifier("native-combobox-apply")
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(L10n.text("完成")) { inputFocused = false }
        }
      }
    }
    .tint(.white)
    .alert(L10n.text("选中项过多"), isPresented: $showsSelectionLimit) {
      Button(L10n.text("确定"), role: .cancel) {}
    }
  }

  /// 搜索只过滤候选行，不修改已选或未知旧值；添加始终保留输入的原始字符。
  private var filtered: [NativeComboboxItem] {
    input.isEmpty
      ? draft.options : draft.options.filter { $0.title.localizedCaseInsensitiveContains(input) }
  }

  /// 空标题（例如 null 选项）仍有可访问名称和明确触控区。
  private func title(_ item: NativeComboboxItem) -> String {
    item.title.isEmpty ? L10n.text("空值") : item.title
  }

  /// 按回车和加号使用同一逻辑；键盘收起不隐式丢弃或提交尚未确认的父草稿。
  private func addInput() {
    _ = commitInput()
  }

  /// 容量不足时保留待输入值，供调整已有选择后重试。
  private func commitInput() -> Bool {
    guard draft.addCustom(input) else {
      showsSelectionLimit = true
      return false
    }
    input = ""
    inputFocused = false
    failed = false
    return true
  }

  /// 应用也接收尚未按加号的输入；预算/会话失败时留在编辑器中保留本地修改。
  private func confirm() {
    guard commitInput() else { return }
    if draft.hasChanges, let value = draft.value, !apply(value) {
      failed = true
      return
    }
    dismiss()
  }
}
