import SwiftUI
import WidgetKit

/// 单一原生扩展注册桌面与锁屏两种组件，数据读取始终使用专用只读仓。
@main
struct MoviePilotWidgets: WidgetBundle {
  /// 系统组件库自行选择尺寸，App 不自动添加到用户桌面或锁屏。
  var body: some Widget {
    MoviePilotHomeWidget()
    MoviePilotStatusWidget()
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
