import SwiftUI
import UIKit

/// 与 Web 端 `agentPetActions.ts` 1:1 对齐的 16 个内置助手动作。
enum NativeAgentPetAction: String, CaseIterable, Sendable {
  case nod
  case wake
  case wave
  case sit
  case eyeRoll = "eye-roll"
  case faint
  case disassemble
  case happyJump = "happy-jump"
  case sleep
  case stretch
  case peek
  case scan
  case charge
  case spinCheer = "spin-cheer"
  case shy
  case confused

  var durationSeconds: Double {
    switch self {
    case .nod: return 1.5
    case .wake: return 1.8
    case .wave: return 2.8
    case .sit: return 4.2
    case .eyeRoll: return 1.9
    case .faint: return 4.8
    case .disassemble: return 6.2
    case .happyJump: return 2.6
    case .sleep: return 6.8
    case .stretch: return 5.2
    case .peek: return 2.8
    case .scan: return 3.2
    case .charge: return 4.8
    case .spinCheer: return 3.6
    case .shy: return 3.0
    case .confused: return 3.4
    }
  }

  var intent: String {
    switch self {
    case .sleep: return "sleeping"
    case .sit, .stretch: return "idle"
    case .scan, .charge: return "thinking"
    case .happyJump, .spinCheer: return "success"
    default: return "reaction"
    }
  }

  /// Web 同款日常温和动作随机池（打盹/伸懒腰/坐下权重更高）。
  static let randomIdlePool: [NativeAgentPetAction] = [
    .wave, .sit, .sleep, .stretch, .peek, .shy, .confused,
  ]

  /// 选择一个不同于上次动作的随机待机动作。
  static func pickRandomIdle(last: NativeAgentPetAction?) -> NativeAgentPetAction {
    var weighted: [NativeAgentPetAction] = []
    for action in randomIdlePool where action != last {
      let weight: Int
      switch action {
      case .sleep: weight = 3
      case .stretch, .sit: weight = 2
      default: weight = 1
      }
      weighted.append(contentsOf: Array(repeating: action, count: weight))
    }
    return weighted.randomElement() ?? .sleep
  }
}

/// Web `CssRobotRenderer.vue` 同款颜色派生（基于主题强调色混白与深墨色 `#090510`）。
struct NativeRobotPalette {
  let outline: Color
  let outlineSoft: Color
  let shellStart: Color
  let shellMid: Color
  let shellEnd: Color
  let shellShade: Color
  let faceStart: Color
  let faceEnd: Color
  let eye: Color
  let eyeGlow: Color
  let shadow: Color

  /// 从系统强调色计算高光、阴影与描边颜色。
  static func derived(from accent: Color) -> NativeRobotPalette {
    let base = UIColor(accent)
    let ink = UIColor(red: 9.0 / 255.0, green: 5.0 / 255.0, blue: 16.0 / 255.0, alpha: 1)
    let white = UIColor.white
    return NativeRobotPalette(
      outline: Color(Self.mix(base, ink, ratio: 0.68)),
      outlineSoft: Color(Self.mix(base, ink, ratio: 0.46)),
      shellStart: Color(Self.mix(base, white, ratio: 0.54)),
      shellMid: Color(Self.mix(base, white, ratio: 0.16)),
      shellEnd: Color(Self.mix(base, ink, ratio: 0.18)),
      shellShade: Color(red: 9.0 / 255.0, green: 5.0 / 255.0, blue: 16.0 / 255.0).opacity(0.24),
      faceStart: Color(red: 0.14, green: 0.11, blue: 0.24),
      faceEnd: Color(red: 0.05, green: 0.06, blue: 0.12),
      eye: Color(red: 0.96, green: 0.94, blue: 1.0),
      eyeGlow: Color(red: 0.45, green: 1.0, blue: 0.94),
      shadow: Color(Self.mix(base, ink, ratio: 0.78)).opacity(0.32)
    )
  }

  /// 按给定比例混合两种 UIKit 颜色。
  private static func mix(_ a: UIColor, _ b: UIColor, ratio: CGFloat) -> UIColor {
    var ar: CGFloat = 0.58
    var ag: CGFloat = 0.44
    var ab: CGFloat = 0.95
    var aa: CGFloat = 1
    var br: CGFloat = 0.04
    var bg: CGFloat = 0.02
    var bb: CGFloat = 0.06
    var ba: CGFloat = 1
    a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    let t = min(max(ratio, 0), 1)
    return UIColor(
      red: ar * (1 - t) + br * t,
      green: ag * (1 - t) + bg * t,
      blue: ab * (1 - t) + bb * t,
      alpha: 1
    )
  }
}

