import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

// MARK: - 已读与佩戴持久化（与 Web 端按 GitHub user_id 隔离语义一致）

/// 轻量持久化管理社区勋章的已读集合与当前佩戴勋章键。
@MainActor
final class NativeCommunityMedalsStore: ObservableObject {
  static let shared = NativeCommunityMedalsStore()

  @Published private(set) var revision = 0

  private func seenKey(userID: Int?) -> String {
    "moviepilot.community-medals-seen:\(userID ?? 0)"
  }

  private func wornKey(userID: Int?) -> String {
    "moviepilot.community-medal-worn:\(userID ?? 0)"
  }

  func seenTokens(userID: Int?) -> Set<String> {
    let array = UserDefaults.standard.stringArray(forKey: seenKey(userID: userID)) ?? []
    return Set(array)
  }

  func isUnseen(_ record: CommunityMedalRecord, userID: Int?) -> Bool {
    !seenTokens(userID: userID).contains(record.seenToken)
  }

  func unseenCount(in medals: [CommunityMedalRecord], userID: Int?) -> Int {
    let seen = seenTokens(userID: userID)
    return medals.filter { !seen.contains($0.seenToken) }.count
  }

  func markSeen(_ record: CommunityMedalRecord, userID: Int?) {
    var seen = seenTokens(userID: userID)
    guard seen.insert(record.seenToken).inserted else { return }
    UserDefaults.standard.set(Array(seen), forKey: seenKey(userID: userID))
    revision += 1
  }

  func wornMedalKey(userID: Int?) -> String? {
    let raw = UserDefaults.standard.string(forKey: wornKey(userID: userID))
    return raw?.isEmpty == false ? raw : nil
  }

  func toggleWear(_ key: String, userID: Int?) {
    let current = wornMedalKey(userID: userID)
    if current == key {
      UserDefaults.standard.removeObject(forKey: wornKey(userID: userID))
    } else {
      UserDefaults.standard.set(key, forKey: wornKey(userID: userID))
    }
    revision += 1
  }
}

// MARK: - 金属档位铭牌（复刻 Web MedalTierNameplate.vue）

/// 阶梯勋章金属铭牌：1 青铜初光、2 白银共建、3 流金卓越、4 黑金核心。
struct NativeMedalTierNameplate: View {
  let tier: Int
  let text: String
  var compact: Bool = false

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let style = CommunityMedalCatalog.tierStyle(for: tier)
    let metal = CommunityMedalColor.color(hex: style.metalHex)
    let ink = CommunityMedalColor.color(
      hex: colorScheme == .dark ? style.darkInkHex : style.lightInkHex)
    let borderOpacity: Double = style.isObsidianGold ? 0.54 : 0.38
    let baseFill: Color =
      style.isObsidianGold
      ? (colorScheme == .dark
        ? Color(red: 0.09, green: 0.10, blue: 0.11).opacity(0.86)
        : metal.opacity(0.16))
      : metal.opacity(colorScheme == .dark ? 0.15 : 0.14)

