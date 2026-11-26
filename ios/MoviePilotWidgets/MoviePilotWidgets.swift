import MoviePilotCore
import SwiftUI
import WidgetKit

/// 单一原生扩展注册桌面主体、锁屏状态、正在播放与插件四类小组件。
@main
struct MoviePilotWidgets: WidgetBundle {
  /// 系统组件库自行选择尺寸，App 不自动添加到用户桌面或锁屏。
  var body: some Widget {
    MoviePilotHomeWidget()
    MoviePilotStatusWidget()
    MoviePilotNowPlayingWidget()
    MoviePilotPluginWidget()
  }
}

/// 桌面及今天视图提供三种尺寸，可分别选择实例与内容。
struct MoviePilotHomeWidget: Widget {
  /// 仅声明系统布局，不引入另一个业务界面或写操作。
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "MoviePilotHome", intent: MoviePilotConfiguration.self, provider: MoviePilotProvider()
    ) {
      MoviePilotWidgetView(entry: $0)
    }
    .configurationDisplayName("MoviePilot")
    .description("查看服务概览、下载、近期入库与订阅。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

/// 锁屏提供行内、圆形与矩形尺寸，默认不显示媒体名称。
struct MoviePilotStatusWidget: Widget {
  /// 单色和着色均交给系统，不用自定义背景遮盖系统材质。
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "MoviePilotStatus", intent: MoviePilotConfiguration.self, provider: MoviePilotProvider()
    ) {
      MoviePilotWidgetView(entry: $0)
    }
    .configurationDisplayName("MoviePilot 状态")
    .description("在锁屏查看下载、上传速度及只读状态。")
    .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
  }
}

/// 固定音频播控桌面小组件，展示正在播放的插件歌曲、封面、同步歌词与播控按钮。
struct MoviePilotNowPlayingWidget: Widget {
  /// 使用系统交互式 Intent 直接触发播放/暂停、切歌与喜欢操作。
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "MoviePilotNowPlaying", provider: MoviePilotNowPlayingProvider()
    ) {
      MoviePilotNowPlayingWidgetView(entry: $0)
    }
    .configurationDisplayName("MoviePilot 正在播放")
    .description("查看正在播放的插件音频、专辑封面与歌词，并快捷控制播放。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

/// 插件预设与声明式自定义布局桌面小组件。
struct MoviePilotPluginWidget: Widget {
  /// 支持选择已启用插件的数据指标、进度列表、海报横幅或自定义交互卡片。
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "MoviePilotPlugin", intent: MoviePilotPluginConfiguration.self,
      provider: MoviePilotPluginProvider()
    ) {
      MoviePilotPluginWidgetView(entry: $0)
    }
    .configurationDisplayName("MoviePilot 插件")
    .description("将已启用插件的实时指标、列表或自定义交互卡片固定到桌面。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
