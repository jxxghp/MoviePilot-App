import MoviePilotCore
import XCTest

final class DanmakuCoreTests: XCTestCase {
  func testCompactPayloadOffsetFilterAndColorDowngrade() {
    let payload = """
      {
        "success": true,
        "data": {
          "schema_version": 1,
          "episode_id": 1001,
          "count": 4,
          "items": [
            [5000, 1, 16711680, "滚动红字", "bilibili"],
            [1000, 5, 65280, "顶部绿字", "tencent"],
            [3000, 4, 255, "底部蓝字", "iqiyi"],
            [500, 1, 16777215, "负时间丢弃", ""]
          ]
        }
      }
      """
    let options = DanmakuFilterOptions(
      allowScroll: true,
      allowTop: true,
      allowBottom: false,
      allowColor: false,
      mergeDuplicates: false,
      maxPerSecond: 12,
      offsetMs: -600
    )
    let timeline = DanmakuTimelineProcessor.prepare(rawPayload: payload, options: options)
    XCTAssertEqual(timeline.rawCount, 4)
    XCTAssertEqual(timeline.filteredCount, 2)
    XCTAssertEqual(timeline.items[0].timeMs, 400)
    XCTAssertEqual(timeline.items[0].mode, .top)
    XCTAssertEqual(timeline.items[0].colorRgb, 0x00FF_FFFF)
    XCTAssertEqual(timeline.items[1].timeMs, 4400)
    XCTAssertEqual(timeline.items[1].mode, .scroll)
  }

  func testDuplicateMergeAndPerSecondThrottlePrefersHotItems() {
    let payload = """
      [
        [1000, 1, 16777215, "普通1"],
        [1050, 1, 16777215, "普通2"],
        [1100, 1, 16777215, "哈哈哈"],
        [1200, 1, 16777215, "哈哈哈"],
        [1300, 1, 16777215, "哈哈哈"],
        [1400, 1, 16777215, "普通3"],
        [5000, 1, 16777215, "哈哈哈"]
      ]
      """
    let options = DanmakuFilterOptions(
      mergeDuplicates: true,
      mergeWindowMs: 3000,
      maxPerSecond: 2
    )
    let timeline = DanmakuTimelineProcessor.prepare(rawPayload: payload, options: options)
    XCTAssertEqual(timeline.filteredCount, 3)
    XCTAssertEqual(timeline.items[0].text, "普通1")
    XCTAssertEqual(timeline.items[1].text, "哈哈哈")
    XCTAssertEqual(timeline.items[1].repeatCount, 3)
    XCTAssertEqual(timeline.items[2].timeMs, 5000)
  }

  func testBilibiliXMLAndKeywordBlocking() {
    let xml = """
      <?xml version="1.0"?>
      <i>
        <d p="2.5,4,25,16711680,1700000000,0,a,1">A &amp; B</d>
        <d p="1.0,1,25,16777215,1700000000,0,b,2">剧透警告</d>
        <d p="3.0,1,25,16777215,1700000000,0,c,3">SPAM-999-AD</d>
      </i>
      """
    let options = DanmakuFilterOptions(
      blockKeywords: ["剧透", "/^spam*ad$/"]
    )
    let timeline = DanmakuTimelineProcessor.prepare(rawPayload: xml, options: options)
    XCTAssertEqual(timeline.filteredCount, 1)
    XCTAssertEqual(timeline.items[0].text, "A & B")
    XCTAssertEqual(timeline.items[0].mode, .bottom)
  }

  func testNormalizeQueryTitle() {
    XCTAssertEqual(
      DanmakuTimelineProcessor.normalizeQueryTitle(
        seriesName: "葬送的芙莉莲", title: "冒险的终点", season: 1, episode: 1, fileName: nil),
      "葬送的芙莉莲"
    )
    XCTAssertEqual(
      DanmakuTimelineProcessor.normalizeQueryTitle(
        seriesName: "鬼灭之刃", title: nil, season: 2, episode: 3, fileName: nil),
      "鬼灭之刃 第2季"
    )
    XCTAssertEqual(
      DanmakuTimelineProcessor.normalizeQueryTitle(
        seriesName: nil, title: nil, season: nil, episode: nil,
        fileName: "/vol/[SubGroup] Frieren.S01E01.1080p.WEB-DL.mkv"),
      "Frieren"
    )
  }
}
