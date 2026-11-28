package com.moviepilot.pluginhost

import org.junit.Assert.assertEquals
import org.junit.Test
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject

/** Vuetify 线性进度值归一化测试。 */
class NativePluginProgressTest {
    /** 真实节点格式包含连字符属性、像素高度、布尔圆角与透明背景；解析后供同一原生渲染分支使用。 */
    @Test
    fun parsesVuetifyNodeAndTransparentOverlay() {
        val props = Json.parseToJsonElement(
            """{"model-value":1,"height":"8px","rounded":false,"bg-opacity":0}""",
        ).jsonObject
        assertEquals(NativePluginProgressSpec(1f, 8f, false, 0f), parseVuetifyProgress(props))
        val aliases = Json.parseToJsonElement("""{"modelValue":"40","bgOpacity":"0.5"}""").jsonObject
        assertEquals(NativePluginProgressSpec(40f, 6f, true, 0.5f), parseVuetifyProgress(aliases))
    }

    /** 验证进度值按 0..100 百分比夹取，且 1 代表 1%，不代表 100%。 */
    @Test
    fun normalizesVuetifyProgressPercent() {
        assertEquals(0f, normalizeVuetifyProgressPercent(-1.0), 0f)
        assertEquals(0f, normalizeVuetifyProgressPercent(0.0), 0f)
        assertEquals(1f, normalizeVuetifyProgressPercent(1.0), 0f)
        assertEquals(42f, normalizeVuetifyProgressPercent(42.0), 0f)
        assertEquals(100f, normalizeVuetifyProgressPercent(101.0), 0f)
    }
}
