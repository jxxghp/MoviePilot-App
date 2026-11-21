import SwiftUI

/// 底部 4+1 右侧独立圆形按钮的动态上下文动作定义；无页面注册时自动回退至全局搜索。
struct NativeDynamicAction: Equatable {
  let id: String
  let title: String
  let symbol: String
  let handler: @MainActor () -> Void

  static func == (lhs: NativeDynamicAction, rhs: NativeDynamicAction) -> Bool {
    lhs.id == rhs.id && lhs.title == rhs.title && lhs.symbol == rhs.symbol
  }
}

/// 跨导航栈协调当前顶层页面声明的动态主按钮状态。
@MainActor
final class NativeDynamicActionCenter: ObservableObject {
  @Published private(set) var current: NativeDynamicAction?
  private var stack: [NativeDynamicAction] = []

  /// 注册或更新当前页面的动态主动作。
  func register(_ action: NativeDynamicAction) {
    if let index = stack.firstIndex(where: { $0.id == action.id }) {
      stack[index] = action
    } else {
      stack.append(action)
    }
    current = stack.last
  }

  /// 页面退出或条件不再满足时注销对应动态动作，自动回退上一级或全局搜索。
  func unregister(id: String) {
    stack.removeAll { $0.id == id }
    current = stack.last
  }

  /// 切换一级标签时清空旧栈遗留的动态按钮。
  func reset() {
    stack.removeAll()
    current = nil
  }
}

/// 供任意业务页面声明底部 +1 独立圆形按钮专属动态动作的修饰符。
private struct NativeDynamicActionModifier: ViewModifier {
  @EnvironmentObject private var center: NativeDynamicActionCenter
  let id: String
  let isActive: Bool
  let title: String
  let symbol: String
  let handler: @MainActor () -> Void

  func body(content: Content) -> some View {
    content
      .onAppear { sync() }
      .onChange(of: isActive) { _ in sync() }
      .onChange(of: title) { _ in sync() }
      .onChange(of: symbol) { _ in sync() }
      .onDisappear { center.unregister(id: id) }
  }

  private func sync() {
    if isActive {
      center.register(
        NativeDynamicAction(id: id, title: title, symbol: symbol, handler: handler))
    } else {
      center.unregister(id: id)
    }
  }
}

extension View {
  /// 当 `isActive` 为真时将底部 4+1 右侧圆形按钮切换为当前页专属动态动作；否则自动回退为全局搜索。
  func nativeDynamicAction(
    id: String,
    isActive: Bool = true,
    title: String,
    symbol: String,
    action: @escaping @MainActor () -> Void
  ) -> some View {
    modifier(
      NativeDynamicActionModifier(
        id: id, isActive: isActive, title: title, symbol: symbol, handler: action))
  }
}
