package com.moviepilot.rustbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PluginUpdateReconcilerTest {
    @Test
    fun updatingOnePluginPreservesOtherPluginsOnMarketSuccessAndFailure() {
        val previousInstalled = listOf(
            PluginItemDto(id = "PluginA", installed = true, hasUpdate = true, repoUrl = "https://repo.test/a"),
            PluginItemDto(id = "PluginB", installed = true, hasUpdate = true, repoUrl = "https://repo.test/b"),
            PluginItemDto(
                id = "PluginC_Clone",
                sourcePluginId = "PluginC",
                installed = true,
                hasUpdate = true,
                repoUrl = "https://repo.test/c",
            ),
        )
        val previousMarket = listOf(
            PluginItemDto(id = "PluginA", installed = true, hasUpdate = true, repoUrl = "https://repo.test/a"),
            PluginItemDto(id = "PluginB", installed = true, hasUpdate = true, repoUrl = "https://repo.test/b"),
            PluginItemDto(id = "PluginC", installed = true, hasUpdate = true, repoUrl = "https://repo.test/c"),
        )

        val updatedMarketCache = PluginUpdateReconciler.markPluginUpdated(previousMarket, "PluginA")
        assertFalse(updatedMarketCache.first { it.id == "PluginA" }.hasUpdate)
        assertTrue(updatedMarketCache.first { it.id == "PluginB" }.hasUpdate)
        assertTrue(updatedMarketCache.first { it.id == "PluginC" }.hasUpdate)

        val freshInstalled = listOf(
            PluginItemDto(id = "PluginA", installed = true, hasUpdate = false),
            PluginItemDto(id = "PluginB", installed = true, hasUpdate = false),
            PluginItemDto(id = "PluginC_Clone", sourcePluginId = "PluginC", installed = true, hasUpdate = false),
        )

        // 场景 1：市场请求失败（null）时，保留 B 与分身 C 的待更新状态且 A 保持已更新
        val fallbackReconciled = PluginUpdateReconciler.reconcileInstalledUpdates(
            installed = freshInstalled,
            freshMarket = null,
            fallbackMarket = updatedMarketCache,
            previousInstalled = previousInstalled,
            completedUpdateIds = setOf("PluginA"),
        )
        assertFalse(fallbackReconciled.first { it.id == "PluginA" }.hasUpdate)
        assertTrue(fallbackReconciled.first { it.id == "PluginB" }.hasUpdate)
        assertEquals("https://repo.test/b", fallbackReconciled.first { it.id == "PluginB" }.repoUrl)
        assertTrue(fallbackReconciled.first { it.id == "PluginC_Clone" }.hasUpdate)

        // 场景 2：市场请求成功返回权威列表后，准确保留 B 与分身 C 并清除 A
        val freshMarket = listOf(
            PluginItemDto(id = "PluginB", installed = true, hasUpdate = true, repoUrl = "https://repo.test/b-v2"),
            PluginItemDto(id = "PluginC", installed = true, hasUpdate = true, repoUrl = "https://repo.test/c"),
        )
        val authoritative = PluginUpdateReconciler.reconcileInstalledUpdates(
            installed = freshInstalled,
            freshMarket = freshMarket,
            fallbackMarket = updatedMarketCache,
            previousInstalled = previousInstalled,
            completedUpdateIds = setOf("PluginA"),
        )
        assertFalse(authoritative.first { it.id == "PluginA" }.hasUpdate)
        assertTrue(authoritative.first { it.id == "PluginB" }.hasUpdate)
        assertEquals("https://repo.test/b-v2", authoritative.first { it.id == "PluginB" }.repoUrl)
        assertTrue(authoritative.first { it.id == "PluginC_Clone" }.hasUpdate)
    }
}
