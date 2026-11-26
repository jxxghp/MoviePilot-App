package com.moviepilot.app

import com.moviepilot.feature.settings.isDetectedFederationVuePlugin
import com.moviepilot.feature.settings.shouldHideAppPluginTopBar
import com.moviepilot.rustbridge.RustCoreBridge
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 验证 Android 侧 Vue 联邦插件本地运行时的路径安全校验、入口规划与实例隔离缓存键派生。 */
class PluginRemoteRuntimeTest {
    @Test
    fun validatesPluginApiPathAndRejectsUnsafeInputs() {
        assertEquals("/api/v1/plugin/Demo/status?page=1", RustCoreBridge.validatePluginApiPath("plugin/Demo/status?page=1"))
        assertEquals("/api/v1/plugin/Demo/config", RustCoreBridge.validatePluginApiPath("/api/v1/plugin/Demo/config"))
        assertNull(RustCoreBridge.validatePluginApiPath("https://evil.example/api/v1/plugin/x"))
        assertNull(RustCoreBridge.validatePluginApiPath("//evil.example/api/v1/plugin/x"))
        assertNull(RustCoreBridge.validatePluginApiPath("/api/v1/plugin/../system/env"))
        assertNull(RustCoreBridge.validatePluginApiPath("/api/v1/plugin/%2e%2e/secret"))
        assertNull(RustCoreBridge.validatePluginApiPath("/api/v1/plugin/demo\\secret"))
    }

    @Test
    fun normalizesRemoteEntryAndResolvesUpstreamSafely() {
        val plan = RustCoreBridge.normalizePluginRemoteEntry(
            pluginId = "VueCompatDemo",
            versionOrHash = "1.2.0",
            rawRemoteUrl = "/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js?v=1.2.0",
        )
        assertNotNull(plan)
        assertEquals("/plugin-remote/vuecompatdemo/1.2.0/dist/assets/remoteEntry.js", plan?.virtualEntryPath)
        assertEquals("/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js", plan?.upstreamFilePath)

        val target = RustCoreBridge.resolvePluginRemoteUpstream(
            "/plugin-remote/vuecompatdemo/1.2.0/dist/assets/chunk-abc.js?t=1",
        )
        assertNotNull(target)
        assertEquals("dist/assets/chunk-abc.js", target?.assetRelPath)
        assertEquals("/api/v1/plugin/file/vuecompatdemo/dist/assets/chunk-abc.js", target?.upstreamApiPath)

        assertNull(RustCoreBridge.resolvePluginRemoteUpstream("/plugin-remote/demo/1.0/../../etc/passwd"))
        assertEquals("assets/plugin-shell.js", RustCoreBridge.validatePluginShellAssetPath("/shell/assets/plugin-shell.js"))
        assertNull(RustCoreBridge.validatePluginShellAssetPath("/shell/../secret.txt"))
    }

    @Test
    fun isolatesCacheKeysPerInstanceOrigin() {
        val a = RustCoreBridge.buildPluginRemoteCacheKey("https://mp-a.example.com/", "MyPlugin", "2.0.1")
        val b = RustCoreBridge.buildPluginRemoteCacheKey("https://mp-b.example.com", "MyPlugin", "2.0.1")
        assertNotEquals(a.instanceHash, b.instanceHash)
        assertEquals("myplugin", a.pluginIdLower)
        assertEquals("2.0.1", a.versionSegment)
        assertEquals("${a.instanceHash}/myplugin/2.0.1", a.relativeDir)
    }

    @Test
    fun hidesAppTopBarOnlyForFederationVuePluginsWithoutLegacyFallback() {
        assertTrue(isDetectedFederationVuePlugin(pluginRenderMode = "vue"))
        assertTrue(isDetectedFederationVuePlugin(pluginRenderMode = "vuetify", pageJson = """{"render_mode": "vue"}"""))
        assertTrue(isDetectedFederationVuePlugin(pluginRenderMode = "vuetify", formJson = """{"data":{"render_mode":"vue","model":{}}}"""))
        assertFalse(isDetectedFederationVuePlugin(pluginRenderMode = "vuetify", pageJson = """{"render_mode":"vuetify","page":[]}"""))

        // 模块联邦插件已自带关闭退出按钮：隐藏 App 顶栏退出按钮
        assertTrue(shouldHideAppPluginTopBar(isInstalled = true, detectedVuePlugin = true, usingLegacyFallback = false))
        // 传统 MoviePilot 自渲染（vuetify）插件：必须保留 App 顶栏返回退出按钮
        assertFalse(shouldHideAppPluginTopBar(isInstalled = true, detectedVuePlugin = false, usingLegacyFallback = false))
        // 未安装插件或手动回退旧版网页壳：保留 App 顶栏返回退出按钮
        assertFalse(shouldHideAppPluginTopBar(isInstalled = false, detectedVuePlugin = true, usingLegacyFallback = false))
        assertFalse(shouldHideAppPluginTopBar(isInstalled = true, detectedVuePlugin = true, usingLegacyFallback = true))
    }
}
