package com.moviepilot.feature.auth

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeBrandDrawable
import com.moviepilot.rustbridge.LoginOutcome
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.SavedServerEntry
import kotlinx.coroutines.launch

/**
 * 连接服务页面（1:1 对标 iOS 黄金截图 `native-v2-01-connection.jpg`）：
 * 顶部品牌图标紫玫光晕、服务地址输入卡片、快捷协议前缀胶囊、主连接按钮与已保存服务列表。
 */
@Composable
fun ServerConnectionScreen(
    savedServers: List<SavedServerEntry>,
    onConnect: (String) -> Result<String>,
    onSelectSaved: (SavedServerEntry) -> Unit,
    onDeleteSaved: (String) -> Unit,
    allowSelfSignedTls: Boolean = false,
    onToggleSelfSignedTls: (Boolean) -> Unit = {},
    currentServerUrl: String? = null,
    onBack: (() -> Unit)? = null,
    repository: MoviePilotRepository? = null,
) {
    val colors = LocalMoviePilotColors.current
    val cfg = LocalConfiguration.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isShortWideLandscape = cfg.screenWidthDp >= 640 && cfg.screenHeightDp < 520
    var address by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var cfAuthBusy by remember { mutableStateOf(false) }
    var cfStatusNotice by remember { mutableStateOf<String?>(null) }
    var cfRevision by remember { mutableStateOf(0) }

    @Composable
    fun ServerFormColumn() {
        Column(
            modifier = Modifier.widthIn(max = 460.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CinematicPanel(padding = 16.dp) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    ) {
                        Icon(Icons.Outlined.Link, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                        Box(modifier = Modifier.weight(1f)) {
                            if (address.isEmpty()) {
                                Text("MoviePilot 服务地址", color = colors.textMuted, fontSize = 16.sp)
                            }
                            BasicTextField(
                                value = address,
                                onValueChange = { address = it; errorMessage = null },
                                singleLine = true,
                                textStyle = TextStyle(color = colors.textPrimary, fontSize = 16.sp),
                                cursorBrush = SolidColor(colors.accent),
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(vertical = 12.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("快捷前缀", color = colors.textMuted, fontSize = 12.sp)
                        NativeAdaptivePill(
                            title = "https://",
                            selected = address.startsWith("https://"),
                            onClick = {
                                address = "https://" + address.removePrefix("https://").removePrefix("http://")
                            },
                        )
                        NativeAdaptivePill(
                            title = "http://",
                            selected = address.startsWith("http://"),
                            onClick = {
                                address = "http://" + address.removePrefix("https://").removePrefix("http://")
                            },
                        )
                    }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(vertical = 10.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("允许自签名 HTTPS 证书", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                            Text("内网 NAS 或私有证书环境可开启", color = colors.textMuted, fontSize = 11.5.sp)
                        }
                        Switch(
                            checked = allowSelfSignedTls,
                            onCheckedChange = onToggleSelfSignedTls,
                            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                        )
                    }
                }
            }

            Spacer(Modifier.height(10.dp))
            Text(
                text = errorMessage ?: "支持 HTTPS、局域网地址和部署子路径。",
                color = if (errorMessage != null) colors.danger else colors.textMuted,
                fontSize = 13.sp,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp),
            )

            Spacer(Modifier.height(if (isShortWideLandscape) 14.dp else 20.dp))
            val canConnect = address.trim().isNotEmpty()
            GlassPrimaryPillButton(
                title = "连接",
                enabled = canConnect,
                onClick = {
                    onConnect(address).onFailure { errorMessage = it.message ?: "服务地址无效" }
                },
            )

            if (repository != null && canConnect) {
                val hasCf = remember(address, cfRevision) { repository.cloudflareOAuth.hasSession(address) }
                Spacer(Modifier.height(12.dp))
                CloudflareAccessCard(
                    hasSession = hasCf,
                    busy = cfAuthBusy,
                    notice = cfStatusNotice,
                    onAuthenticate = {
                        scope.launch {
                            cfAuthBusy = true
                            cfStatusNotice = null
                            errorMessage = null
                            val res = repository.cloudflareOAuth.authenticate(address) { authUrl ->
                                val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(authUrl))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                context.startActivity(browserIntent)
                            }
                            cfAuthBusy = false
                            res.fold(
                                onSuccess = {
                                    cfRevision++
                                    cfStatusNotice = "Cloudflare Access 认证成功"
                                    onConnect(address).onFailure { errorMessage = it.message ?: "服务地址无效" }
                                },
                                onFailure = { err ->
                                    errorMessage = err.message ?: "Cloudflare Access 认证失败"
                                },
                            )
                        }
                    },
                    onClear = {
                        repository.cloudflareOAuth.clearSession(address)
                        cfRevision++
                        cfStatusNotice = "已清除当前服务的 Cloudflare Access 授权"
                    },
                )
            }

            if (savedServers.isNotEmpty()) {
                Spacer(Modifier.height(if (isShortWideLandscape) 20.dp else 32.dp))
                Text(
                    text = "已保存的服务",
                    color = colors.textSecondary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.fillMaxWidth().padding(start = 6.dp, bottom = 10.dp),
                )
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    savedServers.forEach { entry ->
                        CinematicPanel(
                            padding = 14.dp,
                            modifier = Modifier.clickable { onSelectSaved(entry) },
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(40.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(colors.accent.copy(alpha = 0.22f)),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Outlined.Dns, contentDescription = null, tint = colors.accent, modifier = Modifier.size(20.dp))
                                }
                                Spacer(Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        Text(entry.name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                        if (!currentServerUrl.isNullOrBlank() && entry.url.trimEnd('/').equals(currentServerUrl.trimEnd('/'), ignoreCase = true)) {
                                            Box(
                                                modifier = Modifier
                                                    .clip(CircleShape)
                                                    .background(colors.success.copy(alpha = 0.18f))
                                                    .padding(horizontal = 7.dp, vertical = 2.dp),
                                            ) {
                                                Text("当前", color = colors.success, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                            }
                                        }
                                    }
                                    Text(entry.url, color = colors.textMuted, fontSize = 12.sp)
                                }
                                IconButton(
                                    onClick = { onDeleteSaved(entry.url) },
                                    modifier = Modifier.size(34.dp),
                                ) {
                                    Icon(
                                        Icons.Outlined.DeleteOutline,
                                        contentDescription = "删除已保存服务",
                                        tint = colors.textMuted,
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted)
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(if (isShortWideLandscape) 20.dp else 40.dp))
        }
    }

    val safeInsets = WindowInsets.systemBars.union(WindowInsets.displayCutout)
    if (isShortWideLandscape) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(safeInsets)
                .imePadding()
                .padding(horizontal = 24.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (onBack != null) {
                    CinematicCircleButton(
                        icon = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "返回",
                        onClick = onBack,
                        size = 38.dp,
                    )
                } else {
                    Spacer(Modifier.size(38.dp))
                }
                Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text("连接服务", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
                CinematicCircleButton(
                    icon = Icons.Outlined.Language,
                    contentDescription = "语言",
                    onClick = {},
                    size = 38.dp,
                )
            }
            Row(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(
                    modifier = Modifier.weight(0.42f).fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    BrandHeaderBlock(compact = true)
                }
                Box(
                    modifier = Modifier
                        .weight(0.58f)
                        .fillMaxHeight()
                        .verticalScroll(rememberScrollState()),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    ServerFormColumn()
                }
            }
        }
    } else {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(safeInsets)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (onBack != null) {
                    CinematicCircleButton(
                        icon = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "返回",
                        onClick = onBack,
                    )
                } else {
                    Spacer(Modifier.size(44.dp))
                }
                Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text("连接服务", color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                }
                CinematicCircleButton(
                    icon = Icons.Outlined.Language,
                    contentDescription = "语言",
                    onClick = {},
                )
            }

            Spacer(Modifier.height(28.dp))
            BrandHeaderBlock(compact = false)
            Spacer(Modifier.height(28.dp))

            ServerFormColumn()
        }
    }
}

