package com.moviepilot.medal3d

import android.content.Context
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.text.NumberFormat
import java.util.Locale

/** 单仓官方代码贡献事实（按 max(commits, mergedPRs) 计算）。 */
@Serializable
data class CommunityCodeRepoFact(
    val repository: String = "",
    val area: String? = null,
    val commits: Int = 0,
    @SerialName("merged_prs") val mergedPRs: Int = 0,
) {
    val effectiveCount: Int get() = maxOf(commits, mergedPRs)
}

/** 单个布景插件安装量事实。 */
@Serializable
data class CommunityPluginFact(
    val id: String = "",
    val name: String = "",
    val market: String? = null,
    val installs: Int = 0,
)

/** 阶梯勋章的认定事实。 */
@Serializable
data class CommunityMedalFacts(
    val total: Int? = null,
    val repositories: List<CommunityCodeRepoFact> = emptyList(),
    val installs: Int? = null,
    val plugins: List<CommunityPluginFact> = emptyList(),
)

/** 单枚社区勋章记录（对应 `/api/v1/github/community` 中 `medals[]` 元素）。 */
@Serializable
data class CommunityMedalRecord(
    val key: String = "",
    val tier: Int? = null,
    val specialty: String? = null,
    val at: String? = null,
    val basis: String? = null,
    val note: String? = null,
    val serial: String? = null,
    val facts: CommunityMedalFacts? = null,
) {
    val spec: CommunityMedalSpec? get() = CommunityMedalCatalog.spec(key)

    val normalizedTier: Int?
        get() = if (spec?.isLadder == true && tier != null && tier in 1..4) tier else null

    val seenToken: String
        get() = if (normalizedTier != null) "$key:t$normalizedTier" else key
}

/** 后端 `GET /api/v1/github/community` 完整载荷。 */
@Serializable
data class CommunityProfile(
    val state: String = "unknown",
    val login: String? = null,
    @SerialName("user_id") val userId: Int? = null,
    val medals: List<CommunityMedalRecord> = emptyList(),
    @SerialName("generated_at") val generatedAt: String? = null,
    @SerialName("checked_at") val checkedAt: Long? = null,
    val stale: Boolean = false,
    val refreshing: Boolean = false,
) {
    val orderedKnownMedals: List<CommunityMedalRecord>
        get() {
            val order = CommunityMedalCatalog.orderedKeys
            return medals
                .filter { CommunityMedalCatalog.spec(it.key) != null }
                .sortedBy { order.indexOf(it.key).let { idx -> if (idx < 0) Int.MAX_VALUE else idx } }
        }

    val hasEarnedMedals: Boolean
        get() = state == "ready" && orderedKnownMedals.isNotEmpty()
}

/** 单枚社区勋章官方目录规格（1:1 对齐 iOS `CommunityMedalCatalog`）。 */
data class CommunityMedalSpec(
    val key: String,
    val name: String,
    val isLadder: Boolean,
    val isAutomatic: Boolean,
    val toneHex: String,
    val enamelCenterHex: String,
    val enamelEdgeHex: String,
    val inkHex: String,
    val summary: String,
    val rule: String,
    val thresholds: List<Int> = emptyList(),
    val thresholdLabels: List<String> = emptyList(),
) {
    val howLabel: String get() = if (isAutomatic) "自动认定" else "维护团队颁发"
}

/** 阶梯勋章金属铭牌配色（1 青铜初光、2 白银共建、3 流金卓越、4 黑金核心）。 */
data class CommunityTierStyle(
    val tier: Int,
    val name: String,
    val metalHex: String,
    val darkInkHex: String,
    val lightInkHex: String,
    val isObsidianGold: Boolean,
)

/** 阶梯勋章四档进度计算投影。 */
data class CommunityMedalTierProgress(
    val currentTier: Int,
    val nextTier: Int?,
    val currentValue: Int,
    val fromThreshold: Int,
    val toThreshold: Int?,
    val fractionToNext: Double,
    val trackFill: Double,
    val statusText: String,
)

