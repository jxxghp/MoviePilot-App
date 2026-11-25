import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生工作流节点画布与参数编辑页：纯 SwiftUI 渲染节点图、贝塞尔连线、拖拽定位、节点新增与参数编辑，零 WebView。
@MainActor
struct NativeWorkflowCanvasPage: View {
  let session: NativeSession
  let workflowID: Int
  let workflowTitle: String

  @State private var detail: NativeWorkflowDetail?
  @State private var actions: [NativeWorkflowNode] = []
  @State private var flows: [NativeWorkflowEdge] = []
  @State private var actionCatalog: [NativeWorkflowActionDef] = []
  @State private var selectedNodeID: String?
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isSaving = false
  @State private var reloadToken = 0
  @State private var feedback: NativeWorkflowCanvasFeedback?

  @State private var canvasOffset: CGSize = .zero
  @State private var dragCanvasDelta: CGSize = .zero
  @State private var canvasScale: CGFloat = 1.0
  @State private var lastCanvasSize: CGSize = .zero
  @State private var activeNodeDragID: String?
  @State private var activeNodeDragDelta: CGSize = .zero

  @State private var showsAddNodeSheet = false
  @State private var showsInspectorSheet = false
  @State private var showsLinkSheet = false
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  private let nodeWidth: CGFloat = 196
  private let nodeHeight: CGFloat = 86

  private var isCompactHeight: Bool { verticalSizeClass == .compact }