/// 原生内置智能助手浮动机器人（全量对标 Web `CssRobotRenderer.vue`）：
/// - 主题色自动派生立体外壳 + 清晰 2px 实线描边 + 顶部高光与底部暗部倒角；
/// - 靠近屏幕左右边缘空闲 4.2 秒进入「贴边探头」形态：100% 清晰不透明，歪头 ±19° 露出半脸与单眼，内侧手臂 78° 扒住屏幕边缘；
/// - 5.8s 上半身轻呼吸 + 7.6s 双眨眼 + 全部 16 个 Web 离散动作 + 拖拽晃动彩蛋（晃 3 次晕眩、晃 6 次散架重组、久拖困惑、轻挪点头）。
@MainActor
struct NativeAgentFloatingMascot: View {
  let onOpen: () -> Void
  let onHide: () -> Void
  var onSelectPet: (() -> Void)? = nil
  var onContextMenuVisibilityChange: ((Bool) -> Void)? = nil
  var thinking: Bool = false
  var motionActive: Bool = true
  var dockVisible: Bool = true
  var onInteractiveFrameChange: ((_ hitRect: CGRect, _ isDragging: Bool) -> Void)? = nil

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @AppStorage("nativeV2.mascot.x") private var normalizedX: Double = 0.96
  @AppStorage("nativeV2.mascot.y") private var normalizedY: Double = 0.74
  @Environment(\.nativeVerticalBarEdge) private var verticalBarEdge
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var dragTranslation: CGSize = .zero
  @State private var isDragging: Bool = false
  @State private var isPressed: Bool = false
  @State private var isIdleDocked: Bool = false
  @State private var idleRevision: Int = 0

  @State private var activeAction: NativeAgentPetAction? = nil
  @State private var actionStartedAt: Date = .now
  @State private var lastRandomAction: NativeAgentPetAction? = nil
  @State private var actionClearTask: Task<Void, Never>?

  // 摇晃手势状态（对齐 useAgentPetInteractions.ts）
  @State private var dragStartedAt: Date = .now
  @State private var shakePivotX: CGFloat = 0
  @State private var shakeDirection: Int = 0
  @State private var shakeTurns: Int = 0
  @State private var lastShakeTurnAt: Date = .distantPast

  private let mascotWidth: CGFloat = 58
  private let mascotHeight: CGFloat = 70