    Text(text)
      .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
      .foregroundStyle(ink)
      .lineLimit(1)
      .padding(.horizontal, compact ? 7 : 11)
      .padding(.vertical, compact ? 2.5 : 4.5)
      .background {
        Capsule()
          .fill(baseFill)
          .overlay {
            Capsule()
              .fill(
                LinearGradient(
                  colors: [
                    .clear,
                    .white.opacity(style.isObsidianGold ? 0.06 : 0.09),
                    .clear,
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
          }
          .overlay {
            Capsule()
              .strokeBorder(metal.opacity(borderOpacity), lineWidth: 0.75)
          }
      }
  }
}

// MARK: - 「我的」页面社区勋章组件

/// 「我的」仪表盘社区勋章陈列卡片：网格展示全部已获真实勋章，点击直达全屏 3D 动态互动舞台。
@MainActor
struct NativeCommunityMedalsWidget: View {
  let profile: CommunityProfile
  let onSelectMedal: (CommunityMedalRecord) -> Void

  @ObservedObject private var store = NativeCommunityMedalsStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let medals = profile.orderedKnownMedals
    // 已读集合整卡只读取一次，避免每个格子各自访问 UserDefaults 并重建集合。
    let seenTokens = store.seenTokens(userID: profile.userID)
    let unseen = medals.filter { !seenTokens.contains($0.seenToken) }.count
    let wornKey = store.wornMedalKey(userID: profile.userID)
    let columnCount = dynamicTypeSize.isAccessibilitySize ? 3 : 4
    let columns = Array(
      repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
      count: columnCount
    )

    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("社区勋章")
          .font(.headline.weight(.semibold))
          .foregroundStyle(.primary)
        if unseen > 0 {
          let champagne = Color(red: 0.90, green: 0.76, blue: 0.44)
          let champagneInk =
            colorScheme == .light
            ? Color(red: 0.62, green: 0.44, blue: 0.12)
            : Color(red: 0.96, green: 0.85, blue: 0.56)
          Text("\(unseen) 枚新解锁")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(champagneInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .background {
              Capsule()
                .fill(champagne.opacity(colorScheme == .light ? 0.16 : 0.18))
                .overlay {
                  Capsule().strokeBorder(champagne.opacity(0.42), lineWidth: 0.65)
                }
            }
        }
        Spacer(minLength: 6)
        if let login = profile.login, !login.isEmpty {
          Text("@\(login) · 共 \(medals.count) 枚")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
          Text("共 \(medals.count) 枚")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 2)

      CinematicPanel(padding: 14) {
        LazyVGrid(columns: columns, spacing: 14) {
          ForEach(medals) { record in
            medalGridTile(
              record: record,
              isUnseen: !seenTokens.contains(record.seenToken),
              isWorn: wornKey == record.key
            )
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-dashboard-community-medals")
  }

  private func medalGridTile(
    record: CommunityMedalRecord,
    isUnseen: Bool,
    isWorn: Bool
  ) -> some View {
    let spec = record.spec
    let tone = CommunityMedalColor.color(hex: spec?.toneHex ?? "#9b7bff")

    return Button {
      onSelectMedal(record)
    } label: {
      VStack(spacing: 6) {
        ZStack(alignment: .topTrailing) {
          ZStack {
            Circle()
              .fill(
                RadialGradient(
                  colors: [
                    tone.opacity(colorScheme == .dark ? 0.34 : 0.24),
                    tone.opacity(0.02),
                  ],
                  center: .center,
                  startRadius: 4,
                  endRadius: 34
                )
              )
              .frame(width: 64, height: 64)

            NativeCommunityMedalGridArtwork(record: record, tone: tone)
          }
          .frame(width: 64, height: 64)

          if isUnseen {
            let champagne = Color(red: 0.94, green: 0.80, blue: 0.48)
            Circle()
              .fill(champagne)
              .frame(width: 6.5, height: 6.5)
              .shadow(color: champagne.opacity(0.55), radius: 3)
              .overlay {
                Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.8)
              }
              .offset(x: -3, y: 3)
          } else if isWorn {
            Image(systemName: "checkmark.seal.fill")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(tone)
              .background(Circle().fill(Color.black.opacity(0.65)).padding(1.5))
              .offset(x: -1, y: 1)
          }
        }

        VStack(spacing: 3) {
          Text(spec?.name ?? record.key)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)

          if let tier = record.normalizedTier {
            NativeMedalTierNameplate(
              tier: tier,
              text: CommunityMedalCatalog.tierStyle(for: tier).name,
              compact: true
            )
          } else {
            Text(spec?.isAutomatic == true ? "自动" : "荣誉")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.secondary.opacity(0.85))
              .lineLimit(1)
              .padding(.vertical, 2)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(spec?.name ?? record.key)勋章，轻点查看动态 3D 勋章")
    .accessibilityIdentifier("native-community-medal-\(record.key)")
  }
}

/// 勋章网格图：展示降采样并已烘焙投影的缩略图；首帧同步命中内存缓存，未命中时在后台线程生成，不阻塞滚动。
@MainActor
private struct NativeCommunityMedalGridArtwork: View {
  let record: CommunityMedalRecord
  let tone: Color

  /// 勋章本体显示边长（pt），与原网格保持一致。
  private static let medalSide: CGFloat = 58

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.displayScale) private var displayScale
  @State private var image: UIImage?
  @State private var resolvedKey: String?

  var body: some View {
    let stems = CommunityMedalAssetLoader.gridThumbnailStems(for: record)
    let isDark = colorScheme == .dark
    let key = CommunityMedalAssetLoader.gridThumbnailKey(
      stems: stems, medalSide: Self.medalSide, scale: displayScale, isDark: isDark)
    let isResolved = resolvedKey == key
    let thumbnail: UIImage? =
      if isResolved, let image {
        image
      } else {
        CommunityMedalAssetLoader.shared.cachedGridThumbnail(forKey: key)
      }
    let canvasSide = CommunityMedalAssetLoader.gridThumbnailCanvasSide(medalSide: Self.medalSide)

    return Group {
      if let thumbnail {
        // 缩略图画布含阴影余量，按画布原尺寸绘制并居中溢出，勋章本体仍占 58pt。
        Image(uiImage: thumbnail)
          .resizable()
          .frame(width: canvasSide, height: canvasSide)
      } else if isResolved {
        Image(systemName: "medal.fill")
          .font(.title2)
          .foregroundStyle(tone)
      } else {
        Color.clear
      }
    }
    .frame(width: Self.medalSide, height: Self.medalSide)
    .task(id: key) {
      await load(key: key, stems: stems, scale: displayScale, isDark: isDark)
    }
  }

  /// 内存缓存未命中时在后台线程降采样并烘焙投影，完成后回到主线程呈现；素材缺失时回退为符号图标。
  private func load(key: String, stems: [String], scale: CGFloat, isDark: Bool) async {
    if let cached = CommunityMedalAssetLoader.shared.cachedGridThumbnail(forKey: key) {
      image = cached
      resolvedKey = key
      return
    }
    let side = Self.medalSide
    let generated: UIImage? = await Task.detached(priority: .userInitiated) {
      CommunityMedalAssetLoader.shared.makeGridThumbnail(
        stems: stems, medalSide: side, scale: scale, isDark: isDark)
    }.value
    guard !Task.isCancelled else { return }
    image = generated
    resolvedKey = key
  }
}

// MARK: - 全屏 3D 动态勋章互动舞台（复刻 Web CommunityMedalDialog.vue）

/// 全屏沉浸式社区勋章展示与 3D 互动舞台：支持拖动转动、轻点翻面看背面凹雕铭文、切换勋章、佩戴、分享海报与详情弹窗。
@MainActor
struct NativeCommunityMedalShowcaseView: View {
  @Binding var profile: CommunityProfile
  let initialKey: String
  let session: NativeSession

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var store = NativeCommunityMedalsStore.shared

  @State private var activeKey: String
  @State private var showsDetailSheet = false
  @State private var shareImage: ShareableMedalPoster?
  @State private var isGeneratingShare = false
  @State private var isRefreshing = false
  @State private var shareErrorMessage: String?

  init(profile: Binding<CommunityProfile>, initialKey: String, session: NativeSession) {
    _profile = profile
    self.initialKey = initialKey
    self.session = session
    _activeKey = State(initialValue: initialKey)
  }

  private var medals: [CommunityMedalRecord] {
    profile.orderedKnownMedals
  }

  private var activeRecord: CommunityMedalRecord? {
    medals.first(where: { $0.key == activeKey }) ?? medals.first
  }

  var body: some View {
    let record = activeRecord
    let spec = record?.spec
    let tone = CommunityMedalColor.color(hex: spec?.toneHex ?? "#9b7bff")
    let isWorn = record != nil && store.wornMedalKey(userID: profile.userID) == record?.key

    ZStack {
      // 深浅自适应通透模糊暗幕 + 勋章主色动态径向氛围光
      CinematicAmbientGradient()
        .ignoresSafeArea()
        .overlay {
          Color(uiColor: colorScheme == .dark ? .black : .systemBackground)
            .opacity(colorScheme == .dark ? 0.56 : 0.42)
            .ignoresSafeArea()
        }

      GeometryReader { proxy in
        let isCompactLandscape = proxy.size.width > proxy.size.height && proxy.size.height < 520
        let stageSize =
          isCompactLandscape
          ? max(120, min(proxy.size.height - 76, proxy.size.width * 0.40))
          : min(proxy.size.width - 28, min(proxy.size.height * 0.50, 410))
        let glowX = isCompactLandscape ? (20 + stageSize * 0.5) : proxy.size.width * 0.5
        let glowY =
          isCompactLandscape
          ? (42 + max(proxy.size.height - 42, 0) * 0.48)
          : proxy.size.height * 0.38
        ZStack {
          // 勋章背后径向氛围光晕（随切换平滑过渡，紧凑横屏对齐左栏舞台中心）
          Circle()
            .fill(
              RadialGradient(
                colors: [
                  tone.opacity(colorScheme == .dark ? 0.24 : 0.30),
                  tone.opacity(colorScheme == .dark ? 0.07 : 0.10),
                  .clear,
                ],
                center: .center,
                startRadius: 12,
                endRadius: stageSize * 0.62
              )
            )
            .frame(width: stageSize * 1.24, height: stageSize * 1.24)
            .blur(radius: 18)
            .position(x: glowX, y: glowY)
            .animation(.easeInOut(duration: 0.45), value: activeKey)
            .allowsHitTesting(false)

          VStack(spacing: 0) {
            // 顶部栏：左上角更多操作弹出菜单（佩戴 / 保存图片 / 勋章详情），右上角关闭按钮
            HStack {
              if let record {
                Menu {
                  Button {
                    store.toggleWear(record.key, userID: profile.userID)
                  } label: {
                    Label(
                      isWorn ? "取消佩戴" : "佩戴勋章",
                      systemImage: isWorn ? "checkmark.seal.fill" : "seal"
                    )
                  }
                  Button {
                    generateSharePoster(for: record)
                  } label: {
                    Label(
                      isGeneratingShare ? "正在生成图片…" : "保存图片",
                      systemImage: "square.and.arrow.up"
                    )
                  }
                  .disabled(isGeneratingShare)
                  Button {
                    showsDetailSheet = true
                  } label: {
                    Label("勋章详情", systemImage: "info.circle")
                  }
                } label: {
                  HStack(spacing: 6) {
                    if let login = profile.login, !login.isEmpty {
                      Image(
                        systemName: isWorn ? "checkmark.seal.fill" : "person.badge.shield.checkmark"
                      )
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(isWorn ? tone : .primary.opacity(0.78))
                      Text("@\(login)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.84))
                      Image(systemName: "ellipsis")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.55))
                    } else {
                      Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)
                    }
                  }
                  .padding(.horizontal, profile.login?.isEmpty == false ? 12 : 6)
                  .frame(minWidth: 36, minHeight: 36)
                  .background {
                    Capsule()
                      .fill(.primary.opacity(colorScheme == .dark ? 0.14 : 0.10))
                      .overlay {
                        Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.6)
                      }
                  }
                }
                .accessibilityLabel("勋章操作菜单")
                .accessibilityIdentifier("native-medal-showcase-menu")
              }
              Spacer()
              Button {
                dismiss()
              } label: {
                Image(systemName: "xmark")
                  .font(.system(size: 15, weight: .semibold))
                  .foregroundStyle(.primary)
                  .frame(width: 36, height: 36)
                  .background {
                    Circle()
                      .fill(.primary.opacity(colorScheme == .dark ? 0.14 : 0.10))
                      .overlay {
                        Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 0.6)
                      }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("关闭勋章展示")
              .accessibilityIdentifier("native-medal-showcase-close")
            }
            .padding(.horizontal, 20)
            .padding(.top, isCompactLandscape ? 6 : 10)

            if isCompactLandscape {
              HStack(alignment: .center, spacing: 24) {
                VStack(spacing: 6) {
                  if let record {
                    NativeMedal3DStageView(
                      record: record,
                      login: profile.login,
                      reducedMotion: reduceMotion
                    )
                    .frame(width: stageSize, height: stageSize)
                    .accessibilityLabel("\(spec?.name ?? record.key)动态 3D 勋章，轻点翻面，拖动转动")
                    .accessibilityIdentifier("native-medal-3d-stage")
                  }

                  Label("轻点翻面 · 拖动转动", systemImage: "hand.draw")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.56))
                }
                .frame(width: stageSize)

                ScrollView(.vertical, showsIndicators: false) {
                  VStack(alignment: .center, spacing: 10) {
                    if let record {
                      Text(spec?.name ?? record.key)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                      if let tier = record.normalizedTier,
                        let tierLine = CommunityMedalCatalog.tierLine(for: record)
                      {
                        NativeMedalTierNameplate(tier: tier, text: tierLine, compact: false)
                      } else if let timeLine = CommunityMedalCatalog.timeLine(for: record) {
                        Text(timeLine)
                          .font(.caption.weight(.medium).monospacedDigit())
                          .foregroundStyle(.secondary)
                      }

                      if let summary = spec?.summary {
                        Text(summary)
                          .font(.footnote)
                          .foregroundStyle(.primary.opacity(0.74))
                          .multilineTextAlignment(.center)
                          .fixedSize(horizontal: false, vertical: true)
                      }

                      HStack(spacing: 8) {
                        Button {
                          store.toggleWear(record.key, userID: profile.userID)
                        } label: {
                          Label(
                            isWorn ? "已佩戴" : "佩戴勋章",
                            systemImage: isWorn ? "checkmark.seal.fill" : "seal"
                          )
                          .font(.caption.weight(.semibold))
                          .foregroundStyle(isWorn ? tone : .primary)
                          .padding(.horizontal, 11)
                          .padding(.vertical, 6)
                          .background {
                            Capsule()
                              .fill(
                                isWorn
                                  ? tone.opacity(colorScheme == .dark ? 0.24 : 0.18)
                                  : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07)
                              )
                              .overlay {
                                Capsule().strokeBorder(
                                  isWorn ? tone.opacity(0.55) : Color.primary.opacity(0.16),
                                  lineWidth: 0.7
                                )
                              }
                          }
                        }
                        .buttonStyle(.plain)

                        Button {
                          showsDetailSheet = true
                        } label: {
                          Label("勋章详情", systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.88))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background {
                              Capsule()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07))
                                .overlay {
                                  Capsule().strokeBorder(
                                    Color.primary.opacity(0.16), lineWidth: 0.7)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                      }
                      .padding(.top, 2)
                    }

                    if medals.count > 1 {
                      medalSwitcherPills
                        .padding(.top, 4)
                    }
                  }
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
              }
              .padding(.horizontal, 20)
              .padding(.top, 6)
              .padding(.bottom, 10)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
              Spacer(minLength: 8)

              // 中央 3D 动态互动勋章舞台
              if let record {
                NativeMedal3DStageView(
                  record: record,
                  login: profile.login,
                  reducedMotion: reduceMotion
                )
                .frame(width: stageSize, height: stageSize)
                .accessibilityLabel("\(spec?.name ?? record.key)动态 3D 勋章，轻点翻面，拖动转动")
                .accessibilityIdentifier("native-medal-3d-stage")
              }

              // 交互提示
              Label("轻点翻面 · 拖动转动", systemImage: "hand.draw")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary.opacity(0.56))
                .padding(.top, 2)

              // 标题、金属档位铭牌与致敬文案
              if let record {
                VStack(spacing: 8) {
                  Text(spec?.name ?? record.key)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                  if let tier = record.normalizedTier,
                    let tierLine = CommunityMedalCatalog.tierLine(for: record)
                  {
                    NativeMedalTierNameplate(tier: tier, text: tierLine, compact: false)
                  } else if let timeLine = CommunityMedalCatalog.timeLine(for: record) {
                    Text(timeLine)
                      .font(.caption.weight(.medium).monospacedDigit())
                      .foregroundStyle(.secondary)
                  }

                  if let summary = spec?.summary {
                    Text(summary)
                      .font(.footnote)
                      .foregroundStyle(.primary.opacity(0.72))
                      .multilineTextAlignment(.center)
                      .lineLimit(2)
                      .padding(.horizontal, 28)
                  }
                }
                .padding(.top, 12)
              }

              Spacer(minLength: 10)

              // 多枚勋章自动换行居中展示，一屏显示全部已获勋章，无需左右滚动
              if medals.count > 1 {
                medalSwitcherPills
                  .padding(.horizontal, 20)
                  .padding(.bottom, 26)
              } else {
                Spacer().frame(height: 26)
              }
            }
          }
          .opacity(showsDetailSheet ? 0.14 : 1.0)
          .animation(.easeInOut(duration: 0.25), value: showsDetailSheet)
        }
      }
    }
    .onAppear {
      if let record = activeRecord {
        store.markSeen(record, userID: profile.userID)
      }
    }
    .sheet(isPresented: $showsDetailSheet) {
      if let record = activeRecord {
        NativeCommunityMedalDetailSheet(
          record: record,
          profile: profile,
          isRefreshing: isRefreshing,
          onRefresh: { await refreshCommunityProfile() }
        )
      }
    }
    .sheet(item: $shareImage) { poster in
      NativeMedalActivityShareSheet(image: poster.image)
        .ignoresSafeArea()
    }
    .alert(
      "图片生成失败",
      isPresented: Binding(
        get: { shareErrorMessage != nil },
        set: { if !$0 { shareErrorMessage = nil } }
      )
    ) {
      Button("确定", role: .cancel) {}
    } message: {
      Text(shareErrorMessage ?? "请稍后重试。")
    }
  }