  /// 深色紫玫瑰渐变、可缩放拖拽画布、节点卡片、底部选中工具条及顶部保存按钮。
  var body: some View {
    ZStack {
      CinematicBackground()
      mainContent
    }
    .navigationTitle(detail?.name ?? workflowTitle)
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          showsAddNodeSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .tint(.primary)
        .accessibilityLabel("添加节点")
        .accessibilityIdentifier("native-workflow-add-node")
        .disabled(detail == nil)

        Button {
          Task { await saveWorkflow() }
        } label: {
          if isSaving {
            ProgressView().controlSize(.small).tint(.primary)
          } else {
            Text("保存").fontWeight(.semibold)
          }
        }
        .tint(.primary)
        .accessibilityIdentifier("native-workflow-canvas-save")
        .disabled(detail == nil || isSaving)
      }
    }
    .sheet(isPresented: $showsAddNodeSheet) {
      NativeWorkflowAddNodeSheet(catalog: actionCatalog) { def in
        appendNode(from: def)
      }
    }
    .sheet(isPresented: $showsInspectorSheet) {
      if let selectedID = selectedNodeID,
        let index = actions.firstIndex(where: { $0.id == selectedID })
      {
        NativeWorkflowNodeEditorSheet(node: $actions[index])
      }
    }
    .sheet(isPresented: $showsLinkSheet) {
      if let sourceID = selectedNodeID,
        let sourceNode = actions.first(where: { $0.id == sourceID })
      {
        NativeWorkflowLinkSheet(
          source: sourceNode,
          candidates: actions.filter { $0.id != sourceID },
          existingTargets: Set(flows.filter { $0.source == sourceID }.map(\.target)),
          onToggleTarget: { targetID in
            toggleEdge(from: sourceID, to: targetID)
          }
        )
      }
    }
    .task(id: reloadToken) { await load() }
  }

  /// 加载态、失败态或交互式原生节点画布主视图。
  @ViewBuilder
  private var mainContent: some View {
    if isLoading && detail == nil {
      VStack(spacing: 0) {
        if !isCompactHeight {
          HStack(spacing: 10) {
            NativeSkeletonBlock(width: 116, height: 14, cornerRadius: 5)
            Spacer(minLength: 4)
            NativeSkeletonBlock(width: 30, height: 30, cornerRadius: 15)
            NativeSkeletonBlock(width: 52, height: 24, cornerRadius: 12)
            NativeSkeletonBlock(width: 30, height: 30, cornerRadius: 15)
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 8)
          .nativeSkeletonShimmer()
        }

        NativeCardListSkeletonView(
          style: .workflowCanvas,
          isCompactCanvas: isCompactHeight
        )
        .padding(.horizontal, CinematicStyle.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        HStack(spacing: 8) {
          ForEach(0..<3, id: \.self) { idx in
            NativeSkeletonBlock(width: idx == 1 ? 96 : 78, height: 28, cornerRadius: 14)
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.bottom, isCompactHeight ? 6 : 12)
        .nativeSkeletonShimmer()
      }
      .transition(.opacity)
    } else if loadFailed && detail == nil {
      VStack {
        CinematicPanel {
          VStack(alignment: .leading, spacing: 10) {
            Label("暂时无法载入工作流详情", systemImage: "exclamationmark.triangle").font(.headline)
            Button("重试") { reloadToken += 1 }
              .frame(minHeight: 44)
              .accessibilityIdentifier("native-workflow-canvas-retry")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CinematicStyle.margin)
      }
    } else {
      VStack(spacing: 0) {
        if let feedback {
          feedbackBanner(feedback)
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.top, isCompactHeight ? 4 : 8)
        }
        if !isCompactHeight {
          canvasToolbar
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.vertical, 8)
        }
        graphCanvas
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        if let selected = selectedNode {
          selectedInspectorBar(selected)
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.bottom, isCompactHeight ? 6 : 12)
        } else {
          nodeListStrip
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.bottom, isCompactHeight ? 6 : 12)
        }
      }
    }
  }

  /// 当前选中的节点。
  private var selectedNode: NativeWorkflowNode? {
    guard let selectedNodeID else { return nil }
    return actions.first(where: { $0.id == selectedNodeID })
  }

  /// 画布顶部摘要与缩放/居中控制条。
  private var canvasToolbar: some View {
    HStack(spacing: 10) {
      Label("\(actions.count) 节点 · \(flows.count) 连线", systemImage: "flowchart")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary.opacity(0.84))
      Spacer(minLength: 4)
      Button {
        canvasScale = max(0.55, canvasScale - 0.15)
      } label: {
        Image(systemName: "minus.magnifyingglass")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .frame(width: 30, height: 30)
          .background(NativeTheme.chipFill, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("缩小画布")

      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          canvasScale = 1.0
          centerCanvas()
        }
      } label: {
        Text("\(Int((canvasScale * 100).rounded()))%")
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundStyle(.primary.opacity(0.88))
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(NativeTheme.chipFill, in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("重置画布视角")
      .accessibilityIdentifier("native-workflow-canvas-reset-view")

      Button {
        canvasScale = min(1.6, canvasScale + 0.15)
      } label: {
        Image(systemName: "plus.magnifyingglass")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.primary)
          .frame(width: 30, height: 30)
          .background(NativeTheme.chipFill, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("放大画布")
    }
  }

  /// 纯 SwiftUI 交互式节点与连线画布。
  private var graphCanvas: some View {
    GeometryReader { proxy in
      let totalOffset = CGSize(
        width: canvasOffset.width + dragCanvasDelta.width,
        height: canvasOffset.height + dragCanvasDelta.height)

      ZStack(alignment: .topLeading) {
        // 点阵背景 + 贝塞尔连线层
        Canvas { context, size in
          drawDotGrid(in: &context, size: size, offset: totalOffset, scale: canvasScale)
          drawEdges(in: &context, offset: totalOffset, scale: canvasScale)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("native-workflow-canvas-area")
        .onTapGesture {
          selectedNodeID = nil
        }
        .gesture(
          DragGesture(minimumDistance: 6)
            .onChanged { value in
              dragCanvasDelta = value.translation
            }
            .onEnded { value in
              canvasOffset.width += value.translation.width
              canvasOffset.height += value.translation.height
              dragCanvasDelta = .zero
            }
        )

        if actions.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
              .font(.largeTitle)
              .foregroundStyle(.primary.opacity(0.55))
            Text("当前工作流还没有节点")
              .font(.headline)
              .foregroundStyle(.primary)
            Text("点击右上角「+」添加动作节点并自动编排连线")
              .font(.caption)
              .foregroundStyle(.primary.opacity(0.68))
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .allowsHitTesting(false)
        } else {
          ForEach(actions) { node in
            let pt = screenCenter(for: node, offset: totalOffset, scale: canvasScale)
            nodeCard(node)
              .scaleEffect(canvasScale)
              .position(pt)
              .gesture(
                DragGesture(minimumDistance: 4)
                  .onChanged { value in
                    activeNodeDragID = node.id
                    activeNodeDragDelta = CGSize(
                      width: value.translation.width / max(canvasScale, 0.3),
                      height: value.translation.height / max(canvasScale, 0.3))
                  }
                  .onEnded { value in
                    if let idx = actions.firstIndex(where: { $0.id == node.id }) {
                      actions[idx].position.x += Double(
                        value.translation.width / max(canvasScale, 0.3))
                      actions[idx].position.y += Double(
                        value.translation.height / max(canvasScale, 0.3))
                    }
                    activeNodeDragID = nil
                    activeNodeDragDelta = .zero
                  }
              )
          }
        }
      }
      .clipped()
      .overlay(alignment: .top) {
        if isCompactHeight {
          canvasToolbar
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
              Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                  Capsule().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6)
                }
            }
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.top, 6)
        }
      }
      .onAppear {
        lastCanvasSize = proxy.size
        if canvasOffset == .zero && !actions.isEmpty {
          centerCanvas(in: proxy.size)
        }
      }
      .onChange(of: proxy.size) { newSize in
        if lastCanvasSize.width > 0, lastCanvasSize.height > 0,
          abs(newSize.width - lastCanvasSize.width) > 1
            || abs(newSize.height - lastCanvasSize.height) > 1
        {
          canvasOffset.width += (newSize.width - lastCanvasSize.width) / 2
          canvasOffset.height += (newSize.height - lastCanvasSize.height) / 2
        }
        lastCanvasSize = newSize
      }
      .onChange(of: actions.count) { _ in
        if canvasOffset == .zero && !actions.isEmpty {
          centerCanvas(in: proxy.size)
        }
      }
    }
  }

  /// 单个工作流节点的透色紫玫瑰玻璃卡片。
  private func nodeCard(_ node: NativeWorkflowNode) -> some View {
    let selected = selectedNodeID == node.id
    let paramCount = node.data.count
    return Button {
      selectedNodeID = node.id
    } label: {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 6) {
          Circle()
            .fill(
              selected
                ? Color(red: 0.78, green: 0.62, blue: 1.0)
                : Color(red: 0.56, green: 0.88, blue: 0.76)
            )
            .frame(width: 8, height: 8)
          Text(node.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Spacer(minLength: 2)
        }
        Text(node.type)
          .font(.caption2.monospaced())
          .foregroundStyle(NativeTheme.brand)
          .lineLimit(1)
        HStack(spacing: 6) {
          if !node.description.isEmpty {
            Text(node.description)
              .font(.caption2)
              .foregroundStyle(.primary.opacity(0.68))
              .lineLimit(1)
          } else {
            Text("参数 \(paramCount) 项")
              .font(.caption2)
              .foregroundStyle(.primary.opacity(0.64))
          }
          Spacer(minLength: 2)
          if let timeout = node.timeout, timeout > 0 {
            Text("\(timeout)s")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.primary.opacity(0.58))
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(width: nodeWidth, height: nodeHeight, alignment: .leading)
      .background {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        shape
          .fill(.ultraThinMaterial)
          .overlay {
            shape.fill(
              selected
                ? NativeAppearanceStore.shared.accentColor.opacity(0.22)
                : Color.white.opacity(0.05)
            )
          }
          .overlay {
            shape.strokeBorder(
              selected
                ? NativeAppearanceStore.shared.accentColor.opacity(0.90)
                : Color.white.opacity(0.22),
              lineWidth: selected ? 1.5 : 0.75)
          }
      }
      .shadow(color: .black.opacity(selected ? 0.24 : 0.12), radius: selected ? 10 : 6, y: 4)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-workflow-node-\(node.id)")
  }

  /// 未选中节点时的底部快捷节点列表条，方便无障碍与小屏直达选中。
  private var nodeListStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(actions) { node in
          Button {
            selectedNodeID = node.id
          } label: {
            Text(node.name)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.primary.opacity(0.90))
              .padding(.horizontal, 11)
              .padding(.vertical, 7)
              .background {
                Capsule()
                  .fill(.primary.opacity(0.11))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.6) }
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-workflow-chip-\(node.id)")
        }
      }
    }
  }

  /// 选中节点后的底部玻璃属性工具栏：紧凑横屏自动折叠为 ~50pt 单行工具栏，释放画布纵向视口。
  @ViewBuilder
  private func selectedInspectorBar(_ node: NativeWorkflowNode) -> some View {
    let outgoing = flows.filter { $0.source == node.id }.count
    if isCompactHeight {
      CinematicPanel(padding: 8) {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 1) {
            Text(node.name)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            Text("\(node.type) · 参数 \(node.data.count) · 出边 \(outgoing)")
              .font(.caption2)
              .foregroundStyle(.primary.opacity(0.66))
              .lineLimit(1)
          }
          Spacer(minLength: 4)
          Button {
            showsInspectorSheet = true
          } label: {
            Label("编辑参数", systemImage: "slider.horizontal.3")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.primary)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.78))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.24), lineWidth: 0.6) }
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-workflow-edit-node")

          Button {
            showsLinkSheet = true
          } label: {
            Label("连线", systemImage: "arrow.triangle.branch")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.primary)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(.primary.opacity(0.14))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.20), lineWidth: 0.6) }
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-workflow-link-node")

          Button(role: .destructive) {
            deleteNode(node.id)
          } label: {
            Image(systemName: "trash")
              .font(.caption.weight(.semibold))
              .foregroundStyle(NativeTheme.danger)
              .frame(width: 30, height: 30)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("删除")
          .accessibilityIdentifier("native-workflow-delete-node")

          Button {
            selectedNodeID = nil
          } label: {
            Image(systemName: "xmark")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.primary.opacity(0.70))
              .frame(width: 28, height: 30)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("取消选中")
        }
      }
    } else {
      CinematicPanel(padding: 12) {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(node.name).font(.headline).foregroundStyle(.primary)
              Text("\(node.type) · 参数 \(node.data.count) 项 · 出边 \(outgoing) 条")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.68))
            }
            Spacer()
            Button {
              selectedNodeID = nil
            } label: {
              Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.70))
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
          }
          HStack(spacing: 8) {
            Button {
              showsInspectorSheet = true
            } label: {
              Label("编辑参数", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                  Capsule()
                    .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.78))
                    .overlay { Capsule().strokeBorder(.primary.opacity(0.24), lineWidth: 0.6) }
                }
                .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-workflow-edit-node")

            Button {
              showsLinkSheet = true
            } label: {
              Label("连线", systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                  Capsule()
                    .fill(.primary.opacity(0.14))
                    .overlay { Capsule().strokeBorder(.primary.opacity(0.20), lineWidth: 0.6) }
                }
                .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-workflow-link-node")

            Spacer()

            Button(role: .destructive) {
              deleteNode(node.id)
            } label: {
              Label("删除", systemImage: "trash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.danger)
                .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-workflow-delete-node")
          }
        }
      }
    }
  }

  /// 操作反馈横幅。
  private func feedbackBanner(_ feedback: NativeWorkflowCanvasFeedback) -> some View {
    CinematicPanel(padding: 10) {
      HStack(spacing: 8) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : NativeTheme.success)
        Text(feedback.message).font(.subheadline).foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.65)).frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-workflow-canvas-feedback")
  }

  /// 计算节点在画布视口中的屏幕中心坐标。
  private func screenCenter(
    for node: NativeWorkflowNode, offset: CGSize, scale: CGFloat
  ) -> CGPoint {
    let extra = activeNodeDragID == node.id ? activeNodeDragDelta : .zero
    let worldX = CGFloat(node.position.x) + extra.width + nodeWidth / 2
    let worldY = CGFloat(node.position.y) + extra.height + nodeHeight / 2
    return CGPoint(x: worldX * scale + offset.width, y: worldY * scale + offset.height)
  }

  /// 绘制轻柔点阵参考网格。
  private func drawDotGrid(
    in context: inout GraphicsContext, size: CGSize, offset: CGSize, scale: CGFloat
  ) {
    let step = max(22 * scale, 14)
    let startX = offset.width.truncatingRemainder(dividingBy: step)
    let startY = offset.height.truncatingRemainder(dividingBy: step)
    var y = startY
    while y < size.height {
      var x = startX
      while x < size.width {
        let rect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.11)))
        x += step
      }
      y += step
    }
  }

  /// 绘制节点间的三次贝塞尔有向连线与箭头。
  private func drawEdges(in context: inout GraphicsContext, offset: CGSize, scale: CGFloat) {
    let nodeMap = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
    for edge in flows {
      guard let src = nodeMap[edge.source], let dst = nodeMap[edge.target] else { continue }
      let p1 = screenCenter(for: src, offset: offset, scale: scale)
      let p2 = screenCenter(for: dst, offset: offset, scale: scale)
      let horizontal = abs(p2.x - p1.x) >= abs(p2.y - p1.y)
      let start =
        horizontal
        ? CGPoint(x: p1.x + (nodeWidth / 2) * scale, y: p1.y)
        : CGPoint(x: p1.x, y: p1.y + (nodeHeight / 2) * scale)
      let end =
        horizontal
        ? CGPoint(x: p2.x - (nodeWidth / 2) * scale, y: p2.y)
        : CGPoint(x: p2.x, y: p2.y - (nodeHeight / 2) * scale)

      var path = Path()
      path.move(to: start)
      if horizontal {
        let ctrl = max(abs(end.x - start.x) * 0.45, 36 * scale)
        path.addCurve(
          to: end,
          control1: CGPoint(x: start.x + ctrl, y: start.y),
          control2: CGPoint(x: end.x - ctrl, y: end.y))
      } else {
        let ctrl = max(abs(end.y - start.y) * 0.45, 36 * scale)
        path.addCurve(
          to: end,
          control1: CGPoint(x: start.x, y: start.y + ctrl),
          control2: CGPoint(x: end.x, y: end.y - ctrl))
      }

      let active = selectedNodeID == src.id || selectedNodeID == dst.id
      let color =
        active
        ? Color(red: 0.84, green: 0.68, blue: 1.0)
        : Color(red: 0.68, green: 0.56, blue: 0.92).opacity(0.70)
      context.stroke(path, with: .color(color), lineWidth: active ? 2.4 : 1.7)

      let arrowSize: CGFloat = 6 * scale
      var arrow = Path()
      if horizontal {
        arrow.move(to: end)
        arrow.addLine(to: CGPoint(x: end.x - arrowSize * 1.4, y: end.y - arrowSize))
        arrow.addLine(to: CGPoint(x: end.x - arrowSize * 1.4, y: end.y + arrowSize))
      } else {
        arrow.move(to: end)
        arrow.addLine(to: CGPoint(x: end.x - arrowSize, y: end.y - arrowSize * 1.4))
        arrow.addLine(to: CGPoint(x: end.x + arrowSize, y: end.y - arrowSize * 1.4))
      }
      arrow.closeSubpath()
      context.fill(arrow, with: .color(color))
    }
  }

  /// 将现有节点图居中并自动适配视口缩放。
  private func centerCanvas(in size: CGSize = CGSize(width: 390, height: 480)) {
    guard !actions.isEmpty else {
      canvasOffset = .zero
      return
    }
    let minX = actions.map { CGFloat($0.position.x) }.min() ?? 0
    let maxX = actions.map { CGFloat($0.position.x) + nodeWidth }.max() ?? nodeWidth
    let minY = actions.map { CGFloat($0.position.y) }.min() ?? 0
    let spanX = max(maxX - minX, nodeWidth)
    if actions.count >= 2 && spanX > size.width - 32 {
      let fitScale = (size.width - 40) / spanX
      canvasScale = min(1.0, max(0.62, fitScale))
    }
    canvasOffset = CGSize(
      width: 20 - minX * canvasScale,
      height: max(28, size.height * 0.14) - minY * canvasScale)
  }

  /// 从动作目录追加新节点，若当前已有选中节点则自动建立连线。
  private func appendNode(from def: NativeWorkflowActionDef) {
    let last = selectedNode ?? actions.last
    let nextX = (last?.position.x ?? 20) + 40
    let nextY = (last?.position.y ?? 20) + 128
    let newID = "node_\(UUID().uuidString.prefix(8).lowercased())"
    let node = NativeWorkflowNode(
      id: newID,
      type: def.type,
      name: def.name,
      description: def.description ?? "",
      position: NativeWorkflowPosition(x: nextX, y: nextY),
      data: def.data,
      timeout: nil,
      failPolicy: nil
    )
    actions.append(node)
    if let source = last {
      flows.append(
        NativeWorkflowEdge(
          id: "flow_\(source.id)_\(newID)",
          source: source.id,
          target: newID,
          animated: true,
          condition: nil))
    }
    selectedNodeID = newID
    feedback = NativeWorkflowCanvasFeedback(
      isError: false, message: "已添加节点「\(node.name)」，点击右上角保存生效。")
  }

  /// 切换两节点间的有向连线。
  private func toggleEdge(from sourceID: String, to targetID: String) {
    if let idx = flows.firstIndex(where: { $0.source == sourceID && $0.target == targetID }) {
      flows.remove(at: idx)
    } else {
      flows.append(
        NativeWorkflowEdge(
          id: "flow_\(sourceID)_\(targetID)",
          source: sourceID,
          target: targetID,
          animated: true,
          condition: nil))
    }
  }

  /// 删除节点及其关联出入边。
  private func deleteNode(_ nodeID: String) {
    actions.removeAll { $0.id == nodeID }
    flows.removeAll { $0.source == nodeID || $0.target == nodeID }
    if selectedNodeID == nodeID {
      selectedNodeID = nil
    }
  }

  /// 并发拉取 `GET /api/v1/workflow/{id}` 与 `GET /api/v1/workflow/actions`。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let detailEndpoint = try APIEndpoint(path: ["workflow", String(workflowID)])
      let catalogEndpoint = try APIEndpoint(path: ["workflow", "actions"])
      async let detailTask = session.request(detailEndpoint, as: NativeWorkflowDetail.self)
      async let catalogTask = try? session.request(
        catalogEndpoint, as: [NativeWorkflowActionDef].self)
      let loadedDetail = try await detailTask.value
      let loadedCatalog = await catalogTask?.value ?? []
      try Task.checkCancellation()
      detail = loadedDetail
      actions = loadedDetail.normalizedActions
      flows = loadedDetail.flows ?? []
      actionCatalog = loadedCatalog
      if selectedNodeID == nil, let first = actions.first {
        selectedNodeID = first.id
      }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 单次提交更新后的节点与连线（`PUT /api/v1/workflow/{id}`）。
  private func saveWorkflow() async {
    guard let detail, !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    let payload = NativeWorkflowUpdatePayload(
      id: detail.id,
      name: detail.name,
      description: detail.description,
      timer: detail.timer,
      triggerType: detail.triggerType,
      eventType: detail.eventType,
      state: detail.state,
      actions: actions,
      flows: flows
    )
    do {
      let body = try JSONEncoder().encode(payload)
      let endpoint = try APIEndpoint(
        path: ["workflow", String(workflowID)], method: .put, body: body)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      feedback = NativeWorkflowCanvasFeedback(isError: false, message: "工作流节点与连线已保存。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeWorkflowCanvasFeedback(isError: true, message: "保存工作流失败，请检查节点配置后重试。")
    }
  }
}