  var body: some View {
    GeometryReader { proxy in
      let isCompactHeight =
        verticalSizeClass == .compact
        || (proxy.size.width > proxy.size.height && proxy.size.height < 500)
      let leadingClearance: CGFloat = verticalBarEdge == .leading ? 76 : 6
      let trailingClearance: CGFloat = verticalBarEdge == .trailing ? 76 : 6
      let topClearance: CGFloat =
        NativeDeviceLayout.isIPad ? 72 : (isCompactHeight ? 12 : 52)
      let bottomClearance: CGFloat =
        (NativeDeviceLayout.isIPad || verticalBarEdge.isActive)
        ? 28
        : (dockVisible ? (isCompactHeight ? 58 : 94) : 28)

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

      let distToLeft = activeX - leadingClearance - mascotWidth / 2
      let distToRight = (proxy.size.width - trailingClearance) - (activeX + mascotWidth / 2)
      let nearLeft = distToLeft <= 88
      let nearRight = distToRight <= 88
      let canEdgeDock = nearLeft || nearRight
      let dockLeft = distToLeft < distToRight

      // Web `.is-docked` 贴边探头坐标：保持 100% 清晰不透明，仅半张脸与一只扒边手露出
      let effectiveDocked = isIdleDocked && !isDragging && !thinking && canEdgeDock
      let dockedX: CGFloat =
        dockLeft
        ? (leadingClearance + mascotWidth * 0.14)
        : (proxy.size.width - trailingClearance + mascotWidth * 0.14)
      let currentX = effectiveDocked ? dockedX : activeX
      let currentY = activeY
      let hitRect = CGRect(
        x: currentX - mascotWidth * 0.5,
        y: currentY - mascotHeight * 0.5,
        width: mascotWidth,
        height: mascotHeight
      )

      let palette = NativeRobotPalette.derived(from: appearance.accentColor)

      ZStack {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !motionActive))
        { timeline in
          let now = timeline.date
          let t = now.timeIntervalSinceReferenceDate
          let actionProgress: Double = {
            guard let act = activeAction else { return 0 }
            let elapsed = now.timeIntervalSince(actionStartedAt)
            return min(max(elapsed / max(act.durationSeconds, 0.1), 0), 1)
          }()

          NativeCssRobotView(
            palette: palette,
            time: t,
            isDocked: effectiveDocked,
            dockOnLeft: dockLeft,
            isDragging: isDragging,
            isPressed: isPressed,
            isThinking: thinking,
            action: effectiveDocked ? nil : activeAction,
            actionProgress: actionProgress,
            reduceMotion: reduceMotion || !motionActive
          )
          .frame(width: mascotWidth, height: mascotHeight)
        }
        .shadow(
          color: palette.shadow.opacity(effectiveDocked ? 0.55 : 0.95),
          radius: effectiveDocked ? 4 : 7,
          y: effectiveDocked ? 2 : 5
        )
        .scaleEffect(isDragging ? 1.06 : (isPressed ? 0.95 : 1.0))
        .animation(
          reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78),
          value: effectiveDocked
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isDragging)
        .contentShape(Rectangle().inset(by: -8))
        .onTapGesture {
          if effectiveDocked {
            isIdleDocked = false
            idleRevision += 1
            playAction(.wake)
          }
          onOpen()
        }
        .contextMenu {
          Button {
            onOpen()
          } label: {
            Label("打开智能助手", systemImage: "text.bubble")
          }
          .onAppear { onContextMenuVisibilityChange?(true) }
          .onDisappear { onContextMenuVisibilityChange?(false) }
          if let onSelectPet {
            Button {
              onSelectPet()
            } label: {
              Label("更换助手形象", systemImage: "sparkles")
            }
          }
          Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
              normalizedX = 0.96
              normalizedY = 0.74
              isIdleDocked = false
              idleRevision += 1
            }
            playAction(.happyJump)
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
              let now = Date()
              if !isDragging {
                dragStartedAt = now
                shakePivotX = value.location.x
                shakeDirection = 0
                shakeTurns = 0
                lastShakeTurnAt = .distantPast
              } else {
                let delta = value.location.x - shakePivotX
                if abs(delta) >= 18 {
                  let dir = delta > 0 ? 1 : -1
                  if now.timeIntervalSince(lastShakeTurnAt) > 0.55 {
                    shakeTurns = 0
                  }
                  if shakeDirection != 0 && dir != shakeDirection {
                    shakeTurns += 1
                  }
                  shakeDirection = dir
                  shakePivotX = value.location.x
                  lastShakeTurnAt = now
                }
              }
              var t = Transaction()
              t.disablesAnimations = true
              withTransaction(t) {
                isIdleDocked = false
                isDragging = true
                activeAction = nil
                dragTranslation = value.translation
              }
            }
            .onEnded { value in
              let endX = min(max(baseX + value.translation.width, safeLeft), safeRight)
              let endY = min(max(baseY + value.translation.height, safeTop), safeBottom)
              let now = Date()
              let recentTurns = now.timeIntervalSince(lastShakeTurnAt) <= 0.55 ? shakeTurns : 0
              let elapsed = now.timeIntervalSince(dragStartedAt)
              var t = Transaction()
              t.disablesAnimations = true
              withTransaction(t) {
                normalizedX = Double((endX - safeLeft) / usableWidth)
                normalizedY = Double((endY - safeTop) / usableHeight)
                dragTranslation = .zero
                isDragging = false
              }
              idleRevision += 1
              let reaction: NativeAgentPetAction =
                recentTurns >= 6
                ? .disassemble
                : (recentTurns >= 3 ? .faint : (elapsed > 4.0 ? .confused : .nod))
              playAction(reaction)
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
      .onAppear {
        onInteractiveFrameChange?(hitRect, isDragging)
      }
      .onChange(of: "\(Int(hitRect.minX))|\(Int(hitRect.minY))|\(isDragging)") { _ in
        onInteractiveFrameChange?(hitRect, isDragging)
      }
    }
    .ignoresSafeArea()
    .task(id: "\(idleRevision)|\(motionActive)|\(thinking)") {
      isIdleDocked = false
      guard motionActive, !thinking else { return }
      try? await Task.sleep(for: .seconds(4.2))
      guard !Task.isCancelled, !isDragging, !thinking else { return }
      isIdleDocked = true
    }
    .task(id: "\(motionActive)|\(reduceMotion)") {
      guard motionActive, !reduceMotion else { return }
      while !Task.isCancelled {
        let waitSec = Double.random(in: 12.0...24.0)
        try? await Task.sleep(for: .seconds(waitSec))
        guard !Task.isCancelled else { break }
        guard !isDragging, !isIdleDocked, !thinking, activeAction == nil else { continue }
        let next = NativeAgentPetAction.pickRandomIdle(last: lastRandomAction)
        lastRandomAction = next
        playAction(next)
      }
    }
    .onChange(of: thinking) { isThinkingNow in
      if isThinkingNow {
        isIdleDocked = false
        playAction(.scan)
      }
    }
    .onDisappear {
      actionClearTask?.cancel()
      actionClearTask = nil
    }
  }

  /// 播放指定动作并重置动画进度。
  private func playAction(_ action: NativeAgentPetAction) {
    actionClearTask?.cancel()
    activeAction = action
    actionStartedAt = Date()
    let duration = action.durationSeconds
    actionClearTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(duration))
      guard !Task.isCancelled else { return }
      if activeAction == action {
        activeAction = nil
      }
    }
  }
}

/// 1:1 复刻 Web `CssRobotRenderer.vue` 的高质感矢量机器人绘制器（支持呼吸、眨眼、贴边扒边与全部 16 动作）。
struct NativeCssRobotView: View {
  let palette: NativeRobotPalette
  let time: Double
  let isDocked: Bool
  let dockOnLeft: Bool
  let isDragging: Bool
  let isPressed: Bool
  let isThinking: Bool
  let action: NativeAgentPetAction?
  let actionProgress: Double
  let reduceMotion: Bool

