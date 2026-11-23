plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.moviepilot.app"
    compileSdk = 35
    buildToolsVersion = "35.0.0"

    defaultConfig {
        applicationId = "com.moviepilot.app"
        minSdk = 28
        targetSdk = 35
        versionCode = (project.findProperty("MOVIEPILOT_VERSION_CODE") as String?)?.toIntOrNull() ?: 2000201
        versionName = (project.findProperty("MOVIEPILOT_VERSION_NAME") as String?) ?: "2.0.2"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
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
    testImplementation(libs.junit)
}
