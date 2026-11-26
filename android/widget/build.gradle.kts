plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

// 测试 SDK 交由 Gradle 复用仓库与缓存，避免 Robolectric 在测试进程中另行联网下载。
val robolectricSdk29 by configurations.creating { isTransitive = false }
val robolectricSdk35 by configurations.creating { isTransitive = false }
val robolectricSdkDirectory = layout.buildDirectory.dir("robolectric-sdks")

android {
    namespace = "com.moviepilot.widget"
    compileSdk = 35
    buildToolsVersion = "35.0.0"
    defaultConfig { minSdk = 29 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    testOptions { unitTests.isIncludeAndroidResources = true }
}

dependencies {
    api(project(":design-system"))
    api(project(":core-rust-bridge"))
    api(libs.androidx.glance.appwidget)
    api(libs.androidx.glance.material3)
    implementation(libs.androidx.work.runtime.ktx)
    testImplementation(libs.junit)
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.work:work-testing:${libs.versions.workRuntime.get()}")
    // 与 PluginWidgetUpdateTest 的 API 29 / 35 和 Robolectric 4.14.1 保持一致。
    robolectricSdk29("org.robolectric:android-all-instrumented:10-robolectric-5803371-i7")
    robolectricSdk35("org.robolectric:android-all-instrumented:15-robolectric-12650502-i7")
}

// 将两套 SDK 放入同一目录，供 Robolectric 的离线解析器直接读取。
val prepareRobolectricSdks by tasks.registering(Sync::class) {
    from(robolectricSdk29, robolectricSdk35)
    into(robolectricSdkDirectory)
}

tasks.withType<Test>().configureEach {
    dependsOn(prepareRobolectricSdks)
    inputs.files(robolectricSdk29, robolectricSdk35)
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", robolectricSdkDirectory.get().asFile.absolutePath)
    testLogging { exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
