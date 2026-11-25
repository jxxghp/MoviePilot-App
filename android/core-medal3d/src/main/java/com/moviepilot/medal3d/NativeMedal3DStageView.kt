package com.moviepilot.medal3d

import android.content.Context
import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.TextureView
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tanh

/**
 * 原生 OpenGL ES 3D 社区勋章实时物理互动舞台（1:1 对标 iOS SceneKit `NativeMedal3DStageView`）：
 * - 基于透明 `TextureView` + 独立 EGL 60fps 渲染线程，无缝合成于 Compose 图层中（背景氛围光在后，菜单/Sheet 在前）；
 * - 真实 `.outline.json` 多边形挤出金属厚度侧壁（`width=2.4, thickness=0.11`）+ 唇缘实采金属色；
 * - 保留非圆形真实雕刻剪影（`alpha < 0.45` discard）+ 高度图法线贴图 PBR 金属光泽 + 0.52 自发光锁色；
 * - 支持主创勋章外圈机械擒纵 6° 步进旋转（含过冲回弹）；
 * - 背面直接渲染真实 `-back.webp` 铭牌三遍凹雕铭文；
 * - 完整复刻 iOS 物理手感：tanh 限幅拖动、指数回弹、轻点 180° 丝滑翻面与触觉反馈、1.1s 入场缓动、2.5s 闲置微摆。
 */
