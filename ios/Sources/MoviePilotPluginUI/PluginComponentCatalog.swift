/// 已观察到的组件族；真正的原生渲染注册必须另行验收，不由名称推断可用。
public enum PluginComponentCatalog {
  /// HTML 原语只分类，script/style/iframe 明确留在插件兼容边界。
  public static func family(for name: String) -> PluginUIComponentFamily {
    switch name {
    case "VForm", "VRow", "VCol", "VContainer", "VCard", "VCardText", "VCardTitle",
      "VCardSubtitle", "VCardItem", "VCardActions", "VSheet", "VSpacer", "VDivider", "div":
      return .layout
    case "VSwitch", "VCheckbox", "VCheckboxBtn", "VTextField", "VTextarea", "VPathField",
      "VSelect", "VCombobox", "VAutocomplete", "VRadio", "VRadioGroup", "VSlider", "VRangeSlider",
      "VCronField", "VCronVuetify", "VChipGroup", "VBtnToggle", "VColorPicker":
      return .input
    case "VAlert", "VChip", "VLabel", "VList", "VListItem", "VListItemTitle",
      "VListItemSubtitle", "VProgressLinear", "VProgressCircular", "VSkeletonLoader",
      "VScrollToTopBtn", "VPageContentTitle",
      "span", "p", "h1", "h2", "h3", "h4", "h5", "h6", "strong", "b", "em", "i", "u",
      "small", "br", "code", "pre":
      return .display
    case "VTable", "VDataTable", "VDataTableVirtual", "table", "thead", "tbody", "tfoot",
      "tr", "td", "th":
      return .table
    case "VApexChart": return .chart
    case "VImg", "VAvatar", "img": return .image
    case "VIcon", "v-icon": return .icon
    case "VBtn", "VDialog", "VDialogCloseBtn", "VMenu", "VTabs", "VTab", "VWindow",
      "VWindowItem", "VExpansionPanels", "VExpansionPanel", "VExpansionPanelTitle",
      "VExpansionPanelText", "VCarousel", "VCarouselItem", "a":
      return .navigation
    case "VAceEditor": return .editor
    case "script", "style", "iframe", "webview", "object", "embed": return .web
    default: return .unknown
    }
  }
}
