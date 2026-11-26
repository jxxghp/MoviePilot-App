plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

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
}
