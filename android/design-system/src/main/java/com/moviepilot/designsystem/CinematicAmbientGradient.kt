package com.moviepilot.designsystem

import android.content.Context
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.sin

/**
 * Android Material Design 3 沉稳中性画布背景：
 * - 默认采用纯正 Material 3 `colorScheme.background` 实色低眩光底面（深色 `#121116` / 浅色 `#FCF8FF`），
 *   绝不以高饱和紫色霓虹雾背景干扰影视海报与数据层级；
 * - 若用户在「主题与外观」中主动开启柔光氛围，则在顶部叠加极克制（~6%）的主题种子色径向光晕。
 */
@Composable
fun CinematicAmbientGradient(
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val store = LocalAppearanceStore.current
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val bgColor = MaterialTheme.colorScheme.background

    val animateGlow = remember(context, store.animateBackground) {
        if (!store.animateBackground) {
            false
        } else {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val powerSave = pm?.isPowerSaveMode == true
            val animScale = runCatching {
                Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
            }.getOrDefault(1f)
            !powerSave && animScale > 0f
        }
    }

    var phase by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(animateGlow, lifecycleOwner) {
        if (!animateGlow) {
            phase = 0f
            return@LaunchedEffect
        }
        val frameMs = (1000L / GeneratedDesignTokens.AMBIENT_FPS.coerceAtLeast(1))
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                phase += frameMs / 1000f
                delay(frameMs)
            }
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(bgColor),
    ) {
        if (animateGlow) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val cx = size.width * (0.5f + 0.14f * sin(phase * 0.25f))
                val cy = size.height * (0.14f + 0.05f * cos(phase * 0.18f))
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            colors.accent.copy(alpha = if (colors.isDark) 0.11f else 0.08f),
                            Color.Transparent,
                        ),
                        center = Offset(cx, cy),
                        radius = size.maxDimension * 0.65f,
                    ),
                )
            }
        }
    }
}