  /// 多枚勋章自动换行居中切换胶囊栏，供竖屏底部与紧凑横屏右栏共用。
  private var medalSwitcherPills: some View {
    NativeCenteredFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
      ForEach(medals) { item in
        let isSelected = item.key == activeKey
        let itemTone = CommunityMedalColor.color(hex: item.spec?.toneHex ?? "#9b7bff")
        let itemUnseen = store.isUnseen(item, userID: profile.userID)
        Button {
          withAnimation(.easeInOut(duration: 0.22)) {
            activeKey = item.key
          }
          store.markSeen(item, userID: profile.userID)
        } label: {
          HStack(spacing: 5) {
            if let badge = CommunityMedalAssetLoader.shared.badgeImage(for: item) {
              Image(uiImage: badge)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
            }
            Text(item.spec?.name ?? item.key)
              .font(.caption.weight(isSelected ? .semibold : .medium))
              .foregroundStyle(.primary.opacity(isSelected ? 0.98 : 0.74))
            if itemUnseen {
              Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            }
          }
          .padding(.horizontal, 11)
          .padding(.vertical, 7)
          .background {
            Capsule()
              .fill(
                isSelected
                  ? itemTone.opacity(colorScheme == .dark ? 0.28 : 0.22)
                  : Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.06)
              )
              .overlay {
                Capsule()
                  .strokeBorder(
                    isSelected
                      ? itemTone.opacity(0.62)
                      : Color.primary.opacity(0.14),
                    lineWidth: 0.7
                  )
              }
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-medal-switch-\(item.key)")
      }
    }
  }

