import SwiftUI
import Darwin
/// 独立框架诊断，仅包含系统 Form、TextField 与键盘动作，不链接 MoviePilot。
@main struct MPFrameProbe: App {
  /// 原生窗口用于复现焦点切换，不访问账号或网络。
  var body: some Scene { WindowGroup { ProbeForm() } }
}
/// 定时切换焦点，使单次诊断无需自动化操作实际产品。
struct ProbeForm: View {
  @State private var text = ""
  @FocusState private var focused: Bool
  /// 与产品一致使用原生键盘工具栏，无自定义尺寸或材质。
  var body: some View {
    NavigationStack {
      Form { TextField("Address", text: $text).focused($focused) }
    }.task {
      for _ in 0..<3 {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        focused = true
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        focused = false
      }
      NSLog("MPFrameControl focus cycles completed")
    }
  }
}
