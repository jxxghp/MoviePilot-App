package com.moviepilot.rustbridge

import com.moviepilot.rustcore.CronSummaryFfi
import com.moviepilot.rustcore.JwtClaimsFfi
import com.moviepilot.rustcore.MarkdownBlockFfi
import com.moviepilot.rustcore.MedalPaletteFfi
import com.moviepilot.rustcore.NativeSseParser
import com.moviepilot.rustcore.PermissionsFfi
import com.moviepilot.rustcore.SubscribeProgressFfi
import com.moviepilot.rustcore.analyzeCronExpression
import com.moviepilot.rustcore.applyPluginFormPatch
import com.moviepilot.rustcore.buildV3EndpointUrl
import com.moviepilot.rustcore.classifyHttpAuthStatus
import com.moviepilot.rustcore.computeMedalPalette
import com.moviepilot.rustcore.computeSubscribeProgress
import com.moviepilot.rustcore.coreVersion
import com.moviepilot.rustcore.decodeJwtTokenClaims
import com.moviepilot.rustcore.detectPlayableMediaKind
import com.moviepilot.rustcore.evaluatePluginExpression
import com.moviepilot.rustcore.evaluateUserPermissions
import com.moviepilot.rustcore.filterAndGroupResources
import com.moviepilot.rustcore.normalizeServerAddress
import com.moviepilot.rustcore.parseAgentMarkdown
import com.moviepilot.rustcore.parseDeepLinkJson
import com.moviepilot.rustcore.planPluginFormJson
import com.moviepilot.rustcore.serverAddressContains

/**
 * Rust 共享业务内核统一 Kotlin 门面：所有无 UI 核心逻辑（路由解析、SSE 流、9 维筛选分组、
 * JWT/RBAC 权限判定、动态插件表单规划与无损补丁、Cron 摘要、3D 勋章配色）全部委托 UniFFI。
 */
object RustCoreBridge {

    /** 返回 Rust 共享内核版本号，用于启动冒烟检查与关于页展示。 */
    fun version(): String = runCatching { coreVersion() }.getOrDefault("2.0.2")

    /** 规范化 MoviePilot 服务地址，保留部署子路径并拒绝内嵌凭据。 */
    fun normalizeAddress(raw: String): Result<String> = runCatching {
        normalizeServerAddress(raw)
    }

    /** 校验目标 URL 是否严格属于当前实例源及部署子路径。 */
    fun containsUrl(baseUrl: String, candidateUrl: String): Boolean =
        runCatching { serverAddressContains(baseUrl, candidateUrl) }.getOrDefault(false)

    /** 构造安全的 `/api/v1/...` 完整端点 URL。 */
    fun buildEndpointUrl(
        baseUrl: String,
        segments: List<String>,
        query: List<Pair<String, String>> = emptyList(),
        trailingSlash: Boolean = false,
    ): String {
        val queryJson = if (query.isEmpty()) {
            ""
        } else {
            query.joinToString(prefix = "[", postfix = "]") { (k, v) ->
                "[\"${escapeJson(k)}\",\"${escapeJson(v)}\"]"
            }
        }
        return buildV3EndpointUrl(baseUrl, segments, queryJson, trailingSlash)
    }

    /** 解析 `moviepilot://` 或 Web 路径为 JSON 路由对象。 */
    fun parseDeepLink(rawUrl: String): String? =
        runCatching { parseDeepLinkJson(rawUrl) }.getOrNull()

    /** 判别本地或远端媒体路径是否支持原生播放（`video` / `audio` / `null`）。 */
    fun detectMediaKind(pathOrExt: String, includeStreaming: Boolean = false): String? =
        runCatching { detectPlayableMediaKind(pathOrExt, includeStreaming) }.getOrNull()

    /** 解析 AI 智能助手流式 Markdown 块级节点。 */
    fun parseMarkdown(markdown: String): List<MarkdownBlockFfi> =
        runCatching { parseAgentMarkdown(markdown) }.getOrElse { emptyList() }

    /** 创建有状态流式 SSE 解析器，供 OkHttp 响应流逐块喂入。 */
    fun createSseParser(): NativeSseParser = NativeSseParser()

    /** 调用 Rust 9 维级联筛选与同规格分组引擎。 */
    fun filterResources(resourcesJson: String, criteriaJson: String = ""): String =
        filterAndGroupResources(resourcesJson, criteriaJson)

    /** 本地解析 JWT 过期时间与声明。 */
    fun decodeJwt(token: String, nowEpochSecs: Long = System.currentTimeMillis() / 1000): JwtClaimsFfi =
        decodeJwtTokenClaims(token, nowEpochSecs)

    /** 按前后端一致的严格布尔规则计算用户权限矩阵。 */
    fun evaluatePermissions(permissionsJson: String, isSuperuser: Boolean): PermissionsFfi =
        evaluateUserPermissions(permissionsJson, isSuperuser)

    /** 分类 401/403 响应决策：`valid` / `logout` / `forbidden`。 */
    fun classifyAuthStatus(status: Int, bodyText: String): String =
        classifyHttpAuthStatus(status.toUShort(), bodyText)

    /** 解析插件 `get_form`/`get_page` 文档并输出扁平渲染表单计划 JSON。 */
    fun planPluginForm(documentJson: String): String = planPluginFormJson(documentJson)

    /** 将局部表单补丁无损合并回服务端完整模型（保留未知键与 64 位大整数）。 */
    fun applyPluginPatch(originalModelJson: String, patchJson: String): String =
        applyPluginFormPatch(originalModelJson, patchJson)

    /** 沙箱评估插件表单条件表达式（`v-show` / `v-if`）。 */
    fun evalFormExpression(expr: String, modelJson: String): Boolean =
        runCatching { evaluatePluginExpression(expr, modelJson) }.getOrDefault(true)

    /** 分析 5 字段 Cron 表达式并返回可读中文摘要。 */
    fun analyzeCron(expr: String): CronSummaryFfi = analyzeCronExpression(expr)

    /** 计算 3D 社区勋章金属基色与背面凹雕配色方案。 */
    fun medalPalette(medalId: String): MedalPaletteFfi = computeMedalPalette(medalId)

    /** 计算剧集订阅完成进度。 */
    fun subscribeProgress(total: Int, lack: Int): SubscribeProgressFfi =
        computeSubscribeProgress(total, lack)

    private fun escapeJson(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
}