  var body: some View {
    Canvas(opaque: false, rendersAsynchronously: false) { context, size in
      let sx = size.width / 58.0
      let sy = size.height / 70.0
      let cx = size.width * 0.5
      let cy = size.height * 0.5

      let p = actionProgress
      let animEnabled = !reduceMotion

      // 常态 5.8s 上半身轻呼吸 & 7.6s 双眨眼
      let breathPhase =
        animEnabled && action == nil && !isDocked && !isDragging
        ? sin((time / 5.8) * 2.0 * .pi)
        : 0.0
      let breathLiftY = CGFloat(max(0, breathPhase)) * -1.3 * sy
      let breathScaleX = 1.0 + CGFloat(max(0, breathPhase)) * 0.02
      let breathScaleY = 1.0 + CGFloat(max(0, breathPhase)) * 0.036

      let blinkCycle = animEnabled ? (time.truncatingRemainder(dividingBy: 7.6)) / 7.6 : 0.0
      let idleBlinkClosed =
        (blinkCycle > 0.33 && blinkCycle < 0.365) || (blinkCycle > 0.77 && blinkCycle < 0.805)

      // 动作状态派生参数
      var rootOffsetX: CGFloat = 0
      var rootOffsetY: CGFloat = 0
      var rootRotationDeg: Double = 0
      var headOffsetX: CGFloat = 0
      var headOffsetY: CGFloat = breathLiftY
      var headRotationDeg: Double = -3.0
      var bodyOffsetX: CGFloat = 0
      var bodyOffsetY: CGFloat = 0
      var bodyScaleX: CGFloat = breathScaleX
      var bodyScaleY: CGFloat = breathScaleY
      var leftArmDeg: Double = 17.0
      var rightArmDeg: Double = -17.0
      var leftArmOffset = CGSize.zero
      var rightArmOffset = CGSize.zero
      var leftLegOffset = CGSize.zero
      var rightLegOffset = CGSize.zero
      var eyeOffsetX: CGFloat = 0
      var eyeOffsetY: CGFloat = 0
      var eyeScaleY: CGFloat = idleBlinkClosed ? 0.14 : 1.0
      var antennaDeg: Double = 22.0
      var showBlush = false
      var showSleepZ = false
      var showQuestion = false
      var showDizzy = false
      var showScanBeam = isThinking
      var chargeGlow: Double = isThinking ? 0.55 : 0.0
      var happyEyes = false

      if let act = action {
        let waveSin = sin(p * .pi * 2.0)
        switch act {
        case .nod:
          headOffsetY += CGFloat(sin(p * .pi * 4.0)) * 2.2 * sy
          headRotationDeg += sin(p * .pi * 4.0) * 6.0
        case .wake:
          let hop = sin(min(p * 2.2, 1.0) * .pi)
          rootOffsetY -= CGFloat(hop) * 6.0 * sy
          antennaDeg += hop * -18.0
          eyeScaleY = 1.15
        case .wave:
          let env = sin(min(p * 3.0, 1.0) * .pi * 0.5) * sin(min((1.0 - p) * 3.0, 1.0) * .pi * 0.5)
          rightArmDeg = -17.0 - env * (128.0 + sin(p * .pi * 10.0) * 20.0)
          headRotationDeg += env * 7.0
          eyeOffsetX += CGFloat(env) * 1.4 * sx
        case .sit:
          let env = sin(min(p * 3.5, 1.0) * .pi * 0.5) * sin(min((1.0 - p) * 3.5, 1.0) * .pi * 0.5)
          bodyOffsetY += CGFloat(env) * 4.5 * sy
          headOffsetY += CGFloat(env) * 5.2 * sy
          leftLegOffset = CGSize(width: -2.2 * sx * CGFloat(env), height: -2.5 * sy * CGFloat(env))
          rightLegOffset = CGSize(width: 2.2 * sx * CGFloat(env), height: -2.5 * sy * CGFloat(env))
          leftArmDeg = 17.0 - env * 12.0
          rightArmDeg = -17.0 + env * 12.0
        case .eyeRoll:
          eyeOffsetX = CGFloat(cos(p * .pi * 2.0)) * 2.4 * sx
          eyeOffsetY = CGFloat(-abs(sin(p * .pi * 2.0))) * 2.6 * sy
          headRotationDeg += sin(p * .pi * 2.0) * 4.0
        case .faint:
          let env = sin(min(p * 4.0, 1.0) * .pi * 0.5) * sin(min((1.0 - p) * 4.0, 1.0) * .pi * 0.5)
          rootRotationDeg = env * (24.0 + sin(p * .pi * 6.0) * 5.0)
          rootOffsetY += CGFloat(env) * 4.0 * sy
          eyeScaleY = 0.25
          showDizzy = env > 0.2
        case .disassemble:
          let burst = sin(min(max((p - 0.08) / 0.72, 0), 1) * .pi)
          headOffsetY -= CGFloat(burst) * 9.5 * sy
          headRotationDeg += burst * 18.0
          leftArmOffset = CGSize(
            width: -7.5 * sx * CGFloat(burst), height: -3.0 * sy * CGFloat(burst))
          rightArmOffset = CGSize(
            width: 7.5 * sx * CGFloat(burst), height: -3.0 * sy * CGFloat(burst))
          leftArmDeg += burst * 42.0
          rightArmDeg -= burst * 42.0
          leftLegOffset = CGSize(
            width: -4.0 * sx * CGFloat(burst), height: 4.0 * sy * CGFloat(burst))
          rightLegOffset = CGSize(
            width: 4.0 * sx * CGFloat(burst), height: 4.0 * sy * CGFloat(burst))
          bodyOffsetY += CGFloat(burst) * 2.5 * sy
        case .happyJump:
          let bounce = abs(sin(p * .pi * 3.0))
          rootOffsetY -= CGFloat(bounce) * 11.0 * sy
          leftArmDeg = 17.0 + bounce * 118.0
          rightArmDeg = -17.0 - bounce * 118.0
          happyEyes = true
        case .sleep:
          let env = sin(min(p * 4.0, 1.0) * .pi * 0.5) * sin(min((1.0 - p) * 4.0, 1.0) * .pi * 0.5)
          headOffsetY += CGFloat(env) * 2.6 * sy + CGFloat(sin(p * .pi * 6.0)) * 0.8 * sy
          headRotationDeg += env * -9.0
          eyeScaleY = max(0.14, CGFloat(1.0 - env * 0.86))
          showSleepZ = env > 0.25
        case .stretch:
          let env = sin(min(p * 3.0, 1.0) * .pi * 0.5) * sin(min((1.0 - p) * 3.0, 1.0) * .pi * 0.5)
          bodyScaleY = 1.0 + CGFloat(env) * 0.14
          bodyScaleX = 1.0 - CGFloat(env) * 0.06
          headOffsetY -= CGFloat(env) * 3.6 * sy
          leftArmDeg = 17.0 + env * 130.0
          rightArmDeg = -17.0 - env * 130.0
        case .peek:
          let look = sin(p * .pi * 2.0)
          headOffsetX += CGFloat(look) * 4.2 * sx
          headRotationDeg += look * 9.0
          eyeOffsetX += CGFloat(look) * 2.6 * sx
        case .scan:
          showScanBeam = true
          chargeGlow = 0.65
          eyeOffsetX = CGFloat(sin(p * .pi * 4.0)) * 2.2 * sx
        case .charge:
          let env = min(p * 1.4, 1.0)
          chargeGlow = 0.35 + env * 0.65
          rootOffsetX += CGFloat(sin(p * .pi * 28.0)) * 1.3 * sx * CGFloat(env)
          bodyScaleX = 1.0 + CGFloat(env) * 0.06
          bodyScaleY = 1.0 - CGFloat(env) * 0.05
          leftArmDeg = 17.0 + env * 36.0
          rightArmDeg = -17.0 - env * 36.0
        case .spinCheer:
          rootRotationDeg = p < 0.65 ? (p / 0.65) * 360.0 : 0.0
          let lift = sin(p * .pi)
          rootOffsetY -= CGFloat(lift) * 9.0 * sy
          leftArmDeg = 17.0 + lift * 132.0
          rightArmDeg = -17.0 - lift * 132.0
          happyEyes = true
        case .shy:
          let env = sin(min(p * 3.5, 1.0) * .pi * 0.5) * sin(min((1.0 - p) * 3.5, 1.0) * .pi * 0.5)
          showBlush = env > 0.2
          headRotationDeg += waveSin * 7.0 * env
          leftArmDeg = 17.0 - env * 28.0
          rightArmDeg = -17.0 + env * 28.0
          eyeOffsetY += CGFloat(env) * 0.8 * sy
        case .confused:
          let env = sin(min(p * 3.5, 1.0) * .pi * 0.5) * sin(min((1.0 - p) * 3.5, 1.0) * .pi * 0.5)
          headRotationDeg += env * 18.0
          showQuestion = env > 0.22
          eyeOffsetX += CGFloat(env) * 1.2 * sx
        }
      }

      // 贴边探头（Web `.is-docked`：100% 不透明、头歪 ±19° 露出一半、内侧手 78° 扒在最前层）
      if isDocked {
        rootRotationDeg = dockOnLeft ? 19.0 : -19.0
        rootOffsetY = -2.0 * sy
        antennaDeg = dockOnLeft ? -12.0 : 12.0
        eyeOffsetX = (dockOnLeft ? 2.2 : -2.2) * sx
      }

      let strokeW = max(1.6, 1.9 * sx)
      let bodyVisible = !isDocked

      // 主变换上下文（保持 100% 清晰不透明）
      context.drawLayer { layer in
        layer.translateBy(x: cx + rootOffsetX, y: cy + rootOffsetY)
        layer.rotate(by: .degrees(rootRotationDeg))
        layer.translateBy(x: -cx, y: -cy)

        // 1. 蓄力/思考柔和底光
        if chargeGlow > 0.05 && bodyVisible {
          let auraRect = CGRect(
            x: cx - 23 * sx, y: cy - 18 * sy, width: 46 * sx, height: 48 * sy)
          layer.fill(
            Path(ellipseIn: auraRect),
            with: .color(palette.eyeGlow.opacity(0.18 * chargeGlow))
          )
        }

        // 2. 双腿（非贴边态展示）
        if bodyVisible {
          for side in [-1.0, 1.0] {
            let offset = side < 0 ? leftLegOffset : rightLegOffset
            let legW = 8.4 * sx
            let legH = 9.0 * sy
            let lx = cx + CGFloat(side) * 7.6 * sx - legW * 0.5 + offset.width
            let ly = cy + 25.0 * sy - legH * 0.5 + offset.height
            let rect = CGRect(x: lx, y: ly, width: legW, height: legH)
            let path = Path(roundedRect: rect, cornerRadius: 4.0 * sx)
            layer.fill(
              path,
              with: .linearGradient(
                Gradient(colors: [palette.shellMid, palette.outlineSoft]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
              )
            )
            layer.stroke(path, with: .color(palette.outline), lineWidth: strokeW)
          }
        }

        // 3. 手臂（非贴边态在躯干后方）
        if bodyVisible {
          drawArm(
            in: &layer,
            center: CGPoint(
              x: cx - 15.8 * sx + leftArmOffset.width,
              y: cy + 13.5 * sy + leftArmOffset.height),
            size: CGSize(width: 7.4 * sx, height: 13.4 * sy),
            angleDeg: leftArmDeg,
            strokeW: strokeW
          )
          drawArm(
            in: &layer,
            center: CGPoint(
              x: cx + 15.8 * sx + rightArmOffset.width,
              y: cy + 13.5 * sy + rightArmOffset.height),
            size: CGSize(width: 7.4 * sx, height: 13.4 * sy),
            angleDeg: rightArmDeg,
            strokeW: strokeW
          )
        }

        // 4. 圆润躯干 + 胸口纯白播放三角（非贴边态展示）
        if bodyVisible {
          let bodyW = 26.8 * sx * bodyScaleX
          let bodyH = 19.8 * sy * bodyScaleY
          let bx = cx + bodyOffsetX - bodyW * 0.5
          let by = cy + 13.8 * sy + bodyOffsetY - bodyH * 0.5
          let bodyRect = CGRect(x: bx, y: by, width: bodyW, height: bodyH)
          let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 9.2 * sx)

          layer.fill(
            bodyPath,
            with: .linearGradient(
              Gradient(colors: [palette.shellMid, palette.shellEnd]),
              startPoint: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
              endPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY)
            )
          )
          // 顶部柔光高光 & 底部立体倒角暗部
          layer.drawLayer { clipped in
            clipped.clip(to: bodyPath)
            let glossRect = CGRect(
              x: bodyRect.minX + 2 * sx, y: bodyRect.minY + 1.2 * sy,
              width: bodyRect.width - 4 * sx, height: 4.5 * sy)
            clipped.fill(
              Path(roundedRect: glossRect, cornerRadius: 3 * sx),
              with: .color(Color.white.opacity(0.24))
            )
            let shadeRect = CGRect(
              x: bodyRect.minX, y: bodyRect.maxY - 3.2 * sy,
              width: bodyRect.width, height: 3.4 * sy)
            clipped.fill(Path(shadeRect), with: .color(palette.shellShade))
          }
          layer.stroke(bodyPath, with: .color(palette.outline), lineWidth: strokeW)

          // MoviePilot 胸口播放三角
          let corePulse = isThinking ? (0.90 + 0.18 * sin(time * 7.0)) : 1.0
          let playCx = bodyRect.midX + 0.9 * sx
          let playCy = bodyRect.midY
          let pw = 3.9 * sx * CGFloat(corePulse)
          let ph = 4.6 * sy * CGFloat(corePulse)
          var playPath = Path()
          playPath.move(to: CGPoint(x: playCx - pw * 0.85, y: playCy - ph))
          playPath.addLine(to: CGPoint(x: playCx + pw * 1.1, y: playCy))
          playPath.addLine(to: CGPoint(x: playCx - pw * 0.85, y: playCy + ph))
          playPath.closeSubpath()
          layer.fill(playPath, with: .color(isThinking ? palette.eyeGlow : .white))
        }

        // 5. 头部 + 天线 + 深色面罩 + 弯月眼睛
        let headPivot = CGPoint(x: cx + headOffsetX, y: cy - 7.5 * sy + headOffsetY)
        layer.drawLayer { headLayer in
          headLayer.translateBy(x: headPivot.x, y: headPivot.y)
          headLayer.rotate(by: .degrees(headRotationDeg))
          headLayer.translateBy(x: -headPivot.x, y: -headPivot.y)

          // 倾斜天线与圆球
          let antBase = CGPoint(x: headPivot.x + 2.2 * sx, y: headPivot.y - 14.5 * sy)
          headLayer.drawLayer { antLayer in
            antLayer.translateBy(x: antBase.x, y: antBase.y)
            antLayer.rotate(by: .degrees(antennaDeg))
            antLayer.translateBy(x: -antBase.x, y: -antBase.y)
            var stem = Path()
            stem.move(to: antBase)
            stem.addLine(to: CGPoint(x: antBase.x, y: antBase.y - 8.5 * sy))
            antLayer.stroke(
              stem,
              with: .color(palette.outline.opacity(isDocked ? 0.8 : 1.0)),
              style: StrokeStyle(lineWidth: 2.6 * sx, lineCap: .round)
            )
            let ballR = 3.4 * sx
            let ballRect = CGRect(
              x: antBase.x - ballR,
              y: antBase.y - 10.5 * sy - ballR,
              width: ballR * 2,
              height: ballR * 2
            )
            let ballPath = Path(ellipseIn: ballRect)
            antLayer.fill(ballPath, with: .color(palette.shellStart))
            antLayer.stroke(
              ballPath,
              with: .color(palette.outline.opacity(isDocked ? 0.8 : 1.0)),
              lineWidth: strokeW * 0.92
            )
          }

          // 头壳 45×31
          let headW = 45.0 * sx
          let headH = 31.0 * sy
          let headRect = CGRect(
            x: headPivot.x - headW * 0.5,
            y: headPivot.y - headH * 0.5,
            width: headW,
            height: headH
          )
          let headPath = Path(roundedRect: headRect, cornerRadius: 10.8 * sx)
          headLayer.fill(
            headPath,
            with: .linearGradient(
              Gradient(colors: [palette.shellStart, palette.shellMid, palette.shellEnd]),
              startPoint: CGPoint(x: headRect.minX, y: headRect.minY),
              endPoint: CGPoint(x: headRect.maxX, y: headRect.maxY)
            )
          )
          // 头壳顶部内高光 & 底部倒角阴影
          headLayer.drawLayer { clipped in
            clipped.clip(to: headPath)
            let topGloss = CGRect(
              x: headRect.minX + 3 * sx, y: headRect.minY + 1.5 * sy,
              width: headRect.width - 6 * sx, height: 5.0 * sy)
            clipped.fill(
              Path(roundedRect: topGloss, cornerRadius: 3.5 * sx),
              with: .color(Color.white.opacity(0.28))
            )
            let bottomShade = CGRect(
              x: headRect.minX, y: headRect.maxY - 3.6 * sy,
              width: headRect.width, height: 4.0 * sy)
            clipped.fill(Path(bottomShade), with: .color(palette.shellShade))
          }
          headLayer.stroke(headPath, with: .color(palette.outline), lineWidth: strokeW)

          // 深色玻璃面罩 34×19.8
          let faceW = 34.0 * sx
          let faceH = 19.8 * sy
          let faceRect = CGRect(
            x: headPivot.x - 1.5 * sx - faceW * 0.5,
            y: headPivot.y + 0.6 * sy - faceH * 0.5,
            width: faceW,
            height: faceH
          )
          let facePath = Path(roundedRect: faceRect, cornerRadius: 7.2 * sx)
          headLayer.fill(
            facePath,
            with: .linearGradient(
              Gradient(colors: [palette.faceStart, palette.faceEnd]),
              startPoint: CGPoint(x: faceRect.midX, y: faceRect.minY),
              endPoint: CGPoint(x: faceRect.midX, y: faceRect.maxY)
            )
          )
          if isThinking || chargeGlow > 0.2 {
            headLayer.stroke(
              facePath,
              with: .color(palette.eyeGlow.opacity(0.62)),
              lineWidth: 1.8 * sx
            )
          } else {
            headLayer.stroke(facePath, with: .color(palette.outlineSoft), lineWidth: 1.6 * sx)
          }

          // 扫描激光束（scan / thinking）
          if showScanBeam {
            let sweep = (sin(time * 4.2) + 1.0) * 0.5
            let beamX = faceRect.minX + 3 * sx + CGFloat(sweep) * (faceRect.width - 6 * sx)
            headLayer.drawLayer { clipped in
              clipped.clip(to: facePath)
              let beamRect = CGRect(
                x: beamX - 2.2 * sx, y: faceRect.minY, width: 4.4 * sx, height: faceRect.height)
              clipped.fill(Path(beamRect), with: .color(palette.eyeGlow.opacity(0.32)))
            }
          }

          // 害羞腮红（shy）
          if showBlush {
            let blushColor = Color(red: 1.0, green: 0.45, blue: 0.66).opacity(0.55)
            headLayer.fill(
              Path(
                ellipseIn: CGRect(
                  x: faceRect.minX + 3.0 * sx, y: faceRect.midY + 2.2 * sy, width: 5.5 * sx,
                  height: 3.0 * sy)),
              with: .color(blushColor)
            )
            headLayer.fill(
              Path(
                ellipseIn: CGRect(
                  x: faceRect.maxX - 8.5 * sx, y: faceRect.midY + 2.2 * sy, width: 5.5 * sx,
                  height: 3.0 * sy)),
              with: .color(blushColor)
            )
          }

          // 双眼（下弧睡眼 / 开心弯眼）
          let activeEyeColor = (isThinking || chargeGlow > 0.3) ? palette.eyeGlow : palette.eye
          let eyeBaseX = faceRect.midX + eyeOffsetX
          let eyeBaseY = faceRect.midY - 1.2 * sy + eyeOffsetY
          drawRobotEye(
            in: &headLayer,
            center: CGPoint(x: eyeBaseX - 7.3 * sx, y: eyeBaseY),
            width: 7.6 * sx,
            height: 5.2 * sy * eyeScaleY,
            happy: happyEyes,
            color: activeEyeColor
          )
          drawRobotEye(
            in: &headLayer,
            center: CGPoint(x: eyeBaseX + 7.3 * sx, y: eyeBaseY + 0.5 * sy),
            width: 7.6 * sx,
            height: 5.2 * sy * eyeScaleY,
            happy: happyEyes,
            color: activeEyeColor
          )
        }

        // 6. 贴边探头专属：内侧小手移至最前层（z-index: 5）±78° 扒住屏幕边缘！
        if isDocked {
          let gripCenter = CGPoint(
            x: dockOnLeft ? (cx + 4.5 * sx) : (cx - 4.5 * sx),
            y: cy + 12.5 * sy
          )
          drawArm(
            in: &layer,
            center: gripCenter,
            size: CGSize(width: 6.4 * sx, height: 13.8 * sy),
            angleDeg: dockOnLeft ? -78.0 : 78.0,
            strokeW: strokeW
          )
        }
      }

      // 7. 浮动情绪小符号（Zzz / ? / 晕眩星）
      if showSleepZ {
        let floatPhase = (actionProgress * 3.0).truncatingRemainder(dividingBy: 1.0)
        let zPoint = CGPoint(x: cx + 17 * sx, y: cy - 22 * sy - CGFloat(floatPhase) * 9 * sy)
        context.draw(
          Text("zZ").font(.system(size: 10 * sx, weight: .bold, design: .rounded))
            .foregroundColor(palette.shellStart),
          at: zPoint
        )
      } else if showQuestion {
        context.draw(
          Text("?").font(.system(size: 13 * sx, weight: .heavy, design: .rounded))
            .foregroundColor(palette.shellStart),
          at: CGPoint(x: cx + 18 * sx, y: cy - 24 * sy)
        )
      } else if showDizzy {
        let spin = actionProgress * 2.0 * .pi * 3.0
        for idx in 0..<2 {
          let angle = spin + Double(idx) * .pi
          let pt = CGPoint(
            x: cx + CGFloat(cos(angle)) * 16 * sx,
            y: cy - 25 * sy + CGFloat(sin(angle)) * 4 * sy
          )
          context.draw(
            Text("✦").font(.system(size: 9 * sx, weight: .bold)).foregroundColor(palette.eyeGlow),
            at: pt
          )
        }
      }
    }
  }

  /// 按给定姿态绘制机器人手臂。
  private func drawArm(
    in ctx: inout GraphicsContext,
    center: CGPoint,
    size: CGSize,
    angleDeg: Double,
    strokeW: CGFloat
  ) {
    ctx.drawLayer { armLayer in
      armLayer.translateBy(x: center.x, y: center.y)
      armLayer.rotate(by: .degrees(angleDeg))
      let rect = CGRect(
        x: -size.width * 0.5, y: -size.height * 0.5, width: size.width, height: size.height)
      let path = Path(roundedRect: rect, cornerRadius: size.width * 0.5)
      armLayer.fill(
        path,
        with: .linearGradient(
          Gradient(colors: [palette.shellMid, palette.outlineSoft]),
          startPoint: CGPoint(x: 0, y: rect.minY),
          endPoint: CGPoint(x: 0, y: rect.maxY)
        )
      )
      armLayer.stroke(path, with: .color(palette.outline), lineWidth: strokeW)
    }
  }

  /// 绘制带动态状态与高光效果的机器人眼睛。
  private func drawRobotEye(
    in ctx: inout GraphicsContext,
    center: CGPoint,
    width: CGFloat,
    height: CGFloat,
    happy: Bool,
    color: Color
  ) {
    let rx = width * 0.5
    let outerRy = max(height, 1.0)
    let innerRy = outerRy * 0.52
    let steps = 16
    var path = Path()
    let dir: CGFloat = happy ? -1.0 : 1.0
    let baseY = happy ? center.y + outerRy * 0.45 : center.y - outerRy * 0.35
    for i in 0...steps {
      let theta = Double(i) / Double(steps) * .pi
      let x = center.x - rx * CGFloat(cos(theta))
      let y = baseY + dir * outerRy * CGFloat(sin(theta))
      if i == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        path.addLine(to: CGPoint(x: x, y: y))
      }
    }
    for i in stride(from: steps, through: 0, by: -1) {
      let theta = Double(i) / Double(steps) * .pi
      let x = center.x - rx * CGFloat(cos(theta))
      let y = baseY + dir * innerRy * CGFloat(sin(theta))
      path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    ctx.fill(path, with: .color(color))
  }
}
