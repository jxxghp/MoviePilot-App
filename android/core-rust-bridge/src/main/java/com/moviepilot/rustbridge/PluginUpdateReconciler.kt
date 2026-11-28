package com.moviepilot.rustbridge

/**
 * 插件更新标记对账工具：
 * - 单插件更新完成后仅清除该插件（及同源分身）的 `hasUpdate`，保留其余待更新插件的更新状态；
 * - 刷新阶段若市场接口失败或超时，自动沿用旧市场/旧已安装快照，避免其他插件更新状态消失。
 */
object PluginUpdateReconciler {
    fun canonicalId(id: String, sourcePluginId: String = ""): String {
        val raw = sourcePluginId.trim().ifEmpty { id.trim() }
        return raw.lowercase()
    }

    /** 仅清除已更新插件（及同源分身）在列表中的 `hasUpdate`，保留其余插件原有状态。 */
    fun markPluginUpdated(
        items: List<PluginItemDto>,
        pluginId: String,
        sourcePluginId: String = "",
        markInstalled: Boolean = true,
    ): List<PluginItemDto> {
        val targets = normalizedTargets(pluginId, sourcePluginId)
        if (targets.isEmpty() || items.isEmpty()) return items
        return items.map { item ->
            val idKey = item.id.trim().lowercase()
            val canonKey = canonicalId(item.id, item.sourcePluginId)
            if (idKey in targets || canonKey in targets) {
                item.copy(
                    installed = if (markInstalled) true else item.installed,
                    hasUpdate = false,
                )
            } else {
                item
            }
        }
    }

    /**
     * 将市场更新状态投影至已安装插件列表：
     * - 当 `freshMarket` 非空（服务端成功返回最新市场快照）时，以最新市场快照为准权威更新 `hasUpdate` 与缺省 `repoUrl`；
     * - 当 `freshMarket` 为空（市场拉取失败/超时）时，退回 `fallbackMarket` 或 `previousInstalled` 保留未更新插件的 `hasUpdate`，
     *   同时确保 `completedUpdateIds` 中的插件保持 `hasUpdate = false`。
     */
    fun reconcileInstalledUpdates(
        installed: List<PluginItemDto>,
        freshMarket: List<PluginItemDto>?,
        fallbackMarket: List<PluginItemDto> = emptyList(),
        previousInstalled: List<PluginItemDto> = emptyList(),
        completedUpdateIds: Set<String> = emptySet(),
    ): List<PluginItemDto> {
        if (installed.isEmpty()) return installed
        val completed = completedUpdateIds
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
            .toSet()

        if (freshMarket != null) {
            val updatableByKey = buildUpdatableLookup(freshMarket, excluded = emptySet())
            return installed.map { item ->
                val idKey = item.id.trim().lowercase()
                val canonKey = canonicalId(item.id, item.sourcePluginId)
                val match = updatableByKey[canonKey] ?: updatableByKey[idKey]
                item.copy(
                    hasUpdate = match != null,
                    repoUrl = item.repoUrl.ifBlank { match?.repoUrl.orEmpty() },
                )
            }
        }

        val fallbackSource = fallbackMarket.ifEmpty { previousInstalled }
        val updatableByKey = buildUpdatableLookup(fallbackSource, excluded = completed)
        return installed.map { item ->
            val idKey = item.id.trim().lowercase()
            val canonKey = canonicalId(item.id, item.sourcePluginId)
            if (idKey in completed || canonKey in completed) {
                item.copy(hasUpdate = false)
            } else {
                val match = updatableByKey[canonKey] ?: updatableByKey[idKey]
                if (match != null) {
                    item.copy(
                        hasUpdate = true,
                        repoUrl = item.repoUrl.ifBlank { match.repoUrl },
                    )
                } else {
                    item
                }
            }
        }
    }

    private fun normalizedTargets(pluginId: String, sourcePluginId: String): Set<String> =
        buildSet {
            pluginId.trim().lowercase().takeIf { it.isNotEmpty() }?.let(::add)
            sourcePluginId.trim().lowercase().takeIf { it.isNotEmpty() }?.let(::add)
        }

    private fun buildUpdatableLookup(
        items: List<PluginItemDto>,
        excluded: Set<String>,
    ): Map<String, PluginItemDto> {
        val map = LinkedHashMap<String, PluginItemDto>()
        for (item in items) {
            if (!item.hasUpdate) continue
            val idKey = item.id.trim().lowercase()
            val canonKey = canonicalId(item.id, item.sourcePluginId)
            if (idKey in excluded || canonKey in excluded) continue
            if (idKey.isNotEmpty()) map[idKey] = item
            if (canonKey.isNotEmpty()) map[canonKey] = item
        }
        return map
    }
}
