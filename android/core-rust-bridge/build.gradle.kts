plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

// JVM 回归使用桌面 JNA，不将其打入 Android 运行包。
val hostTestJna by configurations.creating

android {
    namespace = "com.moviepilot.rustbridge"
    compileSdk = 35
    buildToolsVersion = "35.0.0"
    defaultConfig {
        minSdk = 29
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    api(libs.androidx.core.ktx)
    api(libs.kotlinx.coroutines.android)
    api(libs.kotlinx.serialization.json)
    api(libs.okhttp)
    // UniFFI Kotlin 绑定使用 JNA AAR 调用原生 libmoviepilot_core.so
    api("net.java.dev.jna:jna:5.15.0@aar")
    testImplementation(libs.junit)
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    hostTestJna("net.java.dev.jna:jna:5.15.0@jar")
}

// 真实 HTTP/JNA 契约测试使用构建脚本已生成的宿主 Rust 库。
tasks.withType<Test>().configureEach {
    inputs.files(hostTestJna)
    doFirst {
        classpath = files(hostTestJna) + classpath
        val nativeTemp = temporaryDir.resolve("jna").also { it.mkdirs() }
        systemProperty("jna.tmpdir", nativeTemp.absolutePath)
    }
    systemProperty("jna.library.path", System.getenv("MOVIEPILOT_RUST_HOST_LIB_DIR")
        ?: "/Volumes/DISK/TmpBuild/moviepilot-rust-target/release")
}