  private func generateSharePoster(for record: CommunityMedalRecord) {
    guard !isGeneratingShare else { return }
    isGeneratingShare = true
    let login = profile.login
    Task.detached(priority: .userInitiated) {
      let poster = CommunityMedalShareRenderer.renderPoster(record: record, login: login)
      await MainActor.run {
        isGeneratingShare = false
        if let poster {
          shareImage = ShareableMedalPoster(image: poster)
        } else {
          shareErrorMessage = "图片生成失败，请稍后重试。"
        }
      }
    }
  }

  private func refreshCommunityProfile() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["github", "community"],
        query: [URLQueryItem(name: "refresh", value: "true")]
      )
      let refreshed = try await session.request(
        endpoint, as: CommunityProfile.self,
        requiring: .init(category: .admin)
      ).value
      profile = refreshed
    } catch {
      return
    }
  }
}

private struct ShareableMedalPoster: Identifiable {
  let id = UUID()
  let image: UIImage
}

/// 逐行自动换行且每行水平居中的流式布局，用于全屏展示底部勋章胶囊切换栏。
private struct NativeCenteredFlowLayout: Layout {
  var horizontalSpacing: CGFloat = 8
  var verticalSpacing: CGFloat = 8

  private struct Row {
    var indices: [Int]
    var sizes: [CGSize]
    var width: CGFloat
    var height: CGFloat
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    let rows = buildRows(maxWidth: maxWidth, subviews: subviews)
    let totalHeight = rows.enumerated().reduce(CGFloat(0)) { acc, pair in
      acc + pair.element.height + (pair.offset > 0 ? verticalSpacing : 0)
    }
    let fittedWidth = proposal.width ?? (rows.map(\.width).max() ?? 0)
    return CGSize(width: fittedWidth, height: totalHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let rows = buildRows(maxWidth: bounds.width, subviews: subviews)
    var y = bounds.minY
    for row in rows {
      var x = bounds.minX + max(0, (bounds.width - row.width) * 0.5)
      for (idx, size) in zip(row.indices, row.sizes) {
        let itemY = y + (row.height - size.height) * 0.5
        subviews[idx].place(
          at: CGPoint(x: x, y: itemY),
          proposal: ProposedViewSize(size)
        )
        x += size.width + horizontalSpacing
      }
      y += row.height + verticalSpacing
    }
  }

