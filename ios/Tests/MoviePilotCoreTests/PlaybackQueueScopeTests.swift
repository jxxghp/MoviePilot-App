import Testing

@testable import MoviePilotCore

/// 播放离线队列归属回归，实例、部署子路径和账号都不能共享桶。
struct PlaybackQueueScopeTests {
  /// 同一实例的等价 URL 复用队列，切换端口、部署路径或账号均独立。
  @Test func isolatesInstancesAndAccounts() throws {
    let a = try ServerAddress("https://MP.example.test:443/a")
    let same = try ServerAddress("https://mp.example.test/a/")
    let key = PlaybackQueueScope.storageKey(address: a, accountID: 7)
    #expect(key == PlaybackQueueScope.storageKey(address: same, accountID: 7))
    #expect(key != PlaybackQueueScope.storageKey(address: a, accountID: 8))
    for address in [
      "https://mp.example.test/b", "https://mp.example.test:8443/a", "http://mp.example.test/a",
    ] {
      #expect(
        key != PlaybackQueueScope.storageKey(address: try ServerAddress(address), accountID: 7))
    }
    #expect(!key.contains("mp.example.test"))
    #expect(!key.contains("pendingStops.v1"))
  }
}