/** 背面铭牌动态雕刻文本。 */
data class CommunityMedalEngraving(
    val title: String,
    val tierLine: String?,
    val recipientLine: String?,
    val timeLine: String?,
    val makerMark: String = "MoviePilot",
)

/** 轮廓 JSON 结构（对应 `community_medals/<stem>.outline.json`）。 */
@Serializable
data class CommunityMedalOutline(
    val outline: List<List<Double>> = emptyList(),
    val dial: DialRect? = null,
    val spin: SpinConfig? = null,
) {
    @Serializable
    data class DialRect(
        val x: Double,
        val y: Double,
        val width: Double,
        val height: Double,
    )

    @Serializable
    data class SpinConfig(
        val x: Double,
        val y: Double,
        val r: Double,
        val period: Double? = null,
        val mode: String? = null,
        val step: Double? = null,
        val interval: Double? = null,
    )
}

/** 社区勋章官方目录、规则文案、档位铭牌与资源命名工具（1:1 复刻 `CommunityMedalsModel.swift`）。 */
object CommunityMedalCatalog {
    val orderedKeys = listOf("code", "plugin", "maintainer", "helper", "security", "tester", "pioneer")

    val allSpecs: List<CommunityMedalSpec> = listOf(
        CommunityMedalSpec(
            key = "code",
            name = "编剧",
            isLadder = true,
            isAutomatic = true,
            toneHex = "#3fc4c9",
            enamelCenterHex = "#0f5560",
            enamelEdgeHex = "#041b20",
            inkHex = "#d2f1ef",
            summary = "致敬为 MoviePilot 写下代码与文档的贡献者。",
            rule = "向 MoviePilot 官方仓库提交并被采纳的贡献累计满 1、10、50、200 次，依次获得初光、共建、卓越、核心。",
            thresholds = listOf(1, 10, 50, 200),
            thresholdLabels = listOf("1 次", "10 次", "50 次", "200 次"),
        ),
        CommunityMedalSpec(
            key = "plugin",
            name = "布景",
            isLadder = true,
            isAutomatic = true,
            toneHex = "#e08a4c",
            enamelCenterHex = "#7d4321",
            enamelEdgeHex = "#211009",
            inkHex = "#f3cb9c",
            summary = "致敬为 MoviePilot 开发插件的作者。",
            rule = "发布首个插件即获得初光；插件累计安装满 1 万、10 万、100 万次，依次获得共建、卓越、核心。",
            thresholds = listOf(1, 10_000, 100_000, 1_000_000),
            thresholdLabels = listOf("首个上架", "1 万次", "10 万次", "100 万次"),
        ),
        CommunityMedalSpec(
            key = "maintainer",
            name = "主创",
            isLadder = false,
            isAutomatic = false,
            toneHex = "#9b7bff",
            enamelCenterHex = "#3d2380",
            enamelEdgeHex = "#120828",
            inkHex = "#e0d6ff",
            summary = "致敬 MoviePilot 的维护者与核心团队。",
            rule = "由维护团队颁发给项目的维护者与核心成员。",
        ),
        CommunityMedalSpec(
            key = "helper",
            name = "掌灯",
            isLadder = false,
            isAutomatic = false,
            toneHex = "#e6b04a",
            enamelCenterHex = "#6e4a12",
            enamelEdgeHex = "#1f1304",
            inkHex = "#f7dca0",
            summary = "致敬在社群里为他人答疑解惑的热心人。",
            rule = "由维护团队颁发给长期在社群中帮助他人的用户。",
        ),
        CommunityMedalSpec(
            key = "security",
            name = "守夜",
            isLadder = false,
            isAutomatic = false,
            toneHex = "#6f8dff",
            enamelCenterHex = "#1d2f7a",
            enamelEdgeHex = "#070c2e",
            inkHex = "#d8e0fb",
            summary = "致敬守护 MoviePilot 安全的人。",
            rule = "由维护团队颁发给负责任地报告安全问题，并协助完成修复的用户。",
        ),
        CommunityMedalSpec(
            key = "tester",
            name = "试映",
            isLadder = false,
            isAutomatic = false,
            toneHex = "#ff86b0",
            enamelCenterHex = "#6e1735",
            enamelEdgeHex = "#22050f",
            inkHex = "#ffd3e2",
            summary = "致敬抢先体验并帮助打磨新版本的测试者。",
            rule = "由维护团队颁发给参与测试版本，并提交有效问题反馈的用户。",
        ),
        CommunityMedalSpec(
            key = "pioneer",
            name = "启幕",
            isLadder = false,
            isAutomatic = false,
            toneHex = "#e0524a",
            enamelCenterHex = "#6e1414",
            enamelEdgeHex = "#200404",
            inkHex = "#ffd2c4",
            summary = "致敬在 MoviePilot 早期给予支持的人。",
            rule = "由维护团队颁发给项目早期的赞助者与贡献者。",
        ),
    )

