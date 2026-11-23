package com.moviepilot.designsystem

import android.content.Context
import android.graphics.RuntimeShader
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.sin

/**
 * Android 13+（API 33+）AGSL RuntimeShader 3×3 呼吸流光网格着色器：
 * 100% 限定在当前主题 4 段同源色板内柔和流动，复刻 iOS 18+ MeshGradient 视觉通透感。
 */
private const val CINEMATIC_MESH_AGSL = """
uniform float2 uSize;
uniform float uPhase;
uniform float4 uC0;
uniform float4 uC1;
uniform float4 uC2;
uniform float4 uC3;

half4 main(float2 fragCoord) {
    float2 uv = fragCoord / max(uSize, float2(1.0, 1.0));
    float cx = 0.50 + 0.18 * sin(uPhase * 0.21 + 1.4);
    float cy = 0.50 + 0.17 * cos(uPhase * 0.19 + 0.3);
    float topX = 0.50 + 0.16 * sin(uPhase * 0.17);
    float botX = 0.50 + 0.16 * cos(uPhase * 0.23 + 1.1);

    float wTop = smoothstep(0.0, 1.0, clamp(uv.x + (topX - 0.5) * 0.45, 0.0, 1.0));
    float wMid = smoothstep(0.0, 1.0, clamp(uv.x + (cx - 0.5) * 0.55, 0.0, 1.0));
    float wBot = smoothstep(0.0, 1.0, clamp(uv.x + (botX - 0.5) * 0.45, 0.0, 1.0));

    float4 row0 = mix(uC0, uC1, wTop);
    float4 row1 = mix(uC1, uC2, wMid);
    float4 row2 = mix(uC2, uC3, wBot);

    float yBlend = clamp(uv.y + (cy - 0.5) * 0.16 * sin(uv.x * 3.14159), 0.0, 1.0);
    float4 col = yBlend < 0.5
        ? mix(row0, row1, smoothstep(0.0, 0.5, yBlend))
        : mix(row1, row2, smoothstep(0.5, 1.0, yBlend));
    return half4(col);
}
"""

/**
 * MoviePilot 连续流光背景组件：
 * - API 33+ 使用原生 GPU AGSL `RuntimeShader` 绘制 3×3 呼吸流光（限 15fps）；
 * - API 28–32 平滑回退端点漂移线性渐变；
 * - 严格监听省电模式、减弱动画与退后台生命周期，自动静止零耗电。
 */
@Composable
fun CinematicAmbientGradient(
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val store = LocalAppearanceStore.current
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    val isSystemStatic = remember(context, store.animateBackground) {
        if (!store.animateBackground) {
            true
        } else {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val powerSave = pm?.isPowerSaveMode == true
            val animScale = runCatching {
                Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
            }.getOrDefault(1f)
            powerSave || animScale <= 0f
        }
    }

    var phase by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(isSystemStatic, lifecycleOwner) {
        if (isSystemStatic) {
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

    val palette = colors.palette
    val c0 = palette.getOrElse(0) { colors.solidSurface }
    val c1 = palette.getOrElse(1) { c0 }
    val c2 = palette.getOrElse(2) { c1 }
    val c3 = palette.getOrElse(3) { c2 }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        val shader = remember { RuntimeShader(CINEMATIC_MESH_AGSL) }
        Canvas(modifier = modifier.fillMaxSize()) {
            shader.setFloatUniform("uSize", size.width, size.height)
            shader.setFloatUniform("uPhase", phase)
            shader.setFloatUniform("uC0", c0.red, c0.green, c0.blue, c0.alpha)
            shader.setFloatUniform("uC1", c1.red, c1.green, c1.blue, c1.alpha)
            shader.setFloatUniform("uC2", c2.red, c2.green, c2.blue, c2.alpha)
            shader.setFloatUniform("uC3", c3.red, c3.green, c3.blue, c3.alpha)
            drawRect(brush = ShaderBrush(shader))
        }
    } else {
        Canvas(modifier = modifier.fillMaxSize()) {
            val sx = (0.08f + 0.12f * sin(phase * 0.19f)) * size.width
            val sy = (0.06f + 0.08f * cos(phase * 0.15f)) * size.height
            val ex = (0.92f + 0.08f * cos(phase * 0.17f + 1.0f)) * size.width
            val ey = (0.94f + 0.06f * sin(phase * 0.21f + 0.8f)) * size.height
            drawRect(
                brush = Brush.linearGradient(
                    colors = listOf(c0, c1, c2, c3),
                    start = Offset(sx, sy),
                    end = Offset(ex, ey),
                ),
            )
        }
    }
}