/// 添加工作流节点目录弹层。
@MainActor
private struct NativeWorkflowAddNodeSheet: View {
  let catalog: [NativeWorkflowActionDef]
  let onSelect: (NativeWorkflowActionDef) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filtered: [NativeWorkflowActionDef] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return catalog }
    return catalog.filter {
      $0.name.lowercased().contains(trimmed)
        || $0.type.lowercased().contains(trimmed)
        || ($0.description ?? "").lowercased().contains(trimmed)
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(spacing: 10) {
            if filtered.isEmpty {
              CinematicPanel {
                Text("暂无可选动作节点")
                  .font(.subheadline)
                  .foregroundStyle(.primary.opacity(0.75))
                  .frame(maxWidth: .infinity, minHeight: 100)
              }
            } else {
              ForEach(filtered) { def in
                Button {
                  onSelect(def)
                  dismiss()
                } label: {
                  CinematicPanel(padding: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                      HStack {
                        Text(def.name).font(.headline).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                          .foregroundStyle(Color(red: 0.80, green: 0.68, blue: 1.0))
                      }
                      Text(def.type)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color(red: 0.82, green: 0.72, blue: 1.0))
                      if let desc = def.description, !desc.isEmpty {
                        Text(desc)
                          .font(.caption)
                          .foregroundStyle(.primary.opacity(0.72))
                          .lineLimit(2)
                      }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workflow-catalog-\(def.type)")
              }
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("添加工作流节点")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .searchable(text: $query, prompt: "搜索动作名称或类名")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-workflow-catalog-close")
        }
      }
    }
    .nativeGlassSheet()
    .nativeAdaptiveSheetSizing()
  }
}

