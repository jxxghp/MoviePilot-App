import SwiftUI

/// 隔离预览的媒体样例；图像仅用于设计评审，不能作为真实后端数据或迁移完成证据。
struct PreviewMedia: Identifiable, Hashable, Sendable {
  let id: String
  let title: String
  let year: String
  let rating: String
  let genre: String

  static let odyssey = PreviewMedia(
    id: "odyssey-hero", title: "奥德赛", year: "2026", rating: "8.4", genre: "冒险 · 动作")
  static let avengers = PreviewMedia(
    id: "avengers-wide", title: "复仇者联盟", year: "2026", rating: "8.7", genre: "科幻 · 动作")
  static let onAir: [PreviewMedia] = [
    .init(id: "rings", title: "指环王：力量之戒", year: "2022", rating: "8.1", genre: "奇幻 · 剧情"),
    .init(id: "voice", title: "美国好声音", year: "2011", rating: "7.8", genre: "音乐 · 真人秀"),
    .init(id: "simpsons", title: "辛普森一家", year: "1989", rating: "9.0", genre: "喜剧 · 动画"),
    .init(id: "greys", title: "实习医生格蕾", year: "2005", rating: "8.4", genre: "剧情"),
    .init(id: "watch", title: "安迪·科恩的现场观察", year: "2009", rating: "7.2", genre: "访谈"),
    .init(id: "mobland", title: "黑帮领地", year: "2025", rating: "8.2", genre: "犯罪 · 剧情"),
    .init(id: "tonight", title: "肥伦今夜秀", year: "2014", rating: "7.0", genre: "脱口秀"),
    .init(id: "running", title: "Running Man", year: "2010", rating: "9.2", genre: "真人秀"),
    .init(id: "hospital", title: "比勒陀利亚医院", year: "2005", rating: "7.6", genre: "剧情"),
  ]
  static let theatrical: [PreviewMedia] = [
    .init(id: "beast", title: "野兽之心", year: "2026", rating: "7.8", genre: "剧情"),
    .init(id: "mother", title: "另一个妈妈", year: "2026", rating: "8.0", genre: "惊悚"),
    .init(id: "hope", title: "希望", year: "2026", rating: "7.9", genre: "剧情"),
  ]
}

/// 海报作为主要内容对象，图片比例、标题及元数据跨页面一致。
@MainActor
struct PreviewPoster: View {
  let media: PreviewMedia

  /// 真正的图片资源配原生文本，不把来源截图中的整行 UI 当作组件。
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Rectangle().fill(.clear).aspectRatio(2.0 / 3.0, contentMode: .fit)
        .overlay {
          GeometryReader { geometry in
            Image(media.id).resizable().scaledToFill()
              .frame(width: geometry.size.width, height: geometry.size.height).clipped()
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
      Text(media.title).font(.footnote.weight(.medium)).lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(media.year).font(.caption).foregroundStyle(.secondary)
    }.foregroundStyle(.primary)
  }
}

/// 页面分区的统一标题，入口保持原生 NavigationLink 与可访问性标签。
@MainActor
struct PreviewSectionTitle: View {
  let title: String

  /// 只用字号、留白和系统箭头区分层级，不为每个分区包一层卡片。
  var body: some View {
    HStack {
      Text(title).font(.title3.weight(.semibold))
      Spacer()
      Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
    }.foregroundStyle(.primary).frame(minHeight: 44).contentShape(Rectangle())
  }
}
