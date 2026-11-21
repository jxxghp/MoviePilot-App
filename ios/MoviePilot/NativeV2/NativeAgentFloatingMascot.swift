import SwiftUI

/// 原生智能助手浮动机器人形象：支持无残影自由拖动到屏幕任意安全位置并持久化坐标，点按直达智能助手对话。
@MainActor
struct NativeAgentFloatingMascot: View {
  let onOpen: () -> Void
  let onHide: () -> Void

  @AppStorage("nativeV2.mascot.x") private var normalizedX: Double = 0.88
  @AppStorage("nativeV2.mascot.y") private var normalizedY: Double = 0.72
  @State private var dragTranslation: CGSize = .zero
  @State private var isDragging: Bool = false
  @State private var isBlinking: Bool = false

  private let mascotWidth: CGFloat = 56
  private let mascotHeight: CGFloat = 68

  var body: some View {
    GeometryReader { proxy in
      let safeLeft = max(proxy.safeAreaInsets.leading, 8) + mascotWidth / 2
      let safeRight = max(
        proxy.size.width - max(proxy.safeAreaInsets.trailing, 8) - mascotWidth / 2, safeLeft + 1)
      let safeTop = max(proxy.safeAreaInsets.top, 44) + 52
      let safeBottom = max(
        proxy.size.height - max(proxy.safeAreaInsets.bottom, 20) - 110, safeTop + 1)
      let usableWidth = max(safeRight - safeLeft, 1)
      let usableHeight = max(safeBottom - safeTop, 1)

      let baseX = safeLeft + usableWidth * min(max(CGFloat(normalizedX), 0), 1)
      let baseY = safeTop + usableHeight * min(max(CGFloat(normalizedY), 0), 1)
      let currentX = min(max(baseX + dragTranslation.width, safeLeft), safeRight)
      let currentY = min(max(baseY + dragTranslation.height, safeTop), safeBottom)

      robotGlyph
        .frame(width: mascotWidth, height: mascotHeight)
        .drawingGroup()
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .scaleEffect(isDragging ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isDragging)
        .contentShape(Rectangle())
        .onTapGesture {
          onOpen()
        }
        .contextMenu {
          Button {
            onOpen()
          } label: {
            Label("打开智能助手", systemImage: "sparkles")
          }
          Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
              normalizedX = 0.88
              normalizedY = 0.72
            }
          } label: {
            Label("重置默认位置", systemImage: "arrow.uturn.backward")
          }
          Button(role: .destructive) {
            onHide()
          } label: {
            Label("隐藏浮动助手", systemImage: "eye.slash")
          }
        }
        .gesture(
          DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
              var t = Transaction()
              t.disablesAnimations = true
              withTransaction(t) {
                isDragging = true
                dragTranslation = value.translation
              }
            }
            .onEnded { value in
              let endX = min(max(baseX + value.translation.width, safeLeft), safeRight)
              let endY = min(max(baseY + value.translation.height, safeTop), safeBottom)
              var t = Transaction()
              t.disablesAnimations = true
              withTransaction(t) {
                normalizedX = Double((endX - safeLeft) / usableWidth)
                normalizedY = Double((endY - safeTop) / usableHeight)
                dragTranslation = .zero
                isDragging = false
              }
            }
        )
        .position(x: currentX, y: currentY)
        .transaction { transaction in
          if isDragging { transaction.animation = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("浮动智能助手")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("native-agent-floating-mascot")
    }
    .ignoresSafeArea()
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(4.2))
        guard !Task.isCancelled else { break }
        guard !isDragging else { continue }
        withAnimation(.easeInOut(duration: 0.09)) { isBlinking = true }
        try? await Task.sleep(for: .milliseconds(130))
        withAnimation(.easeInOut(duration: 0.12)) { isBlinking = false }
      }
    }
  }

  /// 还原 `CssRobotRenderer.vue` 的 MoviePilot 紫蓝渐变小机器人：天线、深色面罩微笑双眼、播放三角核心与短手短脚。
  private var robotGlyph: some View {
    let outline = Color(red: 0.28, green: 0.19, blue: 0.50)
    let shellStart = Color(red: 0.86, green: 0.82, blue: 1.0)
    let shellMid = Color(red: 0.64, green: 0.52, blue: 0.98)
    let shellEnd = Color(red: 0.48, green: 0.34, blue: 0.88)
    let faceStart = Color(red: 0.15, green: 0.13, blue: 0.25)
    let faceEnd = Color(red: 0.06, green: 0.07, blue: 0.14)
    let eyeColor = Color(red: 0.94, green: 0.92, blue: 1.0)

    return ZStack {
      // 左/右小腿
      HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(LinearGradient(colors: [shellMid, outline], startPoint: .top, endPoint: .bottom))
          .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(outline, lineWidth: 1.5)
          )
          .frame(width: 8, height: 9)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(LinearGradient(colors: [shellMid, outline], startPoint: .top, endPoint: .bottom))
          .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(outline, lineWidth: 1.5)
          )
          .frame(width: 8, height: 9)
      }
      .offset(y: 25)

      // 左/右小手臂
      HStack(spacing: 25) {
        Capsule()
          .fill(LinearGradient(colors: [shellMid, shellEnd], startPoint: .top, endPoint: .bottom))
          .overlay(Capsule().stroke(outline, lineWidth: 1.5))
          .frame(width: 7, height: 13)
          .rotationEffect(.degrees(17))
        Capsule()
          .fill(LinearGradient(colors: [shellMid, shellEnd], startPoint: .top, endPoint: .bottom))
          .overlay(Capsule().stroke(outline, lineWidth: 1.5))
          .frame(width: 7, height: 13)
          .rotationEffect(.degrees(-17))
      }
      .offset(y: 14)

      // 圆润躯干 + MoviePilot 白色播放三角核心
      ZStack {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(
            LinearGradient(
              colors: [shellMid, shellEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .stroke(outline, lineWidth: 1.6)
          )
        Image(systemName: "play.fill")
          .font(.system(size: 8.5, weight: .bold))
          .foregroundStyle(.white)
          .offset(x: 0.8)
      }
      .frame(width: 26, height: 19)
      .offset(y: 14)

      // 头部 + 天线 + 深色面罩与弯月眼睛
      ZStack {
        // 倾斜天线与顶部圆球
        VStack(spacing: -2) {
          Circle()
            .fill(shellStart)
            .overlay(Circle().stroke(outline, lineWidth: 1.5))
            .frame(width: 7, height: 7)
          Capsule()
            .fill(outline)
            .frame(width: 2.5, height: 9)
        }
        .rotationEffect(.degrees(20), anchor: .bottom)
        .offset(x: 2, y: -19)

        // 头壳
        RoundedRectangle(cornerRadius: 10.5, style: .continuous)
          .fill(
            LinearGradient(
              colors: [shellStart, shellMid, shellEnd],
              startPoint: .topLeading,
              endPoint: .bottomTrailing)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10.5, style: .continuous)
              .stroke(outline, lineWidth: 1.8)
          )
          .frame(width: 44, height: 30)

        // 深色玻璃面罩
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(LinearGradient(colors: [faceStart, faceEnd], startPoint: .top, endPoint: .bottom))
          .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .stroke(outline.opacity(0.9), lineWidth: 1.4)
          )
          .frame(width: 33, height: 19)
          .offset(x: -1.5, y: 0.5)

        // 灵动微笑双眼（周期眨眼）
        HStack(spacing: 8) {
          robotEye(color: eyeColor)
          robotEye(color: eyeColor)
        }
        .offset(x: -1.5, y: 0.5)
      }
      .rotationEffect(.degrees(-3))
      .offset(y: -7)
    }
  }

  /// 弧形高亮机器人眼睛。
  private func robotEye(color: Color) -> some View {
    Capsule()
      .fill(color)
      .frame(width: 6.5, height: isBlinking ? 1.4 : 4.2)
      .shadow(color: color.opacity(0.65), radius: 2)
  }
}