/// 单个工作流节点的原生参数编辑器弹层（iOS 设置式「左标签 + 右参数值」分组布局）。
@MainActor
private struct NativeWorkflowNodeEditorSheet: View {
  @Binding var node: NativeWorkflowNode
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  @State private var nameText = ""
  @State private var descText = ""
  @State private var timeoutText = ""
  @State private var stringParams: [(key: String, value: String)] = []
  @State private var boolParams: [(key: String, value: Bool)] = []
  @State private var newKey = ""
  @State private var newValue = ""

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
              sectionHeader("基础属性")
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  settingInputRow(
                    "节点名称",
                    placeholder: "输入节点名称",
                    text: $nameText,
                    accessibilityID: "native-workflow-node-name-field"
                  )
                  CinematicFormDivider()
                  settingInputRow(
                    "节点描述",
                    placeholder: "可选说明",
                    text: $descText
                  )
                  CinematicFormDivider()
                  settingInputRow(
                    "超时时间",
                    placeholder: "默认不限制（秒）",
                    text: $timeoutText,
                    keyboardType: .numberPad
                  )
                }
              }
            }

            if !boolParams.isEmpty || !stringParams.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                sectionHeader("动作参数")
                CinematicPanel(padding: 0) {
                  VStack(spacing: 0) {
                    ForEach(Array(boolParams.enumerated()), id: \.element.key) { idx, item in
                      if idx > 0 {
                        CinematicFormDivider()
                      }
                      Toggle(
                        isOn: Binding(
                          get: { boolParams[idx].value },
                          set: { boolParams[idx].value = $0 }
                        )
                      ) {
                        Text(item.key)
                          .font(.subheadline.monospaced())
                          .foregroundStyle(.primary)
                      }
                      .tint(appearance.accentColor)
                      .padding(.horizontal, 15)
                      .padding(.vertical, 10)
                    }
                    ForEach(Array(stringParams.enumerated()), id: \.element.key) { idx, item in
                      if idx > 0 || !boolParams.isEmpty {
                        CinematicFormDivider()
                      }
                      settingInputRow(
                        item.key,
                        placeholder: "输入参数值",
                        text: Binding(
                          get: { stringParams[idx].value },
                          set: { stringParams[idx].value = $0 }
                        ),
                        monospacedLabel: true,
                        accessibilityID: "native-workflow-param-\(item.key)"
                      )
                    }
                  }
                }
              }
            }

            VStack(alignment: .leading, spacing: 8) {
              sectionHeader("新增自定义参数")
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  settingInputRow(
                    "参数键",
                    placeholder: "如 max_count",
                    text: $newKey,
                    monospacedValue: true
                  )
                  CinematicFormDivider()
                  settingInputRow(
                    "参数值",
                    placeholder: "输入默认值",
                    text: $newValue
                  )
                  CinematicFormDivider()
                  Button {
                    let k = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !k.isEmpty else { return }
                    if let existingIdx = stringParams.firstIndex(where: { $0.key == k }) {
                      stringParams[existingIdx].value = newValue
                    } else {
                      stringParams.append((key: k, value: newValue))
                    }
                    newKey = ""
                    newValue = ""
                  } label: {
                    Label("添加参数", systemImage: "plus.circle.fill")
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(
                        newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? .secondary : appearance.accentColor
                      )
                      .frame(maxWidth: .infinity)
                      .padding(.vertical, 12)
                  }
                  .buttonStyle(.plain)
                  .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
              }
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("节点参数")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
            .accessibilityIdentifier("native-workflow-node-editor-cancel")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("应用") {
            applyChanges()
            dismiss()
          }
          .fontWeight(.semibold)
          .tint(.primary)
          .accessibilityIdentifier("native-workflow-node-editor-apply")
        }
      }
      .onAppear { loadFields() }
    }
    .nativeGlassSheet()
    .nativeAdaptiveSheetSizing()
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.footnote.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
  }

  private func settingInputRow(
    _ label: String,
    placeholder: String,
    text: Binding<String>,
    monospacedLabel: Bool = false,
    monospacedValue: Bool = false,
    keyboardType: UIKeyboardType = .default,
    accessibilityID: String? = nil
  ) -> some View {
    HStack(spacing: 12) {
      Text(label)
        .font(monospacedLabel ? .subheadline.monospaced() : .subheadline)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .layoutPriority(1)
      TextField(placeholder, text: text)
        .font(monospacedValue ? .subheadline.monospaced() : .subheadline)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.trailing)
        .keyboardType(keyboardType)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityIdentifier(accessibilityID ?? "")
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 12)
  }

  private func loadFields() {
    nameText = node.name
    descText = node.description
    timeoutText = node.timeout.map(String.init) ?? ""
    var strs: [(String, String)] = []
    var bools: [(String, Bool)] = []
    for key in node.data.keys.sorted() {
      guard let val = node.data[key] else { continue }
      switch val {
      case .bool(let flag):
        bools.append((key, flag))
      case .string(let text):
        strs.append((key, text))
      case .number(let num):
        let formatted =
          abs(num.rounded() - num) < 0.001 ? String(Int(num.rounded())) : String(num)
        strs.append((key, formatted))
      default:
        continue
      }
    }
    stringParams = strs
    boolParams = bools
  }

  private func applyChanges() {
    let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedName.isEmpty { node.name = trimmedName }
    node.description = descText.trimmingCharacters(in: .whitespacesAndNewlines)
    node.timeout = Int(timeoutText.trimmingCharacters(in: .whitespacesAndNewlines))
    var updated = node.data
    for (key, flag) in boolParams {
      updated[key] = .bool(flag)
    }
    for (key, text) in stringParams {
      if case .number = node.data[key], let parsed = Double(text) {
        updated[key] = .number(parsed)
      } else {
        updated[key] = .string(text)
      }
    }
    node.data = updated
  }
}