/**
 * 登录页面（1:1 对标 iOS 黄金截图 `native-v2-02-login.jpg`，短宽横屏自动切换左品牌右表单双栏）：
 * 支持账号密码、OTP 二次验证、保持登录、记住账号密码（Android Keystore）与 Passkey 入口。
 */
@Composable
fun LoginScreen(
    serverUrl: String,
    initialNotice: String?,
    repository: MoviePilotRepository,
    onSwitchServer: () -> Unit,
    onLoginSuccess: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val cfg = LocalConfiguration.current
    val context = LocalContext.current
    val isShortWideLandscape = cfg.screenWidthDp >= 640 && cfg.screenHeightDp < 520
    val scope = rememberCoroutineScope()
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var otpCode by remember { mutableStateOf("") }
    var showPassword by remember { mutableStateOf(false) }
    var showOtpField by remember { mutableStateOf(false) }
    var keepLogin by remember { mutableStateOf(repository.secretStore.keepLogin) }
    var rememberCreds by remember { mutableStateOf(repository.secretStore.rememberCredentials) }
    var loading by remember { mutableStateOf(false) }
    var passkeySupported by remember(serverUrl) { mutableStateOf(false) }
    var passkeyLoading by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf(initialNotice) }
    var cfAuthBusy by remember { mutableStateOf(false) }
    var cfRevision by remember { mutableStateOf(0) }
    var cfChallengeDetected by remember(serverUrl) { mutableStateOf(false) }

    LaunchedEffect(serverUrl) {
        repository.secretStore.loadCredentials(serverUrl)?.let { (u, p) ->
            username = u
            password = p
        }
    }

    LaunchedEffect(serverUrl, cfRevision) {
        passkeySupported = repository.probePasskeyEnabled(serverUrl)
    }

    @Composable
    fun ServerStatusChip() {
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .background(colors.chipFill)
                .border(0.7.dp, colors.chipBorder, CircleShape)
                .clickable(onClick = onSwitchServer)
                .padding(horizontal = 14.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(colors.success))
            Text(serverUrl, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1)
            Icon(Icons.Outlined.Refresh, contentDescription = "切换实例", tint = colors.textMuted, modifier = Modifier.size(14.dp))
        }
    }

    @Composable
    fun LoginFormColumn() {
        Column(
            modifier = Modifier.widthIn(max = 460.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CinematicPanel(padding = 16.dp) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    ) {
                        Icon(Icons.Outlined.Person, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                        Box(modifier = Modifier.weight(1f)) {
                            if (username.isEmpty()) Text("用户名", color = colors.textMuted, fontSize = 16.sp)
                            BasicTextField(
                                value = username,
                                onValueChange = { username = it; notice = null },
                                singleLine = true,
                                textStyle = TextStyle(color = colors.textPrimary, fontSize = 16.sp),
                                cursorBrush = SolidColor(colors.accent),
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(vertical = 10.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                    ) {
                        Icon(Icons.Outlined.Lock, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                        Box(modifier = Modifier.weight(1f)) {
                            if (password.isEmpty()) Text("密码", color = colors.textMuted, fontSize = 16.sp)
                            BasicTextField(
                                value = password,
                                onValueChange = { password = it; notice = null },
                                singleLine = true,
                                visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                                textStyle = TextStyle(color = colors.textPrimary, fontSize = 16.sp),
                                cursorBrush = SolidColor(colors.accent),
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        IconButton(onClick = { showPassword = !showPassword }, modifier = Modifier.size(32.dp)) {
                            Icon(
                                if (showPassword) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                                contentDescription = "显示密码",
                                tint = colors.textSecondary,
                            )
                        }
                    }

                    if (showOtpField) {
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(vertical = 10.dp))
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        ) {
                            Icon(Icons.Outlined.Key, contentDescription = null, tint = colors.accent, modifier = Modifier.size(20.dp))
                            Box(modifier = Modifier.weight(1f)) {
                                if (otpCode.isEmpty()) Text("6 位动态验证码 (OTP)", color = colors.textMuted, fontSize = 15.sp)
                                BasicTextField(
                                    value = otpCode,
                                    onValueChange = { otpCode = it },
                                    singleLine = true,
                                    textStyle = TextStyle(color = colors.textPrimary, fontSize = 16.sp),
                                    cursorBrush = SolidColor(colors.accent),
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(14.dp))

            CinematicPanel(padding = 14.dp) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("保持登录", color = colors.textPrimary, fontSize = 15.sp)
                        Switch(
                            checked = keepLogin,
                            onCheckedChange = { keepLogin = it; repository.secretStore.keepLogin = it },
                            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                        )
                    }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(vertical = 6.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("记住账号密码", color = colors.textPrimary, fontSize = 15.sp)
                        Switch(
                            checked = rememberCreds,
                            onCheckedChange = { rememberCreds = it; repository.secretStore.rememberCredentials = it },
                            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                        )
                    }
                }
            }

            Spacer(Modifier.height(10.dp))
            Text(
                text = notice ?: "密码仅在本机安全保存，验证码不会保存。",
                color = if (notice != null) colors.warning else colors.textMuted,
                fontSize = 12.sp,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp),
            )

            Spacer(Modifier.height(if (isShortWideLandscape) 14.dp else 18.dp))

            val submitPasswordLogin: () -> Unit = {
                scope.launch {
                    loading = true
                    notice = null
                    when (val res = repository.login(serverUrl, username, password, otpCode)) {
                        is LoginOutcome.Success -> onLoginSuccess()
                        is LoginOutcome.OtpRequired -> {
                            showOtpField = true
                            notice = res.message
                        }
                        is LoginOutcome.Failure -> {
                            if (!res.canceled) {
                                if (res.message.contains("Cloudflare Access")) cfChallengeDetected = true
                                notice = res.message
                            }
                        }
                    }
                    loading = false
                }
            }

            val submitPasskeyLogin: () -> Unit = {
                scope.launch {
                    passkeyLoading = true
                    notice = null
                    val res = repository.loginWithPasskey(serverUrl, username) { authUrl ->
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(authUrl))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(browserIntent)
                    }
                    passkeyLoading = false
                    when (res) {
                        is LoginOutcome.Success -> onLoginSuccess()
                        is LoginOutcome.OtpRequired -> {
                            showOtpField = true
                            notice = res.message
                        }
                        is LoginOutcome.Failure -> {
                            if (!res.canceled) {
                                if (res.message.contains("Cloudflare Access")) cfChallengeDetected = true
                                notice = res.message
                            }
                        }
                    }
                }
            }

            val anyBusy = loading || passkeyLoading || cfAuthBusy
            if (isShortWideLandscape && passkeySupported) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    GlassPrimaryPillButton(
                        title = if (loading) "正在登录..." else "登录",
                        enabled = !anyBusy && username.isNotBlank() && password.isNotBlank(),
                        loading = loading,
                        modifier = Modifier.weight(1f),
                        onClick = submitPasswordLogin,
                    )
                    GlassPasskeyPillButton(
                        title = "使用通行密钥登录",
                        enabled = !anyBusy,
                        loading = passkeyLoading,
                        modifier = Modifier.weight(1f),
                        onClick = submitPasskeyLogin,
                    )
                }
            } else {
                GlassPrimaryPillButton(
                    title = if (loading) "正在登录..." else "登录",
                    enabled = !anyBusy && username.isNotBlank() && password.isNotBlank(),
                    loading = loading,
                    onClick = submitPasswordLogin,
                )
                if (passkeySupported) {
                    Spacer(Modifier.height(10.dp))
                    GlassPasskeyPillButton(
                        title = "使用通行密钥登录",
                        enabled = !anyBusy,
                        loading = passkeyLoading,
                        onClick = submitPasskeyLogin,
                    )
                }
            }

            val hasCf = remember(serverUrl, cfRevision) { repository.cloudflareOAuth.hasSession(serverUrl) }
            val startCfAuth: () -> Unit = {
                scope.launch {
                    cfAuthBusy = true
                    notice = null
                    val res = repository.cloudflareOAuth.authenticate(serverUrl) { authUrl ->
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(authUrl))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(browserIntent)
                    }
                    cfAuthBusy = false
                    res.fold(
                        onSuccess = {
                            cfChallengeDetected = false
                            cfRevision++
                            notice = "Cloudflare Access 认证成功，请继续登录"
                        },
                        onFailure = { err ->
                            notice = err.message ?: "Cloudflare Access 认证失败"
                        },
                    )
                }
            }

            Spacer(Modifier.height(12.dp))
            if (!hasCf && !cfChallengeDetected && !cfAuthBusy) {
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(colors.chipFill)
                        .border(0.7.dp, colors.chipBorder, CircleShape)
                        .clickable(enabled = !anyBusy, onClick = startCfAuth)
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        Icons.Outlined.Key,
                        contentDescription = null,
                        tint = colors.accent,
                        modifier = Modifier.size(15.dp),
                    )
                    Text(
                        text = "通过 Cloudflare Access 认证",
                        color = colors.textSecondary,
                        fontSize = 12.5.sp,
                        fontWeight = FontWeight.Medium,
                    )
                    Icon(
                        Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                        contentDescription = null,
                        tint = colors.textMuted,
                        modifier = Modifier.size(15.dp),
                    )
                }
            } else {
                CloudflareAccessCard(
                    hasSession = hasCf,
                    busy = cfAuthBusy,
                    notice = null,
                    onAuthenticate = startCfAuth,
                    onClear = {
                        repository.cloudflareOAuth.clearSession(serverUrl)
                        cfRevision++
                        notice = "已清除当前服务的 Cloudflare Access 授权"
                    },
                )
            }
            Spacer(Modifier.height(if (isShortWideLandscape) 20.dp else 36.dp))
        }
    }

    val safeInsets = WindowInsets.systemBars.union(WindowInsets.displayCutout)
    if (isShortWideLandscape) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(safeInsets)
                .imePadding()
                .padding(horizontal = 24.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CinematicCircleButton(
                    icon = Icons.Outlined.Dns,
                    contentDescription = "切换服务",
                    onClick = onSwitchServer,
                    size = 38.dp,
                )
                Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text("登录", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
                CinematicCircleButton(
                    icon = Icons.Outlined.Language,
                    contentDescription = "语言",
                    onClick = {},
                    size = 38.dp,
                )
            }
            Row(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(
                    modifier = Modifier.weight(0.42f).fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    BrandHeaderBlock(compact = true)
                    Spacer(Modifier.height(10.dp))
                    ServerStatusChip()
                }
                Box(
                    modifier = Modifier
                        .weight(0.58f)
                        .fillMaxHeight()
                        .verticalScroll(rememberScrollState()),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    LoginFormColumn()
                }
            }
        }
    } else {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(safeInsets)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CinematicCircleButton(
                    icon = Icons.Outlined.Dns,
                    contentDescription = "切换服务",
                    onClick = onSwitchServer,
                )
                Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text("登录", color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                }
                CinematicCircleButton(
                    icon = Icons.Outlined.Language,
                    contentDescription = "语言",
                    onClick = {},
                )
            }

            Spacer(Modifier.height(18.dp))
            BrandHeaderBlock(compact = false)
            Spacer(Modifier.height(12.dp))
            ServerStatusChip()
            Spacer(Modifier.height(22.dp))
            LoginFormColumn()
        }
    }
}