    fun spec(key: String): CommunityMedalSpec? = allSpecs.firstOrNull { it.key == key }

    fun tierStyle(tier: Int): CommunityTierStyle = when (tier) {
        1 -> CommunityTierStyle(1, "初光", "#bd926c", "#cfad8e", "#785333", false)
        2 -> CommunityTierStyle(2, "共建", "#a6b6c8", "#bcc9d8", "#536579", false)
        3 -> CommunityTierStyle(3, "卓越", "#c6a45d", "#d7bc81", "#7d6129", false)
        else -> CommunityTierStyle(4, "核心", "#bda16e", "#dfcba1", "#6d5835", true)
    }

    fun specialtyName(specialty: String?): String? = when (specialty) {
        "backend" -> "主程序共建者"
        "frontend" -> "界面共建者"
        "plugins" -> "官方插件共建者"
        "performance" -> "扩展共建者"
        "resources" -> "资源共建者"
        "services" -> "服务共建者"
        "website" -> "官网共建者"
        "docs" -> "文档共建者"
        "ecosystem" -> "生态共建者"
        else -> null
    }

    fun areaName(area: String?): String? = when (area) {
        "backend" -> "主程序"
        "frontend" -> "前端界面"
        "plugins" -> "官方插件"
        "performance" -> "Rust 扩展"
        "resources" -> "构建与资源"
        "services" -> "外围服务"
        "website" -> "官方网站"
        "docs" -> "社区文档"
        else -> null
    }

    fun tierLine(record: CommunityMedalRecord): String? {
        val tier = record.normalizedTier ?: return null
        val tierName = tierStyle(tier).name
        if (record.key == "code") {
            val sp = specialtyName(record.specialty)
            if (sp != null) return "$tierName · $sp"
        }
        return tierName
    }

    fun timeLine(record: CommunityMedalRecord): String? {
        val raw = record.at?.trim().orEmpty()
        if (raw.isEmpty()) return null
        val dotted = raw.replace("-", ".")
        return when (record.basis) {
            "reached" -> "达成 $dotted"
            "recognized" -> "认定 $dotted"
            else -> dotted
        }
    }

    fun engraving(record: CommunityMedalRecord, login: String?): CommunityMedalEngraving {
        val cleanLogin = login?.trim().orEmpty()
        return CommunityMedalEngraving(
            title = record.spec?.name ?: record.key,
            tierLine = tierLine(record),
            recipientLine = if (cleanLogin.isNotEmpty()) "授予 @$cleanLogin" else null,
            timeLine = timeLine(record),
            makerMark = "MoviePilot",
        )
    }