/// 节点出边连线管理弹层。
@MainActor
private struct NativeWorkflowLinkSheet: View {
  let source: NativeWorkflowNode
  let candidates: [NativeWorkflowNode]
  let existingTargets: Set<String>
  let onToggleTarget: (String) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(spacing: 10) {
            ForEach(candidates) { target in
              let linked = existingTargets.contains(target.id)
              Button {
                onToggleTarget(target.id)
                dismiss()
              } label: {
                CinematicPanel(padding: 12) {
                  HStack {
                    VStack(alignment: .leading, spacing: 3) {
                      Text(target.name).font(.headline).foregroundStyle(.primary)
                      Text(target.type).font(.caption2.monospaced()).foregroundStyle(
                        .white.opacity(0.66))
                    }
                    Spacer()
                    Image(systemName: linked ? "link.circle.fill" : "plus.circle")
                      .foregroundStyle(
                        linked
                          ? NativeTheme.success
                          : Color(red: 0.80, green: 0.68, blue: 1.0))
                  }
                }
              }
              .buttonStyle(.plain)
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
        }
      }
      .navigationTitle("从「\(source.name)」连线")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
        }
      }
    }
    .nativeGlassSheet()
    .nativeAdaptiveSheetSizing()
  }
}

/// 画布反馈提示载体。
private struct NativeWorkflowCanvasFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/workflow/{id}` 完整工作流详情模型。
private struct NativeWorkflowDetail: Decodable, Sendable {
  let id: Int
  let name: String
  let description: String?
  let timer: String?
  let triggerType: String?
  let eventType: String?
  let state: String?
  let actions: [NativeWorkflowNode]?
  let flows: [NativeWorkflowEdge]?

  /// 若旧节点缺少坐标，则自动纵向错开布局避免重叠。
  var normalizedActions: [NativeWorkflowNode] {
    let raw = actions ?? []
    let allZero = raw.count > 1 && raw.allSatisfy { $0.position.x == 0 && $0.position.y == 0 }
    guard allZero else { return raw }
    return raw.enumerated().map { idx, item in
      var copy = item
      copy.position = NativeWorkflowPosition(
        x: Double(idx % 2) * 40 + 20, y: Double(idx) * 124 + 20)
      return copy
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, timer, state, actions, flows
    case triggerType = "trigger_type"
    case eventType = "event_type"
  }
}

/// `PUT /api/v1/workflow/{id}` 更新载体。
private struct NativeWorkflowUpdatePayload: Encodable, Sendable {
  let id: Int
  let name: String
  let description: String?
  let timer: String?
  let triggerType: String?
  let eventType: String?
  let state: String?
  let actions: [NativeWorkflowNode]
  let flows: [NativeWorkflowEdge]

  private enum CodingKeys: String, CodingKey {
    case id, name, description, timer, state, actions, flows
    case triggerType = "trigger_type"
    case eventType = "event_type"
  }
}

/// 画布节点位置。
private struct NativeWorkflowPosition: Codable, Sendable {
  var x: Double
  var y: Double
}

/// 单个工作流动作节点。
private struct NativeWorkflowNode: Codable, Sendable, Identifiable {
  let id: String
  let type: String
  var name: String
  var description: String
  var position: NativeWorkflowPosition
  var data: [String: JSONValue]
  var timeout: Int?
  var failPolicy: String?

  init(
    id: String, type: String, name: String, description: String,
    position: NativeWorkflowPosition, data: [String: JSONValue],
    timeout: Int?, failPolicy: String?
  ) {
    self.id = id
    self.type = type
    self.name = name
    self.description = description
    self.position = position
    self.data = data
    self.timeout = timeout
    self.failPolicy = failPolicy
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
    type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "Action"
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? type
    description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
    position =
      (try? c.decodeIfPresent(NativeWorkflowPosition.self, forKey: .position))
      ?? NativeWorkflowPosition(x: 20, y: 20)
    data = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .data)) ?? [:]
    timeout = try? c.decodeIfPresent(Int.self, forKey: .timeout)
    failPolicy = try? c.decodeIfPresent(String.self, forKey: .failPolicy)
  }

  private enum CodingKeys: String, CodingKey {
    case id, type, name, description, position, data, timeout
    case failPolicy = "fail_policy"
  }
}

/// 节点有向连线。
private struct NativeWorkflowEdge: Codable, Sendable, Identifiable {
  let id: String
  let source: String
  let target: String
  let animated: Bool?
  let condition: String?

  init(id: String, source: String, target: String, animated: Bool?, condition: String?) {
    self.id = id
    self.source = source
    self.target = target
    self.animated = animated
    self.condition = condition
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? ""
    target = (try? c.decodeIfPresent(String.self, forKey: .target)) ?? ""
    id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? "flow_\(source)_\(target)"
    animated = try? c.decodeIfPresent(Bool.self, forKey: .animated)
    condition = try? c.decodeIfPresent(String.self, forKey: .condition)
  }
}

/// `GET /api/v1/workflow/actions` 动作目录条目。
private struct NativeWorkflowActionDef: Decodable, Sendable, Identifiable {
  let type: String
  let name: String
  let description: String?
  let data: [String: JSONValue]

  var id: String { type }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? type
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    data = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .data)) ?? [:]
  }

  private enum CodingKeys: String, CodingKey {
    case type, name, description, data
  }
}
