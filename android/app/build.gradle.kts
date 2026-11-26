plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// 解析构建参数 MOVIEPILOT_ABI_FILTERS，未指定时自动扫描 core-rust-bridge 已同步的真实 libmoviepilot_core.so 架构目录，
// 严格锁定打包 ABI，防止 JNA AAR 注入孤立 x86_64/mips 空壳目录引发 UnsatisfiedLinkError。
val requestedAbiFilters = (project.findProperty("MOVIEPILOT_ABI_FILTERS") as String?)
    ?.split(",")
    ?.map { it.trim() }
    ?.filter { it.isNotEmpty() }
    .orEmpty()
val detectedRustAbis = file("../core-rust-bridge/src/main/jniLibs")
    .listFiles()
    ?.filter { dir -> dir.isDirectory && File(dir, "libmoviepilot_core.so").isFile }
    ?.map { it.name }
    ?.sorted()
    .orEmpty()
val effectiveAbiFilters = when {
    requestedAbiFilters.isNotEmpty() -> requestedAbiFilters
    detectedRustAbis.isNotEmpty() -> detectedRustAbis
    else -> listOf("arm64-v8a")
}

val releaseKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")?.trim().orEmpty()
val releaseKeystoreFile = releaseKeystorePath.takeIf { it.isNotEmpty() }?.let { file(it) }
val hasReleaseKeystore = releaseKeystoreFile != null && releaseKeystoreFile.isFile

android {
    namespace = "com.moviepilot.app"
    compileSdk = 35
    buildToolsVersion = "35.0.0"

    defaultConfig {
        applicationId = "com.moviepilot.app"
        minSdk = 29
        targetSdk = 35
        versionCode = (project.findProperty("MOVIEPILOT_VERSION_CODE") as String?)?.toIntOrNull() ?: 2000301
        versionName = (project.findProperty("MOVIEPILOT_VERSION_NAME") as String?) ?: "2.0.3"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters.addAll(effectiveAbiFilters)
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD").orEmpty()
                keyAlias = System.getenv("ANDROID_KEY_ALIAS").orEmpty()
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD").orEmpty()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(project(":core-rust-bridge"))
    implementation(project(":design-system"))
    implementation(project(":core-media"))
    implementation(project(":core-medal3d"))
    implementation(project(":core-plugin-host"))
    implementation(project(":widget"))
    implementation(project(":feature:auth"))
    implementation(project(":feature:discover"))
    implementation(project(":feature:media"))
    implementation(project(":feature:subscribe"))
    implementation(project(":feature:download"))
    implementation(project(":feature:library"))
    implementation(project(":feature:dashboard"))
    implementation(project(":feature:automation"))
    implementation(project(":feature:agent"))
    implementation(project(":feature:settings"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.work.runtime.ktx)
    testImplementation(libs.junit)
}
