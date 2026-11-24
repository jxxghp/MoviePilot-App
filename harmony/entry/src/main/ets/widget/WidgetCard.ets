const widgetStorage = new LocalStorage();

/**
 * 鸿蒙桌面服务卡片 UI：
 * - 展示最近一次同步的实例名称、电影/剧集入库数与实时下载速度；
 * - 点击卡片通过 `postCardAction` 路由唤起 `EntryAbility` 直达仪表盘。
 */
@Entry(widgetStorage)
@Component
struct WidgetCard {
  @LocalStorageProp('server') server: string = 'MoviePilot';
  @LocalStorageProp('movies') movies: number = 0;
  @LocalStorageProp('tvs') tvs: number = 0;
  @LocalStorageProp('speed') speed: string = '0 B/s';

  build() {
    Column({ space: 8 }) {
      Text(this.server)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D6BDFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row() {
        Column() {
          Text(`${this.movies}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('电影').fontSize(11).fontColor('#B8FFFFFF')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column() {
          Text(`${this.tvs}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('剧集').fontSize(11).fontColor('#B8FFFFFF')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Text(`实时下载：${this.speed}`)
        .fontSize(12)
        .fontColor('#75E6A3')
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .linearGradient({ angle: 145, colors: [['#30334A', 0], ['#4A3B57', 0.5], ['#242E40', 1]] })
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          uri: 'moviepilot://dashboard'
        }
      });
    })
  }
}