  private func buildRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var currentIndices: [Int] = []
    var currentSizes: [CGSize] = []
    var currentWidth: CGFloat = 0
    var currentHeight: CGFloat = 0

    for (idx, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      let extra = currentIndices.isEmpty ? size.width : horizontalSpacing + size.width
      if !currentIndices.isEmpty && currentWidth + extra > maxWidth {
        rows.append(
          Row(
            indices: currentIndices, sizes: currentSizes, width: currentWidth, height: currentHeight
          ))
        currentIndices = [idx]
        currentSizes = [size]
        currentWidth = size.width
        currentHeight = size.height
      } else {
        currentIndices.append(idx)
        currentSizes.append(size)
        currentWidth += extra
        currentHeight = max(currentHeight, size.height)
      }
    }
    if !currentIndices.isEmpty {
      rows.append(
        Row(
          indices: currentIndices, sizes: currentSizes, width: currentWidth, height: currentHeight
        ))
    }
    return rows
  }
}

private struct NativeMedalActivityShareSheet: UIViewControllerRepresentable {
  let image: UIImage

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [image], applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 勋章详情弹窗（复刻 Web MedalDetailSheet.vue）

/// 勋章详情原生通透弹窗：规则、四档进度条、编剧官方仓贡献证据、布景插件安装明细与手动刷新。
@MainActor
private struct NativeCommunityMedalDetailSheet: View {
  let record: CommunityMedalRecord
  let profile: CommunityProfile
  let isRefreshing: Bool
  let onRefresh: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var showsAllPlugins = false

