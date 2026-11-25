package com.moviepilot.rustbridge

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** 已保存的 MoviePilot 服务实例条目。 */
@Serializable
data class SavedServerEntry(
    val id: String,
    val name: String,
    val url: String,
    val username: String = "",
    val lastUsedEpochMs: Long = System.currentTimeMillis(),
)

/**
 * ADR-02 Android 原生安全凭据存储：基于 Android Keystore AES-256-GCM 加密保护令牌与账号凭据，
 * 不在源码、日志或明文偏好中落盘真实密钥。
 */
class NativeSecretStore(context: Context) {
    private val prefs = context.getSharedPreferences("mp_native_secure_store", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    companion object {
        private const val KEY_ALIAS = "moviepilot_secret_aes_key_v1"
        private const val KEY_SERVERS = "saved_servers_v1"
        private const val KEY_ACTIVE_SERVER = "active_server_url_v1"
        private const val KEY_KEEP_LOGIN = "keep_login_v1"
        private const val KEY_REMEMBER_CREDS = "remember_creds_v1"
        private const val KEY_ALLOW_INSECURE_TLS = "allow_insecure_tls_v1"
    }

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        val combined = ByteArray(iv.size + ciphertext.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)
        return Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    private fun decrypt(encoded: String): String? = runCatching {
        val combined = Base64.decode(encoded, Base64.NO_WRAP)
        val iv = combined.copyOfRange(0, 12)
        val ciphertext = combined.copyOfRange(12, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }.getOrNull()

    /** 按实例隔离保存访问令牌。 */
    fun saveToken(serverUrl: String, token: String) {
        prefs.edit().putString("tok_${serverUrl.hashCode()}", encrypt(token)).apply()
    }

    /** 读取指定实例的访问令牌。 */
    fun loadToken(serverUrl: String): String? {
        val raw = prefs.getString("tok_${serverUrl.hashCode()}", null) ?: return null
        return decrypt(raw)
    }

    /** 清除指定实例的访问令牌（401 或主动登出时立即调用）。 */
    fun clearToken(serverUrl: String) {
        prefs.edit().remove("tok_${serverUrl.hashCode()}").apply()
    }

    /** 按实例安全保存账号与密码（仅在用户开启「记住账号密码」时使用）。 */
    fun saveCredentials(serverUrl: String, username: String, password: String) {
        prefs.edit()
            .putString("usr_${serverUrl.hashCode()}", encrypt(username))
            .putString("pwd_${serverUrl.hashCode()}", encrypt(password))
            .apply()
    }

    /** 读取指定实例已保存的账号与密码。 */
    fun loadCredentials(serverUrl: String): Pair<String, String>? {
        val u = prefs.getString("usr_${serverUrl.hashCode()}", null)?.let(::decrypt) ?: return null
        val p = prefs.getString("pwd_${serverUrl.hashCode()}", null)?.let(::decrypt) ?: return null
        return u to p
    }

    /** 按规范化实例源加密保存 Cloudflare Access OAuth 会话 JSON。 */
    fun saveCloudflareSessionJson(originKey: String, payloadJson: String) {
        prefs.edit().putString("cf_oauth_${originKey.hashCode()}", encrypt(payloadJson)).apply()
    }

    /** 读取并解密指定实例源的 Cloudflare Access OAuth 会话 JSON。 */
    fun loadCloudflareSessionJson(originKey: String): String? {
        val raw = prefs.getString("cf_oauth_${originKey.hashCode()}", null) ?: return null
        return decrypt(raw)
    }

    /** 清除指定实例源的 Cloudflare Access OAuth 会话。 */
    fun clearCloudflareSession(originKey: String) {
        prefs.edit().remove("cf_oauth_${originKey.hashCode()}").apply()
    }

    /** 忘记指定实例的全部保存数据。 */
    fun forgetServer(serverUrl: String) {
        clearToken(serverUrl)
        val originKey = CloudflareAccessOAuthManager.normalizedOriginKey(serverUrl)
        if (!originKey.isNullOrBlank()) {
            clearCloudflareSession(originKey)
        }
        prefs.edit()
            .remove("usr_${serverUrl.hashCode()}")
            .remove("pwd_${serverUrl.hashCode()}")
            .apply()
        val remaining = loadServers().filterNot { it.url == serverUrl }
        saveServers(remaining)
        if (activeServerUrl() == serverUrl) {
            setActiveServerUrl(remaining.firstOrNull()?.url)
        }
    }

    /** 读取已保存服务列表（按最近使用倒序）。 */
    fun loadServers(): List<SavedServerEntry> {
        val raw = prefs.getString(KEY_SERVERS, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<SavedServerEntry>>(raw) }
            .getOrDefault(emptyList())
            .sortedByDescending { it.lastUsedEpochMs }
    }

    /** 新增或更新已保存的服务地址。 */
    fun upsertServer(entry: SavedServerEntry) {
        val updated = loadServers().filterNot { it.url == entry.url } + entry
        saveServers(updated)
    }

    private fun saveServers(list: List<SavedServerEntry>) {
        prefs.edit().putString(KEY_SERVERS, json.encodeToString(list)).apply()
    }

    fun activeServerUrl(): String? = prefs.getString(KEY_ACTIVE_SERVER, null)
    fun setActiveServerUrl(url: String?) {
        prefs.edit().apply {
            if (url == null) remove(KEY_ACTIVE_SERVER) else putString(KEY_ACTIVE_SERVER, url)
        }.apply()
    }

    var keepLogin: Boolean
        get() = prefs.getBoolean(KEY_KEEP_LOGIN, true)
        set(value) = prefs.edit().putBoolean(KEY_KEEP_LOGIN, value).apply()

    var rememberCredentials: Boolean
        get() = prefs.getBoolean(KEY_REMEMBER_CREDS, false)
        set(value) = prefs.edit().putBoolean(KEY_REMEMBER_CREDS, value).apply()

    var allowSelfSignedTls: Boolean
        get() = prefs.getBoolean(KEY_ALLOW_INSECURE_TLS, false)
        set(value) = prefs.edit().putBoolean(KEY_ALLOW_INSECURE_TLS, value).apply()
}
