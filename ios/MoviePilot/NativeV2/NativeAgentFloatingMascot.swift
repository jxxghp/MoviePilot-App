import SwiftUI

/// 原生智能助手浮动机器人形象：还原网页版 MoviePilot 机器人外观，支持自由拖拽、贴边收起与点按直达智能助手对话。
@MainActor
struct NativeAgentFloatingMascot: View {
  let onOpen: () -> Void
  let onHide: () -> Void

  @State private var normalizedY: CGFloat = 0.68
  @State private var snappedToRight: Bool = true
  @State private var isDocked: Bool = false
  @State private var dragTranslation: CGSize = .zero
  @State private var isDragging: Bool = false
  @State private var isBlinking: Bool = false
  @State private var floatPhase: Bool = false

  private let mascotWidth: CGFloat = 56
  private let mascotHeight: CGFloat = 68

  var body: some View {
    GeometryReader { proxy in
      let safeTop = max(proxy.safeAreaInsets.top, 44) + 56
      let safeBottom = max(proxy.safeAreaInsets.bottom, 20) + 112
      let usableHeight = max(proxy.size.height - safeTop - safeBottom, 120)
      let baseY = safeTop + usableHeight * min(max(normalizedY, 0.08), 0.92)
      let edgeInset: CGFloat = isDocked ? -14 : 12
      let restingX =
        snappedToRight
        ? proxy.size.width - mascotWidth / 2 - edgeInset
        : mascotWidth / 2 + edgeInset
      let currentX = min(
        max(restingX + dragTranslation.width, mascotWidth / 2 - 18),
        proxy.size.width - mascotWidth / 2 + 18)
      let currentY = min(
        max(baseY + dragTranslation.height, safeTop),
        proxy.size.height - safeBottom)

      robotGlyph
        .frame(width: mascotWidth, height: mascotHeight)
        .scaleEffect(isDragging ? 1.07 : 1.0)
        .offset(y: isDragging || isDocked ? 0 : (floatPhase ? -3.5 : 1.5))
        .contentShape(Rectangle())
        .onTapGesture {
          if isDocked {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
              isDocked = false
            }
          }
          onOpen()
        }
        .contextMenu {
          Button {
            onOpen()
          } label: {
            Label("打开智能助手", systemImage: "sparkles")
          }
          Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
              isDocked.toggle()
            }
          } label: {
            Label(
              isDocked ? "展开机器人形象" : "贴边收起",
              systemImage: isDocked ? "arrow.left.and.right" : "sidebar.trailing")
          }
          Button(role: .destructive) {
            onHide()
          } label: {
            Label("隐藏浮动助手", systemImage: "eye.slash")
          }
        }
        .gesture(
          DragGesture(minimumDistance: 6)
            .onChanged { value in
              isDragging = true
              if isDocked { isDocked = false }
              dragTranslation = value.translation
            }
            .onEnded { value in
              let endX = restingX + value.translation.width
              let endY = baseY + value.translation.height
              let clampedY = min(max(endY, safeTop), proxy.size.height - safeBottom)
              let nextRight = endX >= proxy.size.width / 2
              let pushedPastEdge =
                nextRight
                ? endX > proxy.size.width - 8
                : endX < 8
              withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                isDragging = false
                dragTranslation = .zero
                snappedToRight = nextRight
                normalizedY = (clampedY - safeTop) / usableHeight
                isDocked = pushedPastEdge
              }
            }
        )
        .position(x: currentX, y: currentY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("浮动智能助手")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("native-agent-floating-mascot")
    }
    .ignoresSafeArea()
    .task {
      withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
        floatPhase = true
      }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(4.2))
        guard !Task.isCancelled else { break }
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
    .shadow(color: Color(red: 0.48, green: 0.32, blue: 0.90).opacity(0.42), radius: 10, y: 6)
  }

  /// 弧形高亮机器人眼睛。
  private func robotEye(color: Color) -> some View {
    Capsule()
      .fill(color)
      .frame(width: 6.5, height: isBlinking ? 1.4 : 4.2)
      .shadow(color: color.opacity(0.65), radius: 2)
  }
}