  var body: some View {
    let spec = record.spec
    let tone = CommunityMedalColor.color(hex: spec?.toneHex ?? "#9b7bff")
    let badge = CommunityMedalAssetLoader.shared.badgeImage(for: record)

    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // 头部概览卡
          CinematicPanel(padding: 14) {
            HStack(spacing: 12) {
              if let badge {
                Image(uiImage: badge)
                  .resizable()
                  .scaledToFit()
                  .frame(width: 44, height: 44)
              } else {
                Image(systemName: "medal.fill")
                  .font(.title)
                  .foregroundStyle(tone)
                  .frame(width: 44, height: 44)
              }
              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                  Text(spec?.name ?? record.key)
                    .font(.headline.weight(.bold))
                  if let tier = record.normalizedTier,
                    let tierLine = CommunityMedalCatalog.tierLine(for: record)
                  {
                    NativeMedalTierNameplate(tier: tier, text: tierLine, compact: true)
                  }
                }
                HStack(spacing: 6) {
                  if let how = spec?.howLabel {
                    Text(how)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  if let time = CommunityMedalCatalog.timeLine(for: record) {
                    Text("· \(time)")
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(.secondary)
                  }
                }
              }
              Spacer(minLength: 0)
            }
          }

          // 1. 规则与手工备注
          if let spec {
            detailSection(title: "规则") {
              VStack(alignment: .leading, spacing: 8) {
                Text(spec.rule)
                  .font(.subheadline)
                  .foregroundStyle(.primary.opacity(0.88))
                  .fixedSize(horizontal: false, vertical: true)
                if let note = record.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty
                {
                  Text("贡献 · \(note)")
                    .font(.footnote)
                    .foregroundStyle(tone)
                }
              }
            }
          }

