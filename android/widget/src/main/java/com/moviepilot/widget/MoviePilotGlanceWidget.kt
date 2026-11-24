package com.moviepilot.widget

import android.content.ComponentName
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider

/**
 * Android 原生 Jetpack Glance 桌面小组件：展示已同步的真实媒体库统计与实时下载速览，点击直达主界面。
 */
class MoviePilotGlanceWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = context.getSharedPreferences("mp_widget_snapshot_v1", Context.MODE_PRIVATE)
        val movies = prefs.getInt("movies", 0)
        val tvs = prefs.getInt("tvs", 0)
        val speed = prefs.getString("speed", "0 B/s") ?: "0 B/s"
        val server = prefs.getString("server", "MoviePilot") ?: "MoviePilot"
        val launchMain = actionStartActivity(
            ComponentName(context.packageName, "com.moviepilot.app.MainActivity"),
        )

        provideContent {
            MoviePilotWidgetContent(
                server = server,
                movies = movies,
                tvs = tvs,
                speed = speed,
                modifier = GlanceModifier.clickable(launchMain),
            )
        }
    }
}

@Composable
private fun MoviePilotWidgetContent(
    server: String,
    movies: Int,
    tvs: Int,
    speed: String,
    modifier: GlanceModifier = GlanceModifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(ColorProvider(Color(0xFF0E1117)))
            .padding(14.dp),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Text(
            text = server,
            style = TextStyle(
                color = ColorProvider(Color(0xFFD6BDFF)),
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
        Spacer(GlanceModifier.height(8.dp))
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = movies.toString(),
                    style = TextStyle(color = ColorProvider(Color.White), fontSize = 20.sp, fontWeight = FontWeight.Bold),
                )
                Text(
                    text = "电影",
                    style = TextStyle(color = ColorProvider(Color(0xB8FFFFFF)), fontSize = 11.sp),
                )
            }
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = tvs.toString(),
                    style = TextStyle(color = ColorProvider(Color.White), fontSize = 20.sp, fontWeight = FontWeight.Bold),
                )
                Text(
                    text = "剧集",
                    style = TextStyle(color = ColorProvider(Color(0xB8FFFFFF)), fontSize = 11.sp),
                )
            }
        }
        Spacer(GlanceModifier.height(8.dp))
        Text(
            text = "实时下载：$speed",
            style = TextStyle(color = ColorProvider(Color(0xFF75E6A3)), fontSize = 12.sp),
        )
    }
}

/** 桌面小组件系统广播接收器。 */
class MoviePilotWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MoviePilotGlanceWidget()
}
