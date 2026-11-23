const widgetStorage = new LocalStorage();

/** 鸿蒙桌面服务卡片 UI（延续星夜紫玫低雾透色视觉风格）。 */
@Entry(widgetStorage)
@Component
struct WidgetCard {
  @LocalStorageProp('server') server: string = 'MoviePilot';
  @LocalStorageProp('movies') movies: number = 776;
  @LocalStorageProp('tvs') tvs: number = 1268;
  @LocalStorageProp('speed') speed: string = '12.4 MB/s';

  build() {
    Column({ space: 8 }) {
      Text(this.server).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#D6BDFF').width('100%')
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
      Text(`实时下载：${this.speed}`).fontSize(12).fontColor('#75E6A3').width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .linearGradient({ angle: 145, colors: [['#30334A', 0], ['#4A3B57', 0.5], ['#242E40', 1]] })
  }
}
