import MoviePilotCore
import Testing

struct PluginUpdateProjectionTests {
  @Test func updatingOnePluginPreservesOtherPluginsUpdateStatusBeforeAndAfterMarketSync() {
    let previousInstalled = [
      PluginUpdateProjectionItem(id: "PluginA", hasUpdate: true, repoURL: "https://repo.example/a"),
      PluginUpdateProjectionItem(id: "PluginB", hasUpdate: true, repoURL: "https://repo.example/b"),
      PluginUpdateProjectionItem(id: "PluginC_Clone", sourcePluginID: "PluginC", hasUpdate: true, repoURL: "https://repo.example/c"),
    ]
    let cachedMarketBefore = [
      PluginUpdateProjectionItem(id: "PluginA", hasUpdate: true, repoURL: "https://repo.example/a"),
      PluginUpdateProjectionItem(id: "PluginB", hasUpdate: true, repoURL: "https://repo.example/b"),
      PluginUpdateProjectionItem(id: "PluginC", hasUpdate: true, repoURL: "https://repo.example/c"),
    ]

    // 1. PluginA 更新完成：仅清除市场缓存中 PluginA 的更新标记，B 与 C 保持待更新
    let marketAfterA = PluginUpdateProjection.markUpdatedInMarket(cachedMarketBefore, pluginID: "PluginA")
    #expect(marketAfterA.first(where: { $0.id == "PluginA" })?.hasUpdate == false)
    #expect(marketAfterA.first(where: { $0.id == "PluginB" })?.hasUpdate == true)
    #expect(marketAfterA.first(where: { $0.id == "PluginC" })?.hasUpdate == true)

    // 2. 服务端 state=installed 返回全部 has_update=false；承接阶段立刻保留 B 与分身 C 的更新状态且 A 保持已更新
    let freshInstalled = [
      PluginUpdateProjectionItem(id: "PluginA", hasUpdate: false, repoURL: nil),
      PluginUpdateProjectionItem(id: "PluginB", hasUpdate: false, repoURL: nil),
      PluginUpdateProjectionItem(id: "PluginC_Clone", sourcePluginID: "PluginC", hasUpdate: false, repoURL: nil),
    ]
    let carried = PluginUpdateProjection.carryOverBeforeMarketSync(
      freshInstalled: freshInstalled,
      previousInstalled: previousInstalled,
      cachedMarket: marketAfterA,
      completedUpdateIDs: ["plugina"]
    )
    #expect(carried.first(where: { $0.id == "PluginA" })?.hasUpdate == false)
    #expect(carried.first(where: { $0.id == "PluginB" })?.hasUpdate == true)
    #expect(carried.first(where: { $0.id == "PluginB" })?.repoURL == "https://repo.example/b")
    #expect(carried.first(where: { $0.id == "PluginC_Clone" })?.hasUpdate == true)

    // 3. 即使没有市场缓存（如首次进入直接更新），仍能从上一帧 installed 承接 B 与 C 并清除 A
    let carriedWithoutMarketCache = PluginUpdateProjection.carryOverBeforeMarketSync(
      freshInstalled: freshInstalled,
      previousInstalled: previousInstalled,
      cachedMarket: nil,
      completedUpdateIDs: ["PluginA"]
    )
    #expect(carriedWithoutMarketCache.first(where: { $0.id == "PluginA" })?.hasUpdate == false)
    #expect(carriedWithoutMarketCache.first(where: { $0.id == "PluginB" })?.hasUpdate == true)
    #expect(carriedWithoutMarketCache.first(where: { $0.id == "PluginC_Clone" })?.hasUpdate == true)

    // 4. 最新 state=market 返回后，权威覆盖全部更新状态
    let authoritativeMarket = [
      PluginUpdateProjectionItem(id: "PluginB", hasUpdate: true, repoURL: "https://repo.example/b-v2"),
      PluginUpdateProjectionItem(id: "PluginC", hasUpdate: true, repoURL: "https://repo.example/c"),
    ]
    let reconciled = PluginUpdateProjection.applyAuthoritativeMarket(
      installed: carried,
      market: authoritativeMarket
    )
    #expect(reconciled.first(where: { $0.id == "PluginA" })?.hasUpdate == false)
    #expect(reconciled.first(where: { $0.id == "PluginB" })?.hasUpdate == true)
    #expect(reconciled.first(where: { $0.id == "PluginC_Clone" })?.hasUpdate == true)
  }
}