@Composable
fun NativeMedal3DStageView(
    record: CommunityMedalRecord,
    login: String?,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val view = LocalView.current
    val physics = remember { Medal3DPhysicsState() }
    var activeBundle by remember { mutableStateOf<CommunityMedalRenderBundle?>(null) }

    LaunchedEffect(record.key, record.normalizedTier, login, record.at) {
        physics.resetForNewMedal()
        val built = withContext(Dispatchers.Default) {
            CommunityMedalAssetEngine.buildRenderBundle(context, record, login)
        }
        activeBundle = built
        physics.spinConfig = built?.spinConfig
    }

    val glHost = remember { Medal3DTextureHost(context, physics) }
    LaunchedEffect(activeBundle) {
        glHost.setBundle(activeBundle)
    }
    DisposableEffect(glHost) {
        onDispose { glHost.release() }
    }

    Box(
        modifier = modifier
            .pointerInput(record.key) {
                detectTapGestures(
                    onTap = {
                        physics.flip()
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    },
                )
            }
            .pointerInput(record.key) {
                detectDragGestures(
                    onDragStart = { physics.onDragBegan() },
                    onDragEnd = { physics.onDragEnded() },
                    onDragCancel = { physics.onDragEnded() },
                ) { change, drag ->
                    change.consume()
                    physics.onDragMoved(drag.x / density, drag.y / density)
                }
            },
    ) {
        AndroidView(
            factory = { glHost.textureView },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/** 线程安全 3D 勋章物理状态机（常量与公式 1:1 复刻 `NativeCommunityMedal3D.PhysicsBox`）。 */
private class Medal3DPhysicsState {
    private val lock = Any()
    private val yawLimit = 0.65
    private val pitchLimit = 0.45
    private val entranceDuration = 1.1

    private var isDragging = false
    private var dragYaw = 0.0
    private var dragPitch = 0.0
    private var targetFaceAngle = 0.0
    private var faceAngle = 0.0
    private var entranceElapsed = 0.0
    private var lastFrameSec = 0.0
    private var lastInputSec = 0.0
    private var idleStrength = 0.0
    private var spinElapsed = 0.0

    @Volatile
    var spinConfig: CommunityMedalOutline.SpinConfig? = null

    data class FramePose(
        val yawRad: Float,
        val pitchRad: Float,
        val scale: Float,
        val outerSpinRad: Float,
    )

    private fun nowSec(): Double = SystemClock.uptimeMillis() / 1000.0

    fun resetForNewMedal() = synchronized(lock) {
        isDragging = false
        dragYaw = 0.0
        dragPitch = 0.0
        targetFaceAngle = 0.0
        faceAngle = 0.0
        entranceElapsed = 0.0
        idleStrength = 0.0
        spinElapsed = 0.0
        lastInputSec = nowSec()
    }

    fun onDragBegan() = synchronized(lock) {
        isDragging = true
        lastInputSec = nowSec()
    }

    fun onDragMoved(dxDp: Float, dyDp: Float) = synchronized(lock) {
        isDragging = true
        dragYaw += dxDp * 0.012
        dragPitch += dyDp * 0.009
        lastInputSec = nowSec()
    }

    fun onDragEnded() = synchronized(lock) {
        isDragging = false
        lastInputSec = nowSec()
    }

    fun flip() = synchronized(lock) {
        targetFaceAngle += PI
        lastInputSec = nowSec()
    }

    fun step(): FramePose = synchronized(lock) {
        val now = nowSec()
        val dt = if (lastFrameSec > 0.0) (now - lastFrameSec).coerceIn(0.0, 0.05) else 1.0 / 60.0
        lastFrameSec = now

        if (!isDragging) {
            val decay = exp(-dt * 5.0)
            dragYaw *= decay
            dragPitch *= decay
        }

        faceAngle += (targetFaceAngle - faceAngle) * min(1.0, dt * 9.0)

        var entranceScale = 1.0
        var entranceYaw = 0.0
        if (entranceElapsed < entranceDuration) {
            entranceElapsed = min(entranceDuration, entranceElapsed + dt)
            val t = entranceElapsed / entranceDuration
            val ease = 1.0 - (1.0 - t).pow(3.0)
            entranceScale = 0.82 + 0.18 * ease
            entranceYaw = -0.7 * (1.0 - ease)
        }

        val allowIdle = !isDragging && (now - lastInputSec > 2.5)
        idleStrength = if (allowIdle) min(1.0, idleStrength + dt * 1.5) else max(0.0, idleStrength - dt * 3.0)

        val clampedYaw = yawLimit * tanh(dragYaw / yawLimit)
        val clampedPitch = pitchLimit * tanh(dragPitch / pitchLimit)
        val idleYaw = idleStrength * sin(now * 0.45) * 0.15
        val idlePitch = idleStrength * sin(now * 0.30) * 0.06

        val spin = spinConfig
        val spinAngle = if (spin != null) {
            spinElapsed += dt
            computeSpinAngle(spinElapsed, spin)
        } else {
            0.0
        }

        FramePose(
            yawRad = (clampedYaw + idleYaw + entranceYaw + faceAngle).toFloat(),
            pitchRad = (clampedPitch + idlePitch).toFloat(),
            scale = entranceScale.toFloat(),
            outerSpinRad = (-spinAngle).toFloat(),
        )
    }

    private fun computeSpinAngle(elapsed: Double, spin: CommunityMedalOutline.SpinConfig): Double {
        if (spin.mode == "continuous") {
            val period = max(spin.period ?: 180.0, 1.0)
            return (elapsed / period) * PI * 2.0
        }
        val stepDeg = spin.step ?: 6.0
        val interval = max(spin.interval ?: 2.0, 0.4)
        val tickDuration = 0.35
        val overshoot = 0.4 / max(stepDeg, 1.0)
        val stepIndex = floor(elapsed / interval)
        val local = elapsed - stepIndex * interval
        val progress = if (local >= tickDuration) {
            1.0
        } else {
            val u = local / tickDuration
            if (u < 0.7) {
                val p = u / 0.7
                val quad = if (p < 0.5) 2 * p * p else 1 - (-2 * p + 2).pow(2.0) / 2
                quad * (1.0 + overshoot)
            } else {
                val p = (u - 0.7) / 0.3
                val quadOut = 1 - (1 - p).pow(2.0)
                (1.0 + overshoot) - overshoot * quadOut
            }
        }
        return (stepIndex + progress) * stepDeg * PI / 180.0
    }
}

/** 透明 TextureView + EGL14/OpenGL ES 2.0 渲染宿主（兼容所有真机与模拟器 Vulkan/Metal 驱动）。 */
private class Medal3DTextureHost(
    context: Context,
    private val physics: Medal3DPhysicsState,
) : TextureView.SurfaceTextureListener {
    val textureView = TextureView(context).apply {
        isOpaque = false
        surfaceTextureListener = this@Medal3DTextureHost
    }

    private val bundleLock = Any()
    @Volatile
    private var pendingBundle: CommunityMedalRenderBundle? = null
    @Volatile
    private var bundleDirty = false
    private var renderThread: RenderThread? = null

    fun setBundle(bundle: CommunityMedalRenderBundle?) {
        synchronized(bundleLock) {
            pendingBundle = bundle
            bundleDirty = true
        }
    }

    fun release() {
        renderThread?.stopAndJoin()
        renderThread = null
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        release()
        renderThread = RenderThread(surface, width, height).also { it.start() }
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
        renderThread?.resize(width, height)
    }

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        release()
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

    private inner class RenderThread(
        private val surfaceTexture: SurfaceTexture,
        @Volatile private var viewportW: Int,
        @Volatile private var viewportH: Int,
    ) : Thread("Medal3D-GL") {
        @Volatile
        private var running = true
        @Volatile
        private var sizeChanged = true

        private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
        private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
        private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

        private var reliefProgram = 0
        private var rimProgram = 0
        private lateinit var quadBuffer: FloatBuffer
        private var rimBuffer: FloatBuffer? = null
        private var rimVertexCount = 0

        private var texFrontDiffuse = 0
        private var texFrontNormal = 0
        private var texFrontMetal = 0
        private var texOuterDiffuse = 0
        private var texOuterNormal = 0
        private var texOuterMetal = 0
        private var texBackDiffuse = 0
        private var texBackNormal = 0
        private var texBackMetal = 0
        private var texFlatNormal = 0
        private var texDefaultMetal = 0

        private var activeBundle: CommunityMedalRenderBundle? = null

        fun resize(w: Int, h: Int) {
            viewportW = w
            viewportH = h
            sizeChanged = true
        }

        fun stopAndJoin() {
            running = false
            runCatching { join(800) }
        }

        override fun run() {
            if (!initEgl()) return
            try {
                initGlResources()
                val proj = FloatArray(16)
                val view = FloatArray(16)
                val model = FloatArray(16)
                val partModel = FloatArray(16)
                val mvp = FloatArray(16)

                Matrix.setLookAtM(view, 0, 0f, 0f, 5.65f, 0f, 0f, 0f, 0f, 1f, 0f)

                while (running) {
                    val frameStart = SystemClock.uptimeMillis()
                    if (sizeChanged && viewportW > 0 && viewportH > 0) {
                        GLES20.glViewport(0, 0, viewportW, viewportH)
                        val aspect = viewportW.toFloat() / viewportH.toFloat()
                        Matrix.perspectiveM(proj, 0, 28f, aspect, 0.5f, 30f)
                        sizeChanged = false
                    }

                    if (bundleDirty) {
                        val b = synchronized(bundleLock) {
                            bundleDirty = false
                            pendingBundle
                        }
                        uploadBundle(b)
                    }

                    GLES20.glClearColor(0f, 0f, 0f, 0f)
                    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

                    val bundle = activeBundle
                    if (bundle != null) {
                        val pose = physics.step()
                        val thickness = 0.11f
                        val halfT = thickness * 0.5f

                        Matrix.setIdentityM(model, 0)
                        Matrix.scaleM(model, 0, pose.scale, pose.scale, pose.scale)
                        Matrix.rotateM(model, 0, Math.toDegrees(pose.pitchRad.toDouble()).toFloat(), 1f, 0f, 0f)
                        Matrix.rotateM(model, 0, Math.toDegrees(pose.yawRad.toDouble()).toFloat(), 0f, 1f, 0f)

                        // 1. 真实 3D 挤出金属侧壁（厚度 rim）
                        if (rimBuffer != null && rimVertexCount > 0) {
                            drawRim(proj, view, model, mvp, bundle.edgeMetalRgb, bundle.toneRgb)
                        }

                        // 2. 正面浮雕主面（z = +thickness/2）
                        Matrix.translateM(partModel, 0, model, 0, 0f, 0f, halfT)
                        drawReliefPlane(
                            proj, view, partModel, mvp,
                            texFrontDiffuse,
                            if (texFrontNormal != 0) texFrontNormal else texFlatNormal,
                            if (texFrontMetal != 0) texFrontMetal else texDefaultMetal,
                            bundle.toneRgb,
                        )

                        // 3. 主创勋章等外圈机械步进旋转环（绕 spin 中心旋转）
                        val spin = bundle.spinConfig
                        if (texOuterDiffuse != 0 && spin != null) {
                            val width = 2.4f
                            val pivotX = ((spin.x - 0.5) * width).toFloat()
                            val pivotY = ((0.5 - spin.y) * width).toFloat()
                            val tmp = FloatArray(16)
                            Matrix.translateM(tmp, 0, model, 0, pivotX, pivotY, halfT + 0.003f)
                            Matrix.rotateM(tmp, 0, Math.toDegrees(pose.outerSpinRad.toDouble()).toFloat(), 0f, 0f, 1f)
                            Matrix.translateM(partModel, 0, tmp, 0, -pivotX, -pivotY, 0f)
                            drawReliefPlane(
                                proj, view, partModel, mvp,
                                texOuterDiffuse,
                                if (texOuterNormal != 0) texOuterNormal else texFlatNormal,
                                if (texOuterMetal != 0) texOuterMetal else texDefaultMetal,
                                bundle.toneRgb,
                            )
                        }

                        // 4. 背面凹雕铭文主面（z = -thickness/2，绕 Y 轴旋转 180°）
                        val backTmp = FloatArray(16)
                        Matrix.translateM(backTmp, 0, model, 0, 0f, 0f, -halfT)
                        Matrix.rotateM(partModel, 0, backTmp, 0, 180f, 0f, 1f, 0f)
                        drawReliefPlane(
                            proj, view, partModel, mvp,
                            texBackDiffuse,
                            if (texBackNormal != 0) texBackNormal else texFlatNormal,
                            if (texBackMetal != 0) texBackMetal else texDefaultMetal,
                            bundle.toneRgb,
                        )
                    }

                    EGL14.eglSwapBuffers(eglDisplay, eglSurface)
                    val elapsed = SystemClock.uptimeMillis() - frameStart
                    val sleepMs = (16L - elapsed).coerceAtLeast(1L)
                    sleep(sleepMs)
                }
            } catch (_: InterruptedException) {
            } finally {
                releaseGl()
                releaseEgl()
            }
        }

        private fun initEgl(): Boolean {
            eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (eglDisplay == EGL14.EGL_NO_DISPLAY) return false
            val version = IntArray(2)
            if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) return false

            val config = chooseConfig(withMsaa = true) ?: chooseConfig(withMsaa = false) ?: return false
            val ctxAttrs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
            eglContext = EGL14.eglCreateContext(eglDisplay, config, EGL14.EGL_NO_CONTEXT, ctxAttrs, 0)
            if (eglContext == EGL14.EGL_NO_CONTEXT) return false

            val surfAttrs = intArrayOf(EGL14.EGL_NONE)
            eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, config, surfaceTexture, surfAttrs, 0)
            if (eglSurface == EGL14.EGL_NO_SURFACE) return false
            return EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
        }

        private fun chooseConfig(withMsaa: Boolean): EGLConfig? {
            val attrs = if (withMsaa) {
                intArrayOf(
                    EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                    EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
                    EGL14.EGL_DEPTH_SIZE, 16,
                    EGL14.EGL_SAMPLE_BUFFERS, 1, EGL14.EGL_SAMPLES, 4,
                    EGL14.EGL_NONE,
                )
            } else {
                intArrayOf(
                    EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                    EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
                    EGL14.EGL_DEPTH_SIZE, 16,
                    EGL14.EGL_NONE,
                )
            }
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            if (!EGL14.eglChooseConfig(eglDisplay, attrs, 0, configs, 0, 1, count, 0) || count[0] <= 0) {
                return null
            }
            return configs[0]
        }

        private fun initGlResources() {
            GLES20.glEnable(GLES20.GL_DEPTH_TEST)
            GLES20.glDepthFunc(GLES20.GL_LEQUAL)
            GLES20.glEnable(GLES20.GL_CULL_FACE)
            GLES20.glCullFace(GLES20.GL_BACK)
            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)

            reliefProgram = createProgram(RELIEF_VS, RELIEF_FS)
            rimProgram = createProgram(RIM_VS, RIM_FS)

            val h = 1.2f // width = 2.4
            // x, y, z, u, v
            val quadVerts = floatArrayOf(
                -h, h, 0f, 0f, 0f,
                -h, -h, 0f, 0f, 1f,
                h, h, 0f, 1f, 0f,
                h, -h, 0f, 1f, 1f,
            )
            quadBuffer = ByteBuffer.allocateDirect(quadVerts.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
                put(quadVerts)
                position(0)
            }

            texFlatNormal = uploadSolidTexture(128, 128, 255)
            texDefaultMetal = uploadSolidTexture(92, 92, 92)
        }

        private fun uploadBundle(bundle: CommunityMedalRenderBundle?) {
            deleteMedalTextures()
            activeBundle = bundle
            rimBuffer = null
            rimVertexCount = 0
            if (bundle == null) return

            texFrontDiffuse = uploadBitmapTexture(bundle.frontDiffuse)
            texFrontNormal = bundle.frontNormal?.let { uploadBitmapTexture(it) } ?: 0
            texFrontMetal = bundle.frontMetalness?.let { uploadBitmapTexture(it) } ?: 0
            texOuterDiffuse = bundle.frontOuterDiffuse?.let { uploadBitmapTexture(it) } ?: 0
            texOuterNormal = bundle.frontOuterNormal?.let { uploadBitmapTexture(it) } ?: 0
            texOuterMetal = bundle.frontOuterMetalness?.let { uploadBitmapTexture(it) } ?: 0
            texBackDiffuse = uploadBitmapTexture(bundle.backDiffuse)
            texBackNormal = bundle.backNormal?.let { uploadBitmapTexture(it) } ?: 0
            texBackMetal = bundle.backMetalness?.let { uploadBitmapTexture(it) } ?: 0

            buildRimMesh(bundle.frontOutline)
        }

        /** 由 `.outline.json` 生成真实 3D 金属挤出侧壁网格（带平滑法线，内缩 1.4% 紧贴浮雕边缘无毛边）。 */
        private fun buildRimMesh(outline: CommunityMedalOutline?) {
            val pts = outline?.outline?.filter { it.size >= 2 } ?: return
            if (pts.size < 3) return
            val width = 2.4f
            val halfT = (0.11f - 0.008f) * 0.5f

            var cx = 0f
            var cy = 0f
            val mapped = pts.map { p ->
                val x = ((p[0] - 0.5) * width).toFloat()
                val y = ((0.5 - p[1]) * width).toFloat()
                cx += x; cy += y
                x to y
            }
            cx /= mapped.size
            cy /= mapped.size

            val inset = 0.986f
            val ring = mapped.map { (x, y) ->
                (cx + (x - cx) * inset) to (cy + (y - cy) * inset)
            }

            // Determine winding (signed area) so outward normals always point away from center
            var signedArea = 0f
            for (i in ring.indices) {
                val (x0, y0) = ring[i]
                val (x1, y1) = ring[(i + 1) % ring.size]
                signedArea += x0 * y1 - x1 * y0
            }
            val normalSign = if (signedArea >= 0f) 1f else -1f

            // Triangle strip around closed perimeter: 2 vertices per point (front & back), closing back to 0
            val n = ring.size
            val verts = FloatArray((n + 1) * 2 * 6) // x, y, z, nx, ny, nz
            var ptr = 0
            for (i in 0..n) {
                val idx = i % n
                val prev = ring[(idx - 1 + n) % n]
                val cur = ring[idx]
                val next = ring[(idx + 1) % n]
                val tx = next.first - prev.first
                val ty = next.second - prev.second
                var nx = ty * normalSign
                var ny = -tx * normalSign
                val len = sqrt(nx * nx + ny * ny).coerceAtLeast(1e-5f)
                nx /= len
                ny /= len

                // Front edge vertex
                verts[ptr++] = cur.first
                verts[ptr++] = cur.second
                verts[ptr++] = halfT
                verts[ptr++] = nx
                verts[ptr++] = ny
                verts[ptr++] = 0.15f

                // Back edge vertex
                verts[ptr++] = cur.first
                verts[ptr++] = cur.second
                verts[ptr++] = -halfT
                verts[ptr++] = nx
                verts[ptr++] = ny
                verts[ptr++] = -0.15f
            }

            rimBuffer = ByteBuffer.allocateDirect(verts.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
                put(verts)
                position(0)
            }
            rimVertexCount = (n + 1) * 2
        }

        private fun drawRim(
            proj: FloatArray,
            view: FloatArray,
            model: FloatArray,
            mvp: FloatArray,
            edgeRgb: FloatArray,
            toneRgb: FloatArray,
        ) {
            val buf = rimBuffer ?: return
            GLES20.glDisable(GLES20.GL_CULL_FACE)
            GLES20.glUseProgram(rimProgram)

            val mv = FloatArray(16)
            Matrix.multiplyMM(mv, 0, view, 0, model, 0)
            Matrix.multiplyMM(mvp, 0, proj, 0, mv, 0)

            GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(rimProgram, "uMVP"), 1, false, mvp, 0)
            GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(rimProgram, "uModel"), 1, false, model, 0)
            GLES20.glUniform3fv(GLES20.glGetUniformLocation(rimProgram, "uEdgeColor"), 1, edgeRgb, 0)
            GLES20.glUniform3fv(GLES20.glGetUniformLocation(rimProgram, "uToneColor"), 1, toneRgb, 0)

            val aPos = GLES20.glGetAttribLocation(rimProgram, "aPos")
            val aNorm = GLES20.glGetAttribLocation(rimProgram, "aNorm")
            GLES20.glEnableVertexAttribArray(aPos)
            GLES20.glEnableVertexAttribArray(aNorm)
            buf.position(0)
            GLES20.glVertexAttribPointer(aPos, 3, GLES20.GL_FLOAT, false, 24, buf)
            buf.position(3)
            GLES20.glVertexAttribPointer(aNorm, 3, GLES20.GL_FLOAT, false, 24, buf)

            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, rimVertexCount)

            GLES20.glDisableVertexAttribArray(aPos)
            GLES20.glDisableVertexAttribArray(aNorm)
            GLES20.glEnable(GLES20.GL_CULL_FACE)
        }

        private fun drawReliefPlane(
            proj: FloatArray,
            view: FloatArray,
            model: FloatArray,
            mvp: FloatArray,
            diffuseTex: Int,
            normalTex: Int,
            metalTex: Int,
            toneRgb: FloatArray,
        ) {
            if (diffuseTex == 0) return
            GLES20.glUseProgram(reliefProgram)

            val mv = FloatArray(16)
            Matrix.multiplyMM(mv, 0, view, 0, model, 0)
            Matrix.multiplyMM(mvp, 0, proj, 0, mv, 0)

            GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(reliefProgram, "uMVP"), 1, false, mvp, 0)
            GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(reliefProgram, "uModel"), 1, false, model, 0)
            GLES20.glUniform3fv(GLES20.glGetUniformLocation(reliefProgram, "uToneColor"), 1, toneRgb, 0)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, diffuseTex)
            GLES20.glUniform1i(GLES20.glGetUniformLocation(reliefProgram, "uDiffuse"), 0)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, normalTex)
            GLES20.glUniform1i(GLES20.glGetUniformLocation(reliefProgram, "uNormal"), 1)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE2)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, metalTex)
            GLES20.glUniform1i(GLES20.glGetUniformLocation(reliefProgram, "uMetal"), 2)

            val aPos = GLES20.glGetAttribLocation(reliefProgram, "aPos")
            val aUv = GLES20.glGetAttribLocation(reliefProgram, "aUv")
            GLES20.glEnableVertexAttribArray(aPos)
            GLES20.glEnableVertexAttribArray(aUv)
            quadBuffer.position(0)
            GLES20.glVertexAttribPointer(aPos, 3, GLES20.GL_FLOAT, false, 20, quadBuffer)
            quadBuffer.position(3)
            GLES20.glVertexAttribPointer(aUv, 2, GLES20.GL_FLOAT, false, 20, quadBuffer)

            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

            GLES20.glDisableVertexAttribArray(aPos)
            GLES20.glDisableVertexAttribArray(aUv)
        }

        private fun uploadBitmapTexture(bitmap: Bitmap): Int {
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            val id = ids[0]
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR_MIPMAP_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
            GLES20.glGenerateMipmap(GLES20.GL_TEXTURE_2D)
            return id
        }

        private fun uploadSolidTexture(r: Int, g: Int, b: Int): Int {
            val bmp = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888).apply {
                eraseColor(android.graphics.Color.argb(255, r, g, b))
            }
            val id = uploadBitmapTexture(bmp)
            bmp.recycle()
            return id
        }

        private fun deleteMedalTextures() {
            val ids = intArrayOf(
                texFrontDiffuse, texFrontNormal, texFrontMetal,
                texOuterDiffuse, texOuterNormal, texOuterMetal,
                texBackDiffuse, texBackNormal, texBackMetal,
            ).filter { it != 0 }.toIntArray()
            if (ids.isNotEmpty()) GLES20.glDeleteTextures(ids.size, ids, 0)
            texFrontDiffuse = 0; texFrontNormal = 0; texFrontMetal = 0
            texOuterDiffuse = 0; texOuterNormal = 0; texOuterMetal = 0
            texBackDiffuse = 0; texBackNormal = 0; texBackMetal = 0
        }

        private fun releaseGl() {
            deleteMedalTextures()
            val defaults = intArrayOf(texFlatNormal, texDefaultMetal).filter { it != 0 }.toIntArray()
            if (defaults.isNotEmpty()) GLES20.glDeleteTextures(defaults.size, defaults, 0)
            if (reliefProgram != 0) GLES20.glDeleteProgram(reliefProgram)
            if (rimProgram != 0) GLES20.glDeleteProgram(rimProgram)
        }

        private fun releaseEgl() {
            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(eglDisplay, eglSurface)
                if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(eglDisplay, eglContext)
                EGL14.eglTerminate(eglDisplay)
            }
        }

        private fun createProgram(vs: String, fs: String): Int {
            val vShader = compileShader(GLES20.GL_VERTEX_SHADER, vs)
            val fShader = compileShader(GLES20.GL_FRAGMENT_SHADER, fs)
            val p = GLES20.glCreateProgram()
            GLES20.glAttachShader(p, vShader)
            GLES20.glAttachShader(p, fShader)
            GLES20.glLinkProgram(p)
            GLES20.glDeleteShader(vShader)
            GLES20.glDeleteShader(fShader)
            return p
        }

        private fun compileShader(type: Int, src: String): Int {
            val s = GLES20.glCreateShader(type)
            GLES20.glShaderSource(s, src)
            GLES20.glCompileShader(s)
            return s
        }
    }

    companion object {
        private const val RELIEF_VS = """
            uniform mat4 uMVP;
            uniform mat4 uModel;
            attribute vec3 aPos;
            attribute vec2 aUv;
            varying vec2 vUv;
            varying vec3 vWorldPos;
            varying mat3 vTbn;
            void main() {
                vUv = aUv;
                vec4 wp = uModel * vec4(aPos, 1.0);
                vWorldPos = wp.xyz;
                vec3 T = normalize((uModel * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
                vec3 B = normalize((uModel * vec4(0.0, -1.0, 0.0, 0.0)).xyz);
                vec3 N = normalize((uModel * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
                vTbn = mat3(T, B, N);
                gl_Position = uMVP * vec4(aPos, 1.0);
            }
        """

        // 对齐 iOS SceneKit 影棚三灯 + 高度法线贴图 + 0.52 自发光锁色 + 金属柔光条带反射 + alpha < 0.45 裁切
        private const val RELIEF_FS = """
            precision highp float;
            uniform sampler2D uDiffuse;
            uniform sampler2D uNormal;
            uniform sampler2D uMetal;
            uniform vec3 uToneColor;
            varying vec2 vUv;
            varying vec3 vWorldPos;
            varying mat3 vTbn;
            void main() {
                vec4 albedo = texture2D(uDiffuse, vUv);
                if (albedo.a < 0.45) discard;

                vec3 nSample = texture2D(uNormal, vUv).xyz * 2.0 - 1.0;
                nSample.xy *= 0.68;
                vec3 N = normalize(vTbn * normalize(nSample));
                vec3 V = normalize(vec3(0.0, 0.0, 5.65) - vWorldPos);

                float metal = texture2D(uMetal, vUv).r;
                float specPower = mix(22.0, 54.0, metal);

                // 主定向光 (-3, 4, 5)
                vec3 L1 = normalize(vec3(-3.0, 4.0, 5.0));
                vec3 H1 = normalize(L1 + V);
                float diff1 = max(dot(N, L1), 0.0);
                float spec1 = pow(max(dot(N, H1), 0.0), specPower) * (0.16 + 0.52 * metal);

                // 右侧轮廓冷补光 (4, 1.5, 3)
                vec3 L2 = normalize(vec3(4.0, 1.5, 3.0));
                vec3 H2 = normalize(L2 + V);
                float diff2 = max(dot(N, L2), 0.0);
                float spec2 = pow(max(dot(N, H2), 0.0), specPower * 0.85) * (0.10 + 0.34 * metal);

                // 底部勋章主色微氛围补光 (0, -2.5, 3.5)
                vec3 L3 = normalize(vec3(0.0, -2.5, 3.5));
                float diff3 = max(dot(N, L3), 0.0);

                // 影棚柔光条带环境反射（倾斜时金属面呈现细腻丝滑反光）
                vec3 R = reflect(-V, N);
                float stripTop = smoothstep(0.32, 0.85, R.y) * 0.24;
                float stripSide = smoothstep(0.55, 0.95, abs(R.x)) * (1.0 - abs(R.y)) * 0.18;
                vec3 envSheen = mix(vec3(1.0), albedo.rgb, 0.55) * (stripTop + stripSide) * (0.28 + 0.72 * metal);

                vec3 baseLit = albedo.rgb * (0.52 + 0.42 * diff1 + 0.16 * diff2)
                    + albedo.rgb * uToneColor * (0.10 * diff3)
                    + mix(vec3(1.0, 0.99, 0.96), albedo.rgb, 0.35) * spec1
                    + vec3(0.88, 0.94, 1.0) * spec2
                    + envSheen;

                gl_FragColor = vec4(clamp(baseLit, 0.0, 1.0), 1.0);
            }
        """

        private const val RIM_VS = """
            uniform mat4 uMVP;
            uniform mat4 uModel;
            attribute vec3 aPos;
            attribute vec3 aNorm;
            varying vec3 vWorldPos;
            varying vec3 vWorldNorm;
            void main() {
                vec4 wp = uModel * vec4(aPos, 1.0);
                vWorldPos = wp.xyz;
                vWorldNorm = normalize((uModel * vec4(aNorm, 0.0)).xyz);
                gl_Position = uMVP * vec4(aPos, 1.0);
            }
        """

        private const val RIM_FS = """
            precision highp float;
            uniform vec3 uEdgeColor;
            uniform vec3 uToneColor;
            varying vec3 vWorldPos;
            varying vec3 vWorldNorm;
            void main() {
                vec3 N = normalize(vWorldNorm);
                vec3 V = normalize(vec3(0.0, 0.0, 5.65) - vWorldPos);
                vec3 L1 = normalize(vec3(-3.0, 4.0, 5.0));
                vec3 L2 = normalize(vec3(4.0, 1.5, 3.0));
                float d1 = max(dot(N, L1), 0.0);
                float d2 = max(dot(N, L2), 0.0);
                vec3 H1 = normalize(L1 + V);
                vec3 H2 = normalize(L2 + V);
                float s1 = pow(max(dot(N, H1), 0.0), 36.0) * 0.65;
                float s2 = pow(max(dot(N, H2), 0.0), 28.0) * 0.40;
                vec3 col = uEdgeColor * (0.36 + 0.62 * d1 + 0.28 * d2)
                    + mix(vec3(1.0), uEdgeColor, 0.45) * (s1 + s2)
                    + uToneColor * 0.05;
                gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
            }
        """
    }
}
