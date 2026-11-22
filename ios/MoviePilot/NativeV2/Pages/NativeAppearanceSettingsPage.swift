import SwiftUI

/// 原生主题与外观设置页：支持深色/浅色/跟随系统主题切换、预设与自定义三色背景渐变过渡，以及强调前景色与可选自定义文字前景色。
@MainActor
struct NativeAppearanceSettingsPage: View {
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          livePreviewCard
          themeModeSection
          backgroundGradientSection
          foregroundColorSection
          resetSection
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-appearance-scroll")
    }
    .navigationTitle("主题与外观")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
  }

  /// 顶部实时预览卡片：随主题、背景渐变与前景色调整即时反映最终视觉效果。
  private var livePreviewCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader("实时预览")
      ZStack {
        CinematicAmbientGradient()
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 10) {
            Image(systemName: "sparkles.tv")
              .font(.headline.weight(.semibold))
              .foregroundStyle(.white)
              .frame(width: 34, height: 34)
              .background(
                appearance.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
              Text("MoviePilot 原生主题")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
              Text(appearance.summaryText)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.68))
            }
            Spacer(minLength: 0)
            Text("活跃")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 9)
              .padding(.vertical, 4)
              .background(appearance.accentColor, in: Capsule())
          }
          HStack(spacing: 8) {
            Capsule()
              .fill(appearance.accentColor)
              .frame(height: 6)
            Capsule()
              .fill(.primary.opacity(0.18))
              .frame(width: 64, height: 6)
          }
        }
        .padding(14)
        .background {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(colorScheme == .light ? Color.white.opacity(0.68) : Color.white.opacity(0.08))
            .overlay {
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                  colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.18),
                  lineWidth: 0.7)
            }
        }
        .padding(14)
      }
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .strokeBorder(.primary.opacity(0.14), lineWidth: 0.7)
      }
      .accessibilityIdentifier("native-appearance-preview")
    }
  }

  /// 外观模式分区：深色、浅色与跟随系统。
  private var themeModeSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader("外观主题")
      HStack(spacing: 10) {
        ForEach(NativeAppearanceMode.allCases) { option in
          let selected = appearance.mode == option
          Button {
            withAnimation(.easeInOut(duration: 0.22)) {
              appearance.mode = option
            }
          } label: {
            CinematicPanel(padding: 12) {
              VStack(spacing: 8) {
                Image(systemName: option.symbol)
                  .font(.title3.weight(.semibold))
                  .foregroundStyle(selected ? appearance.accentColor : .primary.opacity(0.74))
                Text(option.title)
                  .font(.subheadline.weight(selected ? .semibold : .medium))
                  .foregroundStyle(.primary)
              }
              .frame(maxWidth: .infinity, minHeight: 56)
            }
            .overlay {
              if selected {
                RoundedRectangle(cornerRadius: CinematicStyle.radius, style: .continuous)
                  .strokeBorder(appearance.accentColor, lineWidth: 1.8)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-appearance-mode-\(option.rawValue)")
        }
      }
    }
  }

  /// 背景过渡颜色分区：6 款预设多段渐变 + 自定义起/中/止三色拾色器。
  private var backgroundGradientSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader("背景过渡颜色")
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
        spacing: 10
      ) {
        ForEach(NativeBackgroundPreset.allCases) { preset in
          let selected = appearance.backgroundPreset == preset
          Button {
            withAnimation(.easeInOut(duration: 0.22)) {
              appearance.backgroundPreset = preset
            }
          } label: {
            VStack(spacing: 7) {
              ZStack(alignment: .topTrailing) {
                LinearGradient(
                  stops: previewStops(for: preset),
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                      selected ? appearance.accentColor : .primary.opacity(0.16),
                      lineWidth: selected ? 2.2 : 0.7)
                }
                if selected {
                  Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white, appearance.accentColor)
                    .padding(5)
                }
              }
              Text(preset.title)
                .font(.caption.weight(selected ? .semibold : .medium))
                .foregroundStyle(.primary.opacity(selected ? 0.98 : 0.74))
                .lineLimit(1)
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-appearance-bg-\(preset.rawValue)")
        }
      }

      CinematicPanel(padding: 14) {
        VStack(spacing: 12) {
          ColorPicker(
            "起始过渡色",
            selection: customBgBinding(
              get: { appearance.customBackgroundStartColor },
              setHex: { appearance.customBackgroundStartHex = $0 }
            ),
            supportsOpacity: false
          )
          .font(.subheadline)
          Divider().overlay(.primary.opacity(0.10))
          ColorPicker(
            "中间过渡色",
            selection: customBgBinding(
              get: { appearance.customBackgroundMidColor },
              setHex: { appearance.customBackgroundMidHex = $0 }
            ),
            supportsOpacity: false
          )
          .font(.subheadline)
          Divider().overlay(.primary.opacity(0.10))
          ColorPicker(
            "结束过渡色",
            selection: customBgBinding(
              get: { appearance.customBackgroundEndColor },
              setHex: { appearance.customBackgroundEndHex = $0 }
            ),
            supportsOpacity: false
          )
          .font(.subheadline)
          Divider().overlay(.primary.opacity(0.10))
          Toggle(isOn: $appearance.animateBackground) {
            VStack(alignment: .leading, spacing: 2) {
              Text("动态流光背景")
                .font(.subheadline)
              Text("在当前配色范围内缓慢流动，低电量或减弱动态时自动静止")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          .tint(appearance.accentColor)
          .accessibilityIdentifier("native-appearance-animate-bg")
        }
      }
    }
  }

  /// 前景色分区：主题强调色（图标、开关、高亮控件）+ 可选自定义全局文字前景色。
  private var foregroundColorSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader("前景色")
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 14) {
          Text("强调前景色")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary.opacity(0.82))

          HStack(spacing: 12) {
            ForEach(NativeAccentPreset.allCases.filter { $0 != .custom }) { preset in
              let selected = appearance.accentPreset == preset
              Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                  appearance.accentPreset = preset
                }
              } label: {
                ZStack {
                  Circle()
                    .fill(preset.color)
                    .frame(width: 34, height: 34)
                  if selected {
                    Circle()
                      .strokeBorder(.white, lineWidth: 2.2)
                      .frame(width: 28, height: 28)
                    Image(systemName: "checkmark")
                      .font(.caption2.weight(.bold))
                      .foregroundStyle(.white)
                  }
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(preset.title)
              .accessibilityIdentifier("native-appearance-accent-\(preset.rawValue)")
            }
            Spacer(minLength: 0)
          }

          Divider().overlay(.primary.opacity(0.10))

          ColorPicker(
            "自定义强调前景色",
            selection: Binding(
              get: { appearance.accentColor },
              set: { color in
                appearance.customAccentHex = NativeAppearanceStore.hexString(from: color)
                appearance.accentPreset = .custom
              }
            ),
            supportsOpacity: false
          )
          .font(.subheadline)

          Divider().overlay(.primary.opacity(0.10))

          Toggle("自定义文字前景色", isOn: $appearance.useCustomTextColor)
            .font(.subheadline)
            .tint(appearance.accentColor)
            .accessibilityIdentifier("native-appearance-custom-text-toggle")

          if appearance.useCustomTextColor {
            ColorPicker(
              colorScheme == .light ? "浅色主题文字颜色" : "深色主题文字颜色",
              selection: Binding(
                get: { appearance.customTextColor(for: colorScheme) },
                set: { color in
                  appearance.setCustomTextColor(color, for: colorScheme)
                }
              ),
              supportsOpacity: false
            )
            .font(.subheadline)
          } else {
            Text("默认随深色/浅色主题自动保持高对比可读文字（浅色深灰 / 深色柔白）。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  /// 一键恢复默认外观按钮。
  private var resetSection: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.22)) {
        appearance.resetToDefaults()
      }
    } label: {
      CinematicPanel(padding: 14) {
        HStack {
          Spacer()
          Label("恢复默认外观", systemImage: "arrow.counterclockwise")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(appearance.accentColor)
          Spacer()
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-appearance-reset")
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.primary.opacity(0.72))
      .padding(.horizontal, 2)
  }

  private func previewStops(for preset: NativeBackgroundPreset) -> [Gradient.Stop] {
    if preset == .custom {
      return [
        .init(color: appearance.customBackgroundStartColor, location: 0),
        .init(color: appearance.customBackgroundMidColor, location: 0.5),
        .init(color: appearance.customBackgroundEndColor, location: 1),
      ]
    }
    let colors = colorScheme == .light ? preset.lightStops : preset.darkStops
    return [
      .init(color: colors[0], location: 0),
      .init(color: colors[1], location: 0.33),
      .init(color: colors[2], location: 0.70),
      .init(color: colors[3], location: 1),
    ]
  }

  private func customBgBinding(
    get: @escaping () -> Color, setHex: @escaping (String) -> Void
  ) -> Binding<Color> {
    Binding(
      get: get,
      set: { color in
        setHex(NativeAppearanceStore.hexString(from: color))
        appearance.backgroundPreset = .custom
      }
    )
  }
}