    fun tierProgress(record: CommunityMedalRecord): CommunityMedalTierProgress? {
        val spec = record.spec ?: return null
        if (!spec.isLadder || spec.thresholds.size != 4) return null
        val value = when (record.key) {
            "code" -> record.facts?.total ?: 0
            "plugin" -> record.facts?.installs ?: 0
            else -> return null
        }
        val tier = record.normalizedTier ?: run {
            var computed = 1
            spec.thresholds.forEachIndexed { idx, th -> if (value >= th) computed = idx + 1 }
            computed
        }
        val fromThreshold = spec.thresholds[(tier - 1).coerceAtLeast(0)]
        if (tier >= 4) {
            return CommunityMedalTierProgress(
                currentTier = 4,
                nextTier = null,
                currentValue = value,
                fromThreshold = fromThreshold,
                toThreshold = null,
                fractionToNext = 1.0,
                trackFill = 1.0,
                statusText = "已达最高档",
            )
        }
        val nextTier = tier + 1
        val toThreshold = spec.thresholds[nextTier - 1]
        val span = (toThreshold - fromThreshold).coerceAtLeast(1)
        val fraction = ((value - fromThreshold).toDouble() / span.toDouble()).coerceIn(0.0, 1.0)
        val trackFill = (((tier - 1) + fraction) / 3.0).coerceIn(0.0, 1.0)
        val remaining = (toThreshold - value).coerceAtLeast(0)
        val nextName = tierStyle(nextTier).name
        val statusText = if (record.key == "code") {
            "距${nextName}还差 ${formatCount(remaining)} 次贡献"
        } else {
            "距${nextName}还差 ${formatCount(remaining)} 次安装"
        }
        return CommunityMedalTierProgress(
            currentTier = tier,
            nextTier = nextTier,
            currentValue = value,
            fromThreshold = fromThreshold,
            toThreshold = toThreshold,
            fractionToNext = fraction,
            trackFill = trackFill,
            statusText = statusText,
        )
    }

    fun frontAssetStem(record: CommunityMedalRecord): String =
        record.normalizedTier?.let { "${record.key}-front-t$it" } ?: "${record.key}-front"

    fun backAssetStem(record: CommunityMedalRecord): String = "${record.key}-back"

    fun badgeAssetStem(record: CommunityMedalRecord): String =
        record.normalizedTier?.let { "${record.key}-badge-t$it" } ?: "${record.key}-badge"

    fun formatCount(count: Int): String =
        NumberFormat.getNumberInstance(Locale.CHINA).format(count)

    fun parseColor(hex: String, alpha: Float = 1f): Color {
        val cleaned = hex.trim().removePrefix("#")
        val rgb = cleaned.toLongOrNull(16) ?: 0x9B7BFFL
        return Color((0xFF000000L or rgb)).copy(alpha = alpha)
    }

    fun parseColorInt(hex: String): Int = runCatching {
        android.graphics.Color.parseColor(if (hex.startsWith("#")) hex else "#$hex")
    }.getOrDefault(0xFF9B7BFF.toInt())
}

/** 轻量持久化管理社区勋章的已读状态与当前佩戴勋章键（按 GitHub user_id 隔离）。 */
@Stable
class CommunityMedalsPrefsStore(context: Context) {
    private val prefs = context.getSharedPreferences("mp_community_medals_v2", Context.MODE_PRIVATE)
    var revision by mutableIntStateOf(0)
        private set

    private fun seenKey(userId: Int?) = "seen:${userId ?: 0}"
    private fun wornKey(userId: Int?) = "worn:${userId ?: 0}"

    fun seenTokens(userId: Int?): Set<String> =
        prefs.getStringSet(seenKey(userId), emptySet()) ?: emptySet()

    fun isUnseen(record: CommunityMedalRecord, userId: Int?): Boolean =
        !seenTokens(userId).contains(record.seenToken)

    fun unseenCount(medals: List<CommunityMedalRecord>, userId: Int?): Int {
        val seen = seenTokens(userId)
        return medals.count { !seen.contains(it.seenToken) }
    }

    fun markSeen(record: CommunityMedalRecord, userId: Int?) {
        val current = seenTokens(userId).toMutableSet()
        if (current.add(record.seenToken)) {
            prefs.edit().putStringSet(seenKey(userId), current).apply()
            revision++
        }
    }

    fun wornMedalKey(userId: Int?): String? =
        prefs.getString(wornKey(userId), null)?.takeIf { it.isNotBlank() }

    fun toggleWear(key: String, userId: Int?) {
        val cur = wornMedalKey(userId)
        if (cur == key) {
            prefs.edit().remove(wornKey(userId)).apply()
        } else {
            prefs.edit().putString(wornKey(userId), key).apply()
        }
        revision++
    }
}