@Composable
private fun CloudflareAccessCard(
    hasSession: Boolean,
    busy: Boolean,
    notice: String?,
    onAuthenticate: () -> Unit,
    onClear: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(padding = 14.dp) {
        Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = !busy, onClick = onAuthenticate),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(
                    Icons.Outlined.Key,
                    contentDescription = null,
                    tint = if (hasSession) colors.success else colors.accent,
                    modifier = Modifier.size(19.dp),
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = when {
                            busy -> "正在进行 Cloudflare Access 认证..."
                            hasSession -> "重新进行 Cloudflare Access 认证"
                            else -> "通过 Cloudflare Access 认证"
                        },
                        color = colors.textPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        text = notice ?: if (hasSession) {
                            "已获取同源网关凭据，不影响 MoviePilot 账号令牌"
                        } else {
                            "若服务部署在 Cloudflare Access 后可先完成 OAuth 授权"
                        },
                        color = if (hasSession) colors.success else colors.textMuted,
                        fontSize = 11.5.sp,
                    )
                }
                if (busy) {
                    CircularProgressIndicator(
                        color = colors.accent,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(18.dp),
                    )
                } else {
                    Icon(
                        Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                        contentDescription = null,
                        tint = colors.textMuted,
                    )
                }
            }
            if (hasSession && !busy) {
                HorizontalDivider(color = colors.divider)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onClear)
                        .padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Outlined.DeleteOutline,
                        contentDescription = null,
                        tint = colors.danger,
                        modifier = Modifier.size(16.dp),
                    )
                    Text(
                        text = "清除 Cloudflare Access 授权",
                        color = colors.danger,
                        fontSize = 13.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun BrandHeaderBlock(compact: Boolean = false) {
    val colors = LocalMoviePilotColors.current
    val outerSz = if (compact) 74.dp else 92.dp
    val innerSz = if (compact) 68.dp else 84.dp
    Box(
        modifier = Modifier
            .size(outerSz)
            .shadow(if (compact) 18.dp else 24.dp, RoundedCornerShape(if (compact) 20.dp else 24.dp), ambientColor = colors.accent, spotColor = colors.accent),
        contentAlignment = Alignment.Center,
    ) {
        NativeBrandDrawable(drawableName = "brandmark", size = innerSz, cornerRadius = if (compact) 18.dp else 22.dp)
    }
    Spacer(Modifier.height(if (compact) 10.dp else 16.dp))
    Text(
        text = "MoviePilot",
        color = colors.textPrimary,
        fontSize = if (compact) 23.sp else 28.sp,
        fontWeight = FontWeight.Bold,
    )
    Spacer(Modifier.height(4.dp))
    Text(
        text = "你的媒体世界，随时连接。",
        color = colors.textSecondary,
        fontSize = if (compact) 13.sp else 14.sp,
    )
}

@Composable
private fun GlassPrimaryPillButton(
    title: String,
    enabled: Boolean,
    loading: Boolean = false,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val bgBrush = if (enabled) {
        Brush.horizontalGradient(
            listOf(
                colors.accent.copy(alpha = 0.85f),
                Color(0xFF7B5CE0).copy(alpha = 0.90f),
            ),
        )
    } else {
        Brush.horizontalGradient(
            listOf(
                Color.White.copy(alpha = if (colors.isDark) 0.10f else 0.55f),
                Color.White.copy(alpha = if (colors.isDark) 0.08f else 0.45f),
            ),
        )
    }
    Box(
        modifier = modifier
            .height(54.dp)
            .clip(CircleShape)
            .background(bgBrush)
            .border(0.8.dp, Color.White.copy(alpha = if (enabled) 0.35f else 0.16f), CircleShape)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(horizontal = 14.dp),
        ) {
            if (loading) {
                CircularProgressIndicator(
                    color = Color.White,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
            }
            Text(
                text = title,
                color = if (enabled) Color.White else colors.textMuted,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
            if (!loading) {
                Icon(
                    Icons.AutoMirrored.Rounded.ArrowForward,
                    contentDescription = null,
                    tint = if (enabled) Color.White else colors.textMuted,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

@Composable
private fun GlassPasskeyPillButton(
    title: String,
    enabled: Boolean,
    loading: Boolean = false,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val fillAlpha = if (enabled) {
        if (colors.isDark) 0.15f else 0.10f
    } else {
        if (colors.isDark) 0.07f else 0.05f
    }
    val borderAlpha = if (enabled) {
        if (colors.isDark) 0.42f else 0.34f
    } else {
        if (colors.isDark) 0.20f else 0.16f
    }
    Box(
        modifier = modifier
            .height(50.dp)
            .clip(CircleShape)
            .background(colors.accent.copy(alpha = fillAlpha))
            .border(0.85.dp, colors.accent.copy(alpha = borderAlpha), CircleShape)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(horizontal = 14.dp),
        ) {
            if (loading) {
                CircularProgressIndicator(
                    color = colors.accent,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
            } else {
                Icon(
                    Icons.Outlined.Key,
                    contentDescription = null,
                    tint = if (enabled) colors.accent else colors.textMuted,
                    modifier = Modifier.size(18.dp),
                )
            }
            Text(
                text = title,
                color = if (enabled) colors.textPrimary else colors.textMuted,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
        }
    }
}