          // 2. 四档进度（阶梯勋章）
          if let spec, let progress = CommunityMedalCatalog.tierProgress(for: record) {
            detailSection(title: "档位进度") {
              tierProgressView(spec: spec, progress: progress, tone: tone)
            }
          }

          // 3. 编剧官方仓贡献证据
          if record.key == "code", let facts = record.facts, !facts.repositories.isEmpty {
            let sortedRepos = facts.repositories.sorted { $0.effectiveCount > $1.effectiveCount }
            detailSection(
              title: "已采纳贡献 \(CommunityMedalCatalog.formatCount(facts.total ?? 0)) 次"
            ) {
              VStack(alignment: .leading, spacing: 10) {
                Text("仅列出有贡献的仓库。同一仓库的 PR 与提交，只按其中较多的一项计算。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                ForEach(sortedRepos) { repo in
                  repoContributionRow(repo: repo, tone: tone)
                }
              }
            }
          }

          // 4. 布景插件安装量明细
          if record.key == "plugin", let facts = record.facts, !facts.plugins.isEmpty {
            let sortedPlugins = facts.plugins.sorted { $0.installs > $1.installs }
            let visible = showsAllPlugins ? sortedPlugins : Array(sortedPlugins.prefix(5))
            detailSection(
              title: "累计安装 \(CommunityMedalCatalog.formatCount(facts.installs ?? 0)) 次"
            ) {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(visible) { plugin in
                  HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                      Text(plugin.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                      Text(plugin.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Text(CommunityMedalCatalog.formatCount(plugin.installs))
                      .font(.subheadline.weight(.semibold).monospacedDigit())
                      .foregroundStyle(tone)
                  }
                  .padding(.vertical, 4)
                  if plugin.id != visible.last?.id {
                    Divider().opacity(0.3)
                  }
                }
                if sortedPlugins.count > 5 {
                  Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                      showsAllPlugins.toggle()
                    }
                  } label: {
                    Text(showsAllPlugins ? "收起" : "查看全部 \(sortedPlugins.count) 个")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(tone)
                      .frame(maxWidth: .infinity)
                      .padding(.vertical, 6)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }

          // 5. 底部数据来源与刷新
          CinematicPanel(padding: 12) {
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 3) {
                Text("数据来自 MoviePilot Wiki 社区荣誉名单。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                if let checked = profile.checkedAt {
                  let date = Date(timeIntervalSince1970: TimeInterval(checked))
                  Text("更新于 \(date, format: .dateTime.month().day().hour().minute())")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.85))
                }
                if profile.stale {
                  Text("暂时无法获取最新数据，当前显示的是上次的结果。")
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.warning)
                }
              }
              Spacer(minLength: 6)
              Button {
                Task { await onRefresh() }
              } label: {
                HStack(spacing: 4) {
                  if isRefreshing {
                    ProgressView().controlSize(.mini).tint(.primary)
                  } else {
                    Image(systemName: "arrow.clockwise")
                      .font(.caption2.weight(.semibold))
                  }
                  Text("刷新")
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(.primary.opacity(0.12), in: Capsule())
              }
              .buttonStyle(.plain)
              .disabled(isRefreshing)
              .accessibilityIdentifier("native-medal-detail-refresh")
            }
          }
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .navigationTitle("勋章详情")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("完成") { dismiss() }
            .fontWeight(.semibold)
            .tint(.primary)
        }
      }
    }
    .nativeGlassSheet()
    .nativeAdaptiveSheetSizing()
    .presentationDetents([.medium, .large])
  }

  private func detailSection<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      CinematicPanel(padding: 14) {
        content()
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func tierProgressView(
    spec: CommunityMedalSpec,
    progress: CommunityMedalTierProgress,
    tone: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      GeometryReader { geo in
        let trackWidth = max(geo.size.width * 0.75, 1)
        let startX = geo.size.width * 0.125
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10))
            .frame(width: trackWidth, height: 4)
            .offset(x: startX)
          Capsule()
            .fill(tone)
            .frame(width: trackWidth * progress.trackFill, height: 4)
            .offset(x: startX)
          HStack(spacing: 0) {
            ForEach(1...4, id: \.self) { tier in
              let reached = tier <= progress.currentTier
              Circle()
                .fill(reached ? tone : Color.primary.opacity(0.24))
                .frame(width: reached ? 11 : 8, height: reached ? 11 : 8)
                .overlay {
                  if reached {
                    Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1)
                  }
                }
                .frame(maxWidth: .infinity)
            }
          }
        }
      }
      .frame(height: 14)

      HStack(spacing: 0) {
        ForEach(1...4, id: \.self) { tier in
          let reached = tier <= progress.currentTier
          let label =
            spec.thresholdLabels.indices.contains(tier - 1)
            ? spec.thresholdLabels[tier - 1] : ""
          VStack(spacing: 2) {
            Text(CommunityMedalCatalog.tierStyle(for: tier).name)
              .font(.caption.weight(reached ? .semibold : .regular))
              .foregroundStyle(reached ? .primary : .secondary)
            Text(label)
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }

      Text(progress.statusText)
        .font(.caption.weight(.medium))
        .foregroundStyle(tone)
    }
  }

  private func repoContributionRow(repo: CommunityCodeRepoFact, tone: Color) -> some View {
    let prURL = CommunityMedalCatalog.officialRepoPRsURL(
      repository: repo.repository, login: profile.login)
    let commitURL = CommunityMedalCatalog.officialRepoCommitsURL(
      repository: repo.repository, login: profile.login)

    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(repo.repository)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
        if let area = CommunityMedalCatalog.areaName(for: repo.area) {
          Text(area)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.primary.opacity(0.08), in: Capsule())
        }
        Spacer(minLength: 4)
        Text("\(CommunityMedalCatalog.formatCount(repo.effectiveCount))")
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .foregroundStyle(tone)
      }
      HStack(spacing: 12) {
        if repo.mergedPRs > 0 {
          if let prURL {
            Link("已合并 PR \(CommunityMedalCatalog.formatCount(repo.mergedPRs))", destination: prURL)
              .font(.caption.monospacedDigit())
              .foregroundStyle(tone.opacity(0.92))
          } else {
            Text("已合并 PR \(CommunityMedalCatalog.formatCount(repo.mergedPRs))")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        if repo.commits > 0 {
          if let commitURL {
            Link("作者提交 \(CommunityMedalCatalog.formatCount(repo.commits))", destination: commitURL)
              .font(.caption.monospacedDigit())
              .foregroundStyle(tone.opacity(0.92))
          } else {
            Text("作者提交 \(CommunityMedalCatalog.formatCount(repo.commits))")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }
}
