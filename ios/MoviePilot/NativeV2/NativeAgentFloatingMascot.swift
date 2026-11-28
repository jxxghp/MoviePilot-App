import SwiftUI

/// 原生智能助手浮动机器人形象：支持无残影自由拖动并持久化坐标；空闲 3.2 秒自动吸附最近屏幕边缘半隐，不干扰观影海报与正文内容，点按直达智能助手对话。
@MainActor
struct NativeAgentFloatingMascot: View {
  let onOpen: () -> Void
  let onHide: () -> Void

  @AppStorage("nativeV2.mascot.x") private var normalizedX: Double = 0.94
  @AppStorage("nativeV2.mascot.y") private var normalizedY: Double = 0.74
  @Environment(\.nativeVerticalBarEdge) private var verticalBarEdge
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dragTranslation: CGSize = .zero
  @State private var isDragging: Bool = false
  @State private var isBlinking: Bool = false
  @State private var isIdleDocked: Bool = false
  @State private var idleRevision: Int = 0

  private let mascotWidth: CGFloat = 50
  private let mascotHeight: CGFloat = 60

  var body: some View {
    GeometryReader { proxy in
      let isCompactHeight =
        verticalSizeClass == .compact
        || (proxy.size.width > proxy.size.height && proxy.size.height < 500)
      let leadingClearance: CGFloat = verticalBarEdge == .leading ? 76 : 6
      let trailingClearance: CGFloat = verticalBarEdge == .trailing ? 76 : 6
      let topClearance: CGFloat =
        NativeDeviceLayout.isIPad ? 72 : (isCompactHeight ? 10 : 48)
      let bottomClearance: CGFloat =
        (NativeDeviceLayout.isIPad || verticalBarEdge.isActive)
        ? 28
        : (isCompactHeight ? 56 : 92)
      let safeLeft = leadingClearance + mascotWidth / 2
      let safeRight = max(
        proxy.size.width - trailingClearance - mascotWidth / 2,
        safeLeft + 1)
      let safeTop = topClearance + mascotHeight / 2
      let safeBottom = max(
        proxy.size.height - bottomClearance - mascotHeight / 2, safeTop + 1)
      let usableWidth = max(safeRight - safeLeft, 1)
      let usableHeight = max(safeBottom - safeTop, 1)

      let baseX = safeLeft + usableWidth * min(max(CGFloat(normalizedX), 0), 1)
      let baseY = safeTop + usableHeight * min(max(CGFloat(normalizedY), 0), 1)
      let activeX = min(max(baseX + dragTranslation.width, safeLeft), safeRight)
      let activeY = min(max(baseY + dragTranslation.height, safeTop), safeBottom)
      // 空闲半隐时轻柔贴靠最近一侧边缘，露出约 64% 轮廓，避免浮在页面正文与按钮正中。
      let dockLeft = activeX < proxy.size.width * 0.5
      let dockedX: CGFloat =
        dockLeft
        ? (leadingClearance + mascotWidth * 0.16)
        : (proxy.size.width - trailingClearance - mascotWidth * 0.16)
      let currentX = (isIdleDocked && !isDragging) ? dockedX : activeX
      let currentY = activeY

      ZStack {
        robotGlyph
          .frame(width: mascotWidth, height: mascotHeight)
          .drawingGroup()
          .shadow(color: .black.opacity(isIdleDocked ? 0.10 : 0.20), radius: 5, y: 2)
          .scaleEffect(isDragging ? 1.06 : (isIdleDocked ? 0.90 : 1.0))
          .opacity(isDragging ? 1.0 : (isIdleDocked ? 0.50 : 0.94))
          .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
            value: isIdleDocked
          )
          .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isDragging)
          .contentShape(Rectangle().inset(by: -6))
          .onTapGesture {
            if isIdleDocked {
              isIdleDocked = false
              idleRevision += 1
            }
            onOpen()
          }
          .contextMenu {
            Button {
              onOpen()
            } label: {
              Label("打开智能助手", systemImage: "text.bubble")
            }
            Button {
              withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                normalizedX = 0.94
                normalizedY = 0.74
                isIdleDocked = false
                idleRevision += 1
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
            DragGesture(minimumDistance: 4, coordinateSpace: .named("native-mascot-space"))
              .onChanged { value in
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                  isIdleDocked = false
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
                idleRevision += 1
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
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .coordinateSpace(name: "native-mascot-space")
    }
    .task(id: idleRevision) {
      isIdleDocked = false
      try? await Task.sleep(for: .seconds(3.2))
      guard !Task.isCancelled, !isDragging else { return }
      isIdleDocked = true
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(7.2))
        guard !Task.isCancelled else { break }
        guard !isDragging else { continue }
        withAnimation(.easeInOut(duration: 0.11)) { isBlinking = true }
        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.easeInOut(duration: 0.18)) { isBlinking = false }
      }
    }
  }

  /// 柔化液态玻璃质感的 MoviePilot 紫蓝渐变小机器人：去厚重卡通硬描边，保留天线、深色面罩微笑双眼、播放三角核心与短手短脚。
  private var robotGlyph: some View {
    let outline = Color(red: 0.28, green: 0.19, blue: 0.50).opacity(0.42)
    let rimHighlight = Color.white.opacity(0.28)
    let shellStart = Color(red: 0.84, green: 0.80, blue: 0.99)
    let shellMid = Color(red: 0.62, green: 0.50, blue: 0.96)
    let shellEnd = Color(red: 0.45, green: 0.33, blue: 0.84)
    let faceStart = Color(red: 0.13, green: 0.12, blue: 0.22)
    let faceEnd = Color(red: 0.05, green: 0.06, blue: 0.12)
    let eyeColor = Color(red: 0.95, green: 0.93, blue: 1.0)

    return ZStack {
      // 左/右小腿
      HStack(spacing: 7) {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
          .fill(LinearGradient(colors: [shellMid, shellEnd], startPoint: .top, endPoint: .bottom))
          .overlay(
            RoundedRectangle(cornerRadius: 3.5, style: .continuous).stroke(outline, lineWidth: 0.9)
          )
          .frame(width: 7, height: 8)
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
          .fill(LinearGradient(colors: [shellMid, shellEnd], startPoint: .top, endPoint: .bottom))
          .overlay(
            RoundedRectangle(cornerRadius: 3.5, style: .continuous).stroke(outline, lineWidth: 0.9)
          )
          .frame(width: 7, height: 8)
      }
      .offset(y: 22)

      // 左/右小手臂
      HStack(spacing: 22) {
        Capsule()
          .fill(LinearGradient(colors: [shellMid, shellEnd], startPoint: .top, endPoint: .bottom))
          .overlay(Capsule().stroke(outline, lineWidth: 0.9))
          .frame(width: 6, height: 11.5)
          .rotationEffect(.degrees(17))
        Capsule()
          .fill(LinearGradient(colors: [shellMid, shellEnd], startPoint: .top, endPoint: .bottom))
          .overlay(Capsule().stroke(outline, lineWidth: 0.9))
          .frame(width: 6, height: 11.5)
          .rotationEffect(.degrees(-17))
      }
      .offset(y: 12.5)

      // 圆润躯干 + MoviePilot 白色播放三角核心
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [shellMid, shellEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(rimHighlight, lineWidth: 0.7)
          )
        Image(systemName: "play.fill")
          .font(.system(size: 7.5, weight: .bold))
          .foregroundStyle(.white)
          .offset(x: 0.7)
      }
      .frame(width: 23, height: 17)
      .offset(y: 12.5)

      // 头部 + 天线 + 深色面罩与弯月眼睛
      ZStack {
        // 倾斜天线与顶部圆球
        VStack(spacing: -1.8) {
          Circle()
            .fill(shellStart)
            .overlay(Circle().stroke(rimHighlight, lineWidth: 0.7))
            .frame(width: 6, height: 6)
          Capsule()
            .fill(shellEnd.opacity(0.85))
            .frame(width: 2, height: 8)
        }
        .rotationEffect(.degrees(20), anchor: .bottom)
        .offset(x: 1.8, y: -17)

        // 头壳
        RoundedRectangle(cornerRadius: 9.5, style: .continuous)
          .fill(
            LinearGradient(
              colors: [shellStart, shellMid, shellEnd],
              startPoint: .topLeading,
              endPoint: .bottomTrailing)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 9.5, style: .continuous)
              .stroke(
                LinearGradient(
                  colors: [rimHighlight, outline],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
              )
          )
          .frame(width: 39, height: 27)

        // 深色玻璃面罩
        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
          .fill(LinearGradient(colors: [faceStart, faceEnd], startPoint: .top, endPoint: .bottom))
          .overlay(
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
              .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
          )
          .frame(width: 29.5, height: 17)
          .offset(x: -1.3, y: 0.5)

        // 半眯困倦弯月双眼
        HStack(spacing: 6.5) {
          robotEye(color: eyeColor)
          robotEye(color: eyeColor)
            .offset(y: 0.4)
        }
        .offset(x: -1.3, y: 0.4)
      }
      .rotationEffect(.degrees(-3))
      .offset(y: -6)
    }
  }

  /// 还原 Web 版的半眯下弧眼睛：仅描绘下弧轮廓，呈现困倦放松的眯眼状态。
  private func robotEye(color: Color) -> some View {
    SleepyRobotEyeShape()
      .fill(color)
      .frame(width: 7.2, height: 5.2)
      .scaleEffect(y: isBlinking ? 0.15 : 1.0, anchor: UnitPoint(x: 0.5, y: 0.78))
      .shadow(color: color.opacity(0.35), radius: 1)
  }
}

/// 还原 Web `CssRobotRenderer` 的半眯困倦下弧眼形（`border-radius: 0 0 999px 999px; border-bottom`）。
private struct SleepyRobotEyeShape: Shape {
  func path(in rect: CGRect) -> Path {
    let cx = rect.midX
    let rx = rect.width * 0.5
    let outerRy = rect.height
    let innerRy = max(rect.height * 0.54, 0)
    let steps = 20
    var path = Path()
    for i in 0...steps {
      let theta = Double(i) / Double(steps) * .pi
      let x = cx - rx * CGFloat(cos(theta))
      let y = rect.minY + outerRy * CGFloat(sin(theta))
      if i == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        path.addLine(to: CGPoint(x: x, y: y))
      }
    }
    for i in stride(from: steps, through: 0, by: -1) {
      let theta = Double(i) / Double(steps) * .pi
      let x = cx - rx * CGFloat(cos(theta))
      let y = rect.minY + innerRy * CGFloat(sin(theta))
      path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
  }
}
